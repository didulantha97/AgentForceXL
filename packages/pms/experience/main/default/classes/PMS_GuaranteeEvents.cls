/**
 * Stripe webhook events for card guarantees, called by PMS_StripeWebhook. Makes no callouts (Stripe
 * calls in as the site guest user); card brand and last 4 are filled in later by PMS_GuaranteeJob or
 * when staff open the booking.
 *
 *   setup_intent.succeeded                  card saved on the card page -> booking keeps the pm_ id
 *   payment_intent.succeeded                deposit page with a saved card -> booking keeps the pm_ id;
 *                                           our own off-session charges and captured holds -> Payment
 *   payment_intent.amount_capturable_updated our hold is authorised
 *   payment_intent.canceled                 our hold was released or expired
 *   payment_intent.payment_failed           our charge or hold failed -> Action Needed
 *
 * Only intents created by PMS carry metadata pmsSource = pms-guarantee (or pmsSaveCard = 1 on the
 * deposit page), so ordinary pay-link payments are left to the existing checkout handling.
 */
public without sharing class PMS_GuaranteeEvents {
  private static final Set<String> OPEN_STATUSES = new Set<String>{
    null,
    'Not Required',
    'Awaiting Card',
    'Action Needed'
  };

  public static PMS_Payment__c setupSucceeded(Map<String, Object> si) {
    Map<String, Object> md = PMS_StripeClient.asMap(si.get('metadata'));
    String bookingNumber = PMS_StripeClient.str(md, 'bookingNumber');
    if (
      String.isBlank(bookingNumber) ||
      PMS_StripeClient.str(md, 'pmsSource') != PMS_GuaranteeService.SOURCE
    ) {
      return null;
    }
    PMS_Booking__c b = booking(bookingNumber);
    String pm = idOf(si.get('payment_method'));
    if (b == null || String.isBlank(pm)) {
      return null;
    }
    PMS_Booking__c u = new PMS_Booking__c(
      Id = b.Id,
      Stripe_Payment_Method__c = pm,
      Setup_Intent_Id__c = PMS_StripeClient.str(si, 'id'),
      Card_Saved_At__c = Datetime.now(),
      Card_Brand__c = null,
      Card_Last4__c = null,
      Card_Expiry__c = null,
      Guarantee_Message__c = 'Card saved by the guest.'
    );
    if (OPEN_STATUSES.contains(b.Guarantee_Status__c)) {
      u.Guarantee_Status__c = 'Card Saved';
    }
    if (b.Guarantee__c == null || b.Guarantee__c == 'None') {
      u.Guarantee__c = 'Card on File';
    }
    update u;
    return null;
  }

  public static PMS_Payment__c paymentIntent(
    String eventType,
    Map<String, Object> pi,
    Date received
  ) {
    Map<String, Object> md = PMS_StripeClient.asMap(pi.get('metadata'));
    String bookingNumber = PMS_StripeClient.str(md, 'bookingNumber');
    Boolean ours =
      PMS_StripeClient.str(md, 'pmsSource') == PMS_GuaranteeService.SOURCE;
    Boolean saveCard = PMS_StripeClient.str(md, 'pmsSaveCard') == '1';
    if (String.isBlank(bookingNumber) || (!ours && !saveCard)) {
      return null;
    }
    PMS_Booking__c b = booking(bookingNumber);
    if (b == null) {
      return null;
    }
    String piId = PMS_StripeClient.str(pi, 'id');
    String cur = PMS_StripeClient.str(pi, 'currency');
    String kind = PMS_StripeClient.str(md, 'pmsKind');
    String paymentType = PMS_StripeClient.str(md, 'paymentType');
    PMS_Booking__c u = new PMS_Booking__c(Id = b.Id);
    Boolean changed = false;
    PMS_Payment__c result;

    switch on eventType {
      when 'payment_intent.amount_capturable_updated' {
        if (
          ours &&
          kind == 'hold' &&
          (b.Preauth_Intent_Id__c == null ||
          b.Preauth_Intent_Id__c == piId)
        ) {
          u.Preauth_Intent_Id__c = piId;
          u.Preauth_Status__c = 'Authorized';
          u.Preauth_Amount__c = PMS_StripeClient.toMajor(
            pi.get('amount_capturable'),
            cur
          );
          u.Guarantee_Status__c = 'Hold Placed';
          changed = true;
        }
      }
      when 'payment_intent.canceled' {
        if (
          piId == b.Preauth_Intent_Id__c &&
          b.Preauth_Status__c != 'Captured'
        ) {
          u.Preauth_Status__c = 'Released';
          changed = true;
        }
      }
      when 'payment_intent.payment_failed' {
        if (ours) {
          Map<String, Object> err = PMS_StripeClient.asMap(
            pi.get('last_payment_error')
          );
          u.Guarantee_Status__c = 'Action Needed';
          u.Guarantee_Message__c = PMS_GuaranteeService.cut(
            'Card payment failed: ' + PMS_StripeClient.str(err, 'message'),
            255
          );
          if (kind == 'hold' && piId == b.Preauth_Intent_Id__c) {
            u.Preauth_Status__c = 'Failed';
          }
          changed = true;
        }
      }
      when 'payment_intent.succeeded' {
        if (saveCard) {
          String pm = idOf(pi.get('payment_method'));
          if (String.isNotBlank(pm)) {
            u.Stripe_Payment_Method__c = pm;
            u.Card_Saved_At__c = Datetime.now();
            u.Card_Brand__c = null;
            u.Card_Last4__c = null;
            u.Card_Expiry__c = null;
          }
          u.Guarantee_Status__c = 'Deposit Paid';
          u.Guarantee__c = paymentType == 'Deposit' ? 'Deposit' : 'Prepaid';
          u.Guarantee_Message__c = 'Paid by the guest on the Stripe page; card saved.';
          changed = true;
        }
        if (ours) {
          if (kind == 'hold' && piId == b.Preauth_Intent_Id__c) {
            u.Preauth_Status__c = 'Captured';
            changed = true;
          }
          Decimal amount = PMS_StripeClient.toMajor(
            pi.get('amount_received'),
            cur
          );
          result = recordPayment(
            b,
            piId,
            amount,
            String.isBlank(paymentType) ? 'Payment' : paymentType,
            received
          );
        }
      }
    }
    if (changed) {
      update u;
    }
    return result;
  }

  /**
   * Creates the payment if PMS has not recorded it yet. An existing record (written by the job or
   * the console with its invoice) is only moved to Succeeded, never re-pointed.
   */
  private static PMS_Payment__c recordPayment(
    PMS_Booking__c b,
    String ref,
    Decimal amount,
    String paymentType,
    Date received
  ) {
    if (
      String.isBlank(ref) ||
      amount == null ||
      amount <= 0 ||
      b.Account__c == null
    ) {
      return null;
    }
    List<PMS_Payment__c> existing = [
      SELECT Id, Status__c
      FROM PMS_Payment__c
      WHERE Gateway_Reference__c = :ref
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      PMS_Payment__c p = existing[0];
      if (p.Status__c != 'Succeeded') {
        p.Status__c = 'Succeeded';
        p.Amount__c = amount;
        update p;
      }
      return p;
    }
    PMS_Payment__c p = new PMS_Payment__c(
      Gateway_Reference__c = ref,
      Amount__c = amount,
      Account__c = b.Account__c,
      Booking__c = b.Id,
      Payment_Type__c = paymentType,
      Method__c = 'Card',
      Received_Date__c = received == null ? Date.today() : received,
      Status__c = 'Succeeded'
    );
    PMS_GuaranteeService.copyCurrency(b, p);
    insert p;
    return p;
  }

  private static PMS_Booking__c booking(String bookingNumber) {
    String q =
      'SELECT Id, Account__c, Guarantee_Status__c, Guarantee__c, Preauth_Intent_Id__c, Preauth_Status__c' +
      (UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '') +
      ' FROM PMS_Booking__c WHERE Name = :bookingNumber LIMIT 1';
    List<PMS_Booking__c> bs = Database.query(q);
    return bs.isEmpty() ? null : bs[0];
  }

  /** Stripe sends ids as strings, or as objects when expanded. */
  private static String idOf(Object o) {
    if (o == null) {
      return null;
    }
    if (o instanceof Map<String, Object>) {
      return PMS_StripeClient.str((Map<String, Object>) o, 'id');
    }
    return String.valueOf(o);
  }
}
