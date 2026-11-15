/**
 * Lifecycle of bookings made on the public booking site (Channel = Website).
 *
 *  1. The booking is created as Tentative, which holds the room or time slot.
 *  2. invoiceHotelStay / invoiceAppointment raise a prepayment invoice for the full amount
 *     (the agent's pay-link flow uses them too, through PMS_BookingInvoiceAction).
 *     Hotel stays are invoiced per night as Room Night charges and those nights are marked Posted,
 *     so the night audit never charges them a second time.
 *  3. When Stripe reports the payment, the invoice becomes Paid and confirmPaid() (from
 *     PMS_InvoiceTrigger) moves the booking to Confirmed.
 *  4. releaseExpired() (PMS_WebBookingCleanup, every 15 minutes) cancels bookings still unpaid after
 *     HOLD_MINUTES: charges are voided, the invoice is voided and the nights go back on sale.
 *     Stripe pay links expire after CHECKOUT_EXPIRY_MINUTES, well inside the hold.
 */
public without sharing class PMS_WebBookingHold {
  public static final String CHANNEL = 'Website';
  public static final Integer HOLD_MINUTES = 60;
  public static final Integer CHECKOUT_EXPIRY_MINUTES = 35;

  // ------------------------------------------------------------------ invoicing

  /**
   * Prepayment invoice for a hotel stay: one Room Night charge per night not yet charged (Reserved
   * or In House), with those nights marked Posted so the night audit never charges them again,
   * plus any extras already posted to the booking and not yet invoiced.
   * Also used by the agent's pay-link flow through PMS_BookingInvoiceAction.
   */
  public static PMS_Invoice__c invoiceHotelStay(Id bookingId) {
    PMS_Booking__c b = [
      SELECT
        Id,
        Name,
        Account__c,
        Site__r.Currency_Code__c,
        Rate_Plan__r.Tax_Rate__c,
        Space__r.Name,
        (
          SELECT Id, Stay_Date__c, Rate__c, Status__c
          FROM Room_Nights__r
          ORDER BY Stay_Date__c
        ),
        (
          SELECT Id
          FROM Charges__r
          WHERE Status__c = 'Pending' AND Invoice__c = NULL
        )
      FROM PMS_Booking__c
      WHERE Id = :bookingId
    ];
    Decimal taxRate = b.Rate_Plan__r?.Tax_Rate__c != null
      ? b.Rate_Plan__r.Tax_Rate__c
      : PMS_ModuleConfig.defaultTaxRate(PMS_ModuleConfig.HOTEL);
    List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
    List<PMS_Room_Night__c> nights = new List<PMS_Room_Night__c>();
    String room = b.Space__r == null ? '' : 'Room ' + b.Space__r.Name + ' - ';
    for (PMS_Room_Night__c rn : b.Room_Nights__r) {
      if (rn.Status__c != 'Reserved' && rn.Status__c != 'In House') {
        continue;
      }
      charges.add(
        new PMS_Charge__c(
          Booking__c = b.Id,
          Account__c = b.Account__c,
          Charge_Type__c = 'Room Night',
          Description__c = room +
            'night of ' +
            String.valueOf(rn.Stay_Date__c) +
            ' (prepaid)',
          Quantity__c = 1,
          Unit_Price__c = rn.Rate__c == null ? 0 : rn.Rate__c,
          Tax_Rate__c = taxRate,
          Service_Date__c = rn.Stay_Date__c,
          Status__c = 'Invoiced'
        )
      );
      nights.add(new PMS_Room_Night__c(Id = rn.Id, Status__c = 'Posted'));
    }
    List<PMS_Charge__c> extras = new List<PMS_Charge__c>();
    for (PMS_Charge__c c : b.Charges__r) {
      extras.add(new PMS_Charge__c(Id = c.Id, Status__c = 'Invoiced'));
    }
    if (charges.isEmpty() && extras.isEmpty()) {
      throw new PMS_Exception(
        'There is nothing left to invoice for booking ' + b.Name + '.'
      );
    }
    PMS_Invoice__c inv = newInvoice(
      b.Id,
      b.Account__c,
      b.Site__r.Currency_Code__c,
      PMS_ModuleConfig.HOTEL
    );
    insert inv;
    for (PMS_Charge__c c : charges) {
      c.Invoice__c = inv.Id;
    }
    for (PMS_Charge__c c : extras) {
      c.Invoice__c = inv.Id;
    }
    insert charges; // the charge trigger totals the invoice
    update extras;
    update nights;
    return inv;
  }

  public static PMS_Invoice__c invoiceAppointment(Id bookingId) {
    PMS_Booking__c b = [
      SELECT
        Id,
        Name,
        Account__c,
        Service__c,
        Service__r.Name,
        Start__c,
        End__c,
        Site__r.Currency_Code__c,
        Site__r.Time_Zone__c
      FROM PMS_Booking__c
      WHERE Id = :bookingId
    ];
    // Same quote PMS_BookingService.createBooking used for the booking total.
    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = PMS_ModuleConfig.PRACTICE;
    qr.serviceId = b.Service__c;
    qr.startDate = PMS_DateUtil.toLocalDate(b.Start__c, b.Site__r.Time_Zone__c);
    qr.endDate = PMS_DateUtil.toLocalDate(b.End__c, b.Site__r.Time_Zone__c);
    qr.hours =
      Decimal.valueOf((b.End__c.getTime() - b.Start__c.getTime()) / 60000) / 60;
    PMS_PricingService.Quote q = PMS_PricingService.quote(qr);
    if (q.gross == null || q.gross <= 0) {
      throw new PMS_Exception(
        'We could not price this appointment. Please contact us to book.'
      );
    }
    PMS_Invoice__c inv = newInvoice(
      b.Id,
      b.Account__c,
      b.Site__r.Currency_Code__c,
      PMS_ModuleConfig.PRACTICE
    );
    insert inv;
    insert new PMS_Charge__c(
      Booking__c = b.Id,
      Account__c = b.Account__c,
      Invoice__c = inv.Id,
      Charge_Type__c = 'Consultation Fee',
      Description__c = (b.Service__r.Name + ' (prepaid online)').left(255),
      Quantity__c = 1,
      Unit_Price__c = q.net,
      Tax_Rate__c = q.taxRate,
      Service_Date__c = qr.startDate,
      Status__c = 'Invoiced'
    );
    return inv;
  }

  private static PMS_Invoice__c newInvoice(
    Id bookingId,
    Id accountId,
    String currencyCode,
    String module
  ) {
    return new PMS_Invoice__c(
      RecordTypeId = PMS_ModuleConfig.invoiceRecordTypeId(module),
      Account__c = accountId,
      Booking__c = bookingId,
      Issue_Date__c = Date.today(),
      Due_Date__c = Date.today(),
      Currency_Code__c = currencyCode,
      Subtotal__c = 0,
      Tax_Total__c = 0,
      Amount_Paid__c = 0,
      Status__c = 'Issued'
    );
  }

  // ------------------------------------------------------------------ confirm and release

  /** Tentative website bookings whose invoice is now paid become Confirmed. */
  public static void confirmPaid(Set<Id> bookingIds) {
    bookingIds.remove(null);
    if (bookingIds.isEmpty()) {
      return;
    }
    List<PMS_Booking__c> toConfirm = new List<PMS_Booking__c>();
    Set<Id> toEmail = new Set<Id>();
    for (PMS_Booking__c b : [
      SELECT Id, Confirmation_Sent__c
      FROM PMS_Booking__c
      WHERE
        Id IN :bookingIds
        AND Channel__c = :CHANNEL
        AND Status__c = 'Tentative'
    ]) {
      toConfirm.add(
        new PMS_Booking__c(
          Id = b.Id,
          Status__c = 'Confirmed',
          Confirmation_Sent__c = true
        )
      );
      if (!b.Confirmation_Sent__c) {
        toEmail.add(b.Id);
      }
    }
    if (!toConfirm.isEmpty()) {
      update toConfirm;
      PMS_GuestNotifications.bookingConfirmed(toEmail);
    }
  }

  /** Confirms paid holds that were missed and cancels unpaid holds older than HOLD_MINUTES. */
  public static Integer releaseExpired() {
    Datetime cutoff = Datetime.now().addMinutes(-HOLD_MINUTES);
    List<PMS_Booking__c> holds = [
      SELECT
        Id,
        Amount_Paid__c,
        Special_Requests__c,
        (SELECT Id, Status__c FROM Room_Nights__r WHERE Status__c = 'Posted')
      FROM PMS_Booking__c
      WHERE
        Channel__c = :CHANNEL
        AND Status__c = 'Tentative'
        AND CreatedDate < :cutoff
      LIMIT 200
    ];
    Set<Id> paid = new Set<Id>();
    Map<Id, PMS_Booking__c> expired = new Map<Id, PMS_Booking__c>();
    for (PMS_Booking__c b : holds) {
      if (b.Amount_Paid__c != null && b.Amount_Paid__c > 0) {
        paid.add(b.Id);
      } else {
        expired.put(b.Id, b);
      }
    }
    confirmPaid(paid);
    if (expired.isEmpty()) {
      return 0;
    }
    Set<Id> ids = expired.keySet();
    List<PMS_Charge__c> charges = [
      SELECT Id
      FROM PMS_Charge__c
      WHERE Booking__c IN :ids AND Status__c != 'Void'
    ];
    for (PMS_Charge__c c : charges) {
      c.Status__c = 'Void';
    }
    update charges;
    List<PMS_Invoice__c> invoices = [
      SELECT Id
      FROM PMS_Invoice__c
      WHERE Booking__c IN :ids AND Status__c != 'Void'
    ];
    for (PMS_Invoice__c inv : invoices) {
      inv.Status__c = 'Void';
    }
    update invoices;
    List<PMS_Room_Night__c> nights = new List<PMS_Room_Night__c>();
    List<PMS_Booking__c> cancels = new List<PMS_Booking__c>();
    for (PMS_Booking__c b : expired.values()) {
      for (PMS_Room_Night__c rn : b.Room_Nights__r) {
        nights.add(new PMS_Room_Night__c(Id = rn.Id, Status__c = 'Cancelled'));
      }
      cancels.add(
        new PMS_Booking__c(
          Id = b.Id,
          Status__c = 'Cancelled',
          Special_Requests__c = ((String.isBlank(b.Special_Requests__c)
              ? ''
              : b.Special_Requests__c + '\n') +
            'Cancelled: not paid within ' +
            HOLD_MINUTES +
            ' minutes of booking online.')
            .left(32000)
        )
      );
    }
    update nights;
    update cancels; // the booking trigger releases the nights and refreshes inventory
    return cancels.size();
  }
}
