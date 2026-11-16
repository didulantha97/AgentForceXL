/**
 * Card guarantees, deposits, pre-authorisations and policy fees through Stripe.
 *
 * Cards never reach Salesforce. The guest saves a card (Stripe Checkout in setup mode) or pays a
 * deposit with the card saved for later (Checkout in payment mode with setup_future_usage), and
 * Salesforce only keeps the Stripe ids (cus_..., pm_..., pi_...) plus brand and last 4 for display.
 * Later charges are merchant-initiated (off_session): if the bank asks for authentication, the guest
 * is emailed a pay link instead.
 *
 * Salesforce allows no callout after a DML statement in the same transaction, so every method here
 * makes its Stripe calls first and only collects record changes in a Work object; Work.commitWork()
 * saves them all at the end.
 */
public without sharing class PMS_GuaranteeService {
  public static final String SOURCE = 'pms-guarantee';
  public static final Set<String> CLOSED = new Set<String>{
    'Cancelled',
    'No Show',
    'Completed',
    'Inquiry'
  };
  public static final Set<String> CREDIT_TYPES = new Set<String>{
    'Deposit',
    'Payment',
    'Deposit Return',
    'Refund'
  };

  // ---------------------------------------------------------------- unit of work

  public class Work {
    public Map<Id, PMS_Booking__c> bookings = new Map<Id, PMS_Booking__c>();
    public Map<Id, Account> accounts = new Map<Id, Account>();
    public List<PMS_Payment__c> payments = new List<PMS_Payment__c>();
    public List<FeePosting> fees = new List<FeePosting>();
    public List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    public PMS_Booking__c booking(Id bookingId) {
      if (!bookings.containsKey(bookingId)) {
        bookings.put(bookingId, new PMS_Booking__c(Id = bookingId));
      }
      return bookings.get(bookingId);
    }

    public String customerFor(Id accountId) {
      return accounts.containsKey(accountId)
        ? accounts.get(accountId).Stripe_Customer_Id__c
        : null;
    }

    public void commitWork() {
      if (!accounts.isEmpty()) {
        update accounts.values();
      }
      for (FeePosting f : fees) {
        f.post();
      }
      List<PMS_Payment__c> withRef = new List<PMS_Payment__c>();
      for (PMS_Payment__c p : payments) {
        if (String.isNotBlank(p.Gateway_Reference__c)) {
          withRef.add(p);
        }
      }
      if (!withRef.isEmpty()) {
        upsert withRef Gateway_Reference__c;
      }
      if (!bookings.isEmpty()) {
        update bookings.values();
      }
      if (!emails.isEmpty()) {
        try {
          Messaging.sendEmail(emails, false);
        } catch (Exception e) {
          // Email deliverability off or limits reached: the link is still on the booking panel.
          System.debug(
            LoggingLevel.WARN,
            'Guarantee emails not sent: ' + e.getMessage()
          );
        }
      }
    }
  }

  /** A cancellation or no-show fee: one invoice with one charge, plus the payments that cover it. */
  public class FeePosting {
    public PMS_Booking__c booking;
    public PMS_PolicyService.FeeDecision fee;
    public List<PMS_Payment__c> newPayments = new List<PMS_Payment__c>();
    public PMS_Invoice__c invoice;

    public FeePosting(PMS_Booking__c b, PMS_PolicyService.FeeDecision d) {
      booking = b;
      fee = d;
    }

    public void post() {
      String module = PMS_ModuleConfig.moduleForBookingRecordType(
        booking.RecordTypeId
      );
      invoice = new PMS_Invoice__c(
        RecordTypeId = module == null
          ? null
          : PMS_ModuleConfig.invoiceRecordTypeId(module),
        Account__c = booking.Account__c,
        Booking__c = booking.Id,
        Issue_Date__c = Date.today(),
        Due_Date__c = Date.today(),
        Currency_Code__c = PMS_PolicyService.currencyOf(booking),
        Subtotal__c = 0,
        Tax_Total__c = 0,
        Amount_Paid__c = 0,
        Status__c = 'Issued'
      );
      PMS_GuaranteeService.copyCurrency(booking, invoice);
      insert invoice;
      PMS_Charge__c c = new PMS_Charge__c(
        Booking__c = booking.Id,
        Account__c = booking.Account__c,
        Invoice__c = invoice.Id,
        Charge_Type__c = 'Cancellation Fee',
        Description__c = PMS_GuaranteeService.cut(
          fee.kind + ' fee - booking ' + booking.Name,
          255
        ),
        Quantity__c = 1,
        Unit_Price__c = fee.net,
        Tax_Rate__c = fee.taxRate,
        Service_Date__c = Date.today(),
        Status__c = 'Invoiced'
      );
      PMS_GuaranteeService.copyCurrency(booking, c);
      insert c;
      // Deposits and prepayments already taken for this booking now pay the fee invoice.
      List<PMS_Payment__c> credits = [
        SELECT Id
        FROM PMS_Payment__c
        WHERE
          Booking__c = :booking.Id
          AND Invoice__c = NULL
          AND Status__c = 'Succeeded'
          AND Payment_Type__c IN :PMS_GuaranteeService.CREDIT_TYPES
      ];
      for (PMS_Payment__c p : credits) {
        p.Invoice__c = invoice.Id;
      }
      if (!credits.isEmpty()) {
        update credits;
      }
      for (PMS_Payment__c p : newPayments) {
        p.Invoice__c = invoice.Id;
      }
    }
  }

  // ---------------------------------------------------------------- Stripe customer

  public static String ensureCustomer(PMS_Booking__c b, Work w) {
    if (b.Account__c == null) {
      throw new PMS_Exception(
        'Booking ' + b.Name + ' has no customer account.'
      );
    }
    String existing = w.customerFor(b.Account__c);
    if (String.isBlank(existing) && b.Account__r != null) {
      existing = b.Account__r.Stripe_Customer_Id__c;
    }
    if (String.isNotBlank(existing)) {
      return existing;
    }
    Map<String, String> params = new Map<String, String>{
      'name' => b.Account__r == null ? b.Name : b.Account__r.Name,
      'metadata[accountId]' => String.valueOf(b.Account__c),
      'metadata[source]' => SOURCE
    };
    if (
      b.Primary_Contact__r != null &&
      String.isNotBlank(b.Primary_Contact__r.Email)
    ) {
      params.put('email', b.Primary_Contact__r.Email);
    }
    Map<String, Object> cus = PMS_StripeClient.post(
      '/v1/customers',
      params,
      'pms-cus-' + b.Account__c
    );
    String customerId = PMS_StripeClient.str(cus, 'id');
    w.accounts.put(
      b.Account__c,
      new Account(Id = b.Account__c, Stripe_Customer_Id__c = customerId)
    );
    return customerId;
  }

  // ---------------------------------------------------------------- card / deposit link

  public class LinkResult {
    @AuraEnabled
    public String url;
    @AuraEnabled
    public String mode; // setup = save a card, payment = pay deposit or stay now
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Boolean emailed = false;
    @AuraEnabled
    public String emailedTo;
    @AuraEnabled
    public Datetime expiresAt;
  }

  public static LinkResult createLink(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Work w
  ) {
    String m = PMS_PolicyService.method(p);
    if (m == PMS_PolicyService.M_NONE) {
      throw new PMS_Exception(
        'No payment policy that needs a card applies to booking ' + b.Name + '.'
      );
    }
    if (CLOSED.contains(b.Status__c)) {
      throw new PMS_Exception('Booking ' + b.Name + ' is ' + b.Status__c + '.');
    }
    String customerId = ensureCustomer(b, w);
    String cur = PMS_PolicyService.currencyOf(b);
    String ret = returnUrl();
    String sep = ret.contains('?') ? '&' : '?';
    Decimal amount = 0;
    Boolean payNow =
      (m == PMS_PolicyService.M_DEPOSIT ||
      m == PMS_PolicyService.M_PREPAID) &&
      b.Guarantee_Status__c != 'Deposit Paid' &&
      PMS_PolicyService.depositDueNow(b, p, Datetime.now());
    if (payNow) {
      Decimal credit = PMS_PolicyService.unappliedCredit(new Set<Id>{ b.Id })
        .get(b.Id);
      amount =
        PMS_PolicyService.guaranteeAmount(b, p) -
        (credit == null || m == PMS_PolicyService.M_PREPAID ? 0 : credit);
      payNow = amount > 0;
    }
    Datetime expires = Datetime.now().addHours(23);
    String siteName = b.Site__r == null ? '' : ' at ' + b.Site__r.Name;
    Map<String, String> params = new Map<String, String>{
      'customer' => customerId,
      'client_reference_id' => String.valueOf(b.Id),
      'metadata[bookingNumber]' => b.Name,
      'expires_at' => String.valueOf(expires.getTime() / 1000)
    };
    String terms = p.Guest_Terms__c;
    if (String.isNotBlank(terms)) {
      params.put('custom_text[submit][message]', cut(terms, 1000));
    }
    LinkResult r = new LinkResult();
    r.currencyCode = cur;
    r.expiresAt = expires;
    if (payNow) {
      String paymentType = m == PMS_PolicyService.M_PREPAID
        ? 'Payment'
        : 'Deposit';
      params.put('mode', 'payment');
      params.put('line_items[0][quantity]', '1');
      params.put('line_items[0][price_data][currency]', cur.toLowerCase());
      params.put(
        'line_items[0][price_data][unit_amount]',
        String.valueOf(PMS_StripeClient.toMinor(amount, cur))
      );
      params.put(
        'line_items[0][price_data][product_data][name]',
        (paymentType == 'Deposit' ? 'Deposit, booking ' : 'Booking ') +
          b.Name +
          siteName
      );
      params.put('payment_intent_data[setup_future_usage]', 'off_session');
      params.put('payment_intent_data[metadata][bookingNumber]', b.Name);
      params.put('payment_intent_data[metadata][paymentType]', paymentType);
      params.put('payment_intent_data[metadata][pmsSaveCard]', '1');
      params.put('success_url', ret + sep + 'status=paid');
      params.put('cancel_url', ret + sep + 'status=cancelled');
      r.mode = 'payment';
      r.amount = amount;
    } else {
      params.put('mode', 'setup');
      params.put('currency', cur.toLowerCase());
      params.put('payment_method_types[0]', 'card');
      params.put('setup_intent_data[metadata][bookingNumber]', b.Name);
      params.put('setup_intent_data[metadata][pmsSource]', SOURCE);
      params.put(
        'setup_intent_data[description]',
        'Card guarantee, booking ' + b.Name + siteName
      );
      params.put('success_url', ret + sep + 'status=card-saved');
      params.put('cancel_url', ret + sep + 'status=cancelled');
      r.mode = 'setup';
      r.amount = 0;
    }
    Map<String, Object> session = PMS_StripeClient.post(
      '/v1/checkout/sessions',
      params,
      null
    );
    r.url = PMS_StripeClient.str(session, 'url');
    PMS_Booking__c u = w.booking(b.Id);
    if (
      b.Guarantee_Status__c == null ||
      b.Guarantee_Status__c == 'Not Required' ||
      b.Guarantee_Status__c == 'Action Needed'
    ) {
      u.Guarantee_Status__c = 'Awaiting Card';
    }
    return r;
  }

  /** Adds the guest email for a link to the work; returns false when the booking has no contact email. */
  public static Boolean queueLinkEmail(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    LinkResult r,
    Work w
  ) {
    if (
      b.Primary_Contact__c == null ||
      b.Primary_Contact__r == null ||
      String.isBlank(b.Primary_Contact__r.Email)
    ) {
      return false;
    }
    String site = b.Site__r == null ? '' : b.Site__r.Name;
    String first = String.isBlank(b.Primary_Contact__r.FirstName)
      ? ''
      : ' ' + b.Primary_Contact__r.FirstName;
    String arrival = b.Start__c == null
      ? ''
      : ' on ' + b.Start__c.format('d MMM yyyy');
    String ask = r.mode == 'payment'
      ? 'please pay ' +
        r.amount.setScale(2) +
        ' ' +
        r.currencyCode +
        ' on this secure Stripe page. Your card is saved for any later charges under the terms below.'
      : 'please save a card on this secure Stripe page. Nothing is charged now; the card is only used under the terms below.';
    List<String> lines = new List<String>{
      'Hello' +
      first +
      ',',
      '',
      'To guarantee your booking ' +
      b.Name +
      (String.isBlank(site) ? '' : ' at ' + site) +
      arrival +
      ', ' +
      ask,
      '',
      r.url,
      '',
      'The link works for 23 hours. We never see or store your card number.'
    };
    if (p != null && String.isNotBlank(p.Guest_Terms__c)) {
      lines.add('');
      lines.add(p.Guest_Terms__c);
    }
    lines.add('');
    lines.add(String.isBlank(site) ? 'Thank you' : site);
    Messaging.SingleEmailMessage e = new Messaging.SingleEmailMessage();
    e.setTargetObjectId(b.Primary_Contact__c);
    e.setSaveAsActivity(false);
    e.setSubject(
      (r.mode == 'payment'
        ? 'Payment for booking '
        : 'Guarantee your booking ') + b.Name
    );
    e.setPlainTextBody(String.join(lines, '\n'));
    w.emails.add(e);
    w.booking(b.Id).Card_Link_Sent_At__c = Datetime.now();
    r.emailed = true;
    r.emailedTo = b.Primary_Contact__r.Email;
    return true;
  }

  // ---------------------------------------------------------------- off-session charges and holds

  public class ChargeResult {
    public Boolean ok = false;
    public String paymentIntentId;
    public String status;
    public Decimal amount = 0;
    public String message;
    public Boolean needsGuest = false;
    public Datetime captureBefore;
  }

  public static ChargeResult chargeSaved(
    PMS_Booking__c b,
    Decimal amount,
    String kind,
    String paymentType,
    String description,
    String idempotencyKey
  ) {
    return createIntent(
      b,
      amount,
      kind,
      paymentType,
      description,
      idempotencyKey,
      false
    );
  }

  public static ChargeResult placeHold(
    PMS_Booking__c b,
    Decimal amount,
    String idempotencyKey
  ) {
    return createIntent(
      b,
      amount,
      'hold',
      'Payment',
      'Card hold, booking ' + b.Name,
      idempotencyKey,
      true
    );
  }

  private static ChargeResult createIntent(
    PMS_Booking__c b,
    Decimal amount,
    String kind,
    String paymentType,
    String description,
    String idempotencyKey,
    Boolean manualCapture
  ) {
    ChargeResult r = new ChargeResult();
    String customerId = b.Account__r == null
      ? null
      : b.Account__r.Stripe_Customer_Id__c;
    if (
      String.isBlank(b.Stripe_Payment_Method__c) || String.isBlank(customerId)
    ) {
      r.message = 'No saved card for booking ' + b.Name + '.';
      r.needsGuest = true;
      return r;
    }
    if (amount == null || amount <= 0) {
      r.message = 'Nothing to charge.';
      return r;
    }
    String cur = PMS_PolicyService.currencyOf(b);
    Map<String, String> params = new Map<String, String>{
      'amount' => String.valueOf(PMS_StripeClient.toMinor(amount, cur)),
      'currency' => cur.toLowerCase(),
      'customer' => customerId,
      'payment_method' => b.Stripe_Payment_Method__c,
      'off_session' => 'true',
      'confirm' => 'true',
      'description' => cut(description, 350),
      'metadata[bookingNumber]' => b.Name,
      'metadata[pmsSource]' => SOURCE,
      'metadata[pmsKind]' => kind,
      'metadata[paymentType]' => paymentType
    };
    if (manualCapture) {
      params.put('capture_method', 'manual');
      params.put('expand[0]', 'latest_charge');
    }
    try {
      Map<String, Object> pi = PMS_StripeClient.post(
        '/v1/payment_intents',
        params,
        idempotencyKey
      );
      r.paymentIntentId = PMS_StripeClient.str(pi, 'id');
      r.status = PMS_StripeClient.str(pi, 'status');
      r.amount = amount;
      r.ok = manualCapture
        ? r.status == 'requires_capture'
        : (r.status == 'succeeded' || r.status == 'processing');
      if (manualCapture && r.ok) {
        Map<String, Object> card = PMS_StripeClient.asMap(
          PMS_StripeClient.asMap(
              PMS_StripeClient.asMap(pi.get('latest_charge'))
                .get('payment_method_details')
            )
            .get('card')
        );
        String before = PMS_StripeClient.str(card, 'capture_before');
        if (String.isNotBlank(before) && before.isNumeric()) {
          r.captureBefore = Datetime.newInstance(Long.valueOf(before) * 1000);
        }
      }
      if (!r.ok) {
        r.needsGuest =
          r.status == 'requires_action' ||
          r.status == 'requires_payment_method';
        r.message = 'Stripe left the payment as ' + r.status + '.';
      }
    } catch (PMS_StripeClient.StripeException e) {
      r.paymentIntentId = e.paymentIntentId;
      r.message = e.getMessage();
      r.needsGuest =
        e.code == 'authentication_required' ||
        e.code == 'card_declined' ||
        e.code == 'expired_card' ||
        e.code == 'incorrect_cvc' ||
        e.code == 'insufficient_funds';
    }
    return r;
  }

  public static ChargeResult captureHold(PMS_Booking__c b, Decimal amount) {
    ChargeResult r = new ChargeResult();
    r.paymentIntentId = b.Preauth_Intent_Id__c;
    String cur = PMS_PolicyService.currencyOf(b);
    try {
      Map<String, Object> pi = PMS_StripeClient.post(
        '/v1/payment_intents/' + b.Preauth_Intent_Id__c + '/capture',
        new Map<String, String>{
          'amount_to_capture' => String.valueOf(
            PMS_StripeClient.toMinor(amount, cur)
          )
        },
        'pms-cap-' + b.Preauth_Intent_Id__c
      );
      r.status = PMS_StripeClient.str(pi, 'status');
      r.ok = r.status == 'succeeded';
      Decimal received = PMS_StripeClient.toMajor(
        pi.get('amount_received'),
        cur
      );
      r.amount = received == null ? amount : received;
      if (!r.ok) {
        r.message = 'Stripe left the capture as ' + r.status + '.';
      }
    } catch (PMS_StripeClient.StripeException e) {
      r.message = e.getMessage();
    }
    return r;
  }

  public static ChargeResult releaseIntent(String paymentIntentId) {
    ChargeResult r = new ChargeResult();
    r.paymentIntentId = paymentIntentId;
    if (String.isBlank(paymentIntentId)) {
      r.message = 'No hold to release.';
      return r;
    }
    try {
      Map<String, Object> pi = PMS_StripeClient.post(
        '/v1/payment_intents/' + paymentIntentId + '/cancel',
        null,
        null
      );
      r.status = PMS_StripeClient.str(pi, 'status');
      r.ok = r.status == 'canceled';
    } catch (PMS_StripeClient.StripeException e) {
      r.message = e.getMessage();
      // Already cancelled, expired or captured: nothing is held any more.
      r.ok = e.code == 'payment_intent_unexpected_state';
    }
    return r;
  }

  public static PMS_Payment__c paymentFor(
    PMS_Booking__c b,
    ChargeResult r,
    String paymentType,
    Id invoiceId
  ) {
    PMS_Payment__c pay = new PMS_Payment__c(
      Gateway_Reference__c = r.paymentIntentId,
      Amount__c = r.amount,
      Account__c = b.Account__c,
      Booking__c = b.Id,
      Invoice__c = invoiceId,
      Payment_Type__c = paymentType,
      Method__c = 'Card',
      Received_Date__c = Date.today(),
      Status__c = r.status == 'processing' ? 'Pending' : 'Succeeded'
    );
    copyCurrency(b, pay);
    return pay;
  }

  // ---------------------------------------------------------------- the scheduled steps

  /** Fills brand, last 4 and expiry for a card the guest just saved. */
  public static void refreshCard(PMS_Booking__c b, Work w) {
    if (String.isBlank(b.Stripe_Payment_Method__c)) {
      return;
    }
    Map<String, Object> pm = PMS_StripeClient.get(
      '/v1/payment_methods/' + b.Stripe_Payment_Method__c,
      null
    );
    Map<String, Object> card = PMS_StripeClient.asMap(pm.get('card'));
    PMS_Booking__c u = w.booking(b.Id);
    String brand = PMS_StripeClient.str(card, 'brand');
    u.Card_Brand__c = String.isBlank(brand)
      ? 'Card'
      : cut(brand.capitalize(), 20);
    u.Card_Last4__c = PMS_StripeClient.str(card, 'last4');
    String month = PMS_StripeClient.str(card, 'exp_month');
    String year = PMS_StripeClient.str(card, 'exp_year');
    if (String.isNotBlank(month) && String.isNotBlank(year)) {
      u.Card_Expiry__c = month.leftPad(2, '0') + '/' + year;
    }
  }

  /** Charges the deposit (or the prepayment) to the saved card; emails a pay link if the bank refuses. */
  public static void chargeDeposit(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Decimal credit,
    Work w
  ) {
    String m = PMS_PolicyService.method(p);
    Decimal owed =
      PMS_PolicyService.guaranteeAmount(b, p) -
      (m == PMS_PolicyService.M_PREPAID || credit == null ? 0 : credit);
    PMS_Booking__c u = w.booking(b.Id);
    if (owed <= 0) {
      u.Guarantee_Status__c = 'Deposit Paid';
      return;
    }
    String paymentType = m == PMS_PolicyService.M_PREPAID
      ? 'Payment'
      : 'Deposit';
    String cur = PMS_PolicyService.currencyOf(b);
    ChargeResult r = chargeSaved(
      b,
      owed,
      'deposit',
      paymentType,
      (paymentType == 'Deposit'
        ? 'Deposit, booking '
        : 'Prepayment, booking ') + b.Name,
      'pms-dep-' + b.Id + '-' + PMS_StripeClient.toMinor(owed, cur)
    );
    if (r.ok) {
      w.payments.add(paymentFor(b, r, paymentType, null));
      u.Guarantee_Status__c = 'Deposit Paid';
      u.Guarantee__c = paymentType == 'Deposit' ? 'Deposit' : 'Prepaid';
      u.Guarantee_Message__c = cut(
        paymentType +
          ' of ' +
          owed.setScale(2) +
          ' ' +
          cur +
          ' charged to the saved card.',
        255
      );
      return;
    }
    u.Guarantee_Status__c = 'Action Needed';
    String msg = paymentType + ' charge failed: ' + r.message;
    if (
      r.needsGuest &&
      (b.Card_Link_Sent_At__c == null ||
      b.Card_Link_Sent_At__c < Datetime.now().addHours(-24))
    ) {
      try {
        LinkResult link = createLink(b, p, w);
        if (queueLinkEmail(b, p, link, w)) {
          msg += ' Pay link emailed to the guest.';
        }
      } catch (Exception e) {
        msg += ' Could not send a pay link: ' + e.getMessage();
      }
    }
    u.Guarantee_Message__c = cut(msg, 255);
  }

  public static void placeHoldFor(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Work w
  ) {
    Decimal amount = PMS_PolicyService.guaranteeAmount(b, p);
    PMS_Booking__c u = w.booking(b.Id);
    if (amount <= 0) {
      u.Guarantee_Message__c = 'The hold amount works out to 0, so no hold was placed.';
      return;
    }
    String cur = PMS_PolicyService.currencyOf(b);
    ChargeResult r = placeHold(
      b,
      amount,
      'pms-hold-' + b.Id + '-' + Datetime.now().formatGmt('yyyyMMddHH')
    );
    if (r.ok) {
      u.Preauth_Intent_Id__c = r.paymentIntentId;
      u.Preauth_Amount__c = amount;
      u.Preauth_Status__c = 'Authorized';
      u.Preauth_Expires_At__c = r.captureBefore != null
        ? r.captureBefore
        : Datetime.now().addDays(4);
      u.Guarantee_Status__c = 'Hold Placed';
      u.Guarantee_Message__c = cut(
        'Hold of ' + amount.setScale(2) + ' ' + cur + ' placed on the card.',
        255
      );
    } else {
      u.Preauth_Status__c = 'Failed';
      u.Guarantee_Status__c = 'Action Needed';
      u.Guarantee_Message__c = cut('Hold failed: ' + r.message, 255);
    }
  }

  /** Places a fresh hold before the current one expires, then releases the old one. */
  public static void renewHold(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Work w
  ) {
    String oldIntent = b.Preauth_Intent_Id__c;
    Decimal amount = b.Preauth_Amount__c != null &&
      b.Preauth_Amount__c > 0
      ? b.Preauth_Amount__c
      : PMS_PolicyService.guaranteeAmount(b, p);
    ChargeResult r = placeHold(
      b,
      amount,
      'pms-hold-' + b.Id + '-' + Datetime.now().formatGmt('yyyyMMddHH')
    );
    PMS_Booking__c u = w.booking(b.Id);
    if (r.ok) {
      releaseIntent(oldIntent);
      u.Preauth_Intent_Id__c = r.paymentIntentId;
      u.Preauth_Amount__c = amount;
      u.Preauth_Status__c = 'Authorized';
      u.Preauth_Expires_At__c = r.captureBefore != null
        ? r.captureBefore
        : Datetime.now().addDays(4);
      u.Guarantee_Message__c = 'Hold renewed before it expired.';
    } else {
      u.Guarantee_Status__c = 'Action Needed';
      u.Guarantee_Message__c = cut(
        'Renewing the hold failed (' +
          r.message +
          '). The current hold expires ' +
          String.valueOf(b.Preauth_Expires_At__c) +
          '.',
        255
      );
    }
  }

  /**
   * At check-out: captures what is still owed on the booking's open invoices (up to the hold) and
   * releases the rest. owed and invoiceId come from the caller's query of open invoices.
   */
  public static void settleHold(
    PMS_Booking__c b,
    Decimal owed,
    Id invoiceId,
    Work w
  ) {
    PMS_Booking__c u = w.booking(b.Id);
    String cur = PMS_PolicyService.currencyOf(b);
    if (owed != null && owed > 0) {
      Decimal amount = b.Preauth_Amount__c == null
        ? owed
        : Math.min(owed, b.Preauth_Amount__c);
      ChargeResult r = captureHold(b, amount);
      if (r.ok) {
        w.payments.add(paymentFor(b, r, 'Payment', invoiceId));
        u.Preauth_Status__c = 'Captured';
        u.Guarantee_Status__c = 'Settled';
        u.Guarantee_Message__c = cut(
          'Captured ' +
            r.amount.setScale(2) +
            ' ' +
            cur +
            ' from the hold at check-out; the rest was released.',
          255
        );
      } else {
        u.Guarantee_Status__c = 'Action Needed';
        u.Guarantee_Message__c = cut(
          'Capturing the hold failed: ' + r.message,
          255
        );
      }
      return;
    }
    ChargeResult rel = releaseIntent(b.Preauth_Intent_Id__c);
    if (rel.ok) {
      u.Preauth_Status__c = 'Released';
      u.Guarantee_Status__c = 'Settled';
      u.Guarantee_Message__c = 'Nothing owed at check-out, so the hold was released.';
    } else {
      u.Guarantee_Message__c = cut(
        'Releasing the hold failed: ' + rel.message,
        255
      );
    }
  }

  /**
   * Applies the cancellation or no-show policy once: posts the fee on its own invoice, uses any
   * deposit already paid, then captures the hold or charges the saved card for the rest.
   * credit = deposits and prepayments on the booking that are not on an invoice yet.
   */
  public static void applyPolicy(
    PMS_Booking__c b,
    PMS_Payment_Policy__c p,
    Decimal credit,
    Work w
  ) {
    PMS_Booking__c u = w.booking(b.Id);
    u.Policy_Pending__c = false;
    u.Policy_Fee_Charged__c = true;
    String cur = PMS_PolicyService.currencyOf(b);
    Decimal paidAlready = credit == null ? 0 : credit;
    Boolean holdOpen =
      b.Preauth_Status__c == 'Authorized' &&
      String.isNotBlank(b.Preauth_Intent_Id__c);
    PMS_PolicyService.FeeDecision d = PMS_PolicyService.feeFor(
      b,
      p,
      b.Status__c,
      b.Policy_Event_At__c
    );

    if (d.gross <= 0 || b.Account__c == null) {
      if (holdOpen && releaseIntent(b.Preauth_Intent_Id__c).ok) {
        u.Preauth_Status__c = 'Released';
      }
      u.Policy_Fee_Amount__c = 0;
      u.Refund_Due__c = paidAlready > 0 ? paidAlready : null;
      u.Guarantee_Status__c = 'Settled';
      String msg =
        d.reason +
        (d.gross > 0
          ? ' No customer account, so no fee was posted.'
          : ' No fee.');
      if (paidAlready > 0) {
        msg +=
          ' Refund ' +
          paidAlready.setScale(2) +
          ' ' +
          cur +
          ' to the guest in Stripe.';
      }
      u.Guarantee_Message__c = cut(msg, 255);
      return;
    }

    FeePosting f = new FeePosting(b, d);
    w.fees.add(f);
    Decimal remaining = d.gross - paidAlready;
    String msg =
      d.reason +
      ' Fee ' +
      d.gross.setScale(2) +
      ' ' +
      cur +
      ' invoiced.';
    if (remaining <= 0) {
      u.Refund_Due__c = remaining < 0 ? -remaining : null;
      if (remaining < 0) {
        msg +=
          ' The deposit covers it; refund ' +
          (-remaining).setScale(2) +
          ' ' +
          cur +
          ' in Stripe.';
      } else {
        msg += ' Covered by the deposit.';
      }
      if (holdOpen && releaseIntent(b.Preauth_Intent_Id__c).ok) {
        u.Preauth_Status__c = 'Released';
      }
    } else if (p.Auto_Charge_Fees__c == true) {
      if (holdOpen) {
        Decimal cap = b.Preauth_Amount__c == null
          ? remaining
          : Math.min(remaining, b.Preauth_Amount__c);
        ChargeResult c = captureHold(b, cap);
        if (c.ok) {
          u.Preauth_Status__c = 'Captured';
          remaining -= c.amount;
          addFeePayment(b, c, f, w);
          msg += ' ' + c.amount.setScale(2) + ' captured from the hold.';
        } else {
          msg += ' Capturing the hold failed: ' + c.message;
        }
      }
      if (remaining > 0 && String.isNotBlank(b.Stripe_Payment_Method__c)) {
        ChargeResult c = chargeSaved(
          b,
          remaining,
          'fee',
          'Payment',
          d.kind + ' fee, booking ' + b.Name,
          'pms-fee-' + b.Id + '-' + PMS_StripeClient.toMinor(remaining, cur)
        );
        if (c.ok) {
          remaining -= c.amount;
          addFeePayment(b, c, f, w);
          msg += ' ' + c.amount.setScale(2) + ' charged to the saved card.';
        } else {
          msg += ' Card charge failed: ' + c.message;
        }
      }
    }
    u.Policy_Fee_Amount__c = d.net;
    if (remaining > 0) {
      u.Guarantee_Status__c = 'Action Needed';
      msg +=
        ' ' +
        remaining.setScale(2) +
        ' ' +
        cur +
        ' still owed on the invoice.';
    } else {
      u.Guarantee_Status__c = 'Settled';
    }
    u.Guarantee_Message__c = cut(msg, 255);
  }

  private static void addFeePayment(
    PMS_Booking__c b,
    ChargeResult c,
    FeePosting f,
    Work w
  ) {
    PMS_Payment__c pay = paymentFor(b, c, 'Payment', null);
    f.newPayments.add(pay);
    w.payments.add(pay);
  }

  // ---------------------------------------------------------------- helpers

  public static String returnUrl() {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    String url = s == null ? null : s.Checkout_Return_URL__c;
    if (String.isBlank(url)) {
      throw new PMS_Exception(
        'Set Checkout Return URL in Setup > Custom Settings > PMS Settings first.'
      );
    }
    return url;
  }

  /** Stamps the booking's record currency on new money records, when the org uses multiple currencies. */
  public static void copyCurrency(PMS_Booking__c b, SObject target) {
    if (!UserInfo.isMultiCurrencyOrganization()) {
      return;
    }
    try {
      Object iso = b.get('CurrencyIsoCode');
      if (iso != null) {
        target.put('CurrencyIsoCode', iso);
      }
    } catch (SObjectException e) {
      // CurrencyIsoCode was not queried; the record keeps the running user's currency.
    }
  }

  public static String cut(String s, Integer max) {
    if (s == null) {
      return null;
    }
    return s.length() <= max ? s : s.left(max - 3) + '...';
  }
}
