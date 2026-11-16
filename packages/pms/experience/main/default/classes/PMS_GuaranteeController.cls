/**
 * Booking page panel "Card & Deposit" (LWC pmsBookingGuarantee).
 * Staff see the policy, the saved card, deposit and hold, and can send or copy the card link, charge
 * the deposit, place / capture / release a hold, or apply the cancellation policy.
 * Every action first checks that the user can see the booking (user mode), then runs the shared
 * service, which makes its Stripe calls before saving anything.
 */
public with sharing class PMS_GuaranteeController {
  public class State {
    @AuraEnabled
    public String bookingName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Boolean hasPolicy = false;
    @AuraEnabled
    public String policyName;
    @AuraEnabled
    public String method;
    @AuraEnabled
    public String terms;
    @AuraEnabled
    public Decimal guaranteeAmount;
    @AuraEnabled
    public Decimal freeHours;
    @AuraEnabled
    public Decimal lateFee;
    @AuraEnabled
    public Decimal noShowFee;
    @AuraEnabled
    public Boolean autoCharge = false;
    @AuraEnabled
    public String guaranteeStatus;
    @AuraEnabled
    public Boolean hasCard = false;
    @AuraEnabled
    public String cardBrand;
    @AuraEnabled
    public String cardLast4;
    @AuraEnabled
    public String cardExpiry;
    @AuraEnabled
    public Datetime cardSavedAt;
    @AuraEnabled
    public Datetime linkSentAt;
    @AuraEnabled
    public String contactEmail;
    @AuraEnabled
    public Decimal depositPaid;
    @AuraEnabled
    public String holdStatus;
    @AuraEnabled
    public Decimal holdAmount;
    @AuraEnabled
    public Datetime holdExpires;
    @AuraEnabled
    public Boolean policyApplied = false;
    @AuraEnabled
    public Boolean policyPending = false;
    @AuraEnabled
    public Decimal policyFee;
    @AuraEnabled
    public Decimal refundDue;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Boolean closed = false;
    @AuraEnabled
    public Boolean canSendLink = false;
    @AuraEnabled
    public Boolean canChargeDeposit = false;
    @AuraEnabled
    public Boolean canPlaceHold = false;
    @AuraEnabled
    public Boolean canCaptureHold = false;
    @AuraEnabled
    public Boolean canApplyPolicy = false;
  }

  @AuraEnabled
  public static State getState(Id bookingId) {
    try {
      PMS_Booking__c b = load(bookingId);
      if (
        String.isNotBlank(b.Stripe_Payment_Method__c) &&
        String.isBlank(b.Card_Last4__c)
      ) {
        try {
          PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
          PMS_GuaranteeService.refreshCard(b, w);
          w.commitWork();
          b = PMS_PolicyService.loadOne(bookingId);
        } catch (Exception e) {
          System.debug(
            LoggingLevel.WARN,
            'Card details not refreshed: ' + e.getMessage()
          );
        }
      }
      return state(b);
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static PMS_GuaranteeService.LinkResult sendLink(
    Id bookingId,
    Boolean email
  ) {
    try {
      PMS_Booking__c b = load(bookingId);
      PMS_Payment_Policy__c p = PMS_PolicyService.policyFor(b);
      PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
      PMS_GuaranteeService.LinkResult r = PMS_GuaranteeService.createLink(
        b,
        p,
        w
      );
      if (email == true && !PMS_GuaranteeService.queueLinkEmail(b, p, r, w)) {
        w.booking(b.Id)
          .Guarantee_Message__c = 'The guest has no email address; the link was not emailed.';
      }
      w.commitWork();
      return r;
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static State chargeDeposit(Id bookingId) {
    try {
      PMS_Booking__c b = load(bookingId);
      PMS_Payment_Policy__c p = requirePolicy(b);
      PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
      PMS_GuaranteeService.chargeDeposit(
        b,
        p,
        PMS_PolicyService.unappliedCredit(new Set<Id>{ b.Id }).get(b.Id),
        w
      );
      w.commitWork();
      return state(PMS_PolicyService.loadOne(bookingId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static State placeHold(Id bookingId) {
    try {
      PMS_Booking__c b = load(bookingId);
      if (b.Preauth_Status__c == 'Authorized') {
        throw new PMS_Exception(
          'A hold is already in place. Release it first.'
        );
      }
      PMS_Payment_Policy__c p = requirePolicy(b);
      PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
      PMS_GuaranteeService.placeHoldFor(b, p, w);
      w.commitWork();
      return state(PMS_PolicyService.loadOne(bookingId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  /** Captures the given amount from the hold (the rest is released); 0 or blank releases it all. */
  @AuraEnabled
  public static State captureHold(Id bookingId, Decimal amount) {
    try {
      PMS_Booking__c b = load(bookingId);
      if (b.Preauth_Status__c != 'Authorized') {
        throw new PMS_Exception('There is no open hold on this booking.');
      }
      PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
      if (amount == null || amount <= 0) {
        PMS_GuaranteeService.settleHold(b, 0, null, w);
      } else {
        if (b.Preauth_Amount__c != null && amount > b.Preauth_Amount__c) {
          throw new PMS_Exception(
            'You can capture at most the held amount (' +
              b.Preauth_Amount__c.setScale(2) +
              ').'
          );
        }
        List<PMS_Invoice__c> open = [
          SELECT Id
          FROM PMS_Invoice__c
          WHERE
            Booking__c = :b.Id
            AND Balance__c > 0
            AND Status__c NOT IN ('Void', 'Credited', 'Draft')
          ORDER BY Balance__c DESC
          LIMIT 1
        ];
        PMS_GuaranteeService.settleHold(
          b,
          amount,
          open.isEmpty() ? null : open[0].Id,
          w
        );
      }
      w.commitWork();
      return state(PMS_PolicyService.loadOne(bookingId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  /** Applies the cancellation / no-show policy now, for a booking that is already Cancelled or No Show. */
  @AuraEnabled
  public static State applyPolicyNow(Id bookingId) {
    try {
      PMS_Booking__c b = load(bookingId);
      if (b.Status__c != 'Cancelled' && b.Status__c != 'No Show') {
        throw new PMS_Exception(
          'Set the booking to Cancelled or No Show first.'
        );
      }
      if (b.Policy_Fee_Charged__c == true) {
        throw new PMS_Exception(
          'The policy has already been applied to this booking.'
        );
      }
      PMS_Payment_Policy__c p = requirePolicy(b);
      if (b.Policy_Event_At__c == null) {
        b.Policy_Event_At__c = Datetime.now();
      }
      PMS_GuaranteeService.Work w = new PMS_GuaranteeService.Work();
      w.booking(b.Id).Policy_Event_At__c = b.Policy_Event_At__c;
      PMS_GuaranteeService.applyPolicy(
        b,
        p,
        PMS_PolicyService.unappliedCredit(new Set<Id>{ b.Id }).get(b.Id),
        w
      );
      w.commitWork();
      return state(PMS_PolicyService.loadOne(bookingId));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  // ---------------------------------------------------------------- helpers

  private static PMS_Booking__c load(Id bookingId) {
    List<PMS_Booking__c> visible = [
      SELECT Id
      FROM PMS_Booking__c
      WHERE Id = :bookingId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visible.isEmpty()) {
      throw new PMS_Exception(
        'Booking not found, or you do not have access to it.'
      );
    }
    return PMS_PolicyService.loadOne(bookingId);
  }

  private static PMS_Payment_Policy__c requirePolicy(PMS_Booking__c b) {
    PMS_Payment_Policy__c p = PMS_PolicyService.policyFor(b);
    if (p == null) {
      throw new PMS_Exception(
        'No active payment policy applies to this booking. Set one on the booking, rate plan, service or site.'
      );
    }
    return p;
  }

  @TestVisible
  private static State state(PMS_Booking__c b) {
    PMS_Payment_Policy__c p = PMS_PolicyService.policyFor(b);
    State s = new State();
    s.bookingName = b.Name;
    s.status = b.Status__c;
    s.currencyCode = PMS_PolicyService.currencyOf(b);
    s.closed = PMS_GuaranteeService.CLOSED.contains(b.Status__c);
    s.guaranteeStatus = b.Guarantee_Status__c;
    s.hasCard = String.isNotBlank(b.Stripe_Payment_Method__c);
    s.cardBrand = b.Card_Brand__c;
    s.cardLast4 = b.Card_Last4__c;
    s.cardExpiry = b.Card_Expiry__c;
    s.cardSavedAt = b.Card_Saved_At__c;
    s.linkSentAt = b.Card_Link_Sent_At__c;
    s.contactEmail = b.Primary_Contact__r == null
      ? null
      : b.Primary_Contact__r.Email;
    s.holdStatus = b.Preauth_Status__c;
    s.holdAmount = b.Preauth_Amount__c;
    s.holdExpires = b.Preauth_Expires_At__c;
    s.policyApplied = b.Policy_Fee_Charged__c == true;
    s.policyPending = b.Policy_Pending__c == true;
    s.policyFee = b.Policy_Fee_Amount__c;
    s.refundDue = b.Refund_Due__c;
    s.message = b.Guarantee_Message__c;
    Decimal credit = PMS_PolicyService.unappliedCredit(new Set<Id>{ b.Id })
      .get(b.Id);
    s.depositPaid = credit == null ? 0 : credit;
    if (p != null) {
      s.hasPolicy = true;
      s.policyName = p.Name;
      s.method = PMS_PolicyService.method(p);
      s.terms = p.Guest_Terms__c;
      s.guaranteeAmount = PMS_PolicyService.guaranteeAmount(b, p);
      s.freeHours = p.Free_Cancellation_Hours__c;
      s.lateFee = PMS_PolicyService.amountFor(
        p.Late_Cancel_Basis__c,
        p.Late_Cancel_Value__c,
        b
      );
      s.noShowFee = PMS_PolicyService.amountFor(
        p.No_Show_Basis__c,
        p.No_Show_Value__c,
        b
      );
      s.autoCharge = p.Auto_Charge_Fees__c == true;
      Boolean needsCard = s.method != PMS_PolicyService.M_NONE;
      s.canSendLink = needsCard && !s.closed;
      s.canChargeDeposit =
        !s.closed &&
        s.hasCard &&
        b.Guarantee_Status__c != 'Deposit Paid' &&
        (s.method == PMS_PolicyService.M_DEPOSIT ||
        s.method == PMS_PolicyService.M_PREPAID);
      s.canPlaceHold =
        !s.closed &&
        s.hasCard &&
        b.Preauth_Status__c != 'Authorized';
      s.canApplyPolicy =
        (b.Status__c == 'Cancelled' ||
        b.Status__c == 'No Show') &&
        !s.policyApplied &&
        !s.policyPending;
    }
    s.canCaptureHold = b.Preauth_Status__c == 'Authorized';
    return s;
  }

  private static AuraHandledException fail(Exception e) {
    String msg = e.getMessage();
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    return ex;
  }
}
