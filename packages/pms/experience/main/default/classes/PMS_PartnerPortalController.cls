/**
 * Server side of the PMS Partner Portal (/partners), LWC pmsPartnerPortal.
 *
 * A partner user belongs to one account. That account is
 *   an OWNER  when it is the Owner Account of at least one site: statements and occupancy;
 *   a VENDOR  when it is the Vendor on at least one work order: jobs, quotes, photos and invoices.
 * An account can be both.
 *
 * External sharing on every PMS object is Private, so this class runs without sharing and every
 * query is pinned to the user's own account. Owners only see Published and Paid statements, and
 * summary figures for their own sites (no tenant names). Vendors only see their own work orders,
 * quotes, bills and the files they uploaded.
 */
public without sharing class PMS_PartnerPortalController {
  public static final Integer MAX_FILE_BYTES = 3500000; // the page shrinks photos before upload
  public static final Set<String> VISIBLE_STATEMENTS = new Set<String>{
    'Published',
    'Paid'
  };
  public static final Set<String> VENDOR_HIDDEN = new Set<String>{
    'New',
    'Cancelled'
  };
  public static final Set<String> CAN_QUOTE = new Set<String>{
    'Assigned',
    'Accepted',
    'Quote Requested',
    'Quoted'
  };
  public static final Set<String> CAN_START = new Set<String>{
    'Assigned',
    'Accepted',
    'Approved'
  };
  public static final Set<String> CAN_UPLOAD = new Set<String>{
    'Assigned',
    'Accepted',
    'Quote Requested',
    'Quoted',
    'Approved',
    'In Progress',
    'Completed'
  };
  private static final Set<String> FILE_KINDS = new Set<String>{
    'Photo',
    'Quote',
    'Invoice',
    'Document'
  };

  @TestVisible
  private static Id testAccountId;

  // ------------------------------------------------------------------ DTOs

  public class Home {
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String userName;
    @AuraEnabled
    public Boolean isOwner = false;
    @AuraEnabled
    public Boolean isVendor = false;
    @AuraEnabled
    public List<SiteSummary> sites = new List<SiteSummary>();
    @AuraEnabled
    public List<StatementRow> statements = new List<StatementRow>();
    @AuraEnabled
    public List<WorkOrderRow> workOrders = new List<WorkOrderRow>();
  }

  public class SiteSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String module;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public PMS_OwnerStatementService.Figures monthToDate;
    @AuraEnabled
    public List<UnitRow> units = new List<UnitRow>();
    @AuraEnabled
    public Integer openJobs = 0;
  }

  public class UnitRow {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date leaseEnd;
    @AuraEnabled
    public Decimal rent;
  }

  public class StatementRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Date periodStart;
    @AuraEnabled
    public Date periodEnd;
    @AuraEnabled
    public Decimal gross;
    @AuraEnabled
    public Decimal expenses;
    @AuraEnabled
    public Decimal fee;
    @AuraEnabled
    public Decimal net;
    @AuraEnabled
    public Decimal occupancyPct;
    @AuraEnabled
    public String occupancyBasis;
    @AuraEnabled
    public Decimal arrears;
    @AuraEnabled
    public String status;
  }

  public class StatementDetail {
    @AuraEnabled
    public StatementRow statement;
    @AuraEnabled
    public List<PMS_OwnerStatementService.Line> income;
    @AuraEnabled
    public List<PMS_OwnerStatementService.Line> costs;
    @AuraEnabled
    public Decimal feePercent;
  }

  public class WorkOrderRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String priority;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String accessInstructions;
    @AuraEnabled
    public Boolean entryPermission;
    @AuraEnabled
    public Date scheduledDate;
    @AuraEnabled
    public Date completedDate;
    @AuraEnabled
    public Decimal notToExceed;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String vendorNotes;
    @AuraEnabled
    public Datetime created;
    @AuraEnabled
    public Boolean canAccept = false;
    @AuraEnabled
    public Boolean canQuote = false;
    @AuraEnabled
    public Boolean canStart = false;
    @AuraEnabled
    public Boolean canComplete = false;
    @AuraEnabled
    public Boolean canBill = false;
    @AuraEnabled
    public Boolean canUpload = false;
    @AuraEnabled
    public List<QuoteRow> quotes = new List<QuoteRow>();
    @AuraEnabled
    public List<BillRow> bills = new List<BillRow>();
    @AuraEnabled
    public List<FileRow> files = new List<FileRow>();
  }

  public class QuoteRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal tax;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date validUntil;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String decisionNotes;
  }

  public class BillRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String invoiceNumber;
    @AuraEnabled
    public Date billDate;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date paidDate;
    @AuraEnabled
    public String notes;
  }

  public class FileRow {
    @AuraEnabled
    public Id versionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String extension;
    @AuraEnabled
    public Datetime created;
  }

  /** Sent by the page as JSON for quotes and bills. */
  public class MoneyForm {
    public Decimal amount;
    public Decimal tax;
    public String description;
    public String validUntil;
    public String invoiceNumber;
    public String billDate;
    public String dueDate;
  }

  // ------------------------------------------------------------------ home

  @AuraEnabled
  public static Home getHome() {
    try {
      Account a = myAccount();
      Home h = new Home();
      h.accountName = a.Name;
      h.userName = UserInfo.getFirstName();
      List<PMS_Site__c> sites = [
        SELECT
          Id,
          Name,
          Module__c,
          City__c,
          Currency_Code__c,
          Time_Zone__c,
          Owner_Account__c,
          Management_Fee_Percent__c
        FROM PMS_Site__c
        WHERE Owner_Account__c = :a.Id
        ORDER BY Name
        LIMIT 20
      ];
      h.isOwner = !sites.isEmpty();
      if (h.isOwner) {
        ownerData(h, sites, a.Id);
      }
      h.workOrders = workOrders(a.Id, null);
      h.isVendor =
        !h.workOrders.isEmpty() ||
        [
          SELECT COUNT()
          FROM PMS_Work_Order__c
          WHERE Vendor_Account__c = :a.Id
        ] > 0;
      return h;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  private static void ownerData(Home h, List<PMS_Site__c> sites, Id accountId) {
    Set<Id> siteIds = new Map<Id, PMS_Site__c>(sites).keySet();
    Map<Id, Integer> openJobs = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Site__c s, COUNT(Id) n
      FROM PMS_Work_Order__c
      WHERE
        Site__c IN :siteIds
        AND Status__c NOT IN ('Completed', 'Closed', 'Cancelled')
      GROUP BY Site__c
    ]) {
      openJobs.put((Id) ar.get('s'), (Integer) ar.get('n'));
    }
    Map<Id, List<UnitRow>> unitsBySite = units(siteIds);
    for (PMS_Site__c s : sites) {
      String zone = String.isBlank(s.Time_Zone__c)
        ? UserInfo.getTimeZone().getID()
        : s.Time_Zone__c;
      Date today = PMS_DateUtil.toLocalDate(Datetime.now(), zone);
      SiteSummary ss = new SiteSummary();
      ss.id = s.Id;
      ss.name = s.Name;
      ss.module = s.Module__c;
      ss.city = s.City__c;
      ss.currencyCode = s.Currency_Code__c;
      ss.monthToDate = PMS_OwnerStatementService.compute(
        s,
        today.toStartOfMonth(),
        today
      );
      ss.monthToDate.clearLines(); // totals only on the overview
      ss.openJobs = openJobs.containsKey(s.Id) ? openJobs.get(s.Id) : 0;
      ss.units = unitsBySite.containsKey(s.Id)
        ? unitsBySite.get(s.Id)
        : new List<UnitRow>();
      h.sites.add(ss);
    }
    for (PMS_Owner_Statement__c st : [
      SELECT
        Id,
        Name,
        Site__r.Name,
        Site__r.Currency_Code__c,
        Period_Start__c,
        Period_End__c,
        Gross_Rent__c,
        Expenses__c,
        Management_Fee__c,
        Net_Payout__c,
        Occupancy_Percent__c,
        Occupancy_Basis__c,
        Arrears__c,
        Status__c
      FROM PMS_Owner_Statement__c
      WHERE Owner_Account__c = :accountId AND Status__c IN :VISIBLE_STATEMENTS
      ORDER BY Period_Start__c DESC, Site__r.Name
      LIMIT 60
    ]) {
      h.statements.add(toRow(st));
    }
  }

  /** Units of property sites, with let/vacant status. Tenant names are deliberately not shown. */
  private static Map<Id, List<UnitRow>> units(Set<Id> siteIds) {
    Map<Id, List<UnitRow>> result = new Map<Id, List<UnitRow>>();
    Map<Id, UnitRow> byUnit = new Map<Id, UnitRow>();
    for (PMS_Space__c sp : [
      SELECT Id, Name, Site__c, Base_Rate__c
      FROM PMS_Space__c
      WHERE
        Site__c IN :siteIds
        AND Bookable__c = TRUE
        AND Site__r.Module__c = 'Property'
      ORDER BY Name
      LIMIT 500
    ]) {
      UnitRow u = new UnitRow();
      u.name = sp.Name;
      u.status = 'Vacant';
      byUnit.put(sp.Id, u);
      if (!result.containsKey(sp.Site__c)) {
        result.put(sp.Site__c, new List<UnitRow>());
      }
      result.get(sp.Site__c).add(u);
    }
    if (byUnit.isEmpty()) {
      return result;
    }
    for (PMS_Booking__c l : [
      SELECT Space__c, End__c, Rate_Amount__c, Status__c
      FROM PMS_Booking__c
      WHERE
        Space__c IN :byUnit.keySet()
        AND RecordType.DeveloperName = 'Lease'
        AND Status__c IN ('Confirmed', 'Active')
      ORDER BY Start__c DESC
    ]) {
      UnitRow u = byUnit.get(l.Space__c);
      if (u.status != 'Vacant') {
        continue;
      }
      u.status = l.Status__c == 'Active' ? 'Let' : 'Let from soon';
      u.leaseEnd = l.End__c == null ? null : l.End__c.date();
      u.rent = l.Rate_Amount__c;
    }
    return result;
  }

  // ------------------------------------------------------------------ owner statements

  @AuraEnabled
  public static StatementDetail getStatement(Id statementId) {
    try {
      Account a = myAccount();
      List<PMS_Owner_Statement__c> sts = [
        SELECT
          Id,
          Name,
          Site__c,
          Site__r.Name,
          Site__r.Currency_Code__c,
          Period_Start__c,
          Period_End__c,
          Gross_Rent__c,
          Expenses__c,
          Management_Fee__c,
          Net_Payout__c,
          Occupancy_Percent__c,
          Occupancy_Basis__c,
          Arrears__c,
          Status__c
        FROM PMS_Owner_Statement__c
        WHERE
          Id = :statementId
          AND Owner_Account__c = :a.Id
          AND Status__c IN :VISIBLE_STATEMENTS
        LIMIT 1
      ];
      if (sts.isEmpty()) {
        throw new PMS_Exception('Statement not found.');
      }
      PMS_Owner_Statement__c st = sts[0];
      PMS_OwnerStatementService.Figures f = PMS_OwnerStatementService.compute(
        PMS_OwnerStatementService.site(st.Site__c),
        st.Period_Start__c,
        st.Period_End__c
      );
      StatementDetail d = new StatementDetail();
      d.statement = toRow(st); // the published totals are what count
      d.income = f.getIncome();
      d.costs = f.getCosts();
      d.feePercent = f.getFeePercent();
      return d;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  private static StatementRow toRow(PMS_Owner_Statement__c st) {
    StatementRow r = new StatementRow();
    r.id = st.Id;
    r.name = st.Name;
    r.siteName = st.Site__r?.Name;
    r.currencyCode = st.Site__r?.Currency_Code__c;
    r.periodStart = st.Period_Start__c;
    r.periodEnd = st.Period_End__c;
    r.gross = st.Gross_Rent__c;
    r.expenses = st.Expenses__c;
    r.fee = st.Management_Fee__c;
    r.net = st.Net_Payout__c;
    r.occupancyPct = st.Occupancy_Percent__c;
    r.occupancyBasis = st.Occupancy_Basis__c;
    r.arrears = st.Arrears__c;
    r.status = st.Status__c;
    return r;
  }

  // ------------------------------------------------------------------ vendor: work orders

  private static List<WorkOrderRow> workOrders(Id accountId, Id onlyId) {
    String soql =
      'SELECT Id, Name, Subject__c, Status__c, Priority__c, Description__c, Access_Instructions__c, ' +
      'Entry_Permission__c, Scheduled_Date__c, Completed_Date__c, Not_To_Exceed__c, Currency_Code__c, Vendor_Notes__c, ' +
      'CreatedDate, Site__r.Name, Site__r.Street__c, Site__r.City__c, Space__r.Name, ' +
      '(SELECT Id, Name, Amount__c, Tax_Amount__c, Total__c, Status__c, Valid_Until__c, Description__c, Decision_Notes__c ' +
      ' FROM Quotes__r WHERE Vendor_Account__c = :accountId ORDER BY CreatedDate DESC), ' +
      '(SELECT Id, Name, Vendor_Invoice_Number__c, Bill_Date__c, Due_Date__c, Total__c, Status__c, Paid_Date__c, Notes__c ' +
      ' FROM Bills__r WHERE Vendor_Account__c = :accountId ORDER BY CreatedDate DESC) ' +
      'FROM PMS_Work_Order__c WHERE Vendor_Account__c = :accountId AND Status__c NOT IN :hidden ' +
      (onlyId == null ? '' : 'AND Id = :onlyId ') +
      'ORDER BY CreatedDate DESC LIMIT 100';
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => accountId,
      'hidden' => VENDOR_HIDDEN
    };
    if (onlyId != null) {
      binds.put('onlyId', onlyId);
    }
    List<PMS_Work_Order__c> wos = Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    Map<Id, List<FileRow>> fileMap = filesFor(
      new Map<Id, PMS_Work_Order__c>(wos).keySet()
    );
    List<WorkOrderRow> rows = new List<WorkOrderRow>();
    for (PMS_Work_Order__c w : wos) {
      WorkOrderRow r = new WorkOrderRow();
      r.id = w.Id;
      r.name = w.Name;
      r.subject = w.Subject__c;
      r.status = w.Status__c;
      r.priority = w.Priority__c;
      List<String> loc = new List<String>();
      if (w.Space__r != null) {
        loc.add(w.Space__r.Name);
      }
      if (w.Site__r != null) {
        loc.add(w.Site__r.Name);
        if (String.isNotBlank(w.Site__r.Street__c)) {
          loc.add(w.Site__r.Street__c.replace('\n', ', '));
        }
        if (String.isNotBlank(w.Site__r.City__c)) {
          loc.add(w.Site__r.City__c);
        }
      }
      r.location = String.join(loc, ', ');
      r.description = w.Description__c;
      r.accessInstructions = w.Access_Instructions__c;
      r.entryPermission = w.Entry_Permission__c;
      r.scheduledDate = w.Scheduled_Date__c;
      r.completedDate = w.Completed_Date__c;
      r.notToExceed = w.Not_To_Exceed__c;
      r.currencyCode = w.Currency_Code__c;
      r.vendorNotes = w.Vendor_Notes__c;
      r.created = w.CreatedDate;
      Boolean billed = false;
      for (PMS_Vendor_Bill__c b : w.Bills__r) {
        BillRow br = new BillRow();
        br.id = b.Id;
        br.name = b.Name;
        br.invoiceNumber = b.Vendor_Invoice_Number__c;
        br.billDate = b.Bill_Date__c;
        br.dueDate = b.Due_Date__c;
        br.total = b.Total__c;
        br.status = b.Status__c;
        br.paidDate = b.Paid_Date__c;
        br.notes = b.Notes__c;
        r.bills.add(br);
        billed = billed || b.Status__c != 'Rejected';
      }
      for (PMS_Vendor_Quote__c q : w.Quotes__r) {
        QuoteRow qr = new QuoteRow();
        qr.id = q.Id;
        qr.name = q.Name;
        qr.amount = q.Amount__c;
        qr.tax = q.Tax_Amount__c;
        qr.total = q.Total__c;
        qr.status = q.Status__c;
        qr.validUntil = q.Valid_Until__c;
        qr.description = q.Description__c;
        qr.decisionNotes = q.Decision_Notes__c;
        r.quotes.add(qr);
      }
      r.canAccept = w.Status__c == 'Assigned';
      r.canQuote = CAN_QUOTE.contains(w.Status__c);
      r.canStart = CAN_START.contains(w.Status__c);
      r.canComplete = w.Status__c == 'In Progress';
      r.canBill = w.Status__c == 'Completed' && !billed;
      r.canUpload = CAN_UPLOAD.contains(w.Status__c);
      r.files = fileMap.containsKey(w.Id)
        ? fileMap.get(w.Id)
        : new List<FileRow>();
      rows.add(r);
    }
    return rows;
  }

  /** Files the current user uploaded to these work orders (and to their quotes and bills). */
  private static Map<Id, List<FileRow>> filesFor(Set<Id> woIds) {
    Map<Id, List<FileRow>> result = new Map<Id, List<FileRow>>();
    if (woIds.isEmpty()) {
      return result;
    }
    Map<Id, Id> docToWo = new Map<Id, Id>();
    for (ContentDocumentLink l : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :woIds
    ]) {
      docToWo.put(l.ContentDocumentId, l.LinkedEntityId);
    }
    if (docToWo.isEmpty()) {
      return result;
    }
    Id me = UserInfo.getUserId();
    for (ContentVersion v : [
      SELECT
        Id,
        Title,
        FileExtension,
        Description,
        CreatedDate,
        ContentDocumentId
      FROM ContentVersion
      WHERE
        ContentDocumentId IN :docToWo.keySet()
        AND IsLatest = TRUE
        AND CreatedById = :me
      ORDER BY CreatedDate DESC
    ]) {
      Id woId = docToWo.get(v.ContentDocumentId);
      FileRow f = new FileRow();
      f.versionId = v.Id;
      f.title = v.Title;
      f.extension = v.FileExtension;
      f.kind = kindOf(v.Description);
      f.created = v.CreatedDate;
      if (!result.containsKey(woId)) {
        result.put(woId, new List<FileRow>());
      }
      result.get(woId).add(f);
    }
    return result;
  }

  // ------------------------------------------------------------------ vendor: actions

  @AuraEnabled
  public static WorkOrderRow acceptWorkOrder(Id workOrderId) {
    try {
      PMS_Work_Order__c w = myWorkOrder(
        workOrderId,
        new Set<String>{ 'Assigned' },
        'This job can no longer be accepted.'
      );
      update new PMS_Work_Order__c(Id = w.Id, Status__c = 'Accepted');
      PMS_WorkOrderService.emailStaff(
        w.Id,
        'Vendor accepted the job',
        new List<String[]>()
      );
      return reload(w.Id);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static WorkOrderRow submitQuote(
    Id workOrderId,
    String formJson,
    String fileName,
    String base64Data
  ) {
    try {
      PMS_Work_Order__c w = myWorkOrder(
        workOrderId,
        CAN_QUOTE,
        'Quotes can no longer be submitted for this job.'
      );
      MoneyForm f = form(formJson);
      checkMoney(f);
      if (String.isBlank(f.description)) {
        throw new PMS_Exception('Describe the work the quote covers.');
      }
      Date validUntil = optionalDate(f.validUntil, 'valid-until date');
      List<PMS_Vendor_Quote__c> open = [
        SELECT Id
        FROM PMS_Vendor_Quote__c
        WHERE
          Work_Order__c = :w.Id
          AND Vendor_Account__c = :w.Vendor_Account__c
          AND Status__c = 'Submitted'
      ];
      for (PMS_Vendor_Quote__c o : open) {
        o.Status__c = 'Withdrawn';
        o.Decision_Notes__c = 'Replaced by a newer quote from the vendor.';
      }
      update open;
      PMS_Vendor_Quote__c q = new PMS_Vendor_Quote__c(
        Work_Order__c = w.Id,
        Vendor_Account__c = w.Vendor_Account__c,
        Amount__c = f.amount.setScale(2),
        Tax_Amount__c = f.tax == null ? 0 : f.tax.setScale(2),
        Description__c = f.description.left(32000),
        Valid_Until__c = validUntil,
        Status__c = 'Submitted'
      );
      insert q;
      update new PMS_Work_Order__c(Id = w.Id, Status__c = 'Quoted');
      if (String.isNotBlank(base64Data)) {
        saveFile(new List<Id>{ w.Id, q.Id }, 'Quote', fileName, base64Data);
      }
      PMS_WorkOrderService.emailStaff(
        w.Id,
        'Quote submitted',
        new List<String[]>{
          new List<String>{
            'Amount',
            PMS_WorkOrderService.money(
              q.Amount__c + q.Tax_Amount__c,
              w.Currency_Code__c
            ) + ' incl. tax'
          },
          new List<String>{ 'Scope', f.description.abbreviate(300) }
        }
      );
      return reload(w.Id);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static WorkOrderRow startWork(Id workOrderId) {
    try {
      PMS_Work_Order__c w = myWorkOrder(
        workOrderId,
        CAN_START,
        'This job can\'t be started now.'
      );
      update new PMS_Work_Order__c(Id = w.Id, Status__c = 'In Progress');
      PMS_WorkOrderService.emailStaff(
        w.Id,
        'Work started',
        new List<String[]>()
      );
      return reload(w.Id);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static WorkOrderRow completeWork(Id workOrderId, String notes) {
    try {
      PMS_Work_Order__c w = myWorkOrder(
        workOrderId,
        new Set<String>{ 'In Progress' },
        'Start the job before completing it.'
      );
      if (String.isBlank(notes)) {
        throw new PMS_Exception('Describe what was done.');
      }
      update new PMS_Work_Order__c(
        Id = w.Id,
        Status__c = 'Completed',
        Completed_Date__c = Date.today(),
        Vendor_Notes__c = notes.trim().left(32000)
      );
      PMS_WorkOrderService.emailStaff(
        w.Id,
        'Work completed',
        new List<String[]>{
          new List<String>{ 'Report', notes.trim().abbreviate(500) }
        }
      );
      return reload(w.Id);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static WorkOrderRow submitBill(
    Id workOrderId,
    String formJson,
    String fileName,
    String base64Data
  ) {
    try {
      PMS_Work_Order__c w = myWorkOrder(
        workOrderId,
        new Set<String>{ 'Completed' },
        'Complete the job before sending the invoice.'
      );
      if (
        [
          SELECT COUNT()
          FROM PMS_Vendor_Bill__c
          WHERE
            Work_Order__c = :w.Id
            AND Vendor_Account__c = :w.Vendor_Account__c
            AND Status__c != 'Rejected'
        ] > 0
      ) {
        throw new PMS_Exception(
          'An invoice for this job has already been sent.'
        );
      }
      MoneyForm f = form(formJson);
      checkMoney(f);
      if (String.isBlank(f.invoiceNumber)) {
        throw new PMS_Exception('Enter your invoice number.');
      }
      if (String.isBlank(base64Data)) {
        throw new PMS_Exception('Attach the invoice (PDF or photo).');
      }
      Date billDate = optionalDate(f.billDate, 'invoice date');
      Date dueDate = optionalDate(f.dueDate, 'due date');
      PMS_Vendor_Bill__c b = new PMS_Vendor_Bill__c(
        Work_Order__c = w.Id,
        Site__c = w.Site__c,
        Vendor_Account__c = w.Vendor_Account__c,
        Vendor_Invoice_Number__c = f.invoiceNumber.trim().left(40),
        Bill_Date__c = billDate == null ? Date.today() : billDate,
        Due_Date__c = dueDate == null ? Date.today().addDays(30) : dueDate,
        Amount__c = f.amount.setScale(2),
        Tax_Amount__c = f.tax == null ? 0 : f.tax.setScale(2),
        Notes__c = f.description == null ? null : f.description.left(32000),
        Status__c = 'Submitted'
      );
      insert b;
      saveFile(new List<Id>{ w.Id, b.Id }, 'Invoice', fileName, base64Data);
      Decimal total = b.Amount__c + b.Tax_Amount__c;
      List<String[]> rows = new List<String[]>{
        new List<String>{ 'Invoice', b.Vendor_Invoice_Number__c },
        new List<String>{
          'Amount',
          PMS_WorkOrderService.money(total, w.Currency_Code__c) + ' incl. tax'
        }
      };
      if (w.Not_To_Exceed__c != null && total > w.Not_To_Exceed__c) {
        rows.add(
          new List<String>{
            'Warning',
            'Above the approved amount of ' +
            PMS_WorkOrderService.money(w.Not_To_Exceed__c, w.Currency_Code__c)
          }
        );
      }
      PMS_WorkOrderService.emailStaff(w.Id, 'Invoice submitted', rows);
      return reload(w.Id);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static WorkOrderRow uploadFile(
    Id workOrderId,
    String kind,
    String fileName,
    String base64Data
  ) {
    try {
      PMS_Work_Order__c w = myWorkOrder(
        workOrderId,
        CAN_UPLOAD,
        'Files can no longer be added to this job.'
      );
      if (String.isBlank(base64Data)) {
        throw new PMS_Exception('Choose a file.');
      }
      saveFile(
        new List<Id>{ w.Id },
        FILE_KINDS.contains(kind) ? kind : 'Photo',
        fileName,
        base64Data
      );
      return reload(w.Id);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ helpers

  @TestVisible
  private static Account myAccount() {
    Id accountId;
    if (Test.isRunningTest() && testAccountId != null) {
      accountId = testAccountId;
    } else {
      User u = [
        SELECT ContactId, Contact.AccountId
        FROM User
        WHERE Id = :UserInfo.getUserId()
      ];
      accountId = u.Contact?.AccountId;
    }
    if (accountId == null) {
      throw new PMS_Exception(
        'This portal is for owners and vendors. Your login is not linked to a partner account.'
      );
    }
    return [SELECT Id, Name FROM Account WHERE Id = :accountId];
  }

  private static PMS_Work_Order__c myWorkOrder(
    Id workOrderId,
    Set<String> allowed,
    String notAllowed
  ) {
    Account a = myAccount();
    List<PMS_Work_Order__c> ws = [
      SELECT
        Id,
        Name,
        Status__c,
        Site__c,
        Vendor_Account__c,
        Currency_Code__c,
        Not_To_Exceed__c
      FROM PMS_Work_Order__c
      WHERE Id = :workOrderId AND Vendor_Account__c = :a.Id
      LIMIT 1
    ];
    if (ws.isEmpty()) {
      throw new PMS_Exception('Work order not found.');
    }
    if (allowed != null && !allowed.contains(ws[0].Status__c)) {
      throw new PMS_Exception(notAllowed);
    }
    return ws[0];
  }

  private static WorkOrderRow reload(Id workOrderId) {
    List<WorkOrderRow> rows = workOrders(myAccount().Id, workOrderId);
    return rows.isEmpty() ? null : rows[0];
  }

  @TestVisible
  private static void saveFile(
    List<Id> linkTo,
    String kind,
    String fileName,
    String base64Data
  ) {
    Blob data;
    try {
      data = EncodingUtil.base64Decode(
        base64Data.contains(',') ? base64Data.substringAfter(',') : base64Data
      );
    } catch (Exception e) {
      throw new PMS_Exception('The file could not be read. Please try again.');
    }
    if (data.size() == 0) {
      throw new PMS_Exception('The file is empty.');
    }
    if (data.size() > MAX_FILE_BYTES) {
      throw new PMS_Exception(
        'The file is too large (max 3.5 MB). Please send a smaller PDF or photo.'
      );
    }
    String name = String.isBlank(fileName)
      ? kind.toLowerCase() + '.jpg'
      : fileName.replaceAll('[\\\\/:*?"<>|]', '_').left(200);
    String ext = name.contains('.')
      ? name.substringAfterLast('.').toLowerCase()
      : '';
    if (
      !new Set<String>{ 'jpg', 'jpeg', 'png', 'heic', 'webp', 'gif', 'pdf' }
        .contains(ext)
    ) {
      throw new PMS_Exception('Upload a PDF or a photo (JPG, PNG, HEIC).');
    }
    ContentVersion v = new ContentVersion(
      Title = name.substringBeforeLast('.').left(255),
      PathOnClient = name,
      VersionData = data,
      Description = 'PMS:' + kind
    );
    insert v;
    Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :v.Id]
    .ContentDocumentId;
    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
    for (Id target : linkTo) {
      links.add(
        new ContentDocumentLink(
          ContentDocumentId = docId,
          LinkedEntityId = target,
          ShareType = 'V',
          Visibility = 'AllUsers'
        )
      );
    }
    insert links;
  }

  private static String kindOf(String description) {
    if (description != null && description.startsWith('PMS:')) {
      return description.substringAfter('PMS:');
    }
    return 'Document';
  }

  private static MoneyForm form(String json) {
    try {
      MoneyForm f = (MoneyForm) System.JSON.deserialize(json, MoneyForm.class);
      if (f == null) {
        throw new PMS_Exception('Fill in the form.');
      }
      return f;
    } catch (PMS_Exception e) {
      throw e;
    } catch (Exception e) {
      throw new PMS_Exception('Check the amounts and dates you entered.');
    }
  }

  private static void checkMoney(MoneyForm f) {
    if (f.amount == null || f.amount <= 0) {
      throw new PMS_Exception('Enter the amount excluding tax.');
    }
    if (
      f.amount > 10000000 || (f.tax != null && (f.tax < 0 || f.tax > f.amount))
    ) {
      throw new PMS_Exception('Check the amount and tax.');
    }
  }

  private static Date optionalDate(String value, String label) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Date.valueOf(value.trim());
    } catch (Exception e) {
      throw new PMS_Exception('Choose a valid ' + label + '.');
    }
  }

  private static AuraHandledException handled(Exception e) {
    String msg = e instanceof PMS_Exception
      ? e.getMessage()
      : 'Something went wrong. Please try again or contact us.';
    if (!(e instanceof PMS_Exception)) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS partner portal: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
    }
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    return ex;
  }
}
