/**
 * Server side of the PMS Customer Portal (Experience site "PMS Customer Portal").
 *
 * Security model: external sharing for every PMS object is Private, so portal users have no record
 * access of their own. This class runs without sharing, but every query and every write is pinned
 * to the account of the logged-in portal user (User.Contact.AccountId). A record that belongs to
 * another account is treated as not found. Only the fields the portal shows are returned, as DTOs.
 */
public without sharing class PMS_PortalController {
  private static final Set<String> CLOSED_INVOICE = new Set<String>{
    'Paid',
    'Void',
    'Credited',
    'Draft'
  };
  private static final Set<String> CLOSED_CASE = new Set<String>{ 'Closed' };
  private static final Map<String, String> MODULE_BY_RT = new Map<String, String>{
    'Reservation' => 'Hotel',
    'Lease' => 'Property',
    'Allocation' => 'Project',
    'Appointment' => 'Practice'
  };
  private static final Map<String, String> KIND_BY_RT = new Map<String, String>{
    'Reservation' => 'Hotel stay',
    'Lease' => 'Lease',
    'Allocation' => 'Project booking',
    'Appointment' => 'Appointment'
  };

  // ---------- DTOs ----------

  public class Context {
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public Integer activeBookings = 0;
    @AuraEnabled
    public Integer openInvoices = 0;
    @AuraEnabled
    public Decimal openBalance = 0;
    @AuraEnabled
    public Integer overdueInvoices = 0;
    @AuraEnabled
    public Integer openRequests = 0;
    @AuraEnabled
    public String currencyCode;
  }

  public class BookingRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public String spaceName;
    @AuraEnabled
    public Datetime startAt;
    @AuraEnabled
    public Datetime endAt;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String label;
  }

  public class InvoiceRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date issueDate;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Integer daysOverdue;
    @AuraEnabled
    public Boolean payable;
    @AuraEnabled
    public String bookingName;
  }

  public class RequestRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public String spaceName;
    @AuraEnabled
    public Boolean isOpen;
  }

  public class PayLink {
    @AuraEnabled
    public String url;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
  }

  // ---------- Reads ----------

  @AuraEnabled(cacheable=false)
  public static Context getContext() {
    try {
      Id acct = myAccountId();
      Context c = new Context();
      User u = [
        SELECT FirstName, Contact.Account.Name
        FROM User
        WHERE Id = :UserInfo.getUserId()
      ];
      c.firstName = u.FirstName;
      c.accountName = u.Contact.Account.Name;
      Datetime now = Datetime.now();
      c.activeBookings = [
        SELECT COUNT()
        FROM PMS_Booking__c
        WHERE
          Account__c = :acct
          AND Status__c NOT IN ('Cancelled', 'Completed', 'No Show')
          AND End__c >= :now
      ];
      for (PMS_Invoice__c inv : [
        SELECT Balance__c, Status__c, Days_Overdue__c, Currency_Code__c
        FROM PMS_Invoice__c
        WHERE Account__c = :acct AND Status__c NOT IN :CLOSED_INVOICE
      ]) {
        if (inv.Balance__c == null || inv.Balance__c <= 0) {
          continue;
        }
        c.openInvoices++;
        c.openBalance += inv.Balance__c;
        if (
          inv.Status__c == 'Overdue' ||
          (inv.Days_Overdue__c != null &&
          inv.Days_Overdue__c > 0)
        ) {
          c.overdueInvoices++;
        }
        if (c.currencyCode == null) {
          c.currencyCode = inv.Currency_Code__c;
        }
      }
      c.openRequests = [
        SELECT COUNT()
        FROM Case
        WHERE AccountId = :acct AND Status NOT IN :CLOSED_CASE
      ];
      if (c.currencyCode == null) {
        c.currencyCode = UserInfo.getDefaultCurrency();
      }
      return c;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled(cacheable=false)
  public static List<BookingRow> getBookings() {
    try {
      Id acct = myAccountId();
      List<BookingRow> rows = new List<BookingRow>();
      for (PMS_Booking__c b : [
        SELECT
          Id,
          Name,
          RecordType.DeveloperName,
          Site__r.Name,
          Space__r.Name,
          Start__c,
          End__c,
          Status__c,
          Total_Amount__c,
          Balance_Due__c
        FROM PMS_Booking__c
        WHERE Account__c = :acct
        ORDER BY Start__c DESC
        LIMIT 100
      ]) {
        BookingRow r = new BookingRow();
        r.id = b.Id;
        r.name = b.Name;
        r.kind = KIND_BY_RT.containsKey(b.RecordType.DeveloperName)
          ? KIND_BY_RT.get(b.RecordType.DeveloperName)
          : 'Booking';
        r.siteName = b.Site__r.Name;
        r.spaceName = b.Space__r.Name;
        r.startAt = b.Start__c;
        r.endAt = b.End__c;
        r.status = b.Status__c;
        r.total = b.Total_Amount__c;
        r.balance = b.Balance_Due__c;
        r.label =
          r.kind +
          ' · ' +
          (r.spaceName != null ? r.spaceName + ', ' : '') +
          (r.siteName == null ? '' : r.siteName) +
          ' (' +
          b.Name +
          ')';
        rows.add(r);
      }
      return rows;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled(cacheable=false)
  public static List<InvoiceRow> getInvoices() {
    try {
      Id acct = myAccountId();
      List<InvoiceRow> rows = new List<InvoiceRow>();
      for (PMS_Invoice__c inv : [
        SELECT
          Id,
          Name,
          Issue_Date__c,
          Due_Date__c,
          Total__c,
          Balance__c,
          Status__c,
          Currency_Code__c,
          Days_Overdue__c,
          Booking__r.Name
        FROM PMS_Invoice__c
        WHERE Account__c = :acct AND Status__c != 'Draft'
        ORDER BY Issue_Date__c DESC NULLS LAST, Name DESC
        LIMIT 100
      ]) {
        InvoiceRow r = new InvoiceRow();
        r.id = inv.Id;
        r.name = inv.Name;
        r.issueDate = inv.Issue_Date__c;
        r.dueDate = inv.Due_Date__c;
        r.total = inv.Total__c;
        r.balance = inv.Balance__c;
        r.status = inv.Status__c;
        r.currencyCode = String.isBlank(inv.Currency_Code__c)
          ? UserInfo.getDefaultCurrency()
          : inv.Currency_Code__c;
        r.daysOverdue = inv.Days_Overdue__c == null
          ? 0
          : inv.Days_Overdue__c.intValue();
        r.payable =
          !CLOSED_INVOICE.contains(inv.Status__c) &&
          inv.Balance__c != null &&
          inv.Balance__c > 0;
        r.bookingName = inv.Booking__r.Name;
        rows.add(r);
      }
      return rows;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled(cacheable=false)
  public static List<RequestRow> getRequests() {
    try {
      Id acct = myAccountId();
      List<RequestRow> rows = new List<RequestRow>();
      for (Case c : [
        SELECT
          Id,
          CaseNumber,
          Subject,
          Status,
          CreatedDate,
          PMS_Site__r.Name,
          PMS_Space__r.Name
        FROM Case
        WHERE AccountId = :acct
        ORDER BY CreatedDate DESC
        LIMIT 100
      ]) {
        RequestRow r = new RequestRow();
        r.id = c.Id;
        r.caseNumber = c.CaseNumber;
        r.subject = c.Subject;
        r.status = c.Status;
        r.createdDate = c.CreatedDate;
        r.siteName = c.PMS_Site__r.Name;
        r.spaceName = c.PMS_Space__r.Name;
        r.isOpen = !CLOSED_CASE.contains(c.Status);
        rows.add(r);
      }
      return rows;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ---------- Writes ----------

  /** Creates a Stripe Checkout link for one of the user's own invoices. */
  @AuraEnabled
  public static PayLink payInvoice(Id invoiceId) {
    try {
      Id acct = myAccountId();
      List<PMS_Invoice__c> invs = [
        SELECT Id
        FROM PMS_Invoice__c
        WHERE Id = :invoiceId AND Account__c = :acct
        LIMIT 1
      ];
      if (invs.isEmpty()) {
        throw new PMS_Exception('Invoice not found.');
      }
      PMS_StripeCheckout.Result res = PMS_StripeCheckout.createForVerifiedInvoice(
        invoiceId
      );
      PayLink p = new PayLink();
      p.url = res.url;
      p.amount = res.amount;
      p.currencyCode = res.currencyCode;
      return p;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  /** Logs a service request (Case) for the user's account, optionally linked to one of their bookings. */
  @AuraEnabled
  public static String createRequest(
    String subject,
    String description,
    Id bookingId,
    Boolean entryPermission
  ) {
    try {
      Id acct = myAccountId();
      if (String.isBlank(subject)) {
        throw new PMS_Exception('Please describe the problem in a few words.');
      }
      User u = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId()];
      Case c = new Case(
        Subject = subject.trim().left(255),
        Description = description == null ? null : description.left(32000),
        Origin = 'Web',
        Status = 'New',
        Priority = 'Medium',
        AccountId = acct,
        ContactId = u.ContactId,
        Entry_Permission__c = entryPermission == true
      );
      if (bookingId != null) {
        List<PMS_Booking__c> bs = [
          SELECT Id, Site__c, Space__c, RecordType.DeveloperName
          FROM PMS_Booking__c
          WHERE Id = :bookingId AND Account__c = :acct
          LIMIT 1
        ];
        if (bs.isEmpty()) {
          throw new PMS_Exception('Booking not found.');
        }
        c.PMS_Booking__c = bs[0].Id;
        c.PMS_Site__c = bs[0].Site__c;
        c.PMS_Space__c = bs[0].Space__c;
        c.PMS_Module__c = MODULE_BY_RT.get(bs[0].RecordType.DeveloperName);
      }
      // Run the org's default case assignment rule so the request lands with the right team.
      Database.DMLOptions dmo = new Database.DMLOptions();
      dmo.assignmentRuleHeader.useDefaultRule = true;
      c.setOptions(dmo);
      insert c;
      return [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ---------- Helpers ----------

  @TestVisible
  private static Id myAccountId() {
    User u = [
      SELECT ContactId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    if (u.ContactId == null || u.Contact.AccountId == null) {
      throw new PMS_Exception(
        'This page is only available to customer accounts.'
      );
    }
    return u.Contact.AccountId;
  }

  private static AuraHandledException handled(Exception e) {
    String msg = e instanceof PMS_Exception
      ? e.getMessage()
      : 'Something went wrong. Please try again or contact us.';
    if (!(e instanceof PMS_Exception)) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS portal: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
    }
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    return ex;
  }
}
