/**
 * Agent / Flow action: returns the open invoice for a booking, or creates one so a Stripe pay link
 * can be sent. Called by the "PMS Agent: Get or Create Booking Invoice" flow.
 *
 * How a new invoice is built depends on the booking:
 *  - Hotel reservation: one Room Night charge per night not yet charged, and those nights are marked
 *    Posted, so the night audit does not charge them a second time. Uninvoiced extras are included.
 *  - Appointment: invoices any uninvoiced charges; otherwise one fee from the service price.
 *  - Anything else (leases, project allocations): invoices any uninvoiced charges; otherwise one
 *    charge for the booking total, as the flow did before.
 * Throws when the booking is cancelled or there is nothing to invoice, so the flow and agent stop.
 */
public without sharing class PMS_BookingInvoiceAction {
  private static final Set<String> CLOSED_INVOICE = new Set<String>{
    'Void',
    'Credited',
    'Draft',
    'Paid'
  };
  private static final Set<String> DEAD_BOOKING = new Set<String>{
    'Cancelled',
    'No Show',
    'Inquiry'
  };

  public class Request {
    @InvocableVariable(required=true label='Booking Id')
    public String bookingId;
  }

  public class Result {
    @InvocableVariable(label='Invoice Id')
    public String invoiceId;
    @InvocableVariable(label='Invoice Number')
    public String invoiceNumber;
    @InvocableVariable(label='Balance Due')
    public Decimal balanceDue;
  }

  @InvocableMethod(
    label='PMS: Get or Create Booking Invoice'
    description='Returns the open invoice for a booking, or creates one for what is still owed, without double-charging hotel nights.'
    category='Unified PMS'
  )
  public static List<Result> run(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request r : requests) {
      PMS_Invoice__c inv = getOrCreate((Id) r.bookingId);
      Result res = new Result();
      res.invoiceId = inv.Id;
      res.invoiceNumber = inv.Name;
      res.balanceDue = inv.Balance__c;
      results.add(res);
    }
    return results;
  }

  public static PMS_Invoice__c getOrCreate(Id bookingId) {
    List<PMS_Invoice__c> open = [
      SELECT Id, Name, Balance__c
      FROM PMS_Invoice__c
      WHERE
        Booking__c = :bookingId
        AND Balance__c > 0
        AND Status__c NOT IN :CLOSED_INVOICE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!open.isEmpty()) {
      return open[0];
    }
    List<PMS_Booking__c> bs = [
      SELECT
        Id,
        Name,
        RecordTypeId,
        Status__c,
        Account__c,
        Service__c,
        Total_Amount__c,
        Site__r.Currency_Code__c,
        (
          SELECT Id
          FROM Charges__r
          WHERE Status__c = 'Pending' AND Invoice__c = NULL
        )
      FROM PMS_Booking__c
      WHERE Id = :bookingId
    ];
    if (bs.isEmpty()) {
      throw new PMS_Exception('Booking not found.');
    }
    PMS_Booking__c b = bs[0];
    if (DEAD_BOOKING.contains(b.Status__c)) {
      throw new PMS_Exception(
        'Booking ' +
          b.Name +
          ' is ' +
          b.Status__c +
          ', so there is nothing to pay.'
      );
    }
    if (b.Account__c == null) {
      throw new PMS_Exception(
        'Booking ' + b.Name + ' has no customer account to bill.'
      );
    }
    String module = PMS_ModuleConfig.moduleForBookingRecordType(b.RecordTypeId);
    PMS_Invoice__c inv;
    if (module == PMS_ModuleConfig.HOTEL) {
      inv = PMS_WebBookingHold.invoiceHotelStay(b.Id);
    } else if (!b.Charges__r.isEmpty()) {
      inv = invoiceCharges(b, module);
    } else if (module == PMS_ModuleConfig.PRACTICE && b.Service__c != null) {
      if (
        [
          SELECT COUNT()
          FROM PMS_Charge__c
          WHERE Booking__c = :b.Id AND Status__c != 'Void'
        ] > 0
      ) {
        throw new PMS_Exception(
          'Booking ' + b.Name + ' has already been invoiced.'
        );
      }
      inv = PMS_WebBookingHold.invoiceAppointment(b.Id);
    } else {
      inv = invoiceTotal(b, module);
    }
    return [SELECT Id, Name, Balance__c FROM PMS_Invoice__c WHERE Id = :inv.Id];
  }

  private static PMS_Invoice__c invoiceCharges(
    PMS_Booking__c b,
    String module
  ) {
    PMS_Invoice__c inv = newInvoice(b, module);
    insert inv;
    List<PMS_Charge__c> updates = new List<PMS_Charge__c>();
    for (PMS_Charge__c c : b.Charges__r) {
      updates.add(
        new PMS_Charge__c(
          Id = c.Id,
          Invoice__c = inv.Id,
          Status__c = 'Invoiced'
        )
      );
    }
    update updates;
    return inv;
  }

  /** The previous flow behaviour, kept for bookings with no charges of their own. */
  private static PMS_Invoice__c invoiceTotal(PMS_Booking__c b, String module) {
    if (b.Total_Amount__c == null || b.Total_Amount__c <= 0) {
      throw new PMS_Exception(
        'Booking ' + b.Name + ' has no amount to invoice.'
      );
    }
    if (
      [
        SELECT COUNT()
        FROM PMS_Charge__c
        WHERE Booking__c = :b.Id AND Status__c != 'Void'
      ] > 0
    ) {
      throw new PMS_Exception(
        'Booking ' + b.Name + ' has already been invoiced.'
      );
    }
    PMS_Invoice__c inv = newInvoice(b, module);
    insert inv;
    insert new PMS_Charge__c(
      Booking__c = b.Id,
      Account__c = b.Account__c,
      Invoice__c = inv.Id,
      Charge_Type__c = 'Other',
      Description__c = 'Booking ' + b.Name,
      Quantity__c = 1,
      Unit_Price__c = b.Total_Amount__c,
      Tax_Rate__c = 0,
      Service_Date__c = Date.today(),
      Status__c = 'Invoiced'
    );
    return inv;
  }

  private static PMS_Invoice__c newInvoice(PMS_Booking__c b, String module) {
    return new PMS_Invoice__c(
      RecordTypeId = module == null
        ? null
        : PMS_ModuleConfig.invoiceRecordTypeId(module),
      Account__c = b.Account__c,
      Booking__c = b.Id,
      Issue_Date__c = Date.today(),
      Due_Date__c = Date.today(),
      Currency_Code__c = b.Site__r?.Currency_Code__c,
      Subtotal__c = 0,
      Tax_Total__c = 0,
      Amount_Paid__c = 0,
      Status__c = 'Issued'
    );
  }
}
