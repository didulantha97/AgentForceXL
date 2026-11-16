/**
 * "Revenue: needs attention" for the PMS app home pages.
 *
 * Brings the five revenue packages onto the home pages without touching PMS_HomeController:
 * cards and deposits still missing, card holds about to expire, cancellation / no-show fees waiting,
 * refunds due, invoices in the reminder process, overdue payment-plan instalments, rent adjustments
 * to approve or send, and channel-manager problems.
 *
 * One cacheable call per page. Every query runs in user mode, so the PMS access rules and field
 * security apply. A block that fails is skipped and reported as a warning; the rest still loads.
 * Amounts are left out for users with PMS_Hide_Amounts, names for PMS_Hide_Customer_Details.
 *
 * reportIds() resolves the "Open report" links at runtime, so no org-specific report ids are
 * hard-coded in the LWC (needed for the 2GP package).
 */
public with sharing class PMS_RevenueHomeController {
  static final Integer MAX_ROWS = 5;
  static final Integer MAX_QUERY = 200;

  /**
   * Item key => report developer name (clean names used in the packaged report metadata) and
   * report name (fallback for orgs where the reports were created in the UI with a random suffix).
   */
  @TestVisible
  static final Map<String, List<String>> REPORTS = new Map<String, List<String>>{
    'reminders' => new List<String>{
      'PMS_Invoices_by_Reminder_Stage',
      'PMS Invoices by Reminder Stage'
    },
    'cards' => new List<String>{
      'PMS_Bookings_by_Card_and_Deposit_Status',
      'PMS Bookings by Card and Deposit Status'
    },
    'rent' => new List<String>{
      'PMS_Rent_Adjustments',
      'PMS Rent Adjustments'
    },
    'channelErrors' => new List<String>{
      'PMS_Channel_Errors_24_h',
      'PMS Channel Errors (24 h)'
    }
  };

  public class Row {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String detail;
    @AuraEnabled
    public String url;
  }

  public class Item {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String hintText;
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public Boolean more = false;
    /** info, warning or error */
    @AuraEnabled
    public String severity = 'warning';
    @AuraEnabled
    public List<Row> rows = new List<Row>();
  }

  public class Result {
    @AuraEnabled
    public List<Item> items = new List<Item>();
    @AuraEnabled
    public List<String> warnings = new List<String>();
    @AuraEnabled
    public Boolean hideAmounts = false;
  }

  @TestVisible
  static Boolean hideAmounts = false;
  @TestVisible
  static Boolean hideCustomers = false;

  /**
   * Item key => report id for the reports the running user can see. Matches the clean developer
   * name first, then the report name. Keys without a visible report are left out (no link shown).
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Id> reportIds() {
    Map<String, Id> out = new Map<String, Id>();
    try {
      Set<String> devNames = new Set<String>();
      Set<String> names = new Set<String>();
      for (List<String> r : REPORTS.values()) {
        devNames.add(r[0]);
        names.add(r[1]);
      }
      Map<String, Id> byDev = new Map<String, Id>();
      Map<String, Id> byName = new Map<String, Id>();
      for (Report r : [
        SELECT Id, DeveloperName, Name
        FROM Report
        WHERE DeveloperName IN :devNames OR Name IN :names
        WITH USER_MODE
        ORDER BY CreatedDate
      ]) {
        if (devNames.contains(r.DeveloperName)) {
          byDev.put(r.DeveloperName, r.Id);
        }
        if (names.contains(r.Name) && !byName.containsKey(r.Name)) {
          byName.put(r.Name, r.Id);
        }
      }
      for (String key : REPORTS.keySet()) {
        List<String> r = REPORTS.get(key);
        Id id = byDev.containsKey(r[0]) ? byDev.get(r[0]) : byName.get(r[1]);
        if (id != null) {
          out.put(key, id);
        }
      }
    } catch (Exception e) {
      // No links rather than a broken card.
      System.debug(LoggingLevel.WARN, 'reportIds: ' + e.getMessage());
    }
    return out;
  }

  /** module: Admin, Hotel, Property, Projects or Practice (blank = Admin). */
  @AuraEnabled(cacheable=true)
  public static Result getAttention(String module) {
    String m = String.isBlank(module) ? 'Admin' : module;
    Result res = new Result();
    hideAmounts = FeatureManagement.checkPermission('PMS_Hide_Amounts');
    hideCustomers = FeatureManagement.checkPermission(
      'PMS_Hide_Customer_Details'
    );
    res.hideAmounts = hideAmounts;

    String bookingRt = bookingRecordType(m);
    String invoiceRt = invoiceRecordType(m);
    Boolean hasBookings = m != 'Projects';

    if (hasBookings) {
      add(res, 'cards', m, bookingRt, invoiceRt);
      add(res, 'holds', m, bookingRt, invoiceRt);
      add(res, 'fees', m, bookingRt, invoiceRt);
      add(res, 'refunds', m, bookingRt, invoiceRt);
    }
    add(res, 'reminders', m, bookingRt, invoiceRt);
    add(res, 'instalments', m, bookingRt, invoiceRt);
    if (m == 'Property' || m == 'Admin') {
      add(res, 'rent', m, bookingRt, invoiceRt);
    }
    if (m == 'Hotel' || m == 'Admin') {
      add(res, 'channelErrors', m, bookingRt, invoiceRt);
      add(res, 'otaUnassigned', m, bookingRt, invoiceRt);
    }
    return res;
  }

  static void add(
    Result res,
    String key,
    String m,
    String bookingRt,
    String invoiceRt
  ) {
    try {
      Item it;
      switch on key {
        when 'cards' {
          it = cards(bookingRt);
        }
        when 'holds' {
          it = holds(bookingRt);
        }
        when 'fees' {
          it = fees(bookingRt);
        }
        when 'refunds' {
          it = refunds(bookingRt);
        }
        when 'reminders' {
          it = reminders(invoiceRt);
        }
        when 'instalments' {
          it = instalments(invoiceRt);
        }
        when 'rent' {
          it = rent();
        }
        when 'channelErrors' {
          it = channelErrors();
        }
        when 'otaUnassigned' {
          it = otaUnassigned();
        }
      }
      if (it != null) {
        it.key = key;
        res.items.add(it);
      }
    } catch (Exception e) {
      res.warnings.add(key + ': ' + e.getMessage());
    }
  }

  // ------------------------------------------------------------------ blocks

  static Item cards(String rt) {
    Datetime now = Datetime.now();
    String q =
      'SELECT Id, Name, Start__c, Guarantee_Status__c, Guarantee_Message__c, Site__r.Name, Account__r.Name ' +
      'FROM PMS_Booking__c WHERE Guarantee_Status__c IN (\'Awaiting Card\', \'Action Needed\') ' +
      'AND Status__c NOT IN (\'Cancelled\', \'No Show\', \'Completed\') AND Start__c >= :now' +
      rtFilter('RecordType.DeveloperName', rt) +
      ' ORDER BY Start__c LIMIT ' +
      MAX_QUERY;
    List<PMS_Booking__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'now' => now, 'rt' => rt },
      AccessLevel.USER_MODE
    );
    Item it = item(
      'Card or deposit missing',
      'Upcoming bookings whose payment policy still needs a card or a deposit.',
      recs.size()
    );
    for (PMS_Booking__c b : recs) {
      if (b.Guarantee_Status__c == 'Action Needed') {
        it.severity = 'error';
      }
      if (it.rows.size() < MAX_ROWS) {
        it.rows.add(
          row(
            b.Id,
            b.Name,
            join(
              new List<String>{
                b.Guarantee_Status__c,
                'starts ' + fmt(b.Start__c),
                customer(b.Account__r?.Name),
                b.Guarantee_Message__c
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item holds(String rt) {
    Datetime soon = Datetime.now().addHours(24);
    String q =
      'SELECT Id, Name, Preauth_Expires_At__c, Preauth_Amount__c, CurrencyIsoCode, Account__r.Name ' +
      'FROM PMS_Booking__c WHERE Preauth_Status__c = \'Authorized\' AND Preauth_Expires_At__c <= :soon' +
      rtFilter('RecordType.DeveloperName', rt) +
      ' ORDER BY Preauth_Expires_At__c LIMIT ' +
      MAX_QUERY;
    List<PMS_Booking__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'soon' => soon, 'rt' => rt },
      AccessLevel.USER_MODE
    );
    Item it = item(
      'Card holds expiring',
      'Card holds that expire within 24 hours: capture or release them.',
      recs.size()
    );
    for (PMS_Booking__c b : recs) {
      if (it.rows.size() < MAX_ROWS) {
        it.rows.add(
          row(
            b.Id,
            b.Name,
            join(
              new List<String>{
                'expires ' + fmt(b.Preauth_Expires_At__c),
                money(b.Preauth_Amount__c, b.CurrencyIsoCode),
                customer(b.Account__r?.Name)
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item fees(String rt) {
    String q =
      'SELECT Id, Name, Status__c, Policy_Fee_Amount__c, CurrencyIsoCode, Policy_Event_At__c, Account__r.Name ' +
      'FROM PMS_Booking__c WHERE Policy_Pending__c = TRUE' +
      rtFilter('RecordType.DeveloperName', rt) +
      ' ORDER BY Policy_Event_At__c DESC LIMIT ' +
      MAX_QUERY;
    List<PMS_Booking__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'rt' => rt },
      AccessLevel.USER_MODE
    );
    Item it = item(
      'Cancellation / no-show fees waiting',
      'Fees the payment policy allows but that have not been charged yet.',
      recs.size()
    );
    for (PMS_Booking__c b : recs) {
      if (it.rows.size() < MAX_ROWS) {
        it.rows.add(
          row(
            b.Id,
            b.Name,
            join(
              new List<String>{
                b.Status__c,
                money(b.Policy_Fee_Amount__c, b.CurrencyIsoCode),
                customer(b.Account__r?.Name)
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item refunds(String rt) {
    String q =
      'SELECT Id, Name, Refund_Due__c, CurrencyIsoCode, Account__r.Name ' +
      'FROM PMS_Booking__c WHERE Refund_Due__c > 0' +
      rtFilter('RecordType.DeveloperName', rt) +
      ' ORDER BY LastModifiedDate DESC LIMIT ' +
      MAX_QUERY;
    List<PMS_Booking__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'rt' => rt },
      AccessLevel.USER_MODE
    );
    Item it = item(
      'Refunds due',
      'Deposits or prepayments to give back.',
      recs.size()
    );
    for (PMS_Booking__c b : recs) {
      if (it.rows.size() < MAX_ROWS) {
        it.rows.add(
          row(
            b.Id,
            b.Name,
            join(
              new List<String>{
                money(b.Refund_Due__c, b.CurrencyIsoCode),
                customer(b.Account__r?.Name)
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item reminders(String rt) {
    String q =
      'SELECT Id, Name, Dunning_Stage__c, Dunning_Paused__c, Days_Overdue__c, Balance__c, CurrencyIsoCode, Account__r.Name ' +
      'FROM PMS_Invoice__c WHERE Dunning_Stage__c != NULL AND Balance__c > 0' +
      rtFilter('RecordType.DeveloperName', rt) +
      ' ORDER BY Days_Overdue__c DESC NULLS LAST LIMIT ' +
      MAX_QUERY;
    List<PMS_Invoice__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'rt' => rt },
      AccessLevel.USER_MODE
    );
    Map<String, Integer> byStage = new Map<String, Integer>();
    Item it = item('Invoices in reminders', null, recs.size());
    for (PMS_Invoice__c inv : recs) {
      byStage.put(
        inv.Dunning_Stage__c,
        (byStage.containsKey(inv.Dunning_Stage__c)
          ? byStage.get(inv.Dunning_Stage__c)
          : 0) + 1
      );
      if (inv.Dunning_Stage__c == 'Collections') {
        it.severity = 'error';
      }
      if (it.rows.size() < MAX_ROWS) {
        String days = inv.Days_Overdue__c == null
          ? null
          : String.valueOf(inv.Days_Overdue__c.intValue()) + ' days overdue';
        it.rows.add(
          row(
            inv.Id,
            inv.Name,
            join(
              new List<String>{
                inv.Dunning_Stage__c +
                (inv.Dunning_Paused__c ? ' (paused)' : ''),
                days,
                money(inv.Balance__c, inv.CurrencyIsoCode),
                customer(inv.Account__r?.Name)
              }
            )
          )
        );
      }
    }
    List<String> parts = new List<String>();
    for (
      String stage : new List<String>{
        'Reminder 1',
        'Reminder 2',
        'Plan Offered',
        'Payment Plan',
        'Collections'
      }
    ) {
      if (byStage.containsKey(stage)) {
        parts.add(stage + ': ' + byStage.get(stage));
      }
    }
    it.hintText = parts.isEmpty()
      ? 'Overdue invoices the daily reminder run is working on.'
      : String.join(parts, ' · ');
    return it;
  }

  static Item instalments(String rt) {
    Date today = Date.today();
    String q =
      'SELECT Id, Number__c, Due_Date__c, Amount__c, CurrencyIsoCode, Status__c, Plan__r.Invoice__c, Plan__r.Invoice__r.Name, Plan__r.Invoice__r.Account__r.Name ' +
      'FROM PMS_Payment_Plan_Instalment__c WHERE Due_Date__c < :today AND Status__c NOT IN (\'Paid\', \'Cancelled\', \'Waived\')' +
      rtFilter('Plan__r.Invoice__r.RecordType.DeveloperName', rt) +
      ' ORDER BY Due_Date__c LIMIT ' +
      MAX_QUERY;
    List<PMS_Payment_Plan_Instalment__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'today' => today, 'rt' => rt },
      AccessLevel.USER_MODE
    );
    Item it = item(
      'Plan instalments overdue',
      'Payment-plan instalments past their due date. A missed instalment restarts the reminders.',
      recs.size()
    );
    if (!recs.isEmpty()) {
      it.severity = 'error';
    }
    for (PMS_Payment_Plan_Instalment__c i : recs) {
      if (it.rows.size() < MAX_ROWS) {
        String label =
          (i.Plan__r?.Invoice__r?.Name == null
            ? 'Instalment'
            : i.Plan__r.Invoice__r.Name) +
          (i.Number__c == null ? '' : ' #' + i.Number__c.intValue());
        Id target = i.Plan__r?.Invoice__c != null ? i.Plan__r.Invoice__c : i.Id;
        it.rows.add(
          row(
            target,
            label,
            join(
              new List<String>{
                'due ' + fmt(i.Due_Date__c),
                money(i.Amount__c, i.CurrencyIsoCode),
                customer(i.Plan__r?.Invoice__r?.Account__r?.Name)
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item rent() {
    String q =
      'SELECT Id, Name, Status__c, Kind__c, Effective_Date__c, Warning__c, Lease__r.Name ' +
      'FROM PMS_Rent_Adjustment__c WHERE Status__c IN (\'Draft\', \'Approved\') ORDER BY Effective_Date__c LIMIT ' +
      MAX_QUERY;
    List<PMS_Rent_Adjustment__c> recs = Database.query(
      q,
      AccessLevel.USER_MODE
    );
    Item it = item(
      'Rent adjustments to handle',
      'Drafts to approve and approved adjustments whose notice has not been sent.',
      recs.size()
    );
    for (PMS_Rent_Adjustment__c a : recs) {
      if (String.isNotBlank(a.Warning__c)) {
        it.severity = 'error';
      }
      if (it.rows.size() < MAX_ROWS) {
        String next = a.Status__c == 'Draft' ? 'approve' : 'send notice';
        it.rows.add(
          row(
            a.Id,
            a.Lease__r?.Name == null ? a.Name : a.Lease__r.Name,
            join(
              new List<String>{
                a.Kind__c,
                next,
                'from ' + fmt(a.Effective_Date__c),
                a.Warning__c
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item channelErrors() {
    String q =
      'SELECT Id, Name, Kind__c, Direction__c, Message__c, CreatedDate, Site__r.Name ' +
      'FROM PMS_Channel_Log__c WHERE Status__c IN (\'Error\', \'Failed\') AND CreatedDate = LAST_N_DAYS:1 ' +
      'ORDER BY CreatedDate DESC LIMIT ' +
      MAX_QUERY;
    List<PMS_Channel_Log__c> recs = Database.query(q, AccessLevel.USER_MODE);
    Item it = item(
      'Channel manager errors',
      'Failed Channex pushes or pulls in the last 24 hours.',
      recs.size()
    );
    if (!recs.isEmpty()) {
      it.severity = 'error';
    }
    for (PMS_Channel_Log__c l : recs) {
      if (it.rows.size() < MAX_ROWS) {
        it.rows.add(
          row(
            l.Id,
            l.Name,
            join(
              new List<String>{
                l.Kind__c,
                fmt(l.CreatedDate),
                l.Message__c == null ? null : l.Message__c.abbreviate(90)
              }
            )
          )
        );
      }
    }
    return it;
  }

  static Item otaUnassigned() {
    Datetime now = Datetime.now().addDays(-1);
    String q =
      'SELECT Id, Name, OTA_Name__c, OTA_Reservation_Code__c, Start__c, Room_Type_Requested__r.Name ' +
      'FROM PMS_Booking__c WHERE OTA_Name__c != NULL AND Space__c = NULL AND Start__c >= :now ' +
      'AND Status__c NOT IN (\'Cancelled\', \'No Show\') ORDER BY Start__c LIMIT ' +
      MAX_QUERY;
    List<PMS_Booking__c> recs = Database.queryWithBinds(
      q,
      new Map<String, Object>{ 'now' => now },
      AccessLevel.USER_MODE
    );
    Item it = item(
      'OTA bookings without a room',
      'Channel bookings saved without a room (overbooked). Move a guest or upgrade.',
      recs.size()
    );
    if (!recs.isEmpty()) {
      it.severity = 'error';
    }
    for (PMS_Booking__c b : recs) {
      if (it.rows.size() < MAX_ROWS) {
        it.rows.add(
          row(
            b.Id,
            b.Name,
            join(
              new List<String>{
                b.OTA_Name__c,
                b.OTA_Reservation_Code__c,
                b.Room_Type_Requested__r?.Name,
                'arrives ' + fmt(b.Start__c)
              }
            )
          )
        );
      }
    }
    return it;
  }

  // ------------------------------------------------------------------ helpers

  @TestVisible
  static String bookingRecordType(String m) {
    switch on m {
      when 'Hotel' {
        return 'Reservation';
      }
      when 'Practice' {
        return 'Appointment';
      }
      when 'Property' {
        return 'Lease';
      }
      when else {
        return null;
      }
    }
  }

  @TestVisible
  static String invoiceRecordType(String m) {
    switch on m {
      when 'Hotel' {
        return 'Folio';
      }
      when 'Practice' {
        return 'Client_Bill';
      }
      when 'Property' {
        return 'Rent_Invoice';
      }
      when 'Projects' {
        return 'Project_Invoice';
      }
      when else {
        return null;
      }
    }
  }

  static String rtFilter(String path, String rt) {
    return rt == null ? '' : ' AND ' + path + ' = :rt';
  }

  static Item item(String label, String hintText, Integer size) {
    Item it = new Item();
    it.label = label;
    it.hintText = hintText;
    it.count = size;
    it.more = size >= MAX_QUERY;
    return it;
  }

  static Row row(Id id, String name, String detail) {
    Row r = new Row();
    r.id = id;
    r.name = name;
    r.detail = detail;
    r.url = '/lightning/r/' + id + '/view';
    return r;
  }

  @TestVisible
  static String join(List<String> parts) {
    List<String> keep = new List<String>();
    for (String p : parts) {
      if (String.isNotBlank(p)) {
        keep.add(p);
      }
    }
    return String.join(keep, ' · ');
  }

  @TestVisible
  static String money(Decimal amount, String currencyCode) {
    if (hideAmounts || amount == null) {
      return null;
    }
    return amount.setScale(2).format() +
      (currencyCode == null ? '' : ' ' + currencyCode);
  }

  static String customer(String name) {
    return hideCustomers ? null : name;
  }

  @TestVisible
  static String fmt(Datetime d) {
    return d == null ? null : d.format('d MMM HH:mm');
  }

  @TestVisible
  static String fmt(Date d) {
    return d == null
      ? null
      : Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0))
          .format('d MMM yyyy');
  }
}
