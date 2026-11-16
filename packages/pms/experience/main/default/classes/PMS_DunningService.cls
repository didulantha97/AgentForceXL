/**
 * Dunning for overdue invoices: staged reminders, a reminder or late payment fee, late payment
 * interest, a payment plan offer, then hand-off to collections.
 *
 * Steps (days overdue come from the Dunning Policy of the invoice's site, else the default policy):
 *   Reminder 1    letter + the fee (once per invoice; consumers only when the fee is agreed)
 *   Reminder 2    letter + interest so far + the date the claim goes to collections
 *   Plan Offered  letter with N monthly instalments; paying the first one accepts the plan
 *   Collections   final letter, staff task, optional email to the collections agency;
 *                 residential leases also get a task listing the legal steps for termination
 * One step per run, and never two steps closer than Min Days Between (default 7), so an invoice
 * that is already long overdue still gets every letter in turn.
 *
 * Letters carry a pay link to PMS_PayLinkRest on the PMS Payments site; it opens a fresh Stripe
 * page when clicked (Checkout pages themselves expire within 24 hours). So this class makes no
 * callouts, and the daily run is a plain batch.
 *
 * Swedish rules built in as defaults (edit them on the policy): consumer reminder fee at most
 * 60 SEK and only if agreed in advance; 450 SEK late payment compensation for businesses;
 * interest = reference rate + 8 percentage points from the due date. Fees and interest are posted
 * as Late Fee charges on the overdue invoice, without VAT.
 */
