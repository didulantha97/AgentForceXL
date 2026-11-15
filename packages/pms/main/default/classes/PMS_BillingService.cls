/**
 * Billing for every module.
 *  - generateRecurringCharges: lease charge schedules -> Pending charges (rent run)
 *  - invoicePendingCharges:    Pending charges -> Invoices (one per bill-to account + booking/project/matter)
 *  - recalcInvoices:           subtotal, tax, paid, status from charges and payments
 *  - recalcBookings:           Total Amount and Amount Paid on bookings
 */
public inherited sharing class PMS_BillingService {
  // ---------------------------------------------------------------- rent run

  public static List<PMS_Charge__c> generateRecurringCharges(
    List<PMS_Lease_Charge_Schedule__c> schedules,
    Date runDate
  ) {
    List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
    List<PMS_Lease_Charge_Schedule__c> toUpdate = new List<PMS_Lease_Charge_Schedule__c>();
    for (PMS_Lease_Charge_Schedule__c s : schedules) {
      if (
        s.Active__c != true ||
        s.Next_Run_Date__c == null ||
        s.Next_Run_Date__c > runDate
      ) {
        continue;
      }
      if (
        s.Lease__r.Status__c != 'Active' &&
        s.Lease__r.Status__c != 'Confirmed'
      ) {
        continue;
      }
      Date due = s.Next_Run_Date__c;
      Integer guard = 0;
      while (
        due <= runDate &&
        (s.End_Date__c == null ||
        due <= s.End_Date__c) &&
        guard < 24
      ) {
        Decimal amount = escalatedAmount(s, due);
        charges.add(
          new PMS_Charge__c(
            Booking__c = s.Lease__c,
            Account__c = s.Lease__r.Account__c,
            Charge_Type__c = s.Charge_Type__c,
            Description__c = s.Charge_Type__c +
              ' ' +
              periodLabel(due, s.Frequency__c),
            Quantity__c = 1,
            Unit_Price__c = amount,
            Tax_Rate__c = PMS_ModuleConfig.defaultTaxRate(
              PMS_ModuleConfig.PROPERTY
            ),
            Service_Date__c = due,
            Status__c = 'Pending'
          )
        );
        due = PMS_DateUtil.addFrequency(due, s.Frequency__c);
        guard++;
      }
      s.Next_Run_Date__c = due;
      if (s.End_Date__c != null && due > s.End_Date__c) {
        s.Active__c = false;
      }
      toUpdate.add(s);
    }
    if (!charges.isEmpty()) {
      insert charges;
    }
    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }
    return charges;
  }

  /** Compounds the schedule's escalation % once per full year since its start date. */
  @TestVisible
  private static Decimal escalatedAmount(
    PMS_Lease_Charge_Schedule__c s,
    Date due
  ) {
    Decimal amount = s.Amount__c == null ? 0 : s.Amount__c;
    Decimal pct = s.Escalation_Percent__c != null
      ? s.Escalation_Percent__c
      : s.Lease__r.Escalation_Percent__c;
    if (pct == null || pct == 0 || s.Start_Date__c == null) {
      return amount;
    }
    Integer years = s.Start_Date__c.monthsBetween(due) / 12;
    for (Integer i = 0; i < years; i++) {
      amount = amount * (1 + pct / 100);
    }
    return amount.setScale(2);
  }

  private static String periodLabel(Date d, String frequency) {
    List<String> months = new List<String>{
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    };
    String m = months[d.month() - 1] + ' ' + d.year();
    return frequency == 'Weekly' ? 'week of ' + String.valueOf(d) : m;
  }

  // ---------------------------------------------------------------- invoicing

  public static List<PMS_Invoice__c> invoicePendingCharges(
    List<PMS_Charge__c> charges,
    Date issueDate
  ) {
    Map<String, List<PMS_Charge__c>> groups = new Map<String, List<PMS_Charge__c>>();
    Map<String, PMS_Invoice__c> invoices = new Map<String, PMS_Invoice__c>();
    for (PMS_Charge__c c : charges) {
      if (c.Status__c != 'Pending' || c.Invoice__c != null) {
        continue;
      }
      Id billTo = c.Account__c != null
        ? c.Account__c
        : c.Booking__r?.Account__c;
      if (billTo == null) {
        billTo = c.Project__r?.Account__c != null
          ? c.Project__r.Account__c
          : c.Matter__r?.Account__c;
      }
      if (billTo == null) {
        continue; // nobody to bill yet
      }
      String module = moduleOf(c);
      if (
        module == PMS_ModuleConfig.HOTEL &&
        c.Booking__r?.Status__c == 'Active'
      ) {
        continue; // in-house guests are billed on one folio at check-out
      }
      String k =
        billTo +
        '|' +
        c.Booking__c +
        '|' +
        c.Project__c +
        '|' +
        c.Matter__c;
      if (!groups.containsKey(k)) {
        groups.put(k, new List<PMS_Charge__c>());
        invoices.put(
          k,
          new PMS_Invoice__c(
            RecordTypeId = PMS_ModuleConfig.invoiceRecordTypeId(module),
            Account__c = billTo,
            Booking__c = c.Booking__c,
            Project__c = c.Project__c,
            Matter__c = c.Matter__c,
            Issue_Date__c = issueDate,
            Due_Date__c = issueDate.addDays(
              PMS_ModuleConfig.invoiceDueDays(module)
            ),
            Currency_Code__c = c.Booking__r?.Site__r?.Currency_Code__c,
            Subtotal__c = 0,
            Tax_Total__c = 0,
            Amount_Paid__c = 0,
            Status__c = 'Issued'
          )
        );
      }
      groups.get(k).add(c);
    }
    if (invoices.isEmpty()) {
      return new List<PMS_Invoice__c>();
    }
    insert invoices.values();
    List<PMS_Charge__c> toUpdate = new List<PMS_Charge__c>();
    for (String k : groups.keySet()) {
      for (PMS_Charge__c c : groups.get(k)) {
        toUpdate.add(
          new PMS_Charge__c(
            Id = c.Id,
            Invoice__c = invoices.get(k).Id,
            Status__c = 'Invoiced'
          )
        );
      }
    }
    update toUpdate; // the charge trigger recalculates invoice totals
    return invoices.values();
  }

  private static String moduleOf(PMS_Charge__c c) {
    if (c.Project__c != null) {
      return PMS_ModuleConfig.PROJECT;
    }
    if (c.Matter__c != null) {
      return PMS_ModuleConfig.PRACTICE;
    }
    String m = c.Booking__r == null
      ? null
      : PMS_ModuleConfig.moduleForBookingRecordType(c.Booking__r.RecordTypeId);
    return m == null ? PMS_ModuleConfig.PROPERTY : m;
  }

  public static String pendingChargeQuery() {
    return 'SELECT Id, Status__c, Invoice__c, Account__c, Booking__c, Project__c, Matter__c, ' +
      'Booking__r.Account__c, Booking__r.RecordTypeId, Booking__r.Status__c,Booking__r.Site__r.Currency_Code__c, ' +
      'Project__r.Account__c, Matter__r.Account__c ' +
      'FROM PMS_Charge__c WHERE Status__c = \'Pending\' AND Invoice__c = null';
  }

  // ---------------------------------------------------------------- totals

  public static void recalcInvoices(Set<Id> invoiceIds) {
    invoiceIds.remove(null);
    if (invoiceIds.isEmpty()) {
      return;
    }
    Map<Id, Decimal> net = new Map<Id, Decimal>();
    Map<Id, Decimal> tax = new Map<Id, Decimal>();
    for (PMS_Charge__c c : [
      SELECT Invoice__c, Quantity__c, Unit_Price__c, Tax_Rate__c
      FROM PMS_Charge__c
      WHERE Invoice__c IN :invoiceIds AND Status__c != 'Void'
    ]) {
      Decimal n = nz(c.Quantity__c) * nz(c.Unit_Price__c);
      add(net, c.Invoice__c, n);
      add(tax, c.Invoice__c, n * nz(c.Tax_Rate__c) / 100);
    }
    Map<Id, Decimal> paid = new Map<Id, Decimal>();
    for (PMS_Payment__c p : [
      SELECT Invoice__c, Amount__c, Payment_Type__c
      FROM PMS_Payment__c
      WHERE Invoice__c IN :invoiceIds AND Status__c = 'Succeeded'
    ]) {
      add(paid, p.Invoice__c, signedAmount(p));
    }
    List<PMS_Invoice__c> updates = new List<PMS_Invoice__c>();
    for (PMS_Invoice__c inv : [
      SELECT Id, Status__c, Due_Date__c
      FROM PMS_Invoice__c
      WHERE Id IN :invoiceIds
    ]) {
      Decimal subtotal = get(net, inv.Id).setScale(2);
      Decimal taxTotal = get(tax, inv.Id).setScale(2);
      Decimal amountPaid = get(paid, inv.Id).setScale(2);
      inv.Subtotal__c = subtotal;
      inv.Tax_Total__c = taxTotal;
      inv.Amount_Paid__c = amountPaid;
      if (
        inv.Status__c != 'Void' &&
        inv.Status__c != 'Credited' &&
        inv.Status__c != 'Draft'
      ) {
        Decimal balance = subtotal + taxTotal - amountPaid;
        if (balance <= 0 && subtotal + taxTotal > 0) {
          inv.Status__c = 'Paid';
        } else if (
          inv.Due_Date__c != null &&
          inv.Due_Date__c < Date.today() &&
          balance > 0
        ) {
          inv.Status__c = 'Overdue';
        } else if (amountPaid > 0) {
          inv.Status__c = 'Partially Paid';
        } else {
          inv.Status__c = 'Issued';
        }
      }
      updates.add(inv);
    }
    update updates;
  }

  public static void recalcBookings(Set<Id> bookingIds) {
    bookingIds.remove(null);
    if (bookingIds.isEmpty()) {
      return;
    }
    Map<Id, Decimal> gross = new Map<Id, Decimal>();
    Set<Id> hasCharges = new Set<Id>();
    for (PMS_Charge__c c : [
      SELECT Booking__c, Quantity__c, Unit_Price__c, Tax_Rate__c
      FROM PMS_Charge__c
      WHERE Booking__c IN :bookingIds AND Status__c != 'Void'
    ]) {
      Decimal n = nz(c.Quantity__c) * nz(c.Unit_Price__c);
      add(gross, c.Booking__c, n + n * nz(c.Tax_Rate__c) / 100);
      hasCharges.add(c.Booking__c);
    }
    Map<Id, Decimal> paid = new Map<Id, Decimal>();
    for (PMS_Payment__c p : [
      SELECT Booking__c, Invoice__r.Booking__c, Amount__c, Payment_Type__c
      FROM PMS_Payment__c
      WHERE
        Status__c = 'Succeeded'
        AND (Booking__c IN :bookingIds
        OR Invoice__r.Booking__c IN :bookingIds)
    ]) {
      Id bId = p.Booking__c != null ? p.Booking__c : p.Invoice__r.Booking__c;
      add(paid, bId, signedAmount(p));
    }
    List<PMS_Booking__c> updates = new List<PMS_Booking__c>();
    for (Id bId : bookingIds) {
      PMS_Booking__c b = new PMS_Booking__c(
        Id = bId,
        Amount_Paid__c = get(paid, bId).setScale(2)
      );
      if (hasCharges.contains(bId)) {
        b.Total_Amount__c = get(gross, bId).setScale(2); // keep the quoted total until real charges exist
      }
      updates.add(b);
    }
    Boolean previous = PMS_BookingTriggerHandler.bypass;
    PMS_BookingTriggerHandler.bypass = true;
    try {
      update updates;
    } finally {
      PMS_BookingTriggerHandler.bypass = previous;
    }
  }

  /** Money in counts positive; refunds, deposit returns and owner payouts reduce the paid amount. */
  public static Decimal signedAmount(PMS_Payment__c p) {
    Decimal a = nz(p.Amount__c);
    return (p.Payment_Type__c == 'Refund' ||
      p.Payment_Type__c == 'Deposit Return' ||
      p.Payment_Type__c == 'Owner Payout')
      ? -a
      : a;
  }

  private static void add(Map<Id, Decimal> m, Id k, Decimal v) {
    m.put(k, get(m, k) + v);
  }

  private static Decimal get(Map<Id, Decimal> m, Id k) {
    return m.containsKey(k) ? m.get(k) : 0;
  }

  private static Decimal nz(Decimal d) {
    return d == null ? 0 : d;
  }
}
