/**
 * Owner statements: one PMS_Owner_Statement__c per owned site per calendar month.
 *
 *  Income (Gross_Rent__c)   payments received in the period on the site's bookings and invoices:
 *                           Payment and Retainer count, Refund is subtracted; security Deposits,
 *                           Deposit Returns and Owner Payouts are not income. Only Succeeded payments.
 *  Expenses__c              vendor bills at the site, Approved or Paid, dated in the period.
 *  Management_Fee__c        income x the site's Management Fee % (0 when blank).
 *  Net_Payout__c            formula: income - expenses - fee.
 *  Occupancy                hotels: room nights sold / (bookable rooms x days);
 *                           other sites: let unit-days / (bookable units x days), from leases.
 *  Arrears__c               unpaid invoices at the site due by the end of the period.
 *
 * generate() creates or refreshes Draft statements; Published and Paid statements are never changed.
 * Staff publish a statement (Status = Published) to show it in the Partner Portal.
 * PMS_OwnerStatementJob runs generate() nightly for the current month and, until the 5th, the previous one.
 */
public without sharing class PMS_OwnerStatementService {
  public static final Set<String> INCOME_TYPES = new Set<String>{
    'Payment',
    'Retainer'
  };
  public static final Set<String> NEGATIVE_TYPES = new Set<String>{ 'Refund' };
  public static final Set<String> EXPENSE_STATUSES = new Set<String>{
    'Approved',
    'Paid'
  };
  private static final Set<String> OPEN_INVOICE = new Set<String>{
    'Issued',
    'Partially Paid',
    'Overdue'
  };
  private static final Set<String> LEASE_STATUSES = new Set<String>{
    'Confirmed',
    'Active',
    'Completed'
  };
  private static final Set<String> UNSOLD_NIGHTS = new Set<String>{
    'Cancelled',
    'No Show'
  };

  public class Line {
    @AuraEnabled
    public Date lineDate;
    @AuraEnabled
    public String reference;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
  }

  public class Figures {
    @AuraEnabled
    public Date periodStart;
    @AuraEnabled
    public Date periodEnd;
    @AuraEnabled
    public Decimal gross = 0;
    @AuraEnabled
    public Decimal expenses = 0;
    @AuraEnabled
    public Decimal fee = 0;
    @AuraEnabled
    public Decimal net = 0;
    @AuraEnabled
    public Decimal feePercent = 0;
    @AuraEnabled
    public Decimal arrears = 0;
    @AuraEnabled
    public Decimal occupancyPct;
    @AuraEnabled
    public String occupancyBasis;
    @AuraEnabled
    public List<Line> income = new List<Line>();
    @AuraEnabled
    public List<Line> costs = new List<Line>();
    public Set<Id> billIds = new Set<Id>();
  }

  // ------------------------------------------------------------------ figures

  public static PMS_Site__c site(Id siteId) {
    return [
      SELECT
        Id,
        Name,
        Module__c,
        Time_Zone__c,
        Currency_Code__c,
        Owner_Account__c,
        Management_Fee_Percent__c
      FROM PMS_Site__c
      WHERE Id = :siteId
    ];
  }

  /** Figures for a site between two local dates (inclusive). */
  public static Figures compute(PMS_Site__c s, Date fromDate, Date toDate) {
    Figures f = new Figures();
    f.periodStart = fromDate;
    f.periodEnd = toDate;
    f.feePercent = s.Management_Fee_Percent__c == null
      ? 0
      : s.Management_Fee_Percent__c;

    for (PMS_Payment__c p : [
      SELECT
        Id,
        Name,
        Amount__c,
        Payment_Type__c,
        Received_Date__c,
        Booking__r.Name,
        Invoice__r.Name,
        Account__r.Name
      FROM PMS_Payment__c
      WHERE
        Status__c = 'Succeeded'
        AND Received_Date__c >= :fromDate
        AND Received_Date__c <= :toDate
        AND (Payment_Type__c IN :INCOME_TYPES
        OR Payment_Type__c IN :NEGATIVE_TYPES)
        AND (Booking__r.Site__c = :s.Id
        OR Invoice__r.Booking__r.Site__c = :s.Id)
      ORDER BY Received_Date__c, Name
      LIMIT 5000
    ]) {
      Decimal amt = p.Amount__c == null ? 0 : p.Amount__c;
      if (NEGATIVE_TYPES.contains(p.Payment_Type__c)) {
        amt = -amt.abs();
      }
      f.gross += amt;
      Line l = new Line();
      l.lineDate = p.Received_Date__c;
      l.reference = p.Invoice__r != null
        ? p.Invoice__r.Name
        : (p.Booking__r == null ? p.Name : p.Booking__r.Name);
      l.description =
        (p.Payment_Type__c == 'Payment'
          ? 'Payment received'
          : p.Payment_Type__c) +
        (p.Booking__r == null ? '' : ', booking ' + p.Booking__r.Name);
      l.amount = amt;
      f.income.add(l);
    }

    for (PMS_Vendor_Bill__c b : [
      SELECT
        Id,
        Name,
        Total__c,
        Bill_Date__c,
        Vendor_Invoice_Number__c,
        Vendor_Account__r.Name,
        Work_Order__r.Name,
        Work_Order__r.Subject__c
      FROM PMS_Vendor_Bill__c
      WHERE
        Site__c = :s.Id
        AND Status__c IN :EXPENSE_STATUSES
        AND Bill_Date__c >= :fromDate
        AND Bill_Date__c <= :toDate
      ORDER BY Bill_Date__c, Name
      LIMIT 2000
    ]) {
      Decimal amt = b.Total__c == null ? 0 : b.Total__c;
      f.expenses += amt;
      f.billIds.add(b.Id);
      Line l = new Line();
      l.lineDate = b.Bill_Date__c;
      l.reference = String.isBlank(b.Vendor_Invoice_Number__c)
        ? b.Name
        : b.Vendor_Invoice_Number__c;
      l.description =
        (b.Vendor_Account__r == null ? 'Vendor' : b.Vendor_Account__r.Name) +
        (b.Work_Order__r == null
          ? ''
          : ': ' +
            (String.isBlank(b.Work_Order__r.Subject__c)
              ? b.Work_Order__r.Name
              : b.Work_Order__r.Subject__c));
      l.amount = amt;
      f.costs.add(l);
    }

    Decimal fee = 0;
    if (f.gross > 0) {
      fee = f.gross * f.feePercent / 100;
    }
    f.fee = fee.setScale(2, System.RoundingMode.HALF_UP);
    f.gross = f.gross.setScale(2);
    f.expenses = f.expenses.setScale(2);
    f.net = f.gross - f.expenses - f.fee;

    AggregateResult ar = [
      SELECT SUM(Balance__c) bal
      FROM PMS_Invoice__c
      WHERE
        Booking__r.Site__c = :s.Id
        AND Status__c IN :OPEN_INVOICE
        AND Due_Date__c <= :toDate
        AND Balance__c > 0
    ];
    f.arrears = ar.get('bal') == null
      ? 0
      : ((Decimal) ar.get('bal')).setScale(2);

    occupancy(s, fromDate, toDate, f);
    return f;
  }

  private static void occupancy(
    PMS_Site__c s,
    Date fromDate,
    Date toDate,
    Figures f
  ) {
    Integer days = fromDate.daysBetween(toDate) + 1;
    Integer units = [
      SELECT COUNT()
      FROM PMS_Space__c
      WHERE Site__c = :s.Id AND Bookable__c = TRUE
    ];
    if (units == 0 || days <= 0) {
      return;
    }
    if (s.Module__c == 'Hotel') {
      Integer sold = [
        SELECT COUNT()
        FROM PMS_Room_Night__c
        WHERE
          Reservation__r.Site__c = :s.Id
          AND Stay_Date__c >= :fromDate
          AND Stay_Date__c <= :toDate
          AND Status__c NOT IN :UNSOLD_NIGHTS
      ];
      Integer available = units * days;
      f.occupancyPct = (Decimal.valueOf(sold) *
        100 /
        available)
        .setScale(1, System.RoundingMode.HALF_UP);
      f.occupancyBasis = sold + ' of ' + available + ' room nights';
      return;
    }
    String zone = String.isBlank(s.Time_Zone__c)
      ? UserInfo.getTimeZone().getID()
      : s.Time_Zone__c;
    Datetime windowStart = PMS_DateUtil.toDatetime(
      fromDate,
      Time.newInstance(0, 0, 0, 0),
      zone
    );
    Datetime windowEnd = PMS_DateUtil.toDatetime(
      toDate.addDays(1),
      Time.newInstance(0, 0, 0, 0),
      zone
    );
    Map<Id, Integer> letDaysByUnit = new Map<Id, Integer>();
    Set<Id> letAtEnd = new Set<Id>();
    for (PMS_Booking__c l : [
      SELECT Space__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Site__c = :s.Id
        AND Space__c != NULL
        AND Space__r.Bookable__c = TRUE
        AND RecordType.DeveloperName = 'Lease'
        AND Status__c IN :LEASE_STATUSES
        AND Start__c < :windowEnd
        AND (End__c = NULL
        OR End__c > :windowStart)
      LIMIT 5000
    ]) {
      Date a = PMS_DateUtil.toLocalDate(l.Start__c, zone);
      Date b = l.End__c == null
        ? toDate
        : PMS_DateUtil.toLocalDate(l.End__c, zone);
      Date from2 = a > fromDate ? a : fromDate;
      Date to2 = b < toDate ? b : toDate;
      Integer d = from2.daysBetween(to2) + 1;
      if (d <= 0) {
        continue;
      }
      Integer prior = letDaysByUnit.containsKey(l.Space__c)
        ? letDaysByUnit.get(l.Space__c)
        : 0;
      letDaysByUnit.put(l.Space__c, Math.min(days, prior + d));
      if (b >= toDate) {
        letAtEnd.add(l.Space__c);
      }
    }
    Integer letDays = 0;
    for (Integer d : letDaysByUnit.values()) {
      letDays += d;
    }
    f.occupancyPct = (Decimal.valueOf(letDays) *
      100 /
      (units * days))
      .setScale(1, System.RoundingMode.HALF_UP);
    f.occupancyBasis =
      letAtEnd.size() +
      ' of ' +
      units +
      ' units let on ' +
      toDate.format();
  }

  // ------------------------------------------------------------------ statements

  /** Creates or refreshes Draft statements for every active owned site, for the month containing anyDay. */
  public static Integer generate(Date anyDay) {
    return generate(
      anyDay,
      [
        SELECT Id
        FROM PMS_Site__c
        WHERE Owner_Account__c != NULL AND Status__c = 'Active'
        LIMIT 200
      ]
    );
  }

  public static Integer generate(Date anyDay, List<PMS_Site__c> sites) {
    Date startD = anyDay.toStartOfMonth();
    Date endD = startD.addMonths(1).addDays(-1);
    Set<Id> siteIds = new Map<Id, PMS_Site__c>(sites).keySet();
    Map<Id, PMS_Owner_Statement__c> existing = new Map<Id, PMS_Owner_Statement__c>();
    for (PMS_Owner_Statement__c st : [
      SELECT Id, Site__c, Status__c
      FROM PMS_Owner_Statement__c
      WHERE Site__c IN :siteIds AND Period_Start__c = :startD
    ]) {
      existing.put(st.Site__c, st);
    }
    Integer done = 0;
    for (PMS_Site__c s : [
      SELECT
        Id,
        Name,
        Module__c,
        Time_Zone__c,
        Currency_Code__c,
        Owner_Account__c,
        Management_Fee_Percent__c
      FROM PMS_Site__c
      WHERE Id IN :siteIds AND Owner_Account__c != NULL
    ]) {
      PMS_Owner_Statement__c st = existing.get(s.Id);
      if (st != null && st.Status__c != 'Draft') {
        continue; // published or paid: frozen
      }
      Figures f = compute(s, startD, endD);
      if (st == null) {
        st = new PMS_Owner_Statement__c(
          Site__c = s.Id,
          Period_Start__c = startD,
          Period_End__c = endD,
          Status__c = 'Draft'
        );
      }
      st.Owner_Account__c = s.Owner_Account__c;
      st.Period_End__c = endD;
      st.Gross_Rent__c = f.gross;
      st.Expenses__c = f.expenses;
      st.Management_Fee__c = f.fee;
      st.Occupancy_Percent__c = f.occupancyPct;
      st.Occupancy_Basis__c = f.occupancyBasis == null
        ? null
        : f.occupancyBasis.left(120);
      st.Arrears__c = f.arrears;
      st.Generated_On__c = Datetime.now();
      upsert st;
      if (!f.billIds.isEmpty()) {
        List<PMS_Vendor_Bill__c> bills = new List<PMS_Vendor_Bill__c>();
        for (Id billId : f.billIds) {
          bills.add(
            new PMS_Vendor_Bill__c(Id = billId, Owner_Statement__c = st.Id)
          );
        }
        update bills;
      }
      done++;
    }
    return done;
  }
}
