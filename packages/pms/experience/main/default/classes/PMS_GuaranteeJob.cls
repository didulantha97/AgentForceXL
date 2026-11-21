/**
 * Hourly guarantee sweep ("PMS Guarantees (hourly)"). For bookings that have a payment policy:
 *
 *   1. applies cancellation / no-show policies still pending (safety net for PMS_GuaranteeActionJob)
 *   2. fills card brand, last 4 and expiry for newly saved cards
 *   3. charges deposits and prepayments that fall due (Deposit Due days before arrival)
 *   4. places pre-authorisation holds shortly before arrival, and renews holds about to expire
 *   5. settles holds after check-out: captures what is still owed and releases the rest
 *   6. emails card links for recent bookings created where the trigger could not queue them
 *
 * Every Stripe call is made first and all records are saved at the end. About 30 bookings fit in
 * one run (each can need up to three calls); the rest wait for the next hour.
 *
 * Schedule: System.schedule('PMS Guarantees (hourly)', '0 10 * * * ?', new PMS_GuaranteeJob());
 */
public without sharing class PMS_GuaranteeJob implements Schedulable {
  /** Channels whose bookings never get an automatic card link: the website takes payment itself, OTAs collect their own guarantee. */
  public static final Set<String> NO_LINK_CHANNELS = new Set<String>{
    'Website',
    'OTA'
  };

  public void execute(SchedulableContext ctx) {
    if (PMS_Entitlements.jobsBlocked('PMS_GuaranteeJob')) {
      return; // licence suspended: PMS is read-only
    }
    System.enqueueJob(new Runner());
  }

  public class Runner implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext ctx) {
      PMS_GuaranteeJob.run();
    }
  }

  public static void run() {
    Datetime now = Datetime.now();
    Datetime horizon = now.addDays(horizonDays());
    Datetime settledPending = now.addMinutes(-10);
    Datetime recentCheckout = now.addDays(-7);
    String q =
      'SELECT ' +
      PMS_PolicyService.bookingFields() +
      ' FROM PMS_Booking__c WHERE (' +
      'Payment_Policy__c != null OR Rate_Plan__r.Payment_Policy__c != null ' +
      'OR Service__r.Payment_Policy__c != null OR Site__r.Payment_Policy__c != null) AND (' +
      '(Policy_Pending__c = true AND Policy_Event_At__c <= :settledPending) ' +
      'OR (Stripe_Payment_Method__c != null AND Card_Last4__c = null) ' +
      'OR (Status__c IN (\'Tentative\', \'Confirmed\', \'Active\') AND Start__c <= :horizon AND End__c >= :now) ' +
      'OR (Status__c = \'Completed\' AND Preauth_Status__c = \'Authorized\' AND End__c >= :recentCheckout) ' +
      'OR (Status__c IN (\'Tentative\', \'Confirmed\') AND Card_Link_Sent_At__c = null AND Stripe_Payment_Method__c = null AND CreatedDate = LAST_N_DAYS:2)' +
      ') ORDER BY Start__c LIMIT 200';
    List<PMS_Booking__c> bookings = Database.query(q);
    process(bookings, now);
  }

  @TestVisible
  private static void process(List<PMS_Booking__c> bookings, Datetime now) {
    if (bookings.isEmpty()) {
      return;
    }
    Map<Id, PMS_Payment_Policy__c> policies = PMS_PolicyService.policiesFor(
      bookings
    );
    Set<Id> ids = new Map<Id, PMS_Booking__c>(bookings).keySet();
    Map<Id, Decimal> credit = PMS_PolicyService.unappliedCredit(ids);
    Map<Id, Decimal> owed = new Map<Id, Decimal>();
    Map<Id, Id> owedInvoice = new Map<Id, Id>();
    Set<Id> uninvoiced = new Set<Id>();
    for (PMS_Invoice__c inv : [
      SELECT Id, Booking__c, Balance__c
      FROM PMS_Invoice__c
      WHERE
        Booking__c IN :ids
        AND Balance__c > 0
        AND Status__c NOT IN ('Void', 'Credited', 'Draft')
      ORDER BY Balance__c DESC
    ]) {
      owed.put(
        inv.Booking__c,
        (owed.containsKey(inv.Booking__c) ? owed.get(inv.Booking__c) : 0) +
        inv.Balance__c
      );
      if (!owedInvoice.containsKey(inv.Booking__c)) {
        owedInvoice.put(inv.Booking__c, inv.Id);
      }
    }
    for (PMS_Charge__c c : [
      SELECT Booking__c
      FROM PMS_Charge__c
      WHERE Booking__c IN :ids AND Status__c = 'Pending' AND Invoice__c = NULL
    ]) {
      uninvoiced.add(c.Booking__c);
    }

    PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
    for (PMS_Booking__c b : bookings) {
      if (Limits.getCallouts() > Limits.getLimitCallouts() - 4) {
        break; // the rest wait for the next run
      }
      try {
        step(
          b,
          policies.get(b.Id),
          now,
          credit.get(b.Id),
          owed.get(b.Id),
          owedInvoice.get(b.Id),
          uninvoiced.contains(b.Id),
          w
        );
      } catch (Exception e) {
        w.booking(b.Id).Guarantee_Message__c = PMS_GuaranteeService.cut(
          'Guarantee job: ' + e.getMessage(),
          255
        );
      }
    }
    w.commitWork();
  }

  private static void step(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Datetime now,
    Decimal credit,
    Decimal owed,
    Id owedInvoiceId,
    Boolean hasUninvoiced,
    PMS_GuaranteeService.Work w
  ) {
    if (b.Policy_Pending__c == true) {
      if (b.Policy_Fee_Charged__c != true) {
        PMS_GuaranteeService.applyPolicy(b, p, credit, w);
      } else {
        w.booking(b.Id).Policy_Pending__c = false;
      }
      return;
    }
    if (p == null) {
      return;
    }
    String m = PMS_PolicyService.method(p);
    Boolean hasCard = String.isNotBlank(b.Stripe_Payment_Method__c);
    if (hasCard && String.isBlank(b.Card_Last4__c)) {
      PMS_GuaranteeService.refreshCard(b, w);
    }
    if (b.Status__c == 'Completed') {
      if (
        b.Preauth_Status__c == 'Authorized' &&
        p.Release_Hold_On_Checkout__c == true
      ) {
        if (hasUninvoiced) {
          w.booking(b.Id)
            .Guarantee_Message__c = 'Checked out with charges not invoiced yet; the hold is settled once the folio is invoiced.';
        } else {
          PMS_GuaranteeService.settleHold(b, owed, owedInvoiceId, w);
        }
      }
      return;
    }
    if (PMS_GuaranteeService.CLOSED.contains(b.Status__c)) {
      return;
    }
    Boolean retryBlocked = b.Guarantee_Status__c == 'Action Needed';
    if (
      (m == PMS_PolicyService.M_DEPOSIT ||
      m == PMS_PolicyService.M_PREPAID) &&
      hasCard &&
      !retryBlocked &&
      b.Guarantee_Status__c != 'Deposit Paid' &&
      PMS_PolicyService.depositDueNow(b, p, now)
    ) {
      PMS_GuaranteeService.chargeDeposit(b, p, credit, w);
    } else if (
      m == PMS_PolicyService.M_PREAUTH &&
      hasCard &&
      !retryBlocked &&
      b.Preauth_Status__c == null &&
      PMS_PolicyService.holdDueNow(b, p, now)
    ) {
      PMS_GuaranteeService.placeHoldFor(b, p, w);
    } else if (
      m == PMS_PolicyService.M_PREAUTH &&
      b.Preauth_Status__c == 'Authorized' &&
      b.Preauth_Expires_At__c != null &&
      b.Preauth_Expires_At__c < now.addHours(24) &&
      b.End__c != null &&
      b.End__c > b.Preauth_Expires_At__c
    ) {
      PMS_GuaranteeService.renewHold(b, p, w);
    } else if (
      !hasCard &&
      shouldAutoSend(b, p) &&
      b.CreatedDate >= now.addDays(-2)
    ) {
      sendLink(b, p, w);
    }
  }

  // ---------------------------------------------------------------- used by PMS_GuaranteeActionJob

  public static void sendLinks(Set<Id> ids) {
    List<PMS_Booking__c> bookings = PMS_PolicyService.load(ids);
    Map<Id, PMS_Payment_Policy__c> policies = PMS_PolicyService.policiesFor(
      bookings
    );
    PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
    for (PMS_Booking__c b : bookings) {
      PMS_Payment_Policy__c p = policies.get(b.Id);
      if (shouldAutoSend(b, p)) {
        sendLink(b, p, w);
      } else if (
        p != null &&
        PMS_PolicyService.method(p) != PMS_PolicyService.M_NONE &&
        b.Guarantee_Status__c == null
      ) {
        w.booking(b.Id).Guarantee_Status__c = 'Awaiting Card';
      }
    }
    w.commitWork();
  }

  public static void applyPolicies(Set<Id> ids) {
    List<PMS_Booking__c> bookings = PMS_PolicyService.load(ids);
    Map<Id, PMS_Payment_Policy__c> policies = PMS_PolicyService.policiesFor(
      bookings
    );
    Map<Id, Decimal> credit = PMS_PolicyService.unappliedCredit(ids);
    PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
    for (PMS_Booking__c b : bookings) {
      if (b.Policy_Pending__c != true || b.Policy_Fee_Charged__c == true) {
        continue;
      }
      try {
        PMS_GuaranteeService.applyPolicy(
          b,
          policies.get(b.Id),
          credit.get(b.Id),
          w
        );
      } catch (Exception e) {
        w.booking(b.Id).Guarantee_Message__c = PMS_GuaranteeService.cut(
          'Applying the policy failed: ' + e.getMessage(),
          255
        );
      }
    }
    w.commitWork();
  }

  public static Boolean shouldAutoSend(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p
  ) {
    return p != null &&
      p.Auto_Send_Card_Link__c == true &&
      PMS_PolicyService.method(p) != PMS_PolicyService.M_NONE &&
      String.isBlank(b.Stripe_Payment_Method__c) &&
      b.Card_Link_Sent_At__c == null &&
      b.Primary_Contact__c != null &&
      !NO_LINK_CHANNELS.contains(b.Channel__c) &&
      b.Guarantee__c != 'Prepaid' &&
      b.Guarantee__c != 'Company Guarantee' &&
      (b.Status__c == 'Tentative' ||
      b.Status__c == 'Confirmed');
  }

  private static void sendLink(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    PMS_GuaranteeService.Work w
  ) {
    try {
      PMS_GuaranteeService.LinkResult r = PMS_GuaranteeService.createLink(
        b,
        p,
        w
      );
      if (!PMS_GuaranteeService.queueLinkEmail(b, p, r, w)) {
        w.booking(b.Id)
          .Guarantee_Message__c = 'The guest has no email address; send the card link from the booking.';
      }
    } catch (Exception e) {
      w.booking(b.Id).Guarantee_Message__c = PMS_GuaranteeService.cut(
        'Card link failed: ' + e.getMessage(),
        255
      );
    }
  }

  /** How far ahead deposits can fall due: the largest Deposit Due days of any active policy (at least 2 days). */
  private static Integer horizonDays() {
    AggregateResult[] r = [
      SELECT MAX(Deposit_Due_Days__c) d
      FROM PMS_Payment_Policy__c
      WHERE Active__c = TRUE
    ];
    Object d = r.isEmpty() ? null : r[0].get('d');
    Integer days = d == null ? 0 : Integer.valueOf(d);
    return Math.max(days, 2) + 1;
  }
}
