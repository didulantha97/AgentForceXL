/**
 * "My payments" for the customer portal: what the signed-in customer owes and why.
 *
 * Brings the revenue packages to the customer: open invoices with their reminder stage and a Pay
 * button (the same never-expiring pay link the reminder letters use), payment-plan instalments,
 * upcoming bookings that still need a card or deposit, and rent changes that were notified.
 *
 * Runs without sharing because external sharing is Private on every PMS object and these records are
 * not shared to portal users. Every query is limited to the running user's own account
 * (User.Contact.AccountId), so a customer only ever sees their own records. Read-only.
 */
public without sharing class PMS_PortalMoneyController {
  public class InvoiceRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public Boolean overdue;
    @AuraEnabled
    public String payUrl;
  }

  public class InstalmentRow {
    @AuraEnabled
    public String invoiceName;
    @AuraEnabled
    public Integer instalmentNumber;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean overdue;
  }

  public class CardRow {
    @AuraEnabled
    public String bookingName;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public Datetime startsAt;
    @AuraEnabled
    public String status;
  }

  public class RentRow {
    @AuraEnabled
    public String leaseName;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Date effectiveDate;
    @AuraEnabled
    public Decimal oldRent;
    @AuraEnabled
    public Decimal newRent;
    @AuraEnabled
    public Decimal changePercent;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String status;
  }

  public class Result {
    @AuraEnabled
    public Boolean hasAccount = false;
    @AuraEnabled
    public List<InvoiceRow> invoices = new List<InvoiceRow>();
    @AuraEnabled
    public List<InstalmentRow> instalments = new List<InstalmentRow>();
    @AuraEnabled
    public List<CardRow> cardsNeeded = new List<CardRow>();
    @AuraEnabled
    public List<RentRow> rentChanges = new List<RentRow>();
  }

  @TestVisible
  static Id accountOverride;
  @TestVisible
  static String payBaseOverride;

  /** ", CurrencyIsoCode" only in a multi-currency org (the field does not exist otherwise). */
  static String cur() {
    return UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';
  }

  /**
   * Currency label for a row: the Currency_Code__c found at codePath (the invoice itself, or the
   * invoice / site the row belongs to) when filled in, else the record's CurrencyIsoCode
   * (multi-currency orgs), else the org default.
   */
  @TestVisible
  static String iso(SObject rec, String codePath) {
    String code = codeAt(rec, codePath);
    if (String.isNotBlank(code)) {
      return code;
    }
    if (UserInfo.isMultiCurrencyOrganization()) {
      String isoCode = (String) rec.get('CurrencyIsoCode');
      if (String.isNotBlank(isoCode)) {
        return isoCode;
      }
    }
    return UserInfo.getDefaultCurrency();
  }

  private static String codeAt(SObject rec, String path) {
    List<String> parts = path.split('\\.');
    SObject node = rec;
    for (Integer i = 0; i < parts.size() - 1 && node != null; i++) {
      node = node.getSObject(parts[i]);
    }
    return node == null ? null : (String) node.get(parts[parts.size() - 1]);
  }

  @AuraEnabled
  public static Result getMyPayments() {
    Result res = new Result();
    Id acct = myAccountId();
    if (acct == null) {
      return res;
    }
    res.hasAccount = true;
    Date today = Date.today();
    String payBase = payBase();

    for (
      PMS_Invoice__c inv : (List<PMS_Invoice__c>) Database.queryWithBinds(
        'SELECT Id, Name, Due_Date__c, Balance__c' +
          cur() +
          ', Currency_Code__c, Dunning_Stage__c, Pay_Key__c, Status__c FROM PMS_Invoice__c ' +
          'WHERE Account__c = :acct AND Balance__c > 0 ' +
          'AND Status__c IN (\'Issued\', \'Partially Paid\', \'Overdue\') ' +
          'ORDER BY Due_Date__c LIMIT 50',
        new Map<String, Object>{ 'acct' => acct },
        AccessLevel.SYSTEM_MODE
      )
    ) {
      InvoiceRow r = new InvoiceRow();
      r.id = inv.Id;
      r.name = inv.Name;
      r.dueDate = inv.Due_Date__c;
      r.balance = inv.Balance__c;
      r.currencyCode = iso(inv, 'Currency_Code__c');
      r.stage = inv.Dunning_Stage__c;
      r.overdue =
        inv.Status__c == 'Overdue' ||
        (inv.Due_Date__c != null &&
        inv.Due_Date__c < today);
      if (String.isNotBlank(payBase) && String.isNotBlank(inv.Pay_Key__c)) {
        r.payUrl =
          payBase +
          '/services/apexrest/pms/pay?i=' +
          inv.Id +
          '&k=' +
          EncodingUtil.urlEncode(inv.Pay_Key__c, 'UTF-8');
      }
      res.invoices.add(r);
    }

    for (
      PMS_Payment_Plan_Instalment__c i : (List<PMS_Payment_Plan_Instalment__c>) Database.queryWithBinds(
        'SELECT Number__c, Due_Date__c, Amount__c' +
          cur() +
          ', Status__c, Plan__r.Invoice__r.Name, Plan__r.Invoice__r.Currency_Code__c FROM PMS_Payment_Plan_Instalment__c ' +
          'WHERE Plan__r.Account__c = :acct AND Plan__r.Status__c NOT IN ' +
          '(\'Completed\', \'Cancelled\', \'Defaulted\', \'Broken\', \'Declined\') ' +
          'ORDER BY Due_Date__c LIMIT 50',
        new Map<String, Object>{ 'acct' => acct },
        AccessLevel.SYSTEM_MODE
      )
    ) {
      InstalmentRow r = new InstalmentRow();
      r.invoiceName = i.Plan__r?.Invoice__r?.Name;
      r.instalmentNumber = i.Number__c == null ? null : i.Number__c.intValue();
      r.dueDate = i.Due_Date__c;
      r.amount = i.Amount__c;
      r.currencyCode = iso(i, 'Plan__r.Invoice__r.Currency_Code__c');
      r.status = i.Status__c;
      r.overdue =
        i.Status__c != 'Paid' &&
        i.Due_Date__c != null &&
        i.Due_Date__c < today;
      res.instalments.add(r);
    }

    Datetime now = Datetime.now();
    for (PMS_Booking__c b : [
      SELECT Name, Site__r.Name, Start__c, Guarantee_Status__c
      FROM PMS_Booking__c
      WHERE
        Account__c = :acct
        AND Guarantee_Status__c IN ('Awaiting Card', 'Action Needed')
        AND Status__c NOT IN ('Cancelled', 'No Show', 'Completed')
        AND Start__c >= :now
      ORDER BY Start__c
      LIMIT 20
    ]) {
      CardRow r = new CardRow();
      r.bookingName = b.Name;
      r.siteName = b.Site__r?.Name;
      r.startsAt = b.Start__c;
      r.status = b.Guarantee_Status__c;
      res.cardsNeeded.add(r);
    }

    Date yearAgo = today.addDays(-365);
    for (
      PMS_Rent_Adjustment__c a : (List<PMS_Rent_Adjustment__c>) Database.queryWithBinds(
        'SELECT Lease__r.Name, Kind__c, Effective_Date__c, Old_Rent__c, New_Rent__c, Change_Percent__c' +
          cur() +
          ', Lease__r.Site__r.Currency_Code__c, Status__c FROM PMS_Rent_Adjustment__c ' +
          'WHERE Lease__r.Account__c = :acct AND Status__c IN (\'Notice Sent\', \'Applied\') ' +
          'AND Effective_Date__c >= :yearAgo ORDER BY Effective_Date__c DESC LIMIT 10',
        new Map<String, Object>{ 'acct' => acct, 'yearAgo' => yearAgo },
        AccessLevel.SYSTEM_MODE
      )
    ) {
      RentRow r = new RentRow();
      r.leaseName = a.Lease__r?.Name;
      r.kind = a.Kind__c;
      r.effectiveDate = a.Effective_Date__c;
      r.oldRent = a.Old_Rent__c;
      r.newRent = a.New_Rent__c;
      r.changePercent = a.Change_Percent__c;
      r.currencyCode = iso(a, 'Lease__r.Site__r.Currency_Code__c');
      r.status = a.Status__c;
      res.rentChanges.add(r);
    }
    return res;
  }

  @TestVisible
  static Id myAccountId() {
    if (Test.isRunningTest() && accountOverride != null) {
      return accountOverride;
    }
    List<User> us = [
      SELECT ContactId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (us.isEmpty() || us[0].ContactId == null) {
      return null;
    }
    return us[0].Contact.AccountId;
  }

  /** Base URL of the public PMS Payments site, for example https://...my.salesforce-sites.com/pay */
  @TestVisible
  static String payBase() {
    if (payBaseOverride != null) {
      return payBaseOverride;
    }
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    if (s == null || String.isBlank(s.Public_Pay_URL__c)) {
      return null;
    }
    return s.Public_Pay_URL__c.removeEnd('/');
  }
}
