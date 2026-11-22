/**
 * Data for the PMS app home pages (LWC pmsAppHome).
 *
 * One cacheable call returns everything a module's home page shows: KPI tiles, charts,
 * work queues ("needs attention") and today's agenda, for Admin, Hotel, Property, Projects
 * or Practice, optionally narrowed to one site.
 *
 * - Every query runs in user mode, so sharing, CRUD and FLS apply.
 * - Each block runs on its own: if one query fails (for example a missing field permission)
 *   the block is skipped and reported in warnings, and the rest of the page still loads.
 * - Money is converted into one display currency (the selected site's currency, else the most
 *   common site currency) with the org's exchange rates. In a single-currency org it is used as is.
 */
public with sharing class PMS_HomeController {
  private static final Set<String> MODULES = new Set<String>{
    'Admin',
    'Hotel',
    'Property',
    'Projects',
    'Practice'
  };
  private static final Integer SHOW = 6;
  private static final Integer FETCH = 200;
  private static final Set<String> OPEN_INVOICE = new Set<String>{
    'Issued',
    'Partially Paid',
    'Overdue'
  };
  private static final Set<String> NEGATIVE_PAYMENT = new Set<String>{
    'Refund',
    'Deposit Return',
    'Owner Payout'
  };

  // ------------------------------------------------------------------ DTOs

  public class HomeData {
    @AuraEnabled
    public String module;
    @AuraEnabled
    public String siteId;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String userFirstName;
    @AuraEnabled
    public Datetime generatedAt;
    @AuraEnabled
    public Id dashboardId;
    @AuraEnabled
    public List<Option> sites = new List<Option>();
    @AuraEnabled
    public List<Kpi> kpis = new List<Kpi>();
    @AuraEnabled
    public List<Chart> charts = new List<Chart>();
    @AuraEnabled
    public List<Section> sections = new List<Section>();
    @AuraEnabled
    public List<Item> agenda = new List<Item>();
    @AuraEnabled
    public List<String> warnings = new List<String>();
    /** True when the user's Access Team hides amounts: money tiles, charts and amounts are left out. */
    @AuraEnabled
    public Boolean hideAmounts = false;
    /** True for PMS Access Managers: shows the Access Setup action. */
    @AuraEnabled
    public Boolean canManageAccess = false;
    /** Admin home only, for Access Managers: how far the access rules are applied. */
    @AuraEnabled
    public String accessNotice;
    @AuraEnabled
    public String accessTone;
  }

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class Kpi {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal value;
    /** count, money, percent, hours or decimal */
    @AuraEnabled
    public String format;
    @AuraEnabled
    public String sub;
    /** neutral, success, warning or error */
    @AuraEnabled
    public String tone;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String listView;
  }

  public class Chart {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String subtitle;
    /** bar, line, donut or hbar */
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String format;
    @AuraEnabled
    public List<String> labels = new List<String>();
    @AuraEnabled
    public List<Decimal> values = new List<Decimal>();
  }

  public class Section {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String listView;
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public String emptyText;
    @AuraEnabled
    public List<Item> items = new List<Item>();
  }

  public class Item {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public String badge;
    @AuraEnabled
    public String tone;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Datetime whenDt;
    @AuraEnabled
    public Date whenDate;
  }

  // ------------------------------------------------------------------ entry point

  @AuraEnabled(cacheable=true)
  public static HomeData getHome(String module, String siteId) {
    if (String.isBlank(module) || !MODULES.contains(module)) {
      AuraHandledException e = new AuraHandledException(
        'Unknown PMS module: ' + module
      );
      e.setMessage('Unknown PMS module: ' + module);
      throw e;
    }
    Ctx c = new Ctx(module, siteId);
    c.data.hideAmounts = FeatureManagement.checkPermission('PMS_Hide_Amounts');
    c.data.canManageAccess = FeatureManagement.checkPermission(
      'PMS_Manage_Access'
    );
    for (String part : partsFor(c.scopeModule, c.isAdminView)) {
      if (c.data.hideAmounts && part == 'revenueTrend') {
        continue;
      }
      try {
        run(part, c);
      } catch (Exception e) {
        c.data.warnings.add(part + ': ' + e.getMessage());
      }
    }
    if (c.data.hideAmounts) {
      stripAmounts(c.data);
    }
    if (module == 'Admin' && c.data.canManageAccess) {
      try {
        accessNotice(c.data);
      } catch (Exception e) {
        c.data.warnings.add('access: ' + e.getMessage());
      }
    }
    return c.data;
  }

  /** Leaves out money tiles and charts, and blanks amounts in the lists, for users whose team hides amounts. */
  @TestVisible
  private static void stripAmounts(HomeData d) {
    List<Kpi> kpis = new List<Kpi>();
    for (Kpi k : d.kpis) {
      if (k.format != 'money') {
        kpis.add(k);
      }
    }
    d.kpis = kpis;
    List<Chart> charts = new List<Chart>();
    for (Chart ch : d.charts) {
      if (ch.format != 'money') {
        charts.add(ch);
      }
    }
    d.charts = charts;
    for (Section s : d.sections) {
      for (Item i : s.items) {
        i.amount = null;
      }
    }
    for (Item i : d.agenda) {
      i.amount = null;
    }
  }

  /** One line on the Admin home: how many kinds of records the access rules apply to. */
  private static void accessNotice(HomeData d) {
    Integer total = 0;
    Integer applied = 0;
    for (PMS_Access_Object__mdt o : PMS_AccessService.objectConfigs()) {
      total++;
      if (
        PMS_AccessService.isRestricted(o.Object_API_Name__c) &&
        PMS_AccessService.rowCauseFor(o.Object_API_Name__c) != null
      ) {
        applied++;
      }
    }
    if (total == 0) {
      return;
    }
    if (applied == 0) {
      d.accessNotice = 'Access rules are saved but not applied yet: all staff can see and edit every PMS record. Switch objects to Private when you are ready.';
      d.accessTone = 'warning';
    } else if (applied < total) {
      d.accessNotice =
        'Access rules apply to ' +
        applied +
        ' of ' +
        total +
        ' kinds of records. The rest are still open to all staff.';
      d.accessTone = 'neutral';
    } else {
      d.accessNotice = 'Access rules apply to every kind of PMS record.';
      d.accessTone = 'success';
    }
  }

  @TestVisible
  private static List<String> partsFor(String scopeModule, Boolean adminView) {
    if (adminView) {
      return new List<String>{
        'adminKpis',
        'revenueTrend',
        'adminModuleMix',
        'adminInvoiceStatus',
        'adminCasesByModule',
        'overdueInvoices',
        'failedPayments',
        'openCases',
        'pendingApprovals',
        'awaitingSignature',
        'draftStatements',
        'adminAgenda',
        'dashboard'
      };
    }
    switch on scopeModule {
      when 'Hotel' {
        return new List<String>{
          'hotelKpis',
          'hotelForecast',
          'revenueTrend',
          'hotelChannels',
          'hotelRoomStatus',
          'hotelQueues',
          'overdueInvoices',
          'openCases',
          'hotelAgenda'
        };
      }
      when 'Property' {
        return new List<String>{
          'propertyKpis',
          'propertyOccupancy',
          'revenueTrend',
          'propertyAging',
          'propertyWorkOrders',
          'overdueInvoices',
          'propertyQueues',
          'openCases',
          'awaitingSignature',
          'draftStatements',
          'propertyAgenda'
        };
      }
      when 'Projects' {
        return new List<String>{
          'projectKpis',
          'projectHealth',
          'projectHours',
          'projectTasks',
          'projectBudget',
          'projectQueues',
          'pendingApprovals',
          'overdueInvoices',
          'projectAgenda'
        };
      }
      when else {
        return new List<String>{
          'practiceKpis',
          'practiceWeek',
          'revenueTrend',
          'practicePractitioners',
          'practiceModes',
          'practiceQueues',
          'awaitingSignature',
          'overdueInvoices',
          'practiceAgenda'
        };
      }
    }
  }

  private static void run(String part, Ctx c) {
    switch on part {
      when 'revenueTrend' {
        revenueTrend(c);
      }
      when 'overdueInvoices' {
        overdueInvoicesSection(c);
      }
      when 'openCases' {
        openCasesSection(c);
      }
      when 'pendingApprovals' {
        pendingApprovals(c);
      }
      when 'awaitingSignature' {
        awaitingSignature(c);
      }
      when 'draftStatements' {
        draftStatements(c);
      }
      when 'failedPayments' {
        failedPayments(c);
      }
      when 'dashboard' {
        dashboard(c);
      }
      when 'adminKpis' {
        adminKpis(c);
      }
      when 'adminModuleMix' {
        adminModuleMix(c);
      }
      when 'adminInvoiceStatus' {
        adminInvoiceStatus(c);
      }
      when 'adminCasesByModule' {
        adminCasesByModule(c);
      }
      when 'adminAgenda' {
        adminAgenda(c);
      }
      when 'hotelKpis' {
        hotelKpis(c);
      }
      when 'hotelForecast' {
        hotelForecast(c);
      }
      when 'hotelChannels' {
        hotelChannels(c);
      }
      when 'hotelRoomStatus' {
        hotelRoomStatus(c);
      }
      when 'hotelQueues' {
        hotelQueues(c);
      }
      when 'hotelAgenda' {
        hotelAgenda(c);
      }
      when 'propertyKpis' {
        propertyKpis(c);
      }
      when 'propertyOccupancy' {
        propertyOccupancy(c);
      }
      when 'propertyAging' {
        propertyAging(c);
      }
      when 'propertyWorkOrders' {
        propertyWorkOrders(c);
      }
      when 'propertyQueues' {
        propertyQueues(c);
      }
      when 'propertyAgenda' {
        propertyAgenda(c);
      }
      when 'projectKpis' {
        projectKpis(c);
      }
      when 'projectHealth' {
        projectHealth(c);
      }
      when 'projectHours' {
        projectHours(c);
      }
      when 'projectTasks' {
        projectTasks(c);
      }
      when 'projectBudget' {
        projectBudget(c);
      }
      when 'projectQueues' {
        projectQueues(c);
      }
      when 'projectAgenda' {
        projectAgenda(c);
      }
      when 'practiceKpis' {
        practiceKpis(c);
      }
      when 'practiceWeek' {
        practiceWeek(c);
      }
      when 'practicePractitioners' {
        practicePractitioners(c);
      }
      when 'practiceModes' {
        practiceModes(c);
      }
      when 'practiceQueues' {
        practiceQueues(c);
      }
      when 'practiceAgenda' {
        practiceAgenda(c);
      }
    }
  }

  // ------------------------------------------------------------------ context

  private class Ctx {
    HomeData data = new HomeData();
    String module;
    /** The module whose rules apply. For Admin with a site picked, it is that site's module. */
    String scopeModule;
    /** Site__c.Module__c value for the scope (Project for Projects). Null for the all-sites Admin view. */
    String siteModule;
    Boolean isAdminView;
    Id siteId;
    Set<Id> siteIds = new Set<Id>();
    Boolean isMC = UserInfo.isMultiCurrencyOrganization();
    String displayCurrency;
    Map<String, Decimal> rates = new Map<String, Decimal>();
    Map<String, Object> binds = new Map<String, Object>();
    Date today = Date.today();
    Datetime todayStart;
    Datetime tomorrowStart;
    // caches shared by several blocks
    List<Decimal> monthly;
    List<String> monthLabels;
    List<PMS_Invoice__c> overdue;

    Ctx(String module, String requestedSiteId) {
      this.module = module;
      data.module = module;
      data.userFirstName = UserInfo.getFirstName();
      data.generatedAt = System.now();
      todayStart = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
      tomorrowStart = todayStart.addDays(1);

      String wantedModule = module == 'Admin'
        ? null
        : (module == 'Projects' ? 'Project' : module);
      String siteSoql =
        'SELECT Id, Name, Module__c, Currency_Code__c FROM PMS_Site__c' +
        (wantedModule == null ? '' : ' WHERE Module__c = :wantedModule') +
        ' ORDER BY Name LIMIT 500';
      List<PMS_Site__c> sites = (List<PMS_Site__c>) Database.queryWithBinds(
        siteSoql,
        new Map<String, Object>{ 'wantedModule' => wantedModule },
        AccessLevel.USER_MODE
      );

      Id requested = null;
      if (String.isNotBlank(requestedSiteId)) {
        try {
          requested = Id.valueOf(requestedSiteId);
        } catch (Exception e) {
          requested = null;
        }
      }
      PMS_Site__c picked;
      Map<String, Integer> currencyVotes = new Map<String, Integer>();
      for (PMS_Site__c s : sites) {
        data.sites.add(
          new Option(
            module == 'Admin' ? s.Name + ' (' + s.Module__c + ')' : s.Name,
            s.Id
          )
        );
        siteIds.add(s.Id);
        if (requested != null && s.Id == requested) {
          picked = s;
        }
        if (String.isNotBlank(s.Currency_Code__c)) {
          Integer n = currencyVotes.get(s.Currency_Code__c);
          currencyVotes.put(s.Currency_Code__c, n == null ? 1 : n + 1);
        }
      }

      if (picked != null) {
        siteId = picked.Id;
        siteIds = new Set<Id>{ picked.Id };
        data.siteId = picked.Id;
      }
      isAdminView = module == 'Admin' && picked == null;
      if (module == 'Admin') {
        siteModule = picked == null ? null : picked.Module__c;
        scopeModule = picked == null
          ? 'Admin'
          : (picked.Module__c == 'Project' ? 'Projects' : picked.Module__c);
      } else {
        siteModule = wantedModule;
        scopeModule = module;
      }

      // Display currency: the picked site's, else the most common site currency, else the user's.
      String wanted = picked != null &&
        String.isNotBlank(picked.Currency_Code__c)
        ? picked.Currency_Code__c
        : null;
      if (wanted == null) {
        Integer best = 0;
        for (String iso : currencyVotes.keySet()) {
          if (currencyVotes.get(iso) > best) {
            best = currencyVotes.get(iso);
            wanted = iso;
          }
        }
      }
      if (wanted == null) {
        wanted = UserInfo.getDefaultCurrency();
      }
      String corporate = UserInfo.getDefaultCurrency();
      if (isMC) {
        for (
          SObject ct : Database.query(
            'SELECT IsoCode, ConversionRate, IsCorporate FROM CurrencyType WHERE IsActive = true'
          )
        ) {
          rates.put(
            (String) ct.get('IsoCode'),
            (Decimal) ct.get('ConversionRate')
          );
          if ((Boolean) ct.get('IsCorporate')) {
            corporate = (String) ct.get('IsoCode');
          }
        }
        displayCurrency = rates.containsKey(wanted) ? wanted : corporate;
      } else {
        displayCurrency = UserInfo.getDefaultCurrency();
      }
      data.currencyCode = displayCurrency;

      binds.put('siteIds', siteIds);
      binds.put('siteId', siteId);
      binds.put('siteModule', siteModule);
      binds.put('today', today);
      binds.put('todayStart', todayStart);
      binds.put('tomorrowStart', tomorrowStart);
    }

    /** ", CurrencyIsoCode" in a multi-currency org, so amounts can be converted. */
    String cur() {
      return isMC ? ', CurrencyIsoCode' : '';
    }

    Decimal money(Decimal amount, SObject rec) {
      if (amount == null) {
        return 0;
      }
      if (!isMC) {
        return amount;
      }
      Decimal fromRate = rates.get((String) rec.get('CurrencyIsoCode'));
      Decimal toRate = rates.get(displayCurrency);
      if (fromRate == null || toRate == null || fromRate == 0) {
        return amount;
      }
      return (amount / fromRate * toRate).setScale(2);
    }

    List<SObject> query(String soql) {
      return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    Integer count(String soql) {
      return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    // Scope filters (where fragments). Blank means no filter.
    String bookingScope() {
      return isAdminView ? '' : 'Site__c IN :siteIds';
    }

    String invoiceScope() {
      if (isAdminView) {
        return '';
      }
      if (scopeModule == 'Projects') {
        return siteId == null
          ? 'Project__c != null'
          : 'Project__r.Site__c = :siteId';
      }
      if (scopeModule == 'Practice') {
        return '(Booking__r.Site__c IN :siteIds OR Matter__r.Site__c IN :siteIds' +
          (siteId == null
            ? ' OR (Matter__c != null AND Matter__r.Site__c = null)'
            : '') +
          ')';
      }
      return 'Booking__r.Site__c IN :siteIds';
    }

    String paymentScope() {
      if (isAdminView) {
        return '';
      }
      if (scopeModule == 'Projects') {
        return siteId == null
          ? 'Invoice__r.Project__c != null'
          : 'Invoice__r.Project__r.Site__c = :siteId';
      }
      String s = '(Booking__r.Site__c IN :siteIds OR Invoice__r.Booking__r.Site__c IN :siteIds';
      if (scopeModule == 'Practice') {
        s += ' OR Invoice__r.Matter__r.Site__c IN :siteIds';
        if (siteId == null) {
          s += ' OR (Invoice__r.Matter__c != null AND Invoice__r.Matter__r.Site__c = null)';
        }
      }
      return s + ')';
    }

    String caseScope() {
      if (isAdminView) {
        return '';
      }
      if (siteId != null) {
        return 'PMS_Site__c = :siteId';
      }
      return '(PMS_Site__c IN :siteIds OR PMS_Module__c = :siteModule)';
    }

    /** Projects, matters: filter only when one site is picked (many have no site). */
    String optionalSite(String field) {
      return siteId == null ? '' : field + ' = :siteId';
    }

    String siteFilter(String field) {
      return isAdminView ? '' : field + ' IN :siteIds';
    }
  }

  // ------------------------------------------------------------------ small helpers

  private static String whereOf(List<String> parts) {
    List<String> kept = new List<String>();
    for (String p : parts) {
      if (String.isNotBlank(p)) {
        kept.add(p);
      }
    }
    return kept.isEmpty() ? '' : ' WHERE ' + String.join(kept, ' AND ');
  }

  private static Kpi kpi(
    String key,
    String label,
    Decimal value,
    String format,
    String sub,
    String tone,
    String icon
  ) {
    Kpi k = new Kpi();
    k.key = key;
    k.label = label;
    k.value = value == null ? 0 : value;
    k.format = format;
    k.sub = sub;
    k.tone = tone == null ? 'neutral' : tone;
    k.icon = icon;
    return k;
  }

  private static Kpi nav(Kpi k, String objectApiName, String listView) {
    k.objectApiName = objectApiName;
    k.listView = listView;
    return k;
  }

  private static Section section(
    String key,
    String title,
    String icon,
    String objectApiName,
    String listView,
    String emptyText
  ) {
    Section s = new Section();
    s.key = key;
    s.title = title;
    s.icon = icon;
    s.objectApiName = objectApiName;
    s.listView = listView;
    s.emptyText = emptyText;
    return s;
  }

  private static Item item(
    Id recordId,
    String title,
    String subtitle,
    String badge,
    String tone
  ) {
    Item i = new Item();
    i.recordId = recordId;
    i.title = title;
    i.subtitle = subtitle;
    i.badge = badge;
    i.tone = tone;
    return i;
  }

  private static String join(String a, String b) {
    if (String.isBlank(a)) {
      return b;
    }
    if (String.isBlank(b)) {
      return a;
    }
    return a + ' · ' + b;
  }

  private static Decimal pct(Decimal part, Decimal whole) {
    if (whole == null || whole == 0 || part == null) {
      return 0;
    }
    return (part * 100 / whole).setScale(1);
  }

  private static Decimal nz(Decimal d) {
    return d == null ? 0 : d;
  }

  private static String who(PMS_Booking__c b) {
    if (
      b.Primary_Contact__r != null &&
      String.isNotBlank(b.Primary_Contact__r.Name)
    ) {
      return b.Primary_Contact__r.Name;
    }
    return b.Account__r == null ? null : b.Account__r.Name;
  }

  private static Chart chart(
    String key,
    String title,
    String subtitle,
    String type,
    String format
  ) {
    Chart ch = new Chart();
    ch.key = key;
    ch.title = title;
    ch.subtitle = subtitle;
    ch.type = type;
    ch.format = format;
    return ch;
  }

  /** Fills a chart from an aggregate result with a label alias "l" and a value alias "n". */
  private static Chart fromAggregate(
    Chart ch,
    List<SObject> rows,
    String emptyLabel
  ) {
    for (SObject r : rows) {
      Object l = r.get('l');
      ch.labels.add(l == null ? emptyLabel : String.valueOf(l));
      ch.values.add(dec(r.get('n')));
    }
    return ch;
  }

  /** Aggregate values come back as Integer (COUNT) or Decimal (SUM). */
  private static Decimal dec(Object o) {
    if (o == null) {
      return 0;
    }
    return Decimal.valueOf(String.valueOf(o));
  }

  private static final String BOOKING_FIELDS =
    'SELECT Id, Name, Status__c, Start__c, End__c, Total_Amount__c, Balance_Due__c, Online_Check_In__c, ' +
    'Channel__c, Appointment_Mode__c, Account__r.Name, Primary_Contact__r.Name, Space__r.Name, Site__r.Name, ' +
    'Site__r.Module__c, Practitioner__r.Name, Service__r.Name';

  // ------------------------------------------------------------------ shared blocks

  /** Net money received per month for the last 6 months (cached for the revenue KPI). */
  private static void loadMonthly(Ctx c) {
    if (c.monthly != null) {
      return;
    }
    Date firstMonth = c.today.toStartOfMonth().addMonths(-5);
    c.binds.put('firstMonth', firstMonth);
    c.monthly = new List<Decimal>{ 0, 0, 0, 0, 0, 0 };
    c.monthLabels = new List<String>();
    for (Integer i = 0; i < 6; i++) {
      c.monthLabels.add(
        Datetime.newInstance(
            firstMonth.addMonths(i),
            Time.newInstance(12, 0, 0, 0)
          )
          .format('MMM')
      );
    }
    String soql =
      'SELECT Amount__c, Payment_Type__c, Received_Date__c, CreatedDate' +
      c.cur() +
      ' FROM PMS_Payment__c' +
      whereOf(
        new List<String>{
          c.paymentScope(),
          'Status__c = \'Succeeded\'',
          '(Received_Date__c >= :firstMonth OR (Received_Date__c = null AND CreatedDate >= :firstMonthDt))'
        }
      ) +
      ' LIMIT 10000';
    c.binds.put(
      'firstMonthDt',
      Datetime.newInstance(firstMonth, Time.newInstance(0, 0, 0, 0))
    );
    for (PMS_Payment__c p : (List<PMS_Payment__c>) c.query(soql)) {
      Date d = p.Received_Date__c != null
        ? p.Received_Date__c
        : p.CreatedDate.date();
      Integer idx = firstMonth.monthsBetween(d.toStartOfMonth());
      if (idx < 0 || idx > 5) {
        continue;
      }
      Decimal amt = c.money(p.Amount__c, p);
      c.monthly[idx] += NEGATIVE_PAYMENT.contains(p.Payment_Type__c)
        ? -amt
        : amt;
    }
  }

  private static Decimal revenueMtd(Ctx c) {
    loadMonthly(c);
    return c.monthly[5];
  }

  private static String revenueSub(Ctx c) {
    loadMonthly(c);
    Decimal prev = c.monthly[4];
    if (prev == 0) {
      return 'Received this month';
    }
    Decimal change = ((c.monthly[5] - prev) * 100 / prev.abs()).setScale(0);
    return (change >= 0 ? '+' : '') +
      change +
      '% vs ' +
      c.monthLabels[4] +
      ' (to date)';
  }

  private static void revenueTrend(Ctx c) {
    loadMonthly(c);
    Chart ch = chart(
      'revenue',
      'Money received',
      'Net of refunds, last 6 months',
      'bar',
      'money'
    );
    ch.labels.addAll(c.monthLabels);
    ch.values.addAll(c.monthly);
    c.data.charts.add(ch);
  }

  private static List<PMS_Invoice__c> loadOverdue(Ctx c) {
    if (c.overdue != null) {
      return c.overdue;
    }
    String soql =
      'SELECT Id, Name, Status__c, Due_Date__c, Balance__c, Days_Overdue__c, Account__r.Name' +
      c.cur() +
      ' FROM PMS_Invoice__c' +
      whereOf(
        new List<String>{
          c.invoiceScope(),
          'Status__c IN :openInvoice',
          'Due_Date__c < :today',
          'Balance__c > 0'
        }
      ) +
      ' ORDER BY Due_Date__c ASC LIMIT 2000';
    c.binds.put('openInvoice', OPEN_INVOICE);
    c.overdue = (List<PMS_Invoice__c>) c.query(soql);
    return c.overdue;
  }

  private static Decimal overdueTotal(Ctx c) {
    Decimal sum = 0;
    for (PMS_Invoice__c i : loadOverdue(c)) {
      sum += c.money(i.Balance__c, i);
    }
    return sum;
  }

  private static void overdueInvoicesSection(Ctx c) {
    List<PMS_Invoice__c> rows = loadOverdue(c);
    Section s = section(
      'overdue',
      'Overdue invoices',
      'standard:partner_fund_claim',
      'PMS_Invoice__c',
      'Overdue_Invoices',
      'No overdue invoices. Nice.'
    );
    s.total = rows.size();
    for (PMS_Invoice__c inv : rows) {
      if (s.items.size() == SHOW) {
        break;
      }
      Decimal days = nz(inv.Days_Overdue__c);
      Item it = item(
        inv.Id,
        join(inv.Name, inv.Account__r == null ? null : inv.Account__r.Name),
        days.intValue() + (days == 1 ? ' day overdue' : ' days overdue'),
        days > 60 ? '60+ days' : (days > 30 ? '30+ days' : 'Overdue'),
        days > 30 ? 'error' : 'warning'
      );
      it.amount = c.money(inv.Balance__c, inv);
      it.whenDate = inv.Due_Date__c;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void openCasesSection(Ctx c) {
    String soql =
      'SELECT Id, CaseNumber, Subject, Priority, Status, CreatedDate, Account.Name, PMS_Space__r.Name, SLA_Due__c' +
      ' FROM Case' +
      whereOf(new List<String>{ c.caseScope(), 'IsClosed = false' }) +
      ' ORDER BY CreatedDate ASC LIMIT ' +
      FETCH;
    List<Case> rows = (List<Case>) c.query(soql);
    Section s = section(
      'cases',
      'Open requests',
      'standard:case',
      'Case',
      'PMS_Open_Requests',
      'No open requests.'
    );
    s.total = rows.size();
    List<Case> urgentFirst = new List<Case>();
    Set<Id> placed = new Set<Id>();
    for (Case cs : rows) {
      if (
        cs.Priority == 'High' ||
        (cs.SLA_Due__c != null &&
        cs.SLA_Due__c < System.now())
      ) {
        urgentFirst.add(cs);
        placed.add(cs.Id);
      }
    }
    for (Case cs : rows) {
      if (!placed.contains(cs.Id)) {
        urgentFirst.add(cs);
      }
    }
    for (Case cs : urgentFirst) {
      if (s.items.size() == SHOW) {
        break;
      }
      Boolean late = cs.SLA_Due__c != null && cs.SLA_Due__c < System.now();
      Item it = item(
        cs.Id,
        join(cs.CaseNumber, cs.Subject),
        join(
          cs.PMS_Space__r == null ? null : cs.PMS_Space__r.Name,
          join(cs.Account == null ? null : cs.Account.Name, cs.Status)
        ),
        late ? 'SLA breached' : cs.Priority,
        late || cs.Priority == 'High' ? 'error' : 'neutral'
      );
      it.whenDt = cs.CreatedDate;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void pendingApprovals(Ctx c) {
    String soql =
      'SELECT Id, Name, Title__c, Type__c, Status__c, Due_Date__c, Amount__c, Account__r.Name, Project__r.Name' +
      c.cur() +
      ' FROM PMS_Approval_Request__c' +
      whereOf(
        new List<String>{
          c.isAdminView ? '' : c.optionalSite('Project__r.Site__c'),
          'Status__c IN (\'Draft\', \'Pending\')'
        }
      ) +
      ' ORDER BY Due_Date__c ASC NULLS LAST LIMIT ' +
      FETCH;
    List<PMS_Approval_Request__c> rows = (List<PMS_Approval_Request__c>) c.query(
      soql
    );
    Section s = section(
      'approvals',
      'Client approvals',
      'standard:approval',
      'PMS_Approval_Request__c',
      'All',
      'No approvals waiting.'
    );
    s.total = rows.size();
    for (PMS_Approval_Request__c a : rows) {
      if (s.items.size() == SHOW) {
        break;
      }
      Boolean late = a.Due_Date__c != null && a.Due_Date__c < c.today;
      Item it = item(
        a.Id,
        join(a.Name, a.Title__c),
        join(a.Project__r == null ? null : a.Project__r.Name, a.Type__c),
        a.Status__c == 'Draft'
          ? 'Draft - not sent'
          : (late ? 'Past due' : 'Awaiting client'),
        a.Status__c == 'Draft' ? 'neutral' : (late ? 'error' : 'warning')
      );
      it.amount = a.Amount__c == null ? null : c.money(a.Amount__c, a);
      it.whenDate = a.Due_Date__c;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void awaitingSignature(Ctx c) {
    String scope = c.isAdminView
      ? ''
      : (c.scopeModule == 'Projects'
          ? c.optionalSite('Project__r.Site__c')
          : 'Booking__r.Site__c IN :siteIds');
    String soql =
      'SELECT Id, Name, Title__c, Status__c, Due_Date__c, Signer_Name__c, Contact__r.Name, Viewed_At__c' +
      ' FROM PMS_Document_Request__c' +
      whereOf(
        new List<String>{
          scope,
          'Status__c IN (\'Draft\', \'Sent\', \'Viewed\')'
        }
      ) +
      ' ORDER BY Due_Date__c ASC NULLS LAST LIMIT ' +
      FETCH;
    List<PMS_Document_Request__c> rows = (List<PMS_Document_Request__c>) c.query(
      soql
    );
    Section s = section(
      'signatures',
      'Documents to sign',
      'standard:contract',
      'PMS_Document_Request__c',
      'All',
      'Nothing waiting for a signature.'
    );
    s.total = rows.size();
    for (PMS_Document_Request__c d : rows) {
      if (s.items.size() == SHOW) {
        break;
      }
      String signer = String.isNotBlank(d.Signer_Name__c)
        ? d.Signer_Name__c
        : (d.Contact__r == null ? null : d.Contact__r.Name);
      Item it = item(
        d.Id,
        join(d.Name, d.Title__c),
        signer,
        d.Status__c == 'Draft'
          ? 'Draft - not sent'
          : (d.Status__c == 'Viewed' ? 'Opened, not signed' : 'Sent'),
        d.Status__c == 'Draft' ? 'neutral' : 'warning'
      );
      it.whenDate = d.Due_Date__c;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void draftStatements(Ctx c) {
    String soql =
      'SELECT Id, Name, Status__c, Period_Start__c, Period_End__c, Net_Payout__c, Owner_Account__r.Name, Site__r.Name' +
      c.cur() +
      ' FROM PMS_Owner_Statement__c' +
      whereOf(
        new List<String>{ c.siteFilter('Site__c'), 'Status__c = \'Draft\'' }
      ) +
      ' ORDER BY Period_End__c DESC LIMIT ' +
      FETCH;
    List<PMS_Owner_Statement__c> rows = (List<PMS_Owner_Statement__c>) c.query(
      soql
    );
    Section s = section(
      'statements',
      'Owner statements to publish',
      'standard:report',
      'PMS_Owner_Statement__c',
      'All',
      'All statements are published.'
    );
    s.total = rows.size();
    for (PMS_Owner_Statement__c st : rows) {
      if (s.items.size() == SHOW) {
        break;
      }
      Item it = item(
        st.Id,
        join(
          st.Name,
          st.Owner_Account__r == null ? null : st.Owner_Account__r.Name
        ),
        st.Site__r == null ? null : st.Site__r.Name,
        'Draft',
        'neutral'
      );
      it.amount = c.money(st.Net_Payout__c, st);
      it.whenDate = st.Period_End__c;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void failedPayments(Ctx c) {
    String soql =
      'SELECT Id, Name, Amount__c, Method__c, CreatedDate, Account__r.Name, Invoice__r.Name' +
      c.cur() +
      ' FROM PMS_Payment__c' +
      whereOf(
        new List<String>{
          c.paymentScope(),
          'Status__c = \'Failed\'',
          'CreatedDate = LAST_N_DAYS:30'
        }
      ) +
      ' ORDER BY CreatedDate DESC LIMIT ' +
      FETCH;
    List<PMS_Payment__c> rows = (List<PMS_Payment__c>) c.query(soql);
    Section s = section(
      'failed',
      'Failed payments (30 days)',
      'standard:first_non_empty',
      'PMS_Payment__c',
      'All',
      'No failed payments in the last 30 days.'
    );
    s.total = rows.size();
    for (PMS_Payment__c p : rows) {
      if (s.items.size() == SHOW) {
        break;
      }
      Item it = item(
        p.Id,
        join(p.Name, p.Account__r == null ? null : p.Account__r.Name),
        join(p.Invoice__r == null ? null : p.Invoice__r.Name, p.Method__c),
        'Failed',
        'error'
      );
      it.amount = c.money(p.Amount__c, p);
      it.whenDt = p.CreatedDate;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void dashboard(Ctx c) {
    List<Dashboard> ds = (List<Dashboard>) c.query(
      'SELECT Id FROM Dashboard WHERE Title = \'PMS Overview\' ORDER BY LastModifiedDate DESC LIMIT 1'
    );
    if (!ds.isEmpty()) {
      c.data.dashboardId = ds[0].Id;
    }
  }

  private static Decimal outstanding(Ctx c, List<Integer> countOut) {
    c.binds.put('openInvoice', OPEN_INVOICE);
    String soql =
      'SELECT Balance__c' +
      c.cur() +
      ' FROM PMS_Invoice__c' +
      whereOf(
        new List<String>{
          c.invoiceScope(),
          'Status__c IN :openInvoice',
          'Balance__c > 0'
        }
      ) +
      ' LIMIT 10000';
    Decimal sum = 0;
    List<PMS_Invoice__c> rows = (List<PMS_Invoice__c>) c.query(soql);
    for (PMS_Invoice__c i : rows) {
      sum += c.money(i.Balance__c, i);
    }
    countOut.add(rows.size());
    return sum;
  }

  // ------------------------------------------------------------------ Admin

  private static void adminKpis(Ctx c) {
    List<Integer> openCount = new List<Integer>();
    Decimal ar = outstanding(c, openCount);
    Decimal overdueSum = overdueTotal(c);
    Integer overdueCount = loadOverdue(c).size();
    Integer activeBookings = c.count(
      'SELECT COUNT() FROM PMS_Booking__c WHERE Status__c IN (\'Confirmed\', \'Active\') AND End__c >= :todayStart'
    );
    Integer arrivals = c.count(
      'SELECT COUNT() FROM PMS_Booking__c WHERE Start__c >= :todayStart AND Start__c < :tomorrowStart AND Status__c IN (\'Tentative\', \'Confirmed\', \'Active\')'
    );
    Integer cases = c.count(
      'SELECT COUNT() FROM Case WHERE IsClosed = false AND (PMS_Module__c != null OR PMS_Site__c != null)'
    );
    Integer highCases = c.count(
      'SELECT COUNT() FROM Case WHERE IsClosed = false AND Priority = \'High\' AND (PMS_Module__c != null OR PMS_Site__c != null)'
    );
    Integer sites = c.count(
      'SELECT COUNT() FROM PMS_Site__c WHERE Status__c = \'Active\''
    );

    c.data.kpis.add(
      nav(
        kpi(
          'revenue',
          'Received this month',
          revenueMtd(c),
          'money',
          revenueSub(c),
          'success',
          'utility:moneybag'
        ),
        'PMS_Payment__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'ar',
          'Outstanding',
          ar,
          'money',
          openCount[0] + ' open invoices',
          'neutral',
          'utility:currency'
        ),
        'PMS_Invoice__c',
        'Open_Invoices'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'overdue',
          'Overdue',
          overdueSum,
          'money',
          overdueCount + ' invoices past due',
          overdueCount > 0 ? 'error' : 'success',
          'utility:warning'
        ),
        'PMS_Invoice__c',
        'Overdue_Invoices'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'bookings',
          'Active bookings',
          activeBookings,
          'count',
          arrivals + ' starting today',
          'neutral',
          'utility:date_time'
        ),
        'PMS_Booking__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'cases',
          'Open requests',
          cases,
          'count',
          highCases + ' high priority',
          highCases > 0 ? 'warning' : 'neutral',
          'utility:case'
        ),
        'Case',
        'PMS_Open_Requests'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'sites',
          'Active sites',
          sites,
          'count',
          'Hotel, property, project and practice',
          'neutral',
          'utility:company'
        ),
        'PMS_Site__c',
        null
      )
    );
  }

  private static void adminModuleMix(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Site__r.Module__c l, COUNT(Id) n FROM PMS_Booking__c ' +
      'WHERE Status__c IN (\'Confirmed\', \'Active\') AND End__c >= :todayStart GROUP BY Site__r.Module__c'
    );
    c.data.charts.add(
      fromAggregate(
        chart(
          'moduleMix',
          'Active bookings by module',
          'Confirmed and in progress',
          'donut',
          'count'
        ),
        rows,
        'No site'
      )
    );
  }

  private static void adminInvoiceStatus(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Status__c l, COUNT(Id) n FROM PMS_Invoice__c ' +
      'WHERE Status__c != \'Void\' AND CreatedDate = LAST_N_DAYS:365 GROUP BY Status__c ORDER BY COUNT(Id) DESC'
    );
    c.data.charts.add(
      fromAggregate(
        chart(
          'invoiceStatus',
          'Invoices by status',
          'Last 12 months',
          'hbar',
          'count'
        ),
        rows,
        'None'
      )
    );
  }

  private static void adminCasesByModule(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT PMS_Module__c l, COUNT(Id) n FROM Case ' +
      'WHERE IsClosed = false AND (PMS_Module__c != null OR PMS_Site__c != null) GROUP BY PMS_Module__c'
    );
    c.data.charts.add(
      fromAggregate(
        chart('casesByModule', 'Open requests by module', null, 'bar', 'count'),
        rows,
        'Unassigned'
      )
    );
  }

  private static void adminAgenda(Ctx c) {
    String soql =
      BOOKING_FIELDS +
      ' FROM PMS_Booking__c WHERE Start__c >= :todayStart AND Start__c < :tomorrowStart ' +
      'AND Status__c IN (\'Tentative\', \'Confirmed\', \'Active\') ORDER BY Start__c ASC LIMIT 25';
    for (PMS_Booking__c b : (List<PMS_Booking__c>) c.query(soql)) {
      Item it = item(
        b.Id,
        join(who(b), b.Space__r == null ? null : b.Space__r.Name),
        join(b.Site__r == null ? null : b.Site__r.Name, b.Name),
        b.Site__r == null ? null : b.Site__r.Module__c,
        b.Status__c == 'Active' ? 'success' : 'neutral'
      );
      it.whenDt = b.Start__c;
      c.data.agenda.add(it);
    }
  }

  // ------------------------------------------------------------------ Hotel

  private static Integer bookableSpaces(Ctx c) {
    return c.count(
      'SELECT COUNT() FROM PMS_Space__c' +
      whereOf(new List<String>{ c.siteFilter('Site__c'), 'Bookable__c = true' })
    );
  }

  private static List<PMS_Booking__c> bookingsStartingToday(Ctx c) {
    return (List<PMS_Booking__c>) c.query(
      BOOKING_FIELDS +
        ' FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Start__c >= :todayStart',
            'Start__c < :tomorrowStart',
            'Status__c IN (\'Tentative\', \'Confirmed\', \'Active\')'
          }
        ) +
        ' ORDER BY Start__c ASC LIMIT ' +
        FETCH
    );
  }

  private static List<PMS_Booking__c> bookingsEndingToday(Ctx c) {
    return (List<PMS_Booking__c>) c.query(
      BOOKING_FIELDS +
        ' FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'End__c >= :todayStart',
            'End__c < :tomorrowStart',
            'Status__c IN (\'Active\', \'Completed\')'
          }
        ) +
        ' ORDER BY End__c ASC LIMIT ' +
        FETCH
    );
  }

  private static void hotelKpis(Ctx c) {
    Integer rooms = bookableSpaces(c);
    Integer tonight = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          'Status__c IN (\'Confirmed\', \'Active\')',
          'Start__c < :tomorrowStart',
          'End__c > :tomorrowStart',
          'Space__c != null'
        }
      )
    );
    List<PMS_Booking__c> arrivals = bookingsStartingToday(c);
    Integer arrived = 0;
    for (PMS_Booking__c b : arrivals) {
      if (b.Status__c == 'Active') {
        arrived++;
      }
    }
    List<PMS_Booking__c> departures = bookingsEndingToday(c);
    Integer departed = 0;
    for (PMS_Booking__c b : departures) {
      if (b.Status__c == 'Completed') {
        departed++;
      }
    }
    Integer inHouse = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(new List<String>{ c.bookingScope(), 'Status__c = \'Active\'' })
    );

    Datetime monthStart = Datetime.newInstance(
      c.today.toStartOfMonth(),
      Time.newInstance(0, 0, 0, 0)
    );
    c.binds.put('monthStart', monthStart);
    c.binds.put('nextMonthStart', monthStart.addMonths(1));
    Decimal roomRevenue = 0;
    Decimal nights = 0;
    for (
      PMS_Booking__c b : (List<PMS_Booking__c>) c.query(
        'SELECT Total_Amount__c, Nights__c' +
          c.cur() +
          ' FROM PMS_Booking__c' +
          whereOf(
            new List<String>{
              c.bookingScope(),
              'Status__c IN (\'Confirmed\', \'Active\', \'Completed\')',
              'Start__c >= :monthStart',
              'Start__c < :nextMonthStart'
            }
          ) +
          ' LIMIT 10000'
      )
    ) {
      roomRevenue += c.money(b.Total_Amount__c, b);
      nights += nz(b.Nights__c);
    }
    Decimal occ = pct(tonight, rooms);
    Decimal adr = nights == 0 ? 0 : (roomRevenue / nights).setScale(0);

    c.data.kpis.add(
      nav(
        kpi(
          'occupancy',
          'Occupancy tonight',
          occ,
          'percent',
          tonight + ' of ' + rooms + ' rooms sold',
          occ >= 80 ? 'success' : (occ >= 50 ? 'neutral' : 'warning'),
          'utility:checkin'
        ),
        'PMS_Booking__c',
        'In_House'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'arrivals',
          'Arrivals today',
          arrivals.size(),
          'count',
          arrived + ' checked in',
          arrivals.size() > arrived ? 'warning' : 'success',
          'utility:forward'
        ),
        'PMS_Booking__c',
        'Arrivals_Today'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'departures',
          'Departures today',
          departures.size(),
          'count',
          departed + ' checked out',
          departures.size() > departed ? 'warning' : 'success',
          'utility:back'
        ),
        'PMS_Booking__c',
        'Departures_Today'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'inhouse',
          'In house',
          inHouse,
          'count',
          'Guests currently checked in',
          'neutral',
          'utility:people'
        ),
        'PMS_Booking__c',
        'In_House'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'adr',
          'ADR this month',
          adr,
          'money',
          nights.intValue() + ' room nights booked',
          'neutral',
          'utility:price_book_entries'
        ),
        'PMS_Booking__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'revenue',
          'Received this month',
          revenueMtd(c),
          'money',
          revenueSub(c),
          'success',
          'utility:moneybag'
        ),
        'PMS_Payment__c',
        'All'
      )
    );
  }

  private static void hotelForecast(Ctx c) {
    Integer rooms = bookableSpaces(c);
    c.binds.put('windowEnd', c.todayStart.addDays(15));
    List<PMS_Booking__c> rows = (List<PMS_Booking__c>) c.query(
      'SELECT Start__c, End__c FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Status__c IN (\'Tentative\', \'Confirmed\', \'Active\')',
            'Start__c < :windowEnd',
            'End__c > :todayStart',
            'Space__c != null'
          }
        ) +
        ' LIMIT 10000'
    );
    Chart ch = chart(
      'forecast',
      'Occupancy forecast',
      'Next 14 nights, % of rooms',
      'line',
      'percent'
    );
    for (Integer i = 0; i < 14; i++) {
      Date d = c.today.addDays(i);
      Integer n = 0;
      for (PMS_Booking__c b : rows) {
        if (b.Start__c.date() <= d && b.End__c.date() > d) {
          n++;
        }
      }
      ch.labels.add(
        Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('EEE d')
      );
      ch.values.add(pct(n, rooms));
    }
    c.data.charts.add(ch);
  }

  private static void hotelChannels(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Channel__c l, COUNT(Id) n FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'CreatedDate = LAST_N_DAYS:90',
            'Status__c != \'Cancelled\''
          }
        ) +
        ' GROUP BY Channel__c ORDER BY COUNT(Id) DESC'
    );
    c.data.charts.add(
      fromAggregate(
        chart('channels', 'Booking channels', 'Last 90 days', 'donut', 'count'),
        rows,
        'Not set'
      )
    );
  }

  private static void hotelRoomStatus(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Operational_Status__c l, COUNT(Id) n FROM PMS_Space__c' +
        whereOf(new List<String>{ c.siteFilter('Site__c') }) +
        ' GROUP BY Operational_Status__c ORDER BY COUNT(Id) DESC'
    );
    c.data.charts.add(
      fromAggregate(
        chart(
          'roomStatus',
          'Room status',
          'Housekeeping right now',
          'hbar',
          'count'
        ),
        rows,
        'Not set'
      )
    );
  }

  private static void hotelQueues(Ctx c) {
    Section arr = section(
      'arrivals',
      'Arrivals to check in',
      'standard:event',
      'PMS_Booking__c',
      'Arrivals_Today',
      'Everyone due today has arrived.'
    );
    for (PMS_Booking__c b : bookingsStartingToday(c)) {
      if (b.Status__c == 'Active') {
        continue;
      }
      arr.total++;
      if (arr.items.size() < SHOW) {
        Boolean due = nz(b.Balance_Due__c) > 0;
        Item it = item(
          b.Id,
          join(
            who(b),
            b.Space__r == null ? 'No room yet' : 'Room ' + b.Space__r.Name
          ),
          b.Name,
          b.Online_Check_In__c
            ? 'Checked in online'
            : (due ? 'Balance due' : b.Status__c),
          b.Online_Check_In__c ? 'success' : (due ? 'warning' : 'neutral')
        );
        it.whenDt = b.Start__c;
        it.amount = due ? c.money(b.Balance_Due__c, b) : null;
        arr.items.add(it);
      }
    }
    c.data.sections.add(arr);

    Section dep = section(
      'departures',
      'Departures to check out',
      'standard:return_order',
      'PMS_Booking__c',
      'Departures_Today',
      'No more check-outs today.'
    );
    for (PMS_Booking__c b : bookingsEndingToday(c)) {
      if (b.Status__c != 'Active') {
        continue;
      }
      dep.total++;
      if (dep.items.size() < SHOW) {
        Boolean due = nz(b.Balance_Due__c) > 0;
        Item it = item(
          b.Id,
          join(who(b), b.Space__r == null ? null : 'Room ' + b.Space__r.Name),
          b.Name,
          due ? 'Balance due' : 'Settled',
          due ? 'warning' : 'success'
        );
        it.whenDt = b.End__c;
        it.amount = due ? c.money(b.Balance_Due__c, b) : null;
        dep.items.add(it);
      }
    }
    c.data.sections.add(dep);

    List<PMS_Space__c> rooms = (List<PMS_Space__c>) c.query(
      'SELECT Id, Name, Operational_Status__c, Floor__c, Space_Type__r.Name, Site__r.Name FROM PMS_Space__c' +
        whereOf(
          new List<String>{
            c.siteFilter('Site__c'),
            'Operational_Status__c IN (\'Dirty\', \'Out of Order\')'
          }
        ) +
        ' ORDER BY Operational_Status__c, Name LIMIT ' +
        FETCH
    );
    Section hk = section(
      'housekeeping',
      'Housekeeping',
      'standard:service_resource',
      'PMS_Space__c',
      'Rooms_To_Clean',
      'All rooms are clean and in service.'
    );
    hk.total = rooms.size();
    for (PMS_Space__c r : rooms) {
      if (hk.items.size() == SHOW) {
        break;
      }
      hk.items.add(
        item(
          r.Id,
          'Room ' + r.Name,
          join(
            r.Space_Type__r == null ? null : r.Space_Type__r.Name,
            r.Floor__c == null ? null : 'Floor ' + r.Floor__c
          ),
          r.Operational_Status__c,
          r.Operational_Status__c == 'Out of Order' ? 'error' : 'warning'
        )
      );
    }
    c.data.sections.add(hk);

    onlineCheckIns(c, 'Online check-ins received');
  }

  private static void onlineCheckIns(Ctx c, String title) {
    List<PMS_Check_In__c> rows = (List<PMS_Check_In__c>) c.query(
      'SELECT Id, Name, Full_Name__c, Type__c, Submitted_At__c, Arrival_Time__c, Booking__r.Name, Booking__r.Start__c' +
        ' FROM PMS_Check_In__c' +
        whereOf(
          new List<String>{
            c.siteFilter('Booking__r.Site__c'),
            'Submitted_At__c = LAST_N_DAYS:7'
          }
        ) +
        ' ORDER BY Submitted_At__c DESC LIMIT ' +
        FETCH
    );
    Section s = section(
      'checkins',
      title,
      'standard:form',
      'PMS_Check_In__c',
      'All',
      'No online check-ins in the last 7 days.'
    );
    s.total = rows.size();
    for (PMS_Check_In__c ci : rows) {
      if (s.items.size() == SHOW) {
        break;
      }
      Item it = item(
        ci.Id,
        join(
          ci.Full_Name__c,
          ci.Booking__r == null ? null : ci.Booking__r.Name
        ),
        join(
          ci.Type__c,
          ci.Arrival_Time__c == null ? null : 'Arriving ' + ci.Arrival_Time__c
        ),
        'Received',
        'success'
      );
      it.whenDt = ci.Submitted_At__c;
      s.items.add(it);
    }
    c.data.sections.add(s);
  }

  private static void hotelAgenda(Ctx c) {
    List<Item> all = new List<Item>();
    for (PMS_Booking__c b : bookingsStartingToday(c)) {
      Item it = item(
        b.Id,
        join(who(b), b.Space__r == null ? null : 'Room ' + b.Space__r.Name),
        b.Name,
        b.Status__c == 'Active' ? 'Arrived' : 'Arrival',
        b.Status__c == 'Active' ? 'success' : 'neutral'
      );
      it.whenDt = b.Start__c;
      all.add(it);
    }
    for (PMS_Booking__c b : bookingsEndingToday(c)) {
      Item it = item(
        b.Id,
        join(who(b), b.Space__r == null ? null : 'Room ' + b.Space__r.Name),
        b.Name,
        b.Status__c == 'Completed' ? 'Departed' : 'Departure',
        b.Status__c == 'Completed' ? 'success' : 'warning'
      );
      it.whenDt = b.End__c;
      all.add(it);
    }
    c.data.agenda.addAll(sortByTime(all));
  }

  private static List<Item> sortByTime(List<Item> items) {
    List<AgendaSort> wrapped = new List<AgendaSort>();
    for (Item i : items) {
      wrapped.add(new AgendaSort(i));
    }
    wrapped.sort();
    List<Item> out = new List<Item>();
    for (AgendaSort w : wrapped) {
      if (out.size() == 25) {
        break;
      }
      out.add(w.it);
    }
    return out;
  }

  private class AgendaSort implements Comparable {
    Item it;
    AgendaSort(Item it) {
      this.it = it;
    }
    Long key() {
      if (it.whenDt != null) {
        return it.whenDt.getTime();
      }
      if (it.whenDate != null) {
        return Datetime.newInstance(it.whenDate, Time.newInstance(0, 0, 0, 0))
          .getTime();
      }
      return 0;
    }
    public Integer compareTo(Object other) {
      Long a = key();
      Long b = ((AgendaSort) other).key();
      return a == b ? 0 : (a < b ? -1 : 1);
    }
  }

  // ------------------------------------------------------------------ Property

  private static Set<Id> occupiedUnits(Ctx c) {
    Set<Id> ids = new Set<Id>();
    for (
      PMS_Booking__c b : (List<PMS_Booking__c>) c.query(
        'SELECT Space__c FROM PMS_Booking__c' +
          whereOf(
            new List<String>{
              c.bookingScope(),
              'Status__c = \'Active\'',
              'Space__c != null'
            }
          ) +
          ' LIMIT 10000'
      )
    ) {
      ids.add(b.Space__c);
    }
    return ids;
  }

  private static void propertyKpis(Ctx c) {
    Integer units = c.count(
      'SELECT COUNT() FROM PMS_Space__c' +
      whereOf(new List<String>{ c.siteFilter('Site__c') })
    );
    Integer occupied = occupiedUnits(c).size();
    Decimal occ = pct(occupied, units);
    Decimal arrears = overdueTotal(c);
    Integer arrearsCount = loadOverdue(c).size();
    c.binds.put('in90', c.todayStart.addDays(90));
    Integer expiring = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          'Status__c = \'Active\'',
          'End__c >= :todayStart',
          'End__c < :in90'
        }
      )
    );
    Integer openWo = c.count(
      'SELECT COUNT() FROM PMS_Work_Order__c' +
      whereOf(
        new List<String>{
          c.siteFilter('Site__c'),
          'Status__c NOT IN (\'Completed\', \'Closed\', \'Cancelled\')'
        }
      )
    );
    Integer urgentWo = c.count(
      'SELECT COUNT() FROM PMS_Work_Order__c' +
      whereOf(
        new List<String>{
          c.siteFilter('Site__c'),
          'Status__c NOT IN (\'Completed\', \'Closed\', \'Cancelled\')',
          'Priority__c IN (\'High\', \'Urgent\')'
        }
      )
    );

    c.data.kpis.add(
      nav(
        kpi(
          'occupancy',
          'Occupancy',
          occ,
          'percent',
          occupied + ' of ' + units + ' units let',
          occ >= 95 ? 'success' : (occ >= 85 ? 'neutral' : 'warning'),
          'utility:home'
        ),
        'PMS_Booking__c',
        'Active_Leases'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'vacant',
          'Vacant units',
          units - occupied,
          'count',
          'Ready to let or being prepared',
          units - occupied > 0 ? 'warning' : 'success',
          'utility:open_folder'
        ),
        'PMS_Space__c',
        'Vacant_Units'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'arrears',
          'Arrears',
          arrears,
          'money',
          arrearsCount + ' overdue invoices',
          arrears > 0 ? 'error' : 'success',
          'utility:warning'
        ),
        'PMS_Invoice__c',
        'Overdue_Invoices'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'revenue',
          'Rent received this month',
          revenueMtd(c),
          'money',
          revenueSub(c),
          'success',
          'utility:moneybag'
        ),
        'PMS_Payment__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'expiring',
          'Leases ending',
          expiring,
          'count',
          'In the next 90 days',
          expiring > 0 ? 'warning' : 'neutral',
          'utility:date_input'
        ),
        'PMS_Booking__c',
        'Active_Leases'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'workorders',
          'Open work orders',
          openWo,
          'count',
          urgentWo + ' high or urgent',
          urgentWo > 0 ? 'error' : 'neutral',
          'utility:custom_apps'
        ),
        'PMS_Work_Order__c',
        'All'
      )
    );
  }

  private static void propertyOccupancy(Ctx c) {
    Set<Id> occupied = occupiedUnits(c);
    Integer vacant = 0;
    Integer offline = 0;
    for (
      PMS_Space__c s : (List<PMS_Space__c>) c.query(
        'SELECT Id, Operational_Status__c FROM PMS_Space__c' +
          whereOf(new List<String>{ c.siteFilter('Site__c') }) +
          ' LIMIT 10000'
      )
    ) {
      if (occupied.contains(s.Id)) {
        continue;
      }
      if (
        s.Operational_Status__c == 'Out of Order' ||
        s.Operational_Status__c == 'Under Renovation'
      ) {
        offline++;
      } else {
        vacant++;
      }
    }
    Chart ch = chart(
      'occupancy',
      'Units',
      'Let, vacant and out of service',
      'donut',
      'count'
    );
    ch.labels.addAll(new List<String>{ 'Let', 'Vacant', 'Out of service' });
    ch.values.addAll(new List<Decimal>{ occupied.size(), vacant, offline });
    c.data.charts.add(ch);
  }

  private static void propertyAging(Ctx c) {
    List<Decimal> buckets = new List<Decimal>{ 0, 0, 0, 0 };
    for (PMS_Invoice__c i : loadOverdue(c)) {
      Decimal d = nz(i.Days_Overdue__c);
      Integer idx = d <= 30 ? 0 : (d <= 60 ? 1 : (d <= 90 ? 2 : 3));
      buckets[idx] += c.money(i.Balance__c, i);
    }
    Chart ch = chart(
      'aging',
      'Arrears by age',
      'Overdue balance, days past due',
      'bar',
      'money'
    );
    ch.labels.addAll(new List<String>{ '1-30', '31-60', '61-90', '90+' });
    ch.values.addAll(buckets);
    c.data.charts.add(ch);
  }

  private static void propertyWorkOrders(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Status__c l, COUNT(Id) n FROM PMS_Work_Order__c' +
        whereOf(
          new List<String>{
            c.siteFilter('Site__c'),
            'Status__c NOT IN (\'Closed\', \'Cancelled\')'
          }
        ) +
        ' GROUP BY Status__c ORDER BY COUNT(Id) DESC'
    );
    c.data.charts.add(
      fromAggregate(
        chart('workorders', 'Work orders', 'Open, by stage', 'hbar', 'count'),
        rows,
        'New'
      )
    );
  }

  private static void propertyQueues(Ctx c) {
    c.binds.put('in90', c.todayStart.addDays(90));
    List<PMS_Booking__c> ending = (List<PMS_Booking__c>) c.query(
      'SELECT Id, Name, End__c, Renewal_Status__c, Account__r.Name, Primary_Contact__r.Name, Space__r.Name' +
        ' FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Status__c = \'Active\'',
            'End__c >= :todayStart',
            'End__c < :in90'
          }
        ) +
        ' ORDER BY End__c ASC LIMIT ' +
        FETCH
    );
    Section ex = section(
      'expiring',
      'Leases ending soon',
      'standard:contract',
      'PMS_Booking__c',
      'Active_Leases',
      'No leases end in the next 90 days.'
    );
    ex.total = ending.size();
    for (PMS_Booking__c b : ending) {
      if (ex.items.size() == SHOW) {
        break;
      }
      String rs = String.isBlank(b.Renewal_Status__c)
        ? 'Not Due'
        : b.Renewal_Status__c;
      Item it = item(
        b.Id,
        join(who(b), b.Space__r == null ? null : b.Space__r.Name),
        b.Name,
        rs,
        rs == 'Renewing'
          ? 'success'
          : (rs == 'Not Due' || rs == 'Offer Sent' ? 'warning' : 'error')
      );
      it.whenDt = b.End__c;
      ex.items.add(it);
    }
    c.data.sections.add(ex);

    List<PMS_Work_Order__c> wos = (List<PMS_Work_Order__c>) c.query(
      'SELECT Id, Name, Subject__c, Status__c, Priority__c, Scheduled_Date__c, Space__r.Name, Vendor_Account__r.Name' +
        ' FROM PMS_Work_Order__c' +
        whereOf(
          new List<String>{
            c.siteFilter('Site__c'),
            'Status__c NOT IN (\'Completed\', \'Closed\', \'Cancelled\')'
          }
        ) +
        ' ORDER BY Priority__c DESC, CreatedDate ASC LIMIT ' +
        FETCH
    );
    Section wo = section(
      'workorders',
      'Open work orders',
      'standard:work_order',
      'PMS_Work_Order__c',
      'All',
      'No open work orders.'
    );
    wo.total = wos.size();
    for (PMS_Work_Order__c w : wos) {
      if (wo.items.size() == SHOW) {
        break;
      }
      Boolean hot = w.Priority__c == 'Urgent' || w.Priority__c == 'High';
      Item it = item(
        w.Id,
        join(w.Name, w.Subject__c),
        join(
          w.Space__r == null ? null : w.Space__r.Name,
          join(
            w.Vendor_Account__r == null
              ? 'No vendor yet'
              : w.Vendor_Account__r.Name,
            w.Status__c
          )
        ),
        w.Priority__c,
        hot ? 'error' : 'neutral'
      );
      it.whenDate = w.Scheduled_Date__c;
      wo.items.add(it);
    }
    c.data.sections.add(wo);

    List<PMS_Application__c> apps = (List<PMS_Application__c>) c.query(
      'SELECT Id, Name, Screening_Status__c, Desired_Move_In__c, Applicant__r.Name, Space__r.Name, Listing__r.Name' +
        ' FROM PMS_Application__c' +
        whereOf(
          new List<String>{
            c.isAdminView
              ? ''
              : '(Space__r.Site__c IN :siteIds OR Listing__r.Site__c IN :siteIds)',
            '(Decision__c = null OR Decision__c = \'Pending\')'
          }
        ) +
        ' ORDER BY CreatedDate ASC LIMIT ' +
        FETCH
    );
    Section ap = section(
      'applications',
      'Rental applications to decide',
      'standard:lead',
      'PMS_Application__c',
      'All',
      'No applications waiting.'
    );
    ap.total = apps.size();
    for (PMS_Application__c a : apps) {
      if (ap.items.size() == SHOW) {
        break;
      }
      Item it = item(
        a.Id,
        join(
          a.Applicant__r == null ? a.Name : a.Applicant__r.Name,
          a.Space__r == null ? null : a.Space__r.Name
        ),
        a.Listing__r == null ? a.Name : a.Listing__r.Name,
        String.isBlank(a.Screening_Status__c)
          ? 'Not screened'
          : a.Screening_Status__c,
        'neutral'
      );
      it.whenDate = a.Desired_Move_In__c;
      ap.items.add(it);
    }
    c.data.sections.add(ap);

    List<PMS_Vendor_Bill__c> bills = (List<PMS_Vendor_Bill__c>) c.query(
      'SELECT Id, Name, Status__c, Due_Date__c, Total__c, Vendor_Account__r.Name, Work_Order__r.Name' +
        c.cur() +
        ' FROM PMS_Vendor_Bill__c' +
        whereOf(
          new List<String>{
            c.siteFilter('Site__c'),
            'Status__c = \'Submitted\''
          }
        ) +
        ' ORDER BY Due_Date__c ASC NULLS LAST LIMIT ' +
        FETCH
    );
    Section vb = section(
      'bills',
      'Vendor bills to approve',
      'standard:partner_marketing_budget',
      'PMS_Vendor_Bill__c',
      null,
      'No vendor bills waiting.'
    );
    vb.total = bills.size();
    for (PMS_Vendor_Bill__c b : bills) {
      if (vb.items.size() == SHOW) {
        break;
      }
      Item it = item(
        b.Id,
        join(
          b.Name,
          b.Vendor_Account__r == null ? null : b.Vendor_Account__r.Name
        ),
        b.Work_Order__r == null ? null : b.Work_Order__r.Name,
        'Submitted',
        'warning'
      );
      it.amount = c.money(b.Total__c, b);
      it.whenDate = b.Due_Date__c;
      vb.items.add(it);
    }
    c.data.sections.add(vb);

    vendorQuotes(c);
    onlineCheckIns(c, 'Tenant check-ins received');
  }

  /** Quotes vendors sent from the Partner Portal that nobody has accepted or rejected yet. */
  private static void vendorQuotes(Ctx c) {
    List<PMS_Vendor_Quote__c> quotes = (List<PMS_Vendor_Quote__c>) c.query(
      'SELECT Id, Name, Status__c, Valid_Until__c, Total__c, CreatedDate, Vendor_Account__r.Name, Work_Order__r.Name, Work_Order__r.Subject__c' +
        c.cur() +
        ' FROM PMS_Vendor_Quote__c' +
        whereOf(
          new List<String>{
            c.siteFilter('Work_Order__r.Site__c'),
            'Status__c = \'Submitted\''
          }
        ) +
        ' ORDER BY Valid_Until__c ASC NULLS LAST LIMIT ' +
        FETCH
    );
    Section vq = section(
      'quotes',
      'Vendor quotes to decide',
      'standard:quotes',
      'PMS_Vendor_Quote__c',
      null,
      'No vendor quotes waiting.'
    );
    vq.total = quotes.size();
    for (PMS_Vendor_Quote__c q : quotes) {
      if (vq.items.size() == SHOW) {
        break;
      }
      Boolean expired = q.Valid_Until__c != null && q.Valid_Until__c < c.today;
      Item it = item(
        q.Id,
        join(
          q.Name,
          q.Vendor_Account__r == null ? null : q.Vendor_Account__r.Name
        ),
        q.Work_Order__r == null
          ? null
          : join(q.Work_Order__r.Name, q.Work_Order__r.Subject__c),
        expired ? 'Expired' : 'To decide',
        expired ? 'error' : 'warning'
      );
      it.amount = c.money(q.Total__c, q);
      it.whenDate = q.Valid_Until__c;
      vq.items.add(it);
    }
    c.data.sections.add(vq);
  }

  private static void propertyAgenda(Ctx c) {
    Date in7 = c.today.addDays(7);
    c.binds.put('in7', in7);
    c.binds.put('in7Dt', c.todayStart.addDays(7));
    List<Item> all = new List<Item>();
    for (
      PMS_Work_Order__c w : (List<PMS_Work_Order__c>) c.query(
        'SELECT Id, Name, Subject__c, Scheduled_Date__c, Space__r.Name, Vendor_Account__r.Name FROM PMS_Work_Order__c' +
          whereOf(
            new List<String>{
              c.siteFilter('Site__c'),
              'Scheduled_Date__c >= :today',
              'Scheduled_Date__c <= :in7',
              'Status__c NOT IN (\'Completed\', \'Closed\', \'Cancelled\')'
            }
          ) +
          ' LIMIT 50'
      )
    ) {
      Item it = item(
        w.Id,
        join(w.Subject__c, w.Space__r == null ? null : w.Space__r.Name),
        join(
          w.Name,
          w.Vendor_Account__r == null ? null : w.Vendor_Account__r.Name
        ),
        'Work order',
        'neutral'
      );
      it.whenDate = w.Scheduled_Date__c;
      all.add(it);
    }
    for (
      PMS_Inspection__c i : (List<PMS_Inspection__c>) c.query(
        'SELECT Id, Name, Inspection_Type__c, Inspection_Date__c, Space__r.Name FROM PMS_Inspection__c' +
          whereOf(
            new List<String>{
              c.siteFilter('Site__c'),
              'Inspection_Date__c >= :today',
              'Inspection_Date__c <= :in7'
            }
          ) +
          ' LIMIT 50'
      )
    ) {
      Item it = item(
        i.Id,
        join(
          i.Inspection_Type__c == null
            ? 'Inspection'
            : i.Inspection_Type__c + ' inspection',
          i.Space__r == null ? null : i.Space__r.Name
        ),
        i.Name,
        'Inspection',
        'neutral'
      );
      it.whenDate = i.Inspection_Date__c;
      all.add(it);
    }
    for (
      PMS_Booking__c b : (List<PMS_Booking__c>) c.query(
        'SELECT Id, Name, Start__c, End__c, Status__c, Account__r.Name, Primary_Contact__r.Name, Space__r.Name FROM PMS_Booking__c' +
          whereOf(
            new List<String>{
              c.bookingScope(),
              'Status__c IN (\'Confirmed\', \'Active\')',
              '((Start__c >= :todayStart AND Start__c < :in7Dt) OR (End__c >= :todayStart AND End__c < :in7Dt))'
            }
          ) +
          ' LIMIT 50'
      )
    ) {
      Boolean moveIn =
        b.Start__c >= c.todayStart &&
        b.Start__c < c.todayStart.addDays(7);
      Item it = item(
        b.Id,
        join(who(b), b.Space__r == null ? null : b.Space__r.Name),
        b.Name,
        moveIn ? 'Move-in' : 'Move-out',
        moveIn ? 'success' : 'warning'
      );
      it.whenDt = moveIn ? b.Start__c : b.End__c;
      all.add(it);
    }
    c.data.agenda.addAll(sortByTime(all));
  }

  // ------------------------------------------------------------------ Projects

  private static void projectKpis(Ctx c) {
    String site = c.optionalSite('Site__c');
    String childSite = c.optionalSite('Project__r.Site__c');
    Integer active = c.count(
      'SELECT COUNT() FROM PMS_Project__c' +
      whereOf(
        new List<String>{ site, 'Status__c IN (\'Planning\', \'In Progress\')' }
      )
    );
    Integer atRisk = c.count(
      'SELECT COUNT() FROM PMS_Project__c' +
      whereOf(
        new List<String>{
          site,
          'Status__c IN (\'Planning\', \'In Progress\')',
          'Health__c IN (\'Amber\', \'Red\')'
        }
      )
    );
    Integer red = c.count(
      'SELECT COUNT() FROM PMS_Project__c' +
      whereOf(
        new List<String>{
          site,
          'Status__c IN (\'Planning\', \'In Progress\')',
          'Health__c = \'Red\''
        }
      )
    );
    Integer overdueTasks = c.count(
      'SELECT COUNT() FROM PMS_Project_Task__c' +
      whereOf(
        new List<String>{
          childSite,
          'End_Date__c < :today',
          'Status__c != \'Done\'',
          'Project__r.Status__c IN (\'Planning\', \'In Progress\')'
        }
      )
    );
    c.binds.put('in30', c.today.addDays(30));
    Integer milestones = c.count(
      'SELECT COUNT() FROM PMS_Milestone__c' +
      whereOf(
        new List<String>{
          childSite,
          'Due_Date__c >= :today',
          'Due_Date__c <= :in30',
          'Status__c NOT IN (\'Completed\', \'Accepted\')'
        }
      )
    );
    Integer missed = c.count(
      'SELECT COUNT() FROM PMS_Milestone__c' +
      whereOf(
        new List<String>{
          childSite,
          'Due_Date__c < :today',
          'Status__c NOT IN (\'Completed\', \'Accepted\')'
        }
      )
    );

    Decimal hours = 0;
    for (
      SObject r : c.query(
        'SELECT SUM(Hours__c) n FROM PMS_Time_Entry__c' +
        whereOf(
          new List<String>{
            childSite,
            'Project__c != null',
            'Entry_Date__c = THIS_WEEK'
          }
        )
      )
    ) {
      hours = dec(r.get('n'));
    }
    Decimal budget = 0;
    Decimal actual = 0;
    for (
      PMS_Project__c p : (List<PMS_Project__c>) c.query(
        'SELECT Budget__c, Actual_Cost__c' +
          c.cur() +
          ' FROM PMS_Project__c' +
          whereOf(
            new List<String>{
              site,
              'Status__c IN (\'Planning\', \'In Progress\')'
            }
          ) +
          ' LIMIT 2000'
      )
    ) {
      budget += c.money(p.Budget__c, p);
      actual += c.money(p.Actual_Cost__c, p);
    }
    Decimal used = pct(actual, budget);

    c.data.kpis.add(
      nav(
        kpi(
          'active',
          'Active projects',
          active,
          'count',
          'Planning or in progress',
          'neutral',
          'utility:work_order_type'
        ),
        'PMS_Project__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'risk',
          'At risk',
          atRisk,
          'count',
          red + ' red, ' + (atRisk - red) + ' amber',
          red > 0 ? 'error' : (atRisk > 0 ? 'warning' : 'success'),
          'utility:warning'
        ),
        'PMS_Project__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'overdueTasks',
          'Overdue tasks',
          overdueTasks,
          'count',
          'Past their end date',
          overdueTasks > 0 ? 'error' : 'success',
          'utility:clock'
        ),
        'PMS_Project_Task__c',
        'Open_Tasks'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'milestones',
          'Milestones due',
          milestones,
          'count',
          missed + ' missed, next 30 days shown',
          missed > 0 ? 'warning' : 'neutral',
          'utility:priority'
        ),
        'PMS_Milestone__c',
        null
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'hours',
          'Hours this week',
          hours,
          'hours',
          'Logged against projects',
          'neutral',
          'utility:clock'
        ),
        'PMS_Time_Entry__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'budget',
          'Budget used',
          used,
          'percent',
          'Actual cost vs budget, active projects',
          used > 100 ? 'error' : (used > 85 ? 'warning' : 'success'),
          'utility:moneybag'
        ),
        'PMS_Project__c',
        'All'
      )
    );
  }

  private static void projectHealth(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Health__c l, COUNT(Id) n FROM PMS_Project__c' +
        whereOf(
          new List<String>{
            c.optionalSite('Site__c'),
            'Status__c IN (\'Planning\', \'In Progress\')'
          }
        ) +
        ' GROUP BY Health__c'
    );
    Chart ch = chart(
      'health',
      'Project health',
      'Active projects',
      'donut',
      'count'
    );
    Map<String, Decimal> byHealth = new Map<String, Decimal>{
      'Green' => 0,
      'Amber' => 0,
      'Red' => 0
    };
    for (SObject r : rows) {
      String h = r.get('l') == null ? 'Green' : String.valueOf(r.get('l'));
      byHealth.put(h, nz(byHealth.get(h)) + dec(r.get('n')));
    }
    for (String h : byHealth.keySet()) {
      ch.labels.add(h);
      ch.values.add(byHealth.get(h));
    }
    c.data.charts.add(ch);
  }

  private static void projectHours(Ctx c) {
    Date firstWeek = c.today.toStartOfWeek().addDays(-49);
    c.binds.put('firstWeek', firstWeek);
    Chart ch = chart('hours', 'Hours logged', 'Last 8 weeks', 'bar', 'hours');
    List<Decimal> buckets = new List<Decimal>{ 0, 0, 0, 0, 0, 0, 0, 0 };
    for (
      PMS_Time_Entry__c t : (List<PMS_Time_Entry__c>) c.query(
        'SELECT Hours__c, Entry_Date__c FROM PMS_Time_Entry__c' +
          whereOf(
            new List<String>{
              c.optionalSite('Project__r.Site__c'),
              'Project__c != null',
              'Entry_Date__c >= :firstWeek'
            }
          ) +
          ' LIMIT 10000'
      )
    ) {
      Integer idx = firstWeek.daysBetween(t.Entry_Date__c) / 7;
      if (idx >= 0 && idx < 8) {
        buckets[idx] += nz(t.Hours__c);
      }
    }
    for (Integer i = 0; i < 8; i++) {
      ch.labels.add(
        'w' +
        Datetime.newInstance(
            firstWeek.addDays(i * 7),
            Time.newInstance(12, 0, 0, 0)
          )
          .format('w')
      );
    }
    ch.values.addAll(buckets);
    c.data.charts.add(ch);
  }

  private static void projectTasks(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Status__c l, COUNT(Id) n FROM PMS_Project_Task__c' +
        whereOf(
          new List<String>{
            c.optionalSite('Project__r.Site__c'),
            'Project__r.Status__c IN (\'Planning\', \'In Progress\')'
          }
        ) +
        ' GROUP BY Status__c ORDER BY COUNT(Id) DESC'
    );
    c.data.charts.add(
      fromAggregate(
        chart('tasks', 'Tasks by status', 'Active projects', 'hbar', 'count'),
        rows,
        'Not Started'
      )
    );
  }

  private static void projectBudget(Ctx c) {
    Chart ch = chart(
      'budget',
      'Budget used by project',
      'Actual cost as % of budget',
      'hbar',
      'percent'
    );
    for (
      PMS_Project__c p : (List<PMS_Project__c>) c.query(
        'SELECT Name, Budget__c, Actual_Cost__c FROM PMS_Project__c' +
          whereOf(
            new List<String>{
              c.optionalSite('Site__c'),
              'Status__c IN (\'Planning\', \'In Progress\')',
              'Budget__c > 0'
            }
          ) +
          ' ORDER BY Budget__c DESC LIMIT 6'
      )
    ) {
      ch.labels.add(p.Name);
      ch.values.add(pct(nz(p.Actual_Cost__c), p.Budget__c));
    }
    c.data.charts.add(ch);
  }

  private static void projectQueues(Ctx c) {
    String childSite = c.optionalSite('Project__r.Site__c');
    List<PMS_Project_Task__c> tasks = (List<PMS_Project_Task__c>) c.query(
      'SELECT Id, Name, Status__c, End_Date__c, Priority__c, Project__r.Name, Assignee__r.Name' +
        ' FROM PMS_Project_Task__c' +
        whereOf(
          new List<String>{
            childSite,
            'Status__c != \'Done\'',
            'Project__r.Status__c IN (\'Planning\', \'In Progress\')',
            '(End_Date__c < :today OR Status__c = \'Blocked\')'
          }
        ) +
        ' ORDER BY End_Date__c ASC NULLS LAST LIMIT ' +
        FETCH
    );
    Section ts = section(
      'tasks',
      'Late or blocked tasks',
      'standard:task',
      'PMS_Project_Task__c',
      'Open_Tasks',
      'No late or blocked tasks.'
    );
    ts.total = tasks.size();
    for (PMS_Project_Task__c t : tasks) {
      if (ts.items.size() == SHOW) {
        break;
      }
      Boolean blocked = t.Status__c == 'Blocked';
      Item it = item(
        t.Id,
        t.Name,
        join(
          t.Project__r == null ? null : t.Project__r.Name,
          t.Assignee__r == null ? 'Unassigned' : t.Assignee__r.Name
        ),
        blocked ? 'Blocked' : 'Late',
        blocked ? 'error' : 'warning'
      );
      it.whenDate = t.End_Date__c;
      ts.items.add(it);
    }
    c.data.sections.add(ts);

    List<PMS_RAID_Item__c> raid = (List<PMS_RAID_Item__c>) c.query(
      'SELECT Id, Name, RAID_Type__c, Severity__c, Status__c, Due_Date__c, Project__r.Name, Item_Owner__r.Name' +
        ' FROM PMS_RAID_Item__c' +
        whereOf(
          new List<String>{
            childSite,
            'Status__c != \'Closed\'',
            'Severity__c IN (\'High\', \'Critical\')'
          }
        ) +
        ' ORDER BY Severity__c DESC, Due_Date__c ASC NULLS LAST LIMIT ' +
        FETCH
    );
    Section rs = section(
      'raid',
      'High risks and issues',
      'standard:incident',
      'PMS_RAID_Item__c',
      'All',
      'No high or critical RAID items open.'
    );
    rs.total = raid.size();
    for (PMS_RAID_Item__c r : raid) {
      if (rs.items.size() == SHOW) {
        break;
      }
      Item it = item(
        r.Id,
        join(r.RAID_Type__c, r.Name),
        join(
          r.Project__r == null ? null : r.Project__r.Name,
          r.Item_Owner__r == null ? null : r.Item_Owner__r.Name
        ),
        r.Severity__c,
        r.Severity__c == 'Critical' ? 'error' : 'warning'
      );
      it.whenDate = r.Due_Date__c;
      rs.items.add(it);
    }
    c.data.sections.add(rs);

    List<PMS_Milestone__c> acc = (List<PMS_Milestone__c>) c.query(
      'SELECT Id, Name, Due_Date__c, Amount__c, Invoiced__c, Project__r.Name' +
        c.cur() +
        ' FROM PMS_Milestone__c' +
        whereOf(
          new List<String>{
            childSite,
            'Status__c = \'Completed\'',
            'Accepted_At__c = null'
          }
        ) +
        ' ORDER BY Due_Date__c ASC LIMIT ' +
        FETCH
    );
    Section ms = section(
      'acceptance',
      'Milestones awaiting client sign-off',
      'standard:goals',
      'PMS_Milestone__c',
      null,
      'No milestones waiting for sign-off.'
    );
    ms.total = acc.size();
    for (PMS_Milestone__c m : acc) {
      if (ms.items.size() == SHOW) {
        break;
      }
      Item it = item(
        m.Id,
        m.Name,
        m.Project__r == null ? null : m.Project__r.Name,
        'Awaiting acceptance',
        'warning'
      );
      it.amount = m.Amount__c == null ? null : c.money(m.Amount__c, m);
      it.whenDate = m.Due_Date__c;
      ms.items.add(it);
    }
    c.data.sections.add(ms);

    List<PMS_Time_Entry__c> sheets = (List<PMS_Time_Entry__c>) c.query(
      'SELECT Id, Name, Hours__c, Entry_Date__c, Resource__r.Name, Project__r.Name' +
        ' FROM PMS_Time_Entry__c' +
        whereOf(
          new List<String>{
            childSite,
            'Project__c != null',
            'Approval_Status__c = \'Submitted\''
          }
        ) +
        ' ORDER BY Entry_Date__c ASC LIMIT ' +
        FETCH
    );
    Section tsh = section(
      'timesheets',
      'Time to approve',
      'standard:timesheet',
      'PMS_Time_Entry__c',
      'All',
      'No time entries waiting for approval.'
    );
    tsh.total = sheets.size();
    for (PMS_Time_Entry__c t : sheets) {
      if (tsh.items.size() == SHOW) {
        break;
      }
      Item it = item(
        t.Id,
        join(
          t.Resource__r == null ? t.Name : t.Resource__r.Name,
          nz(t.Hours__c).format() + ' h'
        ),
        t.Project__r == null ? null : t.Project__r.Name,
        'Submitted',
        'neutral'
      );
      it.whenDate = t.Entry_Date__c;
      tsh.items.add(it);
    }
    c.data.sections.add(tsh);
  }

  private static void projectAgenda(Ctx c) {
    String childSite = c.optionalSite('Project__r.Site__c');
    c.binds.put('in14', c.today.addDays(14));
    List<Item> all = new List<Item>();
    for (
      PMS_Milestone__c m : (List<PMS_Milestone__c>) c.query(
        'SELECT Id, Name, Due_Date__c, Status__c, Project__r.Name FROM PMS_Milestone__c' +
          whereOf(
            new List<String>{
              childSite,
              'Due_Date__c >= :today',
              'Due_Date__c <= :in14',
              'Status__c NOT IN (\'Completed\', \'Accepted\')'
            }
          ) +
          ' LIMIT 50'
      )
    ) {
      Item it = item(
        m.Id,
        m.Name,
        m.Project__r == null ? null : m.Project__r.Name,
        'Milestone',
        'warning'
      );
      it.whenDate = m.Due_Date__c;
      all.add(it);
    }
    for (
      PMS_Project_Task__c t : (List<PMS_Project_Task__c>) c.query(
        'SELECT Id, Name, End_Date__c, Project__r.Name, Assignee__r.Name FROM PMS_Project_Task__c' +
          whereOf(
            new List<String>{
              childSite,
              'End_Date__c >= :today',
              'End_Date__c <= :in14',
              'Status__c != \'Done\''
            }
          ) +
          ' LIMIT 50'
      )
    ) {
      Item it = item(
        t.Id,
        t.Name,
        join(
          t.Project__r == null ? null : t.Project__r.Name,
          t.Assignee__r == null ? null : t.Assignee__r.Name
        ),
        'Task due',
        'neutral'
      );
      it.whenDate = t.End_Date__c;
      all.add(it);
    }
    c.data.agenda.addAll(sortByTime(all));
  }

  // ------------------------------------------------------------------ Practice

  private static void practiceKpis(Ctx c) {
    String excluded = 'Status__c NOT IN (\'Cancelled\', \'No Show\', \'Inquiry\')';
    c.binds.put('in7Dt', c.todayStart.addDays(7));
    Integer today = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          excluded,
          'Start__c >= :todayStart',
          'Start__c < :tomorrowStart'
        }
      )
    );
    Integer done = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          'Status__c = \'Completed\'',
          'Start__c >= :todayStart',
          'Start__c < :tomorrowStart'
        }
      )
    );
    Integer week = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          excluded,
          'Start__c >= :todayStart',
          'Start__c < :in7Dt'
        }
      )
    );
    Integer tentative = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          'Status__c = \'Tentative\'',
          'Start__c >= :todayStart'
        }
      )
    );
    Integer matters = c.count(
      'SELECT COUNT() FROM PMS_Matter__c' +
      whereOf(
        new List<String>{
          c.optionalSite('Site__c'),
          'Status__c IN (\'Intake\', \'Open\')'
        }
      )
    );
    Integer intake = c.count(
      'SELECT COUNT() FROM PMS_Matter__c' +
      whereOf(
        new List<String>{ c.optionalSite('Site__c'), 'Status__c = \'Intake\'' }
      )
    );
    List<Integer> openCount = new List<Integer>();
    Decimal ar = outstanding(c, openCount);
    Integer noShow = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          'Status__c = \'No Show\'',
          'Start__c = LAST_N_DAYS:30'
        }
      )
    );
    Integer attended = c.count(
      'SELECT COUNT() FROM PMS_Booking__c' +
      whereOf(
        new List<String>{
          c.bookingScope(),
          'Status__c = \'Completed\'',
          'Start__c = LAST_N_DAYS:30'
        }
      )
    );
    Decimal noShowRate = pct(noShow, noShow + attended);

    c.data.kpis.add(
      nav(
        kpi(
          'today',
          'Appointments today',
          today,
          'count',
          done + ' completed',
          'neutral',
          'utility:event'
        ),
        'PMS_Booking__c',
        'Upcoming_Appointments'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'week',
          'Next 7 days',
          week,
          'count',
          tentative + ' still tentative',
          tentative > 0 ? 'warning' : 'neutral',
          'utility:monthlyview'
        ),
        'PMS_Booking__c',
        'Upcoming_Appointments'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'matters',
          'Open matters',
          matters,
          'count',
          intake + ' in intake',
          'neutral',
          'utility:case'
        ),
        'PMS_Matter__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'revenue',
          'Received this month',
          revenueMtd(c),
          'money',
          revenueSub(c),
          'success',
          'utility:moneybag'
        ),
        'PMS_Payment__c',
        'All'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'ar',
          'Unpaid invoices',
          ar,
          'money',
          openCount[0] + ' open',
          ar > 0 ? 'warning' : 'success',
          'utility:currency'
        ),
        'PMS_Invoice__c',
        'Open_Invoices'
      )
    );
    c.data.kpis.add(
      nav(
        kpi(
          'noshow',
          'No-show rate',
          noShowRate,
          'percent',
          noShow + ' no-shows in 30 days',
          noShowRate > 10 ? 'error' : (noShowRate > 5 ? 'warning' : 'success'),
          'utility:block_visitor'
        ),
        'PMS_Booking__c',
        'All'
      )
    );
  }

  private static void practiceWeek(Ctx c) {
    c.binds.put('in7Dt', c.todayStart.addDays(7));
    List<PMS_Booking__c> rows = (List<PMS_Booking__c>) c.query(
      'SELECT Start__c FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Status__c NOT IN (\'Cancelled\', \'No Show\', \'Inquiry\')',
            'Start__c >= :todayStart',
            'Start__c < :in7Dt'
          }
        ) +
        ' LIMIT 10000'
    );
    Chart ch = chart('week', 'Appointments', 'Next 7 days', 'bar', 'count');
    List<Decimal> buckets = new List<Decimal>{ 0, 0, 0, 0, 0, 0, 0 };
    for (PMS_Booking__c b : rows) {
      Integer idx = c.today.daysBetween(b.Start__c.date());
      if (idx >= 0 && idx < 7) {
        buckets[idx]++;
      }
    }
    for (Integer i = 0; i < 7; i++) {
      ch.labels.add(
        Datetime.newInstance(c.today.addDays(i), Time.newInstance(12, 0, 0, 0))
          .format('EEE d')
      );
    }
    ch.values.addAll(buckets);
    c.data.charts.add(ch);
  }

  private static void practicePractitioners(Ctx c) {
    c.binds.put('in7Dt', c.todayStart.addDays(7));
    List<SObject> rows = c.query(
      'SELECT Practitioner__r.Name l, COUNT(Id) n FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Status__c NOT IN (\'Cancelled\', \'No Show\', \'Inquiry\')',
            'Start__c >= :todayStart',
            'Start__c < :in7Dt'
          }
        ) +
        ' GROUP BY Practitioner__r.Name ORDER BY COUNT(Id) DESC LIMIT 8'
    );
    c.data.charts.add(
      fromAggregate(
        chart(
          'practitioners',
          'Appointments by practitioner',
          'Next 7 days',
          'hbar',
          'count'
        ),
        rows,
        'Unassigned'
      )
    );
  }

  private static void practiceModes(Ctx c) {
    List<SObject> rows = c.query(
      'SELECT Appointment_Mode__c l, COUNT(Id) n FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Status__c NOT IN (\'Cancelled\', \'Inquiry\')',
            'Start__c = LAST_N_DAYS:30'
          }
        ) +
        ' GROUP BY Appointment_Mode__c ORDER BY COUNT(Id) DESC'
    );
    c.data.charts.add(
      fromAggregate(
        chart('modes', 'How clients attend', 'Last 30 days', 'donut', 'count'),
        rows,
        'In Person'
      )
    );
  }

  private static void practiceQueues(Ctx c) {
    List<PMS_Booking__c> tent = (List<PMS_Booking__c>) c.query(
      BOOKING_FIELDS +
        ' FROM PMS_Booking__c' +
        whereOf(
          new List<String>{
            c.bookingScope(),
            'Status__c = \'Tentative\'',
            'Start__c >= :todayStart'
          }
        ) +
        ' ORDER BY Start__c ASC LIMIT ' +
        FETCH
    );
    Section ts = section(
      'tentative',
      'Appointments to confirm',
      'standard:event',
      'PMS_Booking__c',
      'Upcoming_Appointments',
      'All upcoming appointments are confirmed.'
    );
    ts.total = tent.size();
    for (PMS_Booking__c b : tent) {
      if (ts.items.size() == SHOW) {
        break;
      }
      Item it = item(
        b.Id,
        join(who(b), b.Service__r == null ? null : b.Service__r.Name),
        join(
          b.Practitioner__r == null ? null : b.Practitioner__r.Name,
          b.Channel__c
        ),
        'Tentative',
        'warning'
      );
      it.whenDt = b.Start__c;
      ts.items.add(it);
    }
    c.data.sections.add(ts);

    String formScope = c.isAdminView
      ? ''
      : (c.siteId == null
          ? '(Booking__r.Site__c IN :siteIds OR Matter__c != null)'
          : '(Booking__r.Site__c = :siteId OR Matter__r.Site__c = :siteId)');
    List<PMS_Intake_Form__c> forms = (List<PMS_Intake_Form__c>) c.query(
      'SELECT Id, Name, Form_Type__c, CreatedDate, Contact__r.Name, Matter__r.Name, Booking__r.Start__c' +
        ' FROM PMS_Intake_Form__c' +
        whereOf(new List<String>{ formScope, 'Signed_Date__c = null' }) +
        ' ORDER BY CreatedDate ASC LIMIT ' +
        FETCH
    );
    Section fs = section(
      'intake',
      'Intake forms not signed',
      'standard:form',
      'PMS_Intake_Form__c',
      null,
      'Every intake form is signed.'
    );
    fs.total = forms.size();
    for (PMS_Intake_Form__c f : forms) {
      if (fs.items.size() == SHOW) {
        break;
      }
      Item it = item(
        f.Id,
        join(f.Contact__r == null ? f.Name : f.Contact__r.Name, f.Form_Type__c),
        f.Matter__r == null ? null : f.Matter__r.Name,
        'Not signed',
        'warning'
      );
      it.whenDt = f.Booking__r != null &&
        f.Booking__r.Start__c != null
        ? f.Booking__r.Start__c
        : f.CreatedDate;
      fs.items.add(it);
    }
    c.data.sections.add(fs);

    List<PMS_Matter__c> conflicts = (List<PMS_Matter__c>) c.query(
      'SELECT Id, Name, Conflict_Check_Status__c, Open_Date__c, Account__r.Name, Responsible_Practitioner__r.Name' +
        ' FROM PMS_Matter__c' +
        whereOf(
          new List<String>{
            c.optionalSite('Site__c'),
            'Status__c = \'Intake\''
          }
        ) +
        ' ORDER BY CreatedDate ASC LIMIT ' +
        FETCH
    );
    Section ms = section(
      'intakeMatters',
      'Matters in intake',
      'standard:case',
      'PMS_Matter__c',
      'All',
      'No matters waiting in intake.'
    );
    ms.total = conflicts.size();
    for (PMS_Matter__c m : conflicts) {
      if (ms.items.size() == SHOW) {
        break;
      }
      String cc = String.isBlank(m.Conflict_Check_Status__c)
        ? 'Conflict check not started'
        : 'Conflict check: ' + m.Conflict_Check_Status__c;
      Item it = item(
        m.Id,
        join(m.Name, m.Account__r == null ? null : m.Account__r.Name),
        m.Responsible_Practitioner__r == null
          ? 'No practitioner yet'
          : m.Responsible_Practitioner__r.Name,
        cc,
        m.Conflict_Check_Status__c == 'Cleared' ? 'success' : 'warning'
      );
      it.whenDate = m.Open_Date__c;
      ms.items.add(it);
    }
    c.data.sections.add(ms);

    onlineCheckIns(c, 'Questionnaires received');
  }

  private static void practiceAgenda(Ctx c) {
    for (
      PMS_Booking__c b : (List<PMS_Booking__c>) c.query(
        BOOKING_FIELDS +
          ' FROM PMS_Booking__c' +
          whereOf(
            new List<String>{
              c.bookingScope(),
              'Status__c NOT IN (\'Cancelled\', \'Inquiry\')',
              'Start__c >= :todayStart',
              'Start__c < :tomorrowStart'
            }
          ) +
          ' ORDER BY Start__c ASC LIMIT 40'
      )
    ) {
      String tone = b.Status__c == 'Completed'
        ? 'success'
        : (b.Status__c == 'No Show'
            ? 'error'
            : (b.Status__c == 'Tentative' ? 'warning' : 'neutral'));
      Item it = item(
        b.Id,
        join(who(b), b.Service__r == null ? null : b.Service__r.Name),
        join(
          b.Practitioner__r == null ? null : b.Practitioner__r.Name,
          b.Appointment_Mode__c
        ),
        b.Status__c,
        tone
      );
      it.whenDt = b.Start__c;
      c.data.agenda.add(it);
    }
  }
}