public without sharing class PMS_DunningService {
  public static final String R1 = 'Reminder 1';
  public static final String R2 = 'Reminder 2';
  public static final String OFFER = 'Plan Offered';
  public static final String PLAN = 'Payment Plan';
  public static final String COLL = 'Collections';
  public static final List<String> STEPS = new List<String>{
    R1,
    R2,
    OFFER,
    COLL
  };
  public static final Set<String> CLOSED = new Set<String>{
    'Void',
    'Credited',
    'Draft',
    'Paid'
  };
  public static final Set<String> OPEN_PLAN = new Set<String>{
    'Proposed',
    'Active'
  };

  public static final String INVOICE_FIELDS =
    'Id, Name, OwnerId, Status__c, Due_Date__c, Issue_Date__c, Balance__c, Total__c, Amount_Paid__c, Currency_Code__c, ' +
    'Account__c, Account__r.Name, Account__r.PMS_Customer_Type__c, Booking__c, Booking__r.Name, ' +
    'Booking__r.RecordType.DeveloperName, Booking__r.Lease_Type__c, Booking__r.Reminder_Fee_Agreed__c, ' +
    'Booking__r.Primary_Contact__c, Booking__r.Primary_Contact__r.Email, Booking__r.Primary_Contact__r.FirstName, ' +
    'Booking__r.Site__r.Name, Booking__r.Site__r.Manager__c, Booking__r.Site__r.Dunning_Policy__c, Booking__r.Space__r.Name, ' +
    'Project__r.Name, Dunning_Stage__c, Dunning_Paused__c, Dunning_Pause_Reason__c, Dunning_Last_Sent_At__c, ' +
    'Late_Fee_Posted__c, Interest_Through__c, Pay_Key__c';

  public static final String POLICY_FIELDS =
    'Id, Name, Active__c, Is_Default__c, Reminder_1_Days__c, Reminder_2_Days__c, Plan_Offer_Days__c, Collections_Days__c, ' +
    'Min_Days_Between__c, Minimum_Balance__c, Consumer_Reminder_Fee__c, Fee_In_Terms__c, Business_Late_Fee__c, ' +
    'Charge_Interest__c, Reference_Rate__c, Interest_Margin__c, Plan_Instalments__c, Plan_Grace_Days__c, ' +
    'Collections_Agency_Email__c, Sender_Name__c, Payment_Instructions__c';

  public static List<PMS_Invoice__c> load(Set<Id> ids) {
    String fields =
      INVOICE_FIELDS +
      (UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '');
    return Database.query(
      'SELECT ' + fields + ' FROM PMS_Invoice__c WHERE Id IN :ids'
    );
  }

  // ---------------------------------------------------------------- policies

  /** Invoice Id -> its policy: the site's active policy, else the active default. Missing when neither exists. */
  public static Map<Id, PMS_Dunning_Policy__c> policiesFor(
    List<PMS_Invoice__c> invoices
  ) {
    Set<Id> siteIds = new Set<Id>();
    for (PMS_Invoice__c inv : invoices) {
      Id pid = sitePolicyId(inv);
      if (pid != null) {
        siteIds.add(pid);
      }
    }
    Map<Id, PMS_Dunning_Policy__c> byId = new Map<Id, PMS_Dunning_Policy__c>();
    PMS_Dunning_Policy__c fallback;
    for (
      PMS_Dunning_Policy__c p : (List<PMS_Dunning_Policy__c>) Database.query(
        'SELECT ' +
          POLICY_FIELDS +
          ' FROM PMS_Dunning_Policy__c WHERE Active__c = true AND (Id IN :siteIds OR Is_Default__c = true) ORDER BY CreatedDate'
      )
    ) {
      byId.put(p.Id, p);
      if (p.Is_Default__c == true && fallback == null) {
        fallback = p;
      }
    }
    Map<Id, PMS_Dunning_Policy__c> result = new Map<Id, PMS_Dunning_Policy__c>();
    for (PMS_Invoice__c inv : invoices) {
      Id pid = sitePolicyId(inv);
      PMS_Dunning_Policy__c p = pid != null && byId.containsKey(pid)
        ? byId.get(pid)
        : fallback;
      if (p != null) {
        result.put(inv.Id, p);
      }
    }
    return result;
  }

  private static Id sitePolicyId(PMS_Invoice__c inv) {
    return inv.Booking__r == null ||
      inv.Booking__r.Site__r == null
      ? null
      : inv.Booking__r.Site__r.Dunning_Policy__c;
  }

  // ---------------------------------------------------------------- rules

  public static Decimal thresholdOf(PMS_Dunning_Policy__c p, String step) {
    if (step == R1) {
      return p.Reminder_1_Days__c;
    }
    if (step == R2) {
      return p.Reminder_2_Days__c;
    }
    if (step == OFFER) {
      return p.Plan_Offer_Days__c;
    }
    if (step == COLL) {
      return p.Collections_Days__c;
    }
    return null;
  }

  /** The step to take now, or null. force = staff pressed "Send next step now" (skips the waiting rules). */
  public static String nextStep(
    PMS_Invoice__c inv,
    PMS_Dunning_Policy__c p,
    Date today,
    Boolean force
  ) {
    if (
      p == null ||
      inv.Dunning_Paused__c == true ||
      CLOSED.contains(inv.Status__c)
    ) {
      return null;
    }
    if (
      inv.Balance__c == null ||
      inv.Balance__c <= 0 ||
      inv.Due_Date__c == null ||
      inv.Due_Date__c >= today
    ) {
      return null;
    }
    if (
      force != true &&
      p.Minimum_Balance__c != null &&
      inv.Balance__c < p.Minimum_Balance__c
    ) {
      return null;
    }
    String current = inv.Dunning_Stage__c;
    if (current == COLL || current == PLAN) {
      return null;
    }
    Integer days = inv.Due_Date__c.daysBetween(today);
    if (
      force != true &&
      inv.Dunning_Last_Sent_At__c != null &&
      inv.Dunning_Last_Sent_At__c.date().daysBetween(today) < gapDays(p)
    ) {
      return null;
    }
    Integer start = current == null ? 0 : STEPS.indexOf(current) + 1;
    for (Integer i = start; i < STEPS.size(); i++) {
      Decimal threshold = thresholdOf(p, STEPS[i]);
      if (threshold == null) {
        continue; // step switched off on this policy
      }
      return (force == true || days >= threshold) ? STEPS[i] : null;
    }
    return null;
  }

  public static Integer gapDays(PMS_Dunning_Policy__c p) {
    return p.Min_Days_Between__c == null ? 7 : p.Min_Days_Between__c.intValue();
  }

  /** When the next step is expected to run (for the staff panel). */
  public static Date nextStepDate(PMS_Invoice__c inv, PMS_Dunning_Policy__c p) {
    if (p == null || inv.Due_Date__c == null) {
      return null;
    }
    String current = inv.Dunning_Stage__c;
    if (current == COLL || current == PLAN) {
      return null;
    }
    Integer start = current == null ? 0 : STEPS.indexOf(current) + 1;
    for (Integer i = start; i < STEPS.size(); i++) {
      Decimal threshold = thresholdOf(p, STEPS[i]);
      if (threshold == null) {
        continue;
      }
      Date d = inv.Due_Date__c.addDays(threshold.intValue());
      if (inv.Dunning_Last_Sent_At__c != null) {
        Date earliest = inv.Dunning_Last_Sent_At__c.date().addDays(gapDays(p));
        if (earliest > d) {
          d = earliest;
        }
      }
      return d < Date.today() ? Date.today().addDays(1) : d;
    }
    return null;
  }

  public static Boolean isBusiness(PMS_Invoice__c inv) {
    return inv.Account__r != null &&
      inv.Account__r.PMS_Customer_Type__c == 'Business';
  }

  public static Decimal feeFor(PMS_Invoice__c inv, PMS_Dunning_Policy__c p) {
    if (inv.Late_Fee_Posted__c == true) {
      return 0;
    }
    if (isBusiness(inv)) {
      return nz(p.Business_Late_Fee__c);
    }
    Boolean agreed =
      p.Fee_In_Terms__c == true ||
      (inv.Booking__r != null &&
      inv.Booking__r.Reminder_Fee_Agreed__c == true);
    return agreed ? nz(p.Consumer_Reminder_Fee__c) : 0;
  }

  public static Decimal annualRate(PMS_Dunning_Policy__c p) {
    return nz(p.Reference_Rate__c) + nz(p.Interest_Margin__c);
  }

  /**
   * Simple interest on what is owed excluding earlier fees and interest, from the due date (or the
   * last date interest was charged through) to today: principal x rate x days / 365.
   */
  public static Decimal interestFor(
    PMS_Invoice__c inv,
    PMS_Dunning_Policy__c p,
    Decimal dunningCharges,
    Date today
  ) {
    if (p.Charge_Interest__c != true || inv.Due_Date__c == null) {
      return 0;
    }
    Decimal rate = annualRate(p);
    if (rate <= 0) {
      return 0;
    }
    Date fromDate = inv.Interest_Through__c != null &&
      inv.Interest_Through__c > inv.Due_Date__c
      ? inv.Interest_Through__c
      : inv.Due_Date__c;
    Integer days = fromDate.daysBetween(today);
    Decimal principal = nz(inv.Balance__c) - nz(dunningCharges);
    if (days <= 0 || principal <= 0) {
      return 0;
    }
    return (principal *
      rate /
      100 *
      days /
      365)
      .setScale(2, RoundingMode.HALF_UP);
  }

  /** Fees and interest already on each invoice (Late Fee charges, gross). */
  public static Map<Id, Decimal> dunningCharges(Set<Id> invoiceIds) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    for (PMS_Charge__c c : [
      SELECT Invoice__c, Quantity__c, Unit_Price__c, Tax_Rate__c
      FROM PMS_Charge__c
      WHERE
        Invoice__c IN :invoiceIds
        AND Charge_Type__c = 'Late Fee'
        AND Status__c != 'Void'
    ]) {
      Decimal n = nz(c.Quantity__c) * nz(c.Unit_Price__c);
      Decimal gross = n + n * nz(c.Tax_Rate__c) / 100;
      result.put(
        c.Invoice__c,
        (result.containsKey(c.Invoice__c) ? result.get(c.Invoice__c) : 0) +
        gross
      );
    }
    return result;
  }

  // ---------------------------------------------------------------- unit of work

  public class PlanBuild {
    public PMS_Payment_Plan__c plan;
    public List<PMS_Payment_Plan_Instalment__c> instalments = new List<PMS_Payment_Plan_Instalment__c>();
  }

  public class Run {
    public List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
    public Map<Id, PMS_Invoice__c> invoices = new Map<Id, PMS_Invoice__c>();
    public List<PMS_Dunning_Event__c> events = new List<PMS_Dunning_Event__c>();
    public List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    public List<Task> tasks = new List<Task>();
    public List<PlanBuild> newPlans = new List<PlanBuild>();
    public Map<Id, PMS_Payment_Plan__c> planUpdates = new Map<Id, PMS_Payment_Plan__c>();
    public List<PMS_Payment_Plan_Instalment__c> instalmentUpdates = new List<PMS_Payment_Plan_Instalment__c>();
    public List<String> results = new List<String>();

    public PMS_Invoice__c invoice(Id invoiceId) {
      if (!invoices.containsKey(invoiceId)) {
        invoices.put(invoiceId, new PMS_Invoice__c(Id = invoiceId));
      }
      return invoices.get(invoiceId);
    }

    public void commitWork() {
      if (!charges.isEmpty()) {
        insert charges; // the charge trigger recalculates invoice totals and status
      }
      if (!newPlans.isEmpty()) {
        List<PMS_Payment_Plan__c> plans = new List<PMS_Payment_Plan__c>();
        for (PlanBuild b : newPlans) {
          plans.add(b.plan);
        }
        insert plans;
        List<PMS_Payment_Plan_Instalment__c> items = new List<PMS_Payment_Plan_Instalment__c>();
        for (PlanBuild b : newPlans) {
          for (PMS_Payment_Plan_Instalment__c i : b.instalments) {
            i.Plan__c = b.plan.Id;
            items.add(i);
          }
        }
        insert items;
      }
      if (!planUpdates.isEmpty()) {
        update planUpdates.values();
      }
      if (!instalmentUpdates.isEmpty()) {
        update instalmentUpdates;
      }
      if (!invoices.isEmpty()) {
        update invoices.values();
      }
      if (!events.isEmpty()) {
        insert events;
      }
      if (!tasks.isEmpty()) {
        insert tasks;
      }
      if (!emails.isEmpty()) {
        try {
          Messaging.sendEmail(emails, false);
        } catch (Exception e) {
          System.debug(
            LoggingLevel.WARN,
            'Dunning emails not sent: ' + e.getMessage()
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------- the run

  /** Runs dunning for the given invoices. Returns one line per invoice that got a step. */
  public static List<String> process(
    Set<Id> invoiceIds,
    Date today,
    Boolean force
  ) {
    List<PMS_Invoice__c> invoices = load(invoiceIds);
    Map<Id, PMS_Dunning_Policy__c> policies = policiesFor(invoices);
    Map<Id, Decimal> charged = dunningCharges(invoiceIds);
    Map<Id, PMS_Payment_Plan__c> plans = openPlans(invoiceIds);
    Run run = new Run();
    for (PMS_Invoice__c inv : invoices) {
      PMS_Dunning_Policy__c p = policies.get(inv.Id);
      if (
        (inv.Status__c == 'Issued' ||
        inv.Status__c == 'Partially Paid') &&
        inv.Due_Date__c != null &&
        inv.Due_Date__c < today &&
        nz(inv.Balance__c) > 0
      ) {
        run.invoice(inv.Id).Status__c = 'Overdue';
      }
      if (p == null || inv.Dunning_Paused__c == true) {
        continue;
      }
      PMS_Payment_Plan__c plan = plans.get(inv.Id);
      if (plan != null && monitorPlan(inv, p, plan, today, run)) {
        continue; // an open plan is running; no reminders meanwhile
      }
      String step = nextStep(inv, p, today, force);
      if (step != null) {
        apply(inv, p, step, charged.get(inv.Id), today, run, null);
      }
    }
    run.commitWork();
    return run.results;
  }

  /** Takes one step on one invoice. instalmentsOverride sets the plan length when staff offer a plan. */
  public static void apply(
    PMS_Invoice__c inv,
    PMS_Dunning_Policy__c p,
    String step,
    Decimal alreadyCharged,
    Date today,
    Run run,
    Integer instalmentsOverride
  ) {
    Integer days = inv.Due_Date__c.daysBetween(today);
    String cur = currencyOf(inv);
    Boolean business = isBusiness(inv);
    Decimal fee = feeFor(inv, p);
    Decimal interest = step == R1
      ? 0
      : interestFor(inv, p, alreadyCharged, today);
    PMS_Invoice__c u = run.invoice(inv.Id);
    if (fee > 0) {
      run.charges.add(
        lateCharge(
          inv,
          fee,
          business
            ? 'Late payment compensation (förseningsersättning)'
            : 'Reminder fee (påminnelseavgift)'
        )
      );
    }
    u.Late_Fee_Posted__c = true; // decided once per invoice, even when no fee applies
    if (interest > 0) {
      Date fromDate = inv.Interest_Through__c != null &&
        inv.Interest_Through__c > inv.Due_Date__c
        ? inv.Interest_Through__c
        : inv.Due_Date__c;
      run.charges.add(
        lateCharge(
          inv,
          interest,
          'Late payment interest ' +
            annualRate(p).setScale(2) +
            '% p.a., ' +
            fromDate.addDays(1).format() +
            ' - ' +
            today.format()
        )
      );
      u.Interest_Through__c = today;
    }
    Decimal balance = nz(inv.Balance__c) + fee + interest;
    String key = String.isBlank(inv.Pay_Key__c) ? newKey() : inv.Pay_Key__c;
    u.Pay_Key__c = key;
    u.Dunning_Stage__c = step;
    u.Dunning_Last_Sent_At__c = Datetime.now();

    PlanBuild pb;
    if (step == OFFER) {
      Integer n = instalmentsOverride != null
        ? instalmentsOverride
        : (p.Plan_Instalments__c == null
            ? 3
            : p.Plan_Instalments__c.intValue());
      pb = buildPlan(inv, balance, Math.max(2, Math.min(n, 24)), today);
      run.newPlans.add(pb);
    }
    if (step == COLL) {
      for (PMS_Payment_Plan__c old : [
        SELECT Id
        FROM PMS_Payment_Plan__c
        WHERE Invoice__c = :inv.Id AND Status__c = 'Proposed'
      ]) {
        run.planUpdates.put(
          old.Id,
          new PMS_Payment_Plan__c(Id = old.Id, Status__c = 'Cancelled')
        );
      }
      run.tasks.addAll(collectionTasks(inv, balance, cur));
    }

    List<String> to = recipients(inv);
    String link = payUrl(inv.Id, key);
    if (!to.isEmpty()) {
      run.emails.add(
        PMS_DunningLetters.letter(
          step,
          inv,
          p,
          to,
          balance,
          fee,
          interest,
          days,
          link,
          pb,
          today,
          cur
        )
      );
    }
    if (step == COLL && String.isNotBlank(p.Collections_Agency_Email__c)) {
      run.emails.add(
        PMS_DunningLetters.agencyEmail(inv, p, balance, days, cur, to)
      );
    }
    String note = to.isEmpty()
      ? 'No email address on file: send this letter by post.'
      : null;
    if (
      step == COLL &&
      inv.Booking__r != null &&
      inv.Booking__r.Lease_Type__c == 'Residential'
    ) {
      note =
        (note == null ? '' : note + ' ') +
        'Residential lease: see the termination task before taking further steps.';
    }
    run.events.add(
      new PMS_Dunning_Event__c(
        Invoice__c = inv.Id,
        Stage__c = step,
        Sent_At__c = Datetime.now(),
        Sent_To__c = cut(String.join(to, ', '), 255),
        Days_Overdue__c = days,
        Balance__c = balance,
        Fee_Posted__c = fee,
        Interest_Posted__c = interest,
        Note__c = cut(note, 255)
      )
    );
    run.results.add(inv.Name + ': ' + step);
  }

  // ---------------------------------------------------------------- payment plans

  public static Map<Id, PMS_Payment_Plan__c> openPlans(Set<Id> invoiceIds) {
    Map<Id, PMS_Payment_Plan__c> result = new Map<Id, PMS_Payment_Plan__c>();
    for (PMS_Payment_Plan__c p : [
      SELECT
        Id,
        Name,
        Invoice__c,
        Status__c,
        Total__c,
        Paid_At_Start__c,
        Accepted_At__c,
        (
          SELECT Id, Number__c, Due_Date__c, Amount__c, Status__c
          FROM Instalments__r
          ORDER BY Number__c
        )
      FROM PMS_Payment_Plan__c
      WHERE Invoice__c IN :invoiceIds AND Status__c IN :OPEN_PLAN
      ORDER BY CreatedDate DESC
    ]) {
      if (!result.containsKey(p.Invoice__c)) {
        result.put(p.Invoice__c, p);
      }
    }
    return result;
  }

  public static PlanBuild buildPlan(
    PMS_Invoice__c inv,
    Decimal total,
    Integer n,
    Date today
  ) {
    PlanBuild b = new PlanBuild();
    b.plan = new PMS_Payment_Plan__c(
      Invoice__c = inv.Id,
      Account__c = inv.Account__c,
      Status__c = 'Proposed',
      Total__c = total,
      Paid_At_Start__c = nz(inv.Amount_Paid__c)
    );
    copyCurrency(inv, b.plan);
    Decimal each = (total / n).setScale(0, RoundingMode.DOWN);
    Decimal allocated = 0;
    for (Integer i = 1; i <= n; i++) {
      Decimal amount = i == n ? total - allocated : each;
      allocated += amount;
      PMS_Payment_Plan_Instalment__c item = new PMS_Payment_Plan_Instalment__c(
        Number__c = i,
        Due_Date__c = today.addDays(14).addMonths(i - 1),
        Amount__c = amount,
        Status__c = 'Due'
      );
      copyCurrency(inv, item);
      b.instalments.add(item);
    }
    return b;
  }

  /** Amount paid toward the plan so far (payments on the invoice since the plan was made). */
  public static Decimal paidTowardPlan(
    PMS_Invoice__c inv,
    PMS_Payment_Plan__c plan
  ) {
    return nz(inv.Amount_Paid__c) - nz(plan.Paid_At_Start__c);
  }

  /** What the guest should pay now on a plan: the first unpaid instalment, less anything paid toward it. */
  public static Decimal nextInstalmentAmount(
    PMS_Invoice__c inv,
    PMS_Payment_Plan__c plan
  ) {
    Decimal paid = paidTowardPlan(inv, plan);
    Decimal cumulative = 0;
    for (PMS_Payment_Plan_Instalment__c i : plan.Instalments__r) {
      cumulative += nz(i.Amount__c);
      if (paid < cumulative - 0.005) {
        return Math.min(cumulative - paid, nz(inv.Balance__c));
      }
    }
    return nz(inv.Balance__c);
  }

  /**
   * Keeps instalment statuses current and moves the plan on. Returns true while the plan keeps
   * reminders on hold (Proposed and not lapsed, or Active and on track).
   */
  public static Boolean monitorPlan(
    PMS_Invoice__c inv,
    PMS_Dunning_Policy__c p,
    PMS_Payment_Plan__c plan,
    Date today,
    Run run
  ) {
    Decimal paid = paidTowardPlan(inv, plan);
    Integer grace = p == null ||
      p.Plan_Grace_Days__c == null
      ? 10
      : p.Plan_Grace_Days__c.intValue();
    Decimal cumulative = 0;
    Boolean late = false;
    Decimal firstAmount = null;
    for (PMS_Payment_Plan_Instalment__c i : plan.Instalments__r) {
      cumulative += nz(i.Amount__c);
      if (firstAmount == null) {
        firstAmount = nz(i.Amount__c);
      }
      String status = paid >= cumulative - 0.005
        ? 'Paid'
        : (i.Due_Date__c < today ? 'Overdue' : 'Due');
      if (status != i.Status__c) {
        run.instalmentUpdates.add(
          new PMS_Payment_Plan_Instalment__c(Id = i.Id, Status__c = status)
        );
      }
      if (status == 'Overdue' && i.Due_Date__c.daysBetween(today) > grace) {
        late = true;
      }
    }
    PMS_Invoice__c u = run.invoice(inv.Id);
    if (nz(inv.Balance__c) <= 0) {
      run.planUpdates.put(
        plan.Id,
        new PMS_Payment_Plan__c(Id = plan.Id, Status__c = 'Completed')
      );
      return true;
    }
    if (plan.Status__c == 'Proposed') {
      if (firstAmount != null && paid >= firstAmount - 0.005) {
        run.planUpdates.put(
          plan.Id,
          new PMS_Payment_Plan__c(
            Id = plan.Id,
            Status__c = 'Active',
            Accepted_At__c = Datetime.now()
          )
        );
        u.Dunning_Stage__c = PMS_DunningService.PLAN;
        run.events.add(
          event(
            inv,
            'Plan Accepted',
            'First instalment paid; ' + plan.Name + ' is active.'
          )
        );
        run.results.add(inv.Name + ': plan accepted');
        return true;
      }
      if (late) {
        run.planUpdates.put(
          plan.Id,
          new PMS_Payment_Plan__c(Id = plan.Id, Status__c = 'Cancelled')
        );
        run.events.add(
          event(
            inv,
            'Plan Lapsed',
            'The first instalment of ' +
              plan.Name +
              ' was not paid; the offer lapsed.'
          )
        );
        return false; // reminders resume (next: collections when due)
      }
      return true;
    }
    if (late) {
      run.planUpdates.put(
        plan.Id,
        new PMS_Payment_Plan__c(Id = plan.Id, Status__c = 'Broken')
      );
      u.Dunning_Stage__c = OFFER;
      u.Dunning_Last_Sent_At__c = null; // so collections can run straight away
      run.events.add(
        event(
          inv,
          'Plan Broken',
          'An instalment of ' +
            plan.Name +
            ' is more than ' +
            grace +
            ' days late.'
        )
      );
      run.results.add(inv.Name + ': plan broken');
      return true; // collections on the next run
    }
    return true;
  }

  // ---------------------------------------------------------------- building blocks

  public static List<Task> collectionTasks(
    PMS_Invoice__c inv,
    Decimal balance,
    String cur
  ) {
    Id owner = taskOwner(inv);
    String url = URL.getOrgDomainURL().toExternalForm() + '/' + inv.Id;
    List<Task> tasks = new List<Task>{
      new Task(
        OwnerId = owner,
        Subject = cut(
          'Hand over ' +
            inv.Name +
            ' to collections (' +
            balance.setScale(2) +
            ' ' +
            cur +
            ')',
          255
        ),
        ActivityDate = Date.today().addDays(2),
        Priority = 'High',
        Status = 'Not Started',
        Description = 'Customer: ' +
          (inv.Account__r == null ? '' : inv.Account__r.Name) +
          '\nInvoice: ' +
          inv.Name +
          ', due ' +
          inv.Due_Date__c.format() +
          '\nOwed now: ' +
          balance.setScale(2) +
          ' ' +
          cur +
          '\nReminders and fees are listed under Dunning Events on the invoice.' +
          '\n' +
          url
      )
    };
    if (
      inv.Booking__r != null &&
      inv.Booking__r.Lease_Type__c == 'Residential'
    ) {
      tasks.add(
        new Task(
          OwnerId = owner,
          Subject = cut(
            'Unpaid rent ' + inv.Name + ': decide on termination',
            255
          ),
          ActivityDate = Date.today().addDays(5),
          Priority = 'High',
          Status = 'Not Started',
          Description = 'Residential lease ' +
            inv.Booking__r.Name +
            '. Nothing has been sent beyond the reminders. ' +
            'If you intend to terminate the lease for unpaid rent (Jordabalken 12 kap. 42-44 §§):' +
            '\n1. The tenant must first have been asked to pay (the reminders) and still not paid.' +
            '\n2. Serve the termination with the notice that the tenancy can be regained by paying (form 1), by formal service (delgivning).' +
            '\n3. Send notice of the termination and the reason to socialnämnden in the municipality, on form 3 (registered letter).' +
            '\n4. The tenant can regain the tenancy by paying within three weeks of service.' +
            '\nCheck the details with your lawyer or Fastighetsägarna before acting.' +
            '\n' +
            url
        )
      );
    }
    return tasks;
  }

  private static Id taskOwner(PMS_Invoice__c inv) {
    if (
      inv.Booking__r != null &&
      inv.Booking__r.Site__r != null &&
      inv.Booking__r.Site__r.Manager__c != null
    ) {
      return inv.Booking__r.Site__r.Manager__c;
    }
    if (inv.OwnerId != null && String.valueOf(inv.OwnerId).startsWith('005')) {
      return inv.OwnerId;
    }
    return UserInfo.getUserId();
  }

  public static PMS_Dunning_Event__c event(
    PMS_Invoice__c inv,
    String step,
    String note
  ) {
    return new PMS_Dunning_Event__c(
      Invoice__c = inv.Id,
      Stage__c = step,
      Sent_At__c = Datetime.now(),
      Days_Overdue__c = inv.Due_Date__c == null
        ? null
        : inv.Due_Date__c.daysBetween(Date.today()),
      Balance__c = inv.Balance__c,
      Fee_Posted__c = 0,
      Interest_Posted__c = 0,
      Note__c = cut(note, 255)
    );
  }

  private static PMS_Charge__c lateCharge(
    PMS_Invoice__c inv,
    Decimal amount,
    String description
  ) {
    PMS_Charge__c c = new PMS_Charge__c(
      Invoice__c = inv.Id,
      Booking__c = inv.Booking__c,
      Account__c = inv.Account__c,
      Charge_Type__c = 'Late Fee',
      Description__c = cut(description, 255),
      Quantity__c = 1,
      Unit_Price__c = amount,
      Tax_Rate__c = 0,
      Service_Date__c = Date.today(),
      Status__c = 'Invoiced'
    );
    copyCurrency(inv, c);
    return c;
  }

  /** Booking contact first, then the account's contacts, then its portal users. */
  public static List<String> recipients(PMS_Invoice__c inv) {
    List<String> to = new List<String>();
    if (
      inv.Booking__r != null &&
      inv.Booking__r.Primary_Contact__r != null &&
      String.isNotBlank(inv.Booking__r.Primary_Contact__r.Email)
    ) {
      to.add(inv.Booking__r.Primary_Contact__r.Email);
      return to;
    }
    if (inv.Account__c != null) {
      for (Contact c : [
        SELECT Email
        FROM Contact
        WHERE AccountId = :inv.Account__c AND Email != NULL
        ORDER BY CreatedDate
        LIMIT 2
      ]) {
        to.add(c.Email);
      }
      if (to.isEmpty()) {
        to.addAll(PMS_CustomerNotifications.portalEmails(inv.Account__c));
      }
    }
    return to;
  }

  public static String payUrl(Id invoiceId, String key) {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    String base = s == null ? null : s.Public_Pay_URL__c;
    if (String.isBlank(base)) {
      return null;
    }
    return base.removeEnd('/') +
      '/services/apexrest/pms/pay?i=' +
      invoiceId +
      '&k=' +
      key;
  }

  public static String newKey() {
    return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
  }

  public static String currencyOf(PMS_Invoice__c inv) {
    return String.isBlank(inv.Currency_Code__c)
      ? UserInfo.getDefaultCurrency()
      : inv.Currency_Code__c.toUpperCase();
  }

  public static void copyCurrency(PMS_Invoice__c inv, SObject target) {
    if (!UserInfo.isMultiCurrencyOrganization()) {
      return;
    }
    try {
      Object iso = inv.get('CurrencyIsoCode');
      if (iso != null) {
        target.put('CurrencyIsoCode', iso);
      }
    } catch (SObjectException e) {
      // not queried: the record keeps the running user's currency
    }
  }

  public static Decimal nz(Decimal d) {
    return d == null ? 0 : d;
  }

  public static String cut(String s, Integer max) {
    if (s == null) {
      return null;
    }
    return s.length() <= max ? s : s.left(max - 3) + '...';
  }
}
