/**
 * Payment policy rules, with no callouts: which policy applies to a booking, how big the deposit
 * or card hold is, and what a late cancellation or no-show costs.
 *
 * The policy is taken from the first of: the booking, its rate plan, its service, its site.
 * An inactive policy means "no policy".
 *
 * Fee and deposit bases:
 *   First Night       total / nights (for stays), else the booking total (appointments)
 *   Percent of Total  total x value %
 *   Fixed Amount      value
 *   Full Stay         total
 * No amount is ever larger than the booking total (when the total is known).
 */
public without sharing class PMS_PolicyService {
  public static final String M_NONE = 'None';
  public static final String M_CARD = 'Card on File';
  public static final String M_PREAUTH = 'Pre-authorisation';
  public static final String M_DEPOSIT = 'Deposit';
  public static final String M_PREPAID = 'Prepaid';

  public static final String BOOKING_FIELDS =
    'Id, Name, Status__c, Start__c, End__c, CreatedDate, Account__c, Account__r.Name, Account__r.Stripe_Customer_Id__c, ' +
    'Primary_Contact__c, Primary_Contact__r.Email, Primary_Contact__r.FirstName, Primary_Contact__r.Name, ' +
    'Rate_Amount__c, Total_Amount__c, Amount_Paid__c, Nights__c, Channel__c, Guarantee__c, RecordTypeId, ' +
    'Site__c, Site__r.Name, Site__r.Currency_Code__c, Site__r.Payment_Policy__c, ' +
    'Rate_Plan__c, Rate_Plan__r.Payment_Policy__c, Service__c, Service__r.Payment_Policy__c, Payment_Policy__c, ' +
    'Guarantee_Status__c, Stripe_Payment_Method__c, Card_Brand__c, Card_Last4__c, Card_Expiry__c, Card_Saved_At__c, ' +
    'Card_Link_Sent_At__c, Setup_Intent_Id__c, Preauth_Intent_Id__c, Preauth_Amount__c, Preauth_Status__c, ' +
    'Preauth_Expires_At__c, Policy_Fee_Charged__c, Policy_Fee_Amount__c, Policy_Pending__c, Policy_Event_At__c, ' +
    'Refund_Due__c, Guarantee_Message__c';

  public static final String POLICY_FIELDS =
    'Id, Name, Active__c, Guarantee_Method__c, Deposit_Basis__c, Deposit_Value__c, Deposit_Due_Days__c, ' +
    'Preauth_Hours_Before__c, Free_Cancellation_Hours__c, Late_Cancel_Basis__c, Late_Cancel_Value__c, ' +
    'No_Show_Basis__c, No_Show_Value__c, Fee_Tax_Rate__c, Auto_Charge_Fees__c, Auto_Send_Card_Link__c, ' +
    'Release_Hold_On_Checkout__c, Guest_Terms__c';

  /** BOOKING_FIELDS plus CurrencyIsoCode when the org uses multiple currencies. */
  public static String bookingFields() {
    return BOOKING_FIELDS +
      (UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '');
  }

  public static List<PMS_Booking__c> load(Set<Id> ids) {
    return Database.query(
      'SELECT ' + bookingFields() + ' FROM PMS_Booking__c WHERE Id IN :ids'
    );
  }

  public static PMS_Booking__c loadOne(Id bookingId) {
    List<PMS_Booking__c> bs = load(new Set<Id>{ bookingId });
    if (bs.isEmpty()) {
      throw new PMS_Exception('Booking not found.');
    }
    return bs[0];
  }

  public static Id policyId(PMS_Booking__c b) {
    if (b.Payment_Policy__c != null) {
      return b.Payment_Policy__c;
    }
    if (b.Rate_Plan__r != null && b.Rate_Plan__r.Payment_Policy__c != null) {
      return b.Rate_Plan__r.Payment_Policy__c;
    }
    if (b.Service__r != null && b.Service__r.Payment_Policy__c != null) {
      return b.Service__r.Payment_Policy__c;
    }
    if (b.Site__r != null && b.Site__r.Payment_Policy__c != null) {
      return b.Site__r.Payment_Policy__c;
    }
    return null;
  }

  /** Booking Id -> its active policy. Bookings without one are left out. */
  public static Map<Id, PMS_Payment_Policy__c> policiesFor(
    List<PMS_Booking__c> bookings
  ) {
    Map<Id, Id> policyByBooking = new Map<Id, Id>();
    for (PMS_Booking__c b : bookings) {
      Id pid = policyId(b);
      if (pid != null) {
        policyByBooking.put(b.Id, pid);
      }
    }
    Map<Id, PMS_Payment_Policy__c> result = new Map<Id, PMS_Payment_Policy__c>();
    if (policyByBooking.isEmpty()) {
      return result;
    }
    Set<Id> policyIds = new Set<Id>(policyByBooking.values());
    Map<Id, PMS_Payment_Policy__c> policies = new Map<Id, PMS_Payment_Policy__c>(
      (List<PMS_Payment_Policy__c>) Database.query(
        'SELECT ' +
          POLICY_FIELDS +
          ' FROM PMS_Payment_Policy__c WHERE Id IN :policyIds AND Active__c = true'
      )
    );
    for (Id bookingId : policyByBooking.keySet()) {
      PMS_Payment_Policy__c p = policies.get(policyByBooking.get(bookingId));
      if (p != null) {
        result.put(bookingId, p);
      }
    }
    return result;
  }

  public static PMS_Payment_Policy__c policyFor(PMS_Booking__c b) {
    return policiesFor(new List<PMS_Booking__c>{ b }).get(b.Id);
  }

  public static String method(PMS_Payment_Policy__c p) {
    return p == null || String.isBlank(p.Guarantee_Method__c)
      ? M_NONE
      : p.Guarantee_Method__c;
  }

  /** Stripe currency for the booking: the site's currency, else the booking's record currency. */
  public static String currencyOf(PMS_Booking__c b) {
    String c = b.Site__r == null ? null : b.Site__r.Currency_Code__c;
    if (String.isBlank(c) && UserInfo.isMultiCurrencyOrganization()) {
      try {
        c = (String) b.get('CurrencyIsoCode');
      } catch (SObjectException e) {
        c = null;
      }
    }
    return String.isBlank(c) ? UserInfo.getDefaultCurrency() : c.toUpperCase();
  }

  // ---------------------------------------------------------------- amounts

  public static Decimal amountFor(
    String basis,
    Decimal value,
    PMS_Booking__c b
  ) {
    if (String.isBlank(basis) || basis == 'None') {
      return 0;
    }
    Decimal total = b.Total_Amount__c == null ? 0 : b.Total_Amount__c;
    Decimal v = value == null ? 0 : value;
    Decimal result;
    switch on basis {
      when 'First Night' {
        result = firstNight(b);
      }
      when 'Percent of Total' {
        result = total * v / 100;
      }
      when 'Fixed Amount' {
        result = v;
      }
      when 'Full Stay' {
        result = total;
      }
      when else {
        result = 0;
      }
    }
    if (total > 0 && result > total) {
      result = total;
    }
    return result < 0 ? 0 : result.setScale(2, RoundingMode.HALF_UP);
  }

  public static Decimal firstNight(PMS_Booking__c b) {
    Decimal total = b.Total_Amount__c == null ? 0 : b.Total_Amount__c;
    if (total > 0 && b.Nights__c != null && b.Nights__c > 0) {
      return total / b.Nights__c;
    }
    if (total > 0) {
      return total;
    }
    return b.Rate_Amount__c == null ? 0 : b.Rate_Amount__c;
  }

  /** Deposit to take (Deposit) or the amount still to prepay (Prepaid); the hold size for Pre-authorisation. */
  public static Decimal guaranteeAmount(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p
  ) {
    String m = method(p);
    if (m == M_PREPAID) {
      Decimal total = b.Total_Amount__c == null ? 0 : b.Total_Amount__c;
      Decimal paid = b.Amount_Paid__c == null ? 0 : b.Amount_Paid__c;
      Decimal open = total - paid;
      return open > 0 ? open.setScale(2, RoundingMode.HALF_UP) : 0;
    }
    if (m == M_DEPOSIT || m == M_PREAUTH) {
      return amountFor(p.Deposit_Basis__c, p.Deposit_Value__c, b);
    }
    return 0;
  }

  /** True when the deposit (or prepayment) is due now rather than on a later date. */
  public static Boolean depositDueNow(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Datetime now
  ) {
    Decimal days = p == null ||
      p.Deposit_Due_Days__c == null
      ? 0
      : p.Deposit_Due_Days__c;
    if (days <= 0 || b.Start__c == null) {
      return true;
    }
    return b.Start__c.getTime() - now.getTime() <= days * 86400000L;
  }

  /** True when a pre-authorisation hold should be placed now. */
  public static Boolean holdDueNow(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Datetime now
  ) {
    Decimal hours = p == null ||
      p.Preauth_Hours_Before__c == null
      ? 24
      : p.Preauth_Hours_Before__c;
    if (b.Start__c == null) {
      return false;
    }
    return b.Start__c.getTime() - now.getTime() <= hours * 3600000L;
  }

  // ---------------------------------------------------------------- fees

  public class FeeDecision {
    public String kind; // 'No-show', 'Late cancellation', 'Free cancellation' or null
    public Decimal net = 0; // fee before VAT
    public Decimal taxRate = 0; // percent, e.g. 25
    public Decimal gross = 0; // fee including VAT
    public String reason;
  }

  public static FeeDecision feeFor(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    String status,
    Datetime eventAt
  ) {
    FeeDecision d = new FeeDecision();
    if (p == null) {
      d.reason = 'No payment policy applies.';
      return d;
    }
    if (status == 'No Show') {
      d.kind = 'No-show';
      d.net = amountFor(p.No_Show_Basis__c, p.No_Show_Value__c, b);
      d.reason = 'No-show fee (' + p.No_Show_Basis__c + ').';
    } else if (status == 'Cancelled') {
      Decimal free = p.Free_Cancellation_Hours__c == null
        ? 0
        : p.Free_Cancellation_Hours__c;
      Datetime at = eventAt == null ? Datetime.now() : eventAt;
      Decimal hoursBefore = b.Start__c == null
        ? null
        : Decimal.valueOf(b.Start__c.getTime() - at.getTime()) / 3600000;
      if (hoursBefore != null && hoursBefore >= free) {
        d.kind = 'Free cancellation';
        d.reason =
          'Cancelled ' +
          hoursBefore.setScale(0, RoundingMode.DOWN) +
          ' h before arrival; free up to ' +
          free +
          ' h.';
      } else {
        d.kind = 'Late cancellation';
        d.net = amountFor(p.Late_Cancel_Basis__c, p.Late_Cancel_Value__c, b);
        d.reason =
          'Late cancellation' +
          (hoursBefore == null
            ? ''
            : ' (' +
              hoursBefore.setScale(0, RoundingMode.DOWN) +
              ' h before arrival)') +
          '.';
      }
    } else {
      d.reason = 'Policy fees only apply to cancelled or no-show bookings.';
      return d;
    }
    d.taxRate = p.Fee_Tax_Rate__c == null ? 0 : p.Fee_Tax_Rate__c;
    d.gross = (d.net * (1 + d.taxRate / 100)).setScale(2, RoundingMode.HALF_UP);
    return d;
  }

  // ---------------------------------------------------------------- payments already taken

  /** Succeeded deposits and payments on the booking that are not on an invoice yet, net of deposit returns. */
  public static Map<Id, Decimal> unappliedCredit(Set<Id> bookingIds) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    for (PMS_Payment__c p : [
      SELECT Booking__c, Amount__c, Payment_Type__c
      FROM PMS_Payment__c
      WHERE
        Booking__c IN :bookingIds
        AND Invoice__c = NULL
        AND Status__c = 'Succeeded'
        AND Payment_Type__c IN (
          'Deposit',
          'Payment',
          'Deposit Return',
          'Refund'
        )
    ]) {
      Decimal sign = (p.Payment_Type__c == 'Deposit Return' ||
        p.Payment_Type__c == 'Refund')
        ? -1
        : 1;
      Decimal cur = result.containsKey(p.Booking__c)
        ? result.get(p.Booking__c)
        : 0;
      result.put(
        p.Booking__c,
        cur + sign * (p.Amount__c == null ? 0 : p.Amount__c)
      );
    }
    return result;
  }
}
