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

    for (PMS_Invoice__c inv : [
      SELECT
        Id,
        Name,
        Due_Date__c,
        Balance__c,
        CurrencyIsoCode,
        Dunning_Stage__c,
        Pay_Key__c,
        Status__c
      FROM PMS_Invoice__c
      WHERE
        Account__c = :acct
        AND Balance__c > 0
        AND Status__c IN ('Issued', 'Partially Paid', 'Overdue')
      ORDER BY Due_Date__c
      LIMIT 50
    ]) {
      InvoiceRow r = new InvoiceRow();
      r.id = inv.Id;
      r.name = inv.Name;
      r.dueDate = inv.Due_Date__c;
      r.balance = inv.Balance__c;
      r.currencyCode = inv.CurrencyIsoCode;
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

    for (PMS_Payment_Plan_Instalment__c i : [
      SELECT
        Number__c,
        Due_Date__c,
        Amount__c,
        CurrencyIsoCode,
        Status__c,
        Plan__r.Invoice__r.Name
      FROM PMS_Payment_Plan_Instalment__c
      WHERE
        Plan__r.Account__c = :acct
        AND Plan__r.Status__c NOT IN (
          'Completed',
          'Cancelled',
          'Defaulted',
          'Broken',
          'Declined'
        )
      ORDER BY Due_Date__c
      LIMIT 50
    ]) {
      InstalmentRow r = new InstalmentRow();
      r.invoiceName = i.Plan__r?.Invoice__r?.Name;
      r.instalmentNumber = i.Number__c == null ? null : i.Number__c.intValue();
      r.dueDate = i.Due_Date__c;
      r.amount = i.Amount__c;
      r.currencyCode = i.CurrencyIsoCode;
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
    for (PMS_Rent_Adjustment__c a : [
      SELECT
        Lease__r.Name,
        Kind__c,
        Effective_Date__c,
        Old_Rent__c,
        New_Rent__c,
        Change_Percent__c,
        CurrencyIsoCode,
        Status__c
      FROM PMS_Rent_Adjustment__c
      WHERE
        Lease__r.Account__c = :acct
        AND Status__c IN ('Notice Sent', 'Applied')
        AND Effective_Date__c >= :yearAgo
      ORDER BY Effective_Date__c DESC
      LIMIT 10
    ]) {
      RentRow r = new RentRow();
      r.leaseName = a.Lease__r?.Name;
      r.kind = a.Kind__c;
      r.effectiveDate = a.Effective_Date__c;
      r.oldRent = a.Old_Rent__c;
      r.newRent = a.New_Rent__c;
      r.changePercent = a.Change_Percent__c;
      r.currencyCode = a.CurrencyIsoCode;
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
