/**
 * Demo data steps: projects, the clinic (practice), requests (service), work orders and vendors (ops) and
 * channel manager logs (channels). Called by PMS_DemoData, one step per transaction.
 */
public with sharing class PMS_DemoDataWork {
  // ------------------------------------------------------------------ projects

  public static PMS_Project_Task__c task(
    PMS_DemoData.Ctx c,
    String project,
    String assignee,
    String name,
    String status,
    Integer percent,
    Integer fromDay,
    Integer toDay,
    Integer hours,
    String priority,
    String milestone
  ) {
    return new PMS_Project_Task__c(
      Name = name,
      Project__c = c.ref(project),
      Assignee__c = c.ref(assignee),
      Status__c = status,
      Percent_Complete__c = percent,
      Start_Date__c = c.day(fromDay),
      End_Date__c = c.day(toDay),
      Estimated_Hours__c = hours,
      Priority__c = priority,
      Milestone__c = milestone == null ? null : c.ref(milestone)
    );
  }

  public static void projects(PMS_DemoData.Ctx c) {
    Id site = c.ref('s.proj');
    c.add(
      new PMS_Resource__c(
        Name = 'Karin Holm',
        Role__c = 'Projektledare',
        Resource_Type__c = 'Person',
        Bill_Rate__c = 1250,
        Cost_Rate__c = 780,
        Weekly_Capacity__c = 40,
        Active__c = true
      ),
      'rs.1'
    );
    c.add(
      new PMS_Resource__c(
        Name = 'Daniel Sandberg',
        Role__c = 'Byggledare',
        Resource_Type__c = 'Person',
        Bill_Rate__c = 1100,
        Cost_Rate__c = 700,
        Weekly_Capacity__c = 40,
        Active__c = true
      ),
      'rs.2'
    );
    c.add(
      new PMS_Resource__c(
        Name = 'Ulrika Nyberg',
        Role__c = 'Arkitekt',
        Resource_Type__c = 'Person',
        Bill_Rate__c = 1350,
        Cost_Rate__c = 850,
        Weekly_Capacity__c = 32,
        Active__c = true
      ),
      'rs.3'
    );
    c.add(
      new PMS_Resource__c(
        Name = 'Tomas Ekberg',
        Role__c = 'Elkonstruktör',
        Resource_Type__c = 'Person',
        Bill_Rate__c = 1050,
        Cost_Rate__c = 650,
        Weekly_Capacity__c = 40,
        Active__c = true
      ),
      'rs.4'
    );
    c.add(
      new PMS_Resource__c(
        Name = 'Bygg & Montage Norr AB',
        Role__c = 'Entreprenör',
        Resource_Type__c = 'Contractor',
        Bill_Rate__c = 950,
        Cost_Rate__c = 800,
        Weekly_Capacity__c = 80,
        Active__c = true
      ),
      'rs.5'
    );
    c.save();

    // Three active projects (red, amber, green) and one completed
    c.add(
      new PMS_Project__c(
        Name = 'Ombyggnad Kv. Tallen',
        Account__c = c.ref('a.p2'),
        Site__c = site,
        Status__c = 'In Progress',
        Health__c = 'Red',
        Billing_Type__c = 'Milestone',
        Budget__c = 2400000,
        Actual_Cost__c = 1950000,
        Percent_Complete__c = 62,
        Start_Date__c = c.day(-120),
        End_Date__c = c.day(90),
        Project_Manager__c = c.userId
      ),
      'pj.1'
    );
    c.add(
      new PMS_Project__c(
        Name = 'Fasadrenovering Brf Solgläntan',
        Account__c = c.ref('a.p1'),
        Site__c = site,
        Status__c = 'In Progress',
        Health__c = 'Amber',
        Billing_Type__c = 'Fixed Price',
        Budget__c = 1200000,
        Actual_Cost__c = 1010000,
        Percent_Complete__c = 55,
        Start_Date__c = c.day(-75),
        End_Date__c = c.day(40),
        Project_Manager__c = c.userId
      ),
      'pj.2'
    );
    c.add(
      new PMS_Project__c(
        Name = 'Energieffektivisering Hammarby',
        Account__c = c.ref('a.p2'),
        Site__c = site,
        Status__c = 'Planning',
        Health__c = 'Green',
        Billing_Type__c = 'Time and Materials',
        Budget__c = 500000,
        Actual_Cost__c = 40000,
        Percent_Complete__c = 8,
        Start_Date__c = c.day(-14),
        End_Date__c = c.day(120),
        Project_Manager__c = c.userId
      ),
      'pj.3'
    );
    c.add(
      new PMS_Project__c(
        Name = 'Kontorsflytt Sundbyberg',
        Account__c = c.ref('a.p1'),
        Site__c = site,
        Status__c = 'Completed',
        Health__c = 'Green',
        Billing_Type__c = 'Fixed Price',
        Budget__c = 300000,
        Actual_Cost__c = 285000,
        Percent_Complete__c = 100,
        Start_Date__c = c.day(-200),
        End_Date__c = c.day(-60),
        Project_Manager__c = c.userId
      ),
      'pj.4'
    );
    c.save();

    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.1'),
        Category__c = 'Labour',
        Budget_Amount__c = 900000,
        Committed__c = 880000,
        Actual__c = 790000
      ),
      'bl.1a'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.1'),
        Category__c = 'Materials',
        Budget_Amount__c = 1000000,
        Committed__c = 950000,
        Actual__c = 820000
      ),
      'bl.1b'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.1'),
        Category__c = 'Subcontractors',
        Budget_Amount__c = 400000,
        Committed__c = 380000,
        Actual__c = 310000
      ),
      'bl.1c'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.1'),
        Category__c = 'Contingency',
        Budget_Amount__c = 100000,
        Committed__c = 30000,
        Actual__c = 30000
      ),
      'bl.1d'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.2'),
        Category__c = 'Labour',
        Budget_Amount__c = 450000,
        Committed__c = 450000,
        Actual__c = 430000
      ),
      'bl.2a'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.2'),
        Category__c = 'Materials',
        Budget_Amount__c = 500000,
        Committed__c = 480000,
        Actual__c = 420000
      ),
      'bl.2b'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.2'),
        Category__c = 'Equipment',
        Budget_Amount__c = 250000,
        Committed__c = 180000,
        Actual__c = 160000
      ),
      'bl.2c'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.3'),
        Category__c = 'Other',
        Budget_Amount__c = 150000,
        Committed__c = 40000,
        Actual__c = 40000
      ),
      'bl.3a'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.3'),
        Category__c = 'Labour',
        Budget_Amount__c = 350000,
        Committed__c = 0,
        Actual__c = 0
      ),
      'bl.3b'
    );
    c.save();

    // Milestones: one waiting for client sign-off, one missed, two coming up
    c.add(
      new PMS_Milestone__c(
        Name = 'Rivning klar',
        Project__c = c.ref('pj.1'),
        Status__c = 'Completed',
        Due_Date__c = c.day(-10),
        Amount__c = 300000,
        Invoiced__c = true
      ),
      'ms.1a'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Stomme och bjälklag',
        Project__c = c.ref('pj.1'),
        Status__c = 'In Progress',
        Due_Date__c = c.day(-3),
        Amount__c = 600000,
        Invoiced__c = false
      ),
      'ms.1b'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Slutbesiktning',
        Project__c = c.ref('pj.1'),
        Status__c = 'Not Started',
        Due_Date__c = c.day(12),
        Amount__c = 400000,
        Invoiced__c = false
      ),
      'ms.1c'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Ställning uppsatt',
        Project__c = c.ref('pj.2'),
        Status__c = 'Accepted',
        Due_Date__c = c.day(-30),
        Amount__c = 150000,
        Invoiced__c = true,
        Accepted_At__c = c.nowDt.addDays(-25),
        Accepted_By__c = c.ref('c.p1')
      ),
      'ms.2a'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Fasadmålning etapp 1',
        Project__c = c.ref('pj.2'),
        Status__c = 'In Progress',
        Due_Date__c = c.day(25),
        Amount__c = 350000,
        Invoiced__c = false
      ),
      'ms.2b'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Förstudie klar',
        Project__c = c.ref('pj.3'),
        Status__c = 'Completed',
        Due_Date__c = c.day(-2),
        Amount__c = 80000,
        Invoiced__c = false
      ),
      'ms.3a'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Upphandling klar',
        Project__c = c.ref('pj.3'),
        Status__c = 'Not Started',
        Due_Date__c = c.day(40),
        Amount__c = 120000,
        Invoiced__c = false
      ),
      'ms.3b'
    );
    c.save();

    // Tasks: late, blocked and in-review ones fill the home queue
    c.add(
      task(
        c,
        'pj.1',
        'rs.5',
        'Rivningsarbeten',
        'Done',
        100,
        -110,
        -12,
        160,
        'Medium',
        null
      ),
      't.1a'
    );
    c.add(
      task(
        c,
        'pj.1',
        'rs.2',
        'Stomkomplettering',
        'In Progress',
        55,
        -30,
        5,
        240,
        'High',
        'ms.1b'
      ),
      't.1b'
    );
    c.add(
      task(
        c,
        'pj.1',
        'rs.4',
        'El- och VVS-dragning',
        'Blocked',
        20,
        -15,
        -2,
        120,
        'High',
        null
      ),
      't.1c'
    );
    c.add(
      task(
        c,
        'pj.1',
        'rs.2',
        'Besiktning av byggnadsställning',
        'In Review',
        90,
        -20,
        -4,
        16,
        'Medium',
        null
      ),
      't.1d'
    );
    c.add(
      task(
        c,
        'pj.2',
        'rs.5',
        'Tvättning av fasad',
        'Done',
        100,
        -70,
        -45,
        80,
        'Medium',
        null
      ),
      't.2a'
    );
    c.add(
      task(
        c,
        'pj.2',
        'rs.2',
        'Spackling och grundmålning',
        'In Progress',
        40,
        -10,
        10,
        200,
        'High',
        'ms.2b'
      ),
      't.2b'
    );
    c.add(
      task(
        c,
        'pj.3',
        'rs.3',
        'Energikartläggning',
        'In Progress',
        70,
        -14,
        3,
        60,
        'Medium',
        null
      ),
      't.3a'
    );
    c.save();
    // Tasks that follow another one
    PMS_Project_Task__c t1e = task(
      c,
      'pj.1',
      'rs.5',
      'Ytskikt och målning',
      'Not Started',
      0,
      6,
      30,
      120,
      'Medium',
      'ms.1c'
    );
    t1e.Predecessor__c = c.ref('t.1b');
    c.add(t1e, 't.1e');
    PMS_Project_Task__c t1f = task(
      c,
      'pj.1',
      'rs.5',
      'Slutstädning',
      'Not Started',
      0,
      35,
      40,
      24,
      'Low',
      'ms.1c'
    );
    t1f.Predecessor__c = c.ref('t.1b');
    c.add(t1f, 't.1f');
    PMS_Project_Task__c t2c = task(
      c,
      'pj.2',
      'rs.2',
      'Målning etapp 1',
      'Not Started',
      0,
      11,
      24,
      160,
      'Medium',
      null
    );
    t2c.Predecessor__c = c.ref('t.2b');
    c.add(t2c, 't.2c');
    PMS_Project_Task__c t2d = task(
      c,
      'pj.2',
      'rs.1',
      'Kvalitetskontroll',
      'Not Started',
      0,
      26,
      28,
      12,
      'Medium',
      null
    );
    t2d.Predecessor__c = c.ref('t.2b');
    c.add(t2d, 't.2d');
    PMS_Project_Task__c t3b = task(
      c,
      'pj.3',
      'rs.3',
      'Rapport och rekommendationer',
      'Not Started',
      0,
      4,
      20,
      80,
      'Medium',
      null
    );
    t3b.Predecessor__c = c.ref('t.3a');
    c.add(t3b, 't.3b');
    PMS_Project_Task__c t3c = task(
      c,
      'pj.3',
      'rs.1',
      'Beslutsunderlag till styrelsen',
      'Not Started',
      0,
      21,
      30,
      24,
      'Low',
      null
    );
    t3c.Predecessor__c = c.ref('t.3a');
    c.add(t3c, 't.3c');
    c.save();

    // Time entries: eight weeks, this week still being submitted
    List<List<String>> combos = new List<List<String>>{
      new List<String>{ 'pj.1', 't.1b', 'rs.2' },
      new List<String>{ 'pj.2', 't.2b', 'rs.2' },
      new List<String>{ 'pj.3', 't.3a', 'rs.3' },
      new List<String>{ 'pj.1', 't.1c', 'rs.4' }
    };
    Map<String, Decimal> rates = new Map<String, Decimal>{
      'rs.1' => 1250,
      'rs.2' => 1100,
      'rs.3' => 1350,
      'rs.4' => 1050
    };
    for (Integer w = 0; w < 8; w++) {
      for (Integer k = 0; k < 3; k++) {
        List<String> combo = combos[Math.mod(w + k, combos.size())];
        String status = w == 0
          ? (k == 2 ? 'Draft' : 'Submitted')
          : (w == 1 ? 'Submitted' : (w >= 5 ? 'Invoiced' : 'Approved'));
        Integer back = w == 0 ? 0 : w * 7 + k;
        c.add(
          new PMS_Time_Entry__c(
            Project__c = c.ref(combo[0]),
            Project_Task__c = c.ref(combo[1]),
            Resource__c = c.ref(combo[2]),
            Entry_Date__c = c.day(-back),
            Hours__c = k == 0 ? 8.0 : (k == 1 ? 6.5 : 4.0),
            Billable__c = true,
            Rate__c = rates.get(combo[2]),
            Approval_Status__c = status,
            Description__c = 'Arbete enligt tidplan, vecka ' + (8 - w)
          ),
          'te.' + w + '.' + k
        );
      }
    }
    c.save();

    // RAID log
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.1'),
        RAID_Type__c = 'Risk',
        Severity__c = 'Critical',
        Status__c = 'Open',
        Description__c = 'Leveransen av stålbalkar försenas två veckor.',
        Mitigation__c = 'Beställ från alternativ leverantör och förskjut ytskikt.',
        Due_Date__c = c.day(7),
        Item_Owner__c = c.userId
      ),
      'rd.1'
    );
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.1'),
        RAID_Type__c = 'Issue',
        Severity__c = 'High',
        Status__c = 'Mitigating',
        Description__c = 'Fuktskada upptäckt i bjälklag plan 2.',
        Mitigation__c = 'Torkning pågår, ny kontroll om en vecka.',
        Due_Date__c = c.day(5),
        Item_Owner__c = c.userId
      ),
      'rd.2'
    );
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.2'),
        RAID_Type__c = 'Risk',
        Severity__c = 'High',
        Status__c = 'Open',
        Description__c = 'Boende klagar på buller under arbetstid.',
        Mitigation__c = 'Begränsa bullrande arbete till 08-16.',
        Due_Date__c = c.day(10),
        Item_Owner__c = c.userId
      ),
      'rd.3'
    );
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.2'),
        RAID_Type__c = 'Assumption',
        Severity__c = 'Low',
        Status__c = 'Open',
        Description__c = 'Ställningen får stå kvar till etapp 2.',
        Item_Owner__c = c.userId
      ),
      'rd.4'
    );
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.3'),
        RAID_Type__c = 'Decision',
        Severity__c = 'Medium',
        Status__c = 'Open',
        Description__c = 'Välj värmepump eller fjärrvärme.',
        Due_Date__c = c.day(21),
        Item_Owner__c = c.userId
      ),
      'rd.5'
    );
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.3'),
        RAID_Type__c = 'Risk',
        Severity__c = 'Medium',
        Status__c = 'Closed',
        Description__c = 'Tillståndet drar ut på tiden.',
        Item_Owner__c = c.userId
      ),
      'rd.6'
    );
    c.save();

    // Client approvals: two waiting, one past due, one draft
    c.add(
      new PMS_Approval_Request__c(
        Project__c = c.ref('pj.1'),
        Account__c = c.ref('a.p2'),
        Type__c = 'Change Order',
        Status__c = 'Pending',
        Title__c = 'Extra bjälklagsförstärkning',
        Details__c = 'Fuktskadan kräver förstärkning av bjälklaget på plan 2.',
        Amount__c = 185000,
        Schedule_Impact_Days__c = 6,
        Due_Date__c = c.day(5)
      ),
      'ar.1'
    );
    c.add(
      new PMS_Approval_Request__c(
        Project__c = c.ref('pj.1'),
        Account__c = c.ref('a.p2'),
        Type__c = 'Budget',
        Status__c = 'Pending',
        Title__c = 'Utökad budget för elinstallation',
        Details__c = 'Elarbetet blev större än kalkylerat.',
        Amount__c = 90000,
        Due_Date__c = c.day(-2)
      ),
      'ar.2'
    );
    c.add(
      new PMS_Approval_Request__c(
        Project__c = c.ref('pj.2'),
        Account__c = c.ref('a.p1'),
        Type__c = 'Design Choice',
        Status__c = 'Draft',
        Title__c = 'Val av fasadfärg',
        Details__c = 'Tre kulörer att välja mellan.',
        Due_Date__c = c.day(9)
      ),
      'ar.3'
    );
    c.save();
  }

  // ------------------------------------------------------------------ practice

  private static final Map<String, Decimal> SERVICE_PRICE = new Map<String, Decimal>{
    'sv.1' => 1100,
    'sv.2' => 950,
    'sv.3' => 750,
    'sv.4' => 1100,
    'sv.5' => 1400,
    'sv.6' => 600
  };

  /** One appointment. The caller may set more fields on the returned record. */
  public static PMS_Booking__c appt(
    PMS_DemoData.Ctx c,
    String key,
    String practitioner,
    String service,
    String client,
    Integer day,
    Integer hour,
    Integer minute,
    Integer minutes,
    String status,
    String mode,
    String channel,
    String matter
  ) {
    Datetime start = c.at(day, hour, minute);
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = c.rt(PMS_Booking__c.SObjectType, 'Appointment'),
      Site__c = c.ref('s.prac'),
      Practitioner__c = c.ref(practitioner),
      Service__c = c.ref(service),
      Account__c = c.ref('a.' + client),
      Primary_Contact__c = c.ref('c.' + client),
      Matter__c = matter == null ? null : c.ref(matter),
      Start__c = start,
      End__c = start.addMinutes(minutes),
      Status__c = status,
      Appointment_Mode__c = mode,
      Channel__c = channel,
      Adults__c = 1,
      Rate_Amount__c = SERVICE_PRICE.get(service),
      Total_Amount__c = SERVICE_PRICE.get(service)
    );
    c.add(b, key);
    return b;
  }

  public static void practice(PMS_DemoData.Ctx c) {
    Id site = c.ref('s.prac');
    c.add(
      new PMS_Practitioner__c(
        Name = 'Dr. Annika Berg',
        Site__c = site,
        Speciality__c = 'Allmänmedicin',
        Hourly_Rate__c = 1500,
        Licence_Number__c = 'SE-LK-48213',
        Working_Hours__c = '08:00-16:00',
        Active__c = true
      ),
      'pr.1'
    );
    c.add(
      new PMS_Practitioner__c(
        Name = 'Dr. Magnus Ekdahl',
        Site__c = site,
        Speciality__c = 'Allmänmedicin',
        Hourly_Rate__c = 1500,
        Licence_Number__c = 'SE-LK-51877',
        Working_Hours__c = '09:00-17:00',
        Active__c = true
      ),
      'pr.2'
    );
    c.add(
      new PMS_Practitioner__c(
        Name = 'Sara Wennberg',
        Site__c = site,
        Speciality__c = 'Fysioterapi',
        Hourly_Rate__c = 1100,
        Licence_Number__c = 'SE-LK-60244',
        Working_Hours__c = '08:00-16:00',
        Active__c = true
      ),
      'pr.3'
    );
    c.add(
      new PMS_Practitioner__c(
        Name = 'Johan Rydén',
        Site__c = site,
        Speciality__c = 'Psykologi',
        Hourly_Rate__c = 1300,
        Licence_Number__c = 'SE-LK-70512',
        Working_Hours__c = '10:00-18:00',
        Active__c = true
      ),
      'pr.4'
    );
    c.add(
      new PMS_Service__c(
        Name = 'Allmänt läkarbesök',
        Duration_Minutes__c = 30,
        Price__c = 1100,
        Tax_Rate__c = 0,
        Bookable_Online__c = true,
        Practice_Area__c = 'General Medicine',
        Description__c = 'Besök hos distriktsläkare.'
      ),
      'sv.1'
    );
    c.add(
      new PMS_Service__c(
        Name = 'Fysioterapi, första besök',
        Duration_Minutes__c = 60,
        Price__c = 950,
        Tax_Rate__c = 0,
        Bookable_Online__c = true,
        Practice_Area__c = 'Physiotherapy',
        Description__c = 'Bedömning och behandlingsplan.'
      ),
      'sv.2'
    );
    c.add(
      new PMS_Service__c(
        Name = 'Fysioterapi, återbesök',
        Duration_Minutes__c = 45,
        Price__c = 750,
        Tax_Rate__c = 0,
        Bookable_Online__c = true,
        Practice_Area__c = 'Physiotherapy',
        Description__c = 'Uppföljning och träning.'
      ),
      'sv.3'
    );
    c.add(
      new PMS_Service__c(
        Name = 'Samtalsterapi',
        Duration_Minutes__c = 50,
        Price__c = 1100,
        Tax_Rate__c = 0,
        Bookable_Online__c = true,
        Practice_Area__c = 'Therapy',
        Description__c = 'Enskilt samtal med psykolog.'
      ),
      'sv.4'
    );
    c.add(
      new PMS_Service__c(
        Name = 'Hälsokontroll',
        Duration_Minutes__c = 45,
        Price__c = 1400,
        Tax_Rate__c = 25,
        Bookable_Online__c = false,
        Practice_Area__c = 'General Medicine',
        Description__c = 'Företagshälsokontroll med provtagning.'
      ),
      'sv.5'
    );
    c.add(
      new PMS_Service__c(
        Name = 'Digitalt läkarbesök',
        Duration_Minutes__c = 20,
        Price__c = 600,
        Tax_Rate__c = 0,
        Bookable_Online__c = true,
        Practice_Area__c = 'General Medicine',
        Description__c = 'Videobesök för enklare ärenden.'
      ),
      'sv.6'
    );
    c.save();

    // Matters: two in intake, four open, one on hold, one closed
    c.add(
      matter(
        c,
        'Rehabilitering knä, M. Dahl',
        'c4',
        'Intake',
        'Not Started',
        'Physiotherapy',
        'Per Appointment',
        'pr.3',
        -3,
        0
      ),
      'mt.1'
    );
    c.add(
      matter(
        c,
        'Samtalsstöd, H. Forsman',
        'c5',
        'Intake',
        'In Progress',
        'Therapy',
        'Per Appointment',
        'pr.4',
        -5,
        0
      ),
      'mt.2'
    );
    c.add(
      matter(
        c,
        'Kroniskt ryggont, I. Axelsson',
        'c1',
        'Open',
        'Cleared',
        'Physiotherapy',
        'Insurance',
        'pr.3',
        -90,
        0
      ),
      'mt.3'
    );
    c.add(
      matter(
        c,
        'Hälsouppföljning, G. Holmberg',
        'c2',
        'Open',
        'Cleared',
        'General Medicine',
        'Per Appointment',
        'pr.1',
        -60,
        0
      ),
      'mt.4'
    );
    c.add(
      matter(
        c,
        'Stressrehabilitering, C. Ström',
        'c3',
        'Open',
        'Cleared',
        'Therapy',
        'Retainer',
        'pr.4',
        -45,
        4500
      ),
      'mt.5'
    );
    c.add(
      matter(
        c,
        'Axelskada, P. Åkesson',
        'c6',
        'Open',
        'Cleared',
        'Physiotherapy',
        'Insurance',
        'pr.3',
        -30,
        0
      ),
      'mt.6'
    );
    c.add(
      matter(
        c,
        'Diabetesuppföljning, I. Axelsson',
        'c1',
        'On Hold',
        'Not Required',
        'General Medicine',
        'Per Appointment',
        'pr.2',
        -120,
        0
      ),
      'mt.7'
    );
    PMS_Matter__c closed = matter(
      c,
      'Förkylning, G. Holmberg',
      'c2',
      'Closed',
      'Cleared',
      'General Medicine',
      'Per Appointment',
      'pr.2',
      -40,
      0
    );
    closed.Close_Date__c = c.day(-20);
    c.add(closed, 'mt.8');
    c.save();

    // Appointments today: two done, one no-show, two coming, one tentative
    appt(
      c,
      'bk.a.t1',
      'pr.1',
      'sv.1',
      'c2',
      0,
      8,
      0,
      30,
      'Completed',
      'In Person',
      'Direct',
      'mt.4'
    );
    appt(
      c,
      'bk.a.t2',
      'pr.3',
      'sv.2',
      'c1',
      0,
      9,
      0,
      60,
      'Completed',
      'In Person',
      'Direct',
      'mt.3'
    );
    appt(
      c,
      'bk.a.t3',
      'pr.4',
      'sv.4',
      'c3',
      0,
      10,
      30,
      50,
      'No Show',
      'In Person',
      'Phone',
      'mt.5'
    );
    appt(
      c,
      'bk.a.t4',
      'pr.1',
      'sv.5',
      'c4',
      0,
      13,
      0,
      45,
      'Confirmed',
      'In Person',
      'Website',
      null
    );
    appt(
      c,
      'bk.a.t5',
      'pr.3',
      'sv.3',
      'c6',
      0,
      14,
      30,
      45,
      'Confirmed',
      'In Person',
      'Direct',
      'mt.6'
    );
    appt(
      c,
      'bk.a.t6',
      'pr.2',
      'sv.1',
      'c5',
      0,
      15,
      30,
      30,
      'Tentative',
      'In Person',
      'Phone',
      null
    );
    // Next seven days
    PMS_Booking__c n1 = appt(
      c,
      'bk.a.n1',
      'pr.1',
      'sv.6',
      'c2',
      1,
      9,
      0,
      20,
      'Confirmed',
      'Video',
      'Website',
      null
    );
    n1.Guarantee__c = 'Card on File';
    n1.Guarantee_Status__c = 'Hold Placed';
    n1.Preauth_Status__c = 'Authorized';
    n1.Preauth_Amount__c = 600;
    n1.Preauth_Expires_At__c = c.nowDt.addHours(12);
    PMS_Booking__c n2 = appt(
      c,
      'bk.a.n2',
      'pr.3',
      'sv.3',
      'c1',
      1,
      11,
      0,
      45,
      'Tentative',
      'In Person',
      'Phone',
      'mt.3'
    );
    n2.Guarantee__c = 'Card on File';
    n2.Guarantee_Status__c = 'Awaiting Card';
    appt(
      c,
      'bk.a.n3',
      'pr.4',
      'sv.4',
      'c4',
      2,
      10,
      0,
      50,
      'Confirmed',
      'Video',
      'Website',
      'mt.1'
    );
    appt(
      c,
      'bk.a.n4',
      'pr.2',
      'sv.1',
      'c5',
      2,
      14,
      0,
      30,
      'Confirmed',
      'In Person',
      'Direct',
      'mt.2'
    );
    appt(
      c,
      'bk.a.n5',
      'pr.3',
      'sv.2',
      'c6',
      3,
      9,
      30,
      60,
      'Confirmed',
      'In Person',
      'Direct',
      'mt.6'
    );
    PMS_Booking__c n6 = appt(
      c,
      'bk.a.n6',
      'pr.1',
      'sv.5',
      'c3',
      4,
      13,
      0,
      45,
      'Tentative',
      'In Person',
      'Website',
      'mt.5'
    );
    n6.Guarantee__c = 'Card on File';
    n6.Guarantee_Status__c = 'Action Needed';
    n6.Guarantee_Message__c = 'Kortet har gått ut.';
    appt(
      c,
      'bk.a.n7',
      'pr.2',
      'sv.6',
      'c1',
      5,
      8,
      30,
      20,
      'Confirmed',
      'Phone',
      'Phone',
      null
    );
    appt(
      c,
      'bk.a.n8',
      'pr.4',
      'sv.4',
      'c2',
      6,
      15,
      0,
      50,
      'Confirmed',
      'Video',
      'Website',
      null
    );
    // Cancelled with a fee waiting, and cancelled with a refund due
    PMS_Booking__c nc1 = appt(
      c,
      'bk.a.c1',
      'pr.1',
      'sv.1',
      'c6',
      2,
      16,
      0,
      30,
      'Cancelled',
      'In Person',
      'Phone',
      null
    );
    nc1.Policy_Pending__c = true;
    nc1.Policy_Fee_Amount__c = 550;
    nc1.Policy_Event_At__c = c.nowDt.addHours(-4);
    PMS_Booking__c nc2 = appt(
      c,
      'bk.a.c2',
      'pr.3',
      'sv.2',
      'c3',
      8,
      10,
      0,
      60,
      'Cancelled',
      'In Person',
      'Website',
      null
    );
    nc2.Refund_Due__c = 950;
    nc2.Deposit_Amount__c = 950;
    // Last 30 days: eight attended, three no-shows
    appt(
      c,
      'bk.a.p1',
      'pr.1',
      'sv.1',
      'c1',
      -2,
      10,
      0,
      30,
      'Completed',
      'In Person',
      'Direct',
      'mt.3'
    );
    appt(
      c,
      'bk.a.p2',
      'pr.3',
      'sv.3',
      'c6',
      -4,
      11,
      0,
      45,
      'Completed',
      'In Person',
      'Direct',
      'mt.6'
    );
    appt(
      c,
      'bk.a.p3',
      'pr.2',
      'sv.1',
      'c5',
      -5,
      9,
      0,
      30,
      'Completed',
      'Phone',
      'Phone',
      null
    );
    appt(
      c,
      'bk.a.p4',
      'pr.4',
      'sv.4',
      'c3',
      -8,
      13,
      0,
      50,
      'Completed',
      'Video',
      'Website',
      'mt.5'
    );
    appt(
      c,
      'bk.a.p5',
      'pr.3',
      'sv.2',
      'c1',
      -10,
      9,
      0,
      60,
      'Completed',
      'In Person',
      'Direct',
      'mt.3'
    );
    appt(
      c,
      'bk.a.p6',
      'pr.1',
      'sv.5',
      'c2',
      -14,
      14,
      0,
      45,
      'Completed',
      'In Person',
      'Website',
      'mt.4'
    );
    appt(
      c,
      'bk.a.p7',
      'pr.2',
      'sv.6',
      'c4',
      -19,
      8,
      30,
      20,
      'Completed',
      'Video',
      'Website',
      null
    );
    appt(
      c,
      'bk.a.p8',
      'pr.3',
      'sv.3',
      'c6',
      -25,
      15,
      0,
      45,
      'Completed',
      'In Person',
      'Direct',
      'mt.6'
    );
    appt(
      c,
      'bk.a.s1',
      'pr.4',
      'sv.4',
      'c4',
      -3,
      16,
      0,
      50,
      'No Show',
      'In Person',
      'Phone',
      null
    );
    appt(
      c,
      'bk.a.s2',
      'pr.1',
      'sv.1',
      'c5',
      -6,
      11,
      30,
      30,
      'No Show',
      'In Person',
      'Direct',
      null
    );
    appt(
      c,
      'bk.a.s3',
      'pr.3',
      'sv.2',
      'c2',
      -12,
      10,
      0,
      60,
      'No Show',
      'In Person',
      'Direct',
      null
    );
    c.save();

    // Intake forms: four not signed, two signed
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.a.n3'),
        Contact__c = c.ref('c.c4'),
        Matter__c = c.ref('mt.1'),
        Form_Type__c = 'New Client Intake',
        Responses__c = '{"besvär":"Smärta i höger knä, 5/10","tidigare":"Ingen operation"}'
      ),
      'if.1'
    );
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.a.n2'),
        Contact__c = c.ref('c.c1'),
        Matter__c = c.ref('mt.3'),
        Form_Type__c = 'Health Questionnaire'
      ),
      'if.2'
    );
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.a.n6'),
        Contact__c = c.ref('c.c3'),
        Matter__c = c.ref('mt.5'),
        Form_Type__c = 'GDPR Consent'
      ),
      'if.3'
    );
    c.add(
      new PMS_Intake_Form__c(
        Contact__c = c.ref('c.c5'),
        Matter__c = c.ref('mt.2'),
        Form_Type__c = 'New Client Intake'
      ),
      'if.4'
    );
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.a.p1'),
        Contact__c = c.ref('c.c1'),
        Matter__c = c.ref('mt.3'),
        Form_Type__c = 'Engagement Letter',
        Consent_Given__c = true,
        Signed_Date__c = c.day(-5)
      ),
      'if.5'
    );
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.a.p2'),
        Contact__c = c.ref('c.c6'),
        Matter__c = c.ref('mt.6'),
        Form_Type__c = 'Treatment Consent',
        Consent_Given__c = true,
        Signed_Date__c = c.day(-7)
      ),
      'if.6'
    );
    c.save();

    // Documents to sign (opened or still a draft, so nothing is e-mailed)
    c.add(
      new PMS_Document_Request__c(
        Title__c = 'Engagemangsbrev: rehabilitering',
        Account__c = c.ref('a.c4'),
        Contact__c = c.ref('c.c4'),
        Booking__c = c.ref('bk.a.n3'),
        Requires_Signature__c = true,
        Status__c = 'Viewed',
        Viewed_At__c = c.nowDt.addHours(-5),
        Due_Date__c = c.day(2),
        Signer_Name__c = 'Mikael Dahl',
        Signer_Email__c = 'mikael.dahl@example.com'
      ),
      'doc.a1'
    );
    c.add(
      new PMS_Document_Request__c(
        Title__c = 'Samtycke till behandling',
        Account__c = c.ref('a.c1'),
        Contact__c = c.ref('c.c1'),
        Booking__c = c.ref('bk.a.n2'),
        Requires_Signature__c = true,
        Status__c = 'Draft',
        Due_Date__c = c.day(1),
        Signer_Name__c = 'Ingrid Axelsson'
      ),
      'doc.a2'
    );
    c.save();
  }

  private static PMS_Matter__c matter(
    PMS_DemoData.Ctx c,
    String name,
    String client,
    String status,
    String conflict,
    String area,
    String fee,
    String practitioner,
    Integer openedDay,
    Decimal retainer
  ) {
    return new PMS_Matter__c(
      Name = name,
      Account__c = c.ref('a.' + client),
      Primary_Contact__c = c.ref('c.' + client),
      Site__c = c.ref('s.prac'),
      Status__c = status,
      Conflict_Check_Status__c = conflict,
      Practice_Area__c = area,
      Fee_Arrangement__c = fee,
      Responsible_Practitioner__c = c.ref(practitioner),
      Open_Date__c = c.day(openedDay),
      Retainer_Balance__c = retainer
    );
  }

  // ------------------------------------------------------------------ service requests

  private static Case req(
    PMS_DemoData.Ctx c,
    String subject,
    String description,
    String priority,
    String status,
    String origin,
    String module,
    String site
  ) {
    return new Case(
      Subject = subject,
      Description = description,
      Priority = priority,
      Status = status,
      Origin = origin,
      PMS_Module__c = module,
      PMS_Site__c = c.ref(site)
    );
  }

  public static void service(PMS_DemoData.Ctx c) {
    // Hotel
    Case c1 = req(
      c,
      'Rum 105: luftkonditioneringen fungerar inte',
      'Gästen rapporterar att rummet är för varmt.',
      'High',
      'New',
      'Phone',
      'Hotel',
      's.hotel'
    );
    c1.PMS_Space__c = c.ref('r.105');
    c1.SLA_Due__c = c.nowDt.addHours(-3);
    c1.AccountId = c.ref('a.g6');
    c1.ContactId = c.ref('c.g6');
    c.add(c1, 'cs.1');
    Case c2 = req(
      c,
      'Extra kuddar till rum 201',
      'Företagsgästen ber om två extra kuddar.',
      'Medium',
      'New',
      'Phone',
      'Hotel',
      's.hotel'
    );
    c2.PMS_Space__c = c.ref('r.201');
    c2.PMS_Booking__c = c.ref('bk.h3');
    c2.AccountId = c.ref('a.g3');
    c2.ContactId = c.ref('c.g3');
    c2.SLA_Due__c = c.nowDt.addHours(4);
    c.add(c2, 'cs.2');
    Case c3 = req(
      c,
      'Fråga om sen utcheckning',
      'Gästen undrar om utcheckning kan ske klockan 14.',
      'Low',
      'Working',
      'Email',
      'Hotel',
      's.hotel'
    );
    c3.PMS_Booking__c = c.ref('bk.h2');
    c3.AccountId = c.ref('a.g2');
    c3.ContactId = c.ref('c.g2');
    c.add(c3, 'cs.3');
    // Property
    Case c4 = req(
      c,
      'Vattenläcka i badrum A-104',
      'Hyresgästen ser vatten under tvättstället.',
      'High',
      'New',
      'Phone',
      'Property',
      's.prop'
    );
    c4.PMS_Space__c = c.ref('u.A-104');
    c4.Entry_Permission__c = true;
    c4.AccountId = c.ref('a.t4');
    c4.ContactId = c.ref('c.t4');
    c4.SLA_Due__c = c.nowDt.addHours(-1);
    c.add(c4, 'cs.4');
    Case c5 = req(
      c,
      'Trasigt ytterdörrslås A-102',
      'Låset kärvar och går inte att låsa efter 18.',
      'Medium',
      'Working',
      'Email',
      'Property',
      's.prop'
    );
    c5.PMS_Space__c = c.ref('u.A-102');
    c5.AccountId = c.ref('a.t2');
    c5.ContactId = c.ref('c.t2');
    c.add(c5, 'cs.5');
    Case c6 = req(
      c,
      'Önskemål om extra parkeringsplats',
      'Hyresgästen vill hyra en plats till i garaget.',
      'Low',
      'New',
      'Email',
      'Property',
      's.prop'
    );
    c6.AccountId = c.ref('a.t3');
    c6.ContactId = c.ref('c.t3');
    c.add(c6, 'cs.6');
    // Practice and projects
    Case c7 = req(
      c,
      'Fråga om faktura från I. Axelsson',
      'Patienten undrar över högkostnadsskyddet på fakturan.',
      'Medium',
      'New',
      'Email',
      'Practice',
      's.prac'
    );
    c7.AccountId = c.ref('a.c1');
    c7.ContactId = c.ref('c.c1');
    c.add(c7, 'cs.7');
    Case c8 = req(
      c,
      'Grannar klagar på buller under rivning',
      'Styrelsen i Tallen vill ha en bullerplan.',
      'Medium',
      'Escalated',
      'Phone',
      'Project',
      's.proj'
    );
    c8.AccountId = c.ref('a.p2');
    c8.ContactId = c.ref('c.p2');
    c8.SLA_Due__c = c.nowDt.addHours(24);
    c.add(c8, 'cs.8');
    // A closed one, which the home pages leave out
    Case c9 = req(
      c,
      'Nyckelbyte genomfört i A-103',
      'Nytt lås monterat och nycklar utlämnade.',
      'Low',
      'Closed',
      'Email',
      'Property',
      's.prop'
    );
    c9.AccountId = c.ref('a.t3');
    c.add(c9, 'cs.9');
    c.save();
  }

  // ------------------------------------------------------------------ work orders, vendors, check-ins

  private static PMS_Work_Order__c workOrder(
    PMS_DemoData.Ctx c,
    String site,
    String space,
    String subject,
    String priority,
    String status,
    String vendor,
    Integer scheduledDay
  ) {
    return new PMS_Work_Order__c(
      Site__c = c.ref(site),
      Space__c = space == null ? null : c.ref(space),
      Subject__c = subject,
      Priority__c = priority,
      Status__c = status,
      Vendor_Account__c = vendor == null ? null : c.ref(vendor),
      Scheduled_Date__c = scheduledDay == null ? null : c.day(scheduledDay),
      Description__c = subject + '. Skapad som demodata.'
    );
  }

  public static void ops(PMS_DemoData.Ctx c) {
    PMS_Work_Order__c w1 = workOrder(
      c,
      's.prop',
      'u.A-104',
      'Vattenläcka i badrum A-104',
      'Urgent',
      'New',
      null,
      1
    );
    w1.Case__c = c.ref('cs.4');
    w1.Entry_Permission__c = true;
    c.add(w1, 'wo.1');
    c.add(
      workOrder(
        c,
        's.prop',
        'u.A-102',
        'Byte av element A-102',
        'High',
        'Assigned',
        'a.v1',
        3
      ),
      'wo.2'
    );
    c.add(
      workOrder(
        c,
        's.prop',
        null,
        'Ny elcentral i källare',
        'Medium',
        'Quote Requested',
        'a.v2',
        null
      ),
      'wo.3'
    );
    c.add(
      workOrder(
        c,
        's.prop',
        'u.A-108',
        'Renovering kök A-108',
        'Medium',
        'Quoted',
        'a.v1',
        null
      ),
      'wo.4'
    );
    c.add(
      workOrder(
        c,
        's.prop',
        null,
        'Målning av trapphus',
        'Medium',
        'In Progress',
        'a.v3',
        6
      ),
      'wo.5'
    );
    PMS_Work_Order__c w6 = workOrder(
      c,
      's.prop',
      null,
      'Planering av hissbyte',
      'Low',
      'Approved',
      'a.v4',
      20
    );
    w6.Not_To_Exceed__c = 180000;
    c.add(w6, 'wo.6');
    c.add(
      workOrder(
        c,
        's.prop',
        'u.A-103',
        'Byte av fönster A-103',
        'Medium',
        'Completed',
        'a.v1',
        -6
      ),
      'wo.7'
    );
    c.add(
      workOrder(
        c,
        's.prop',
        null,
        'Byte av lysrör i garaget',
        'Low',
        'Closed',
        'a.v2',
        -20
      ),
      'wo.8'
    );
    c.add(
      workOrder(
        c,
        's.hotel',
        'r.204',
        'Luftkonditionering rum 204',
        'High',
        'New',
        null,
        2
      ),
      'wo.9'
    );
    c.add(
      workOrder(
        c,
        's.hotel',
        'r.105',
        'Byta madrass rum 105',
        'Medium',
        'Assigned',
        'a.v3',
        2
      ),
      'wo.10'
    );
    c.save();

    c.add(
      new PMS_Vendor_Quote__c(
        Work_Order__c = c.ref('wo.3'),
        Vendor_Account__c = c.ref('a.v2'),
        Status__c = 'Submitted',
        Amount__c = 84000,
        Tax_Amount__c = 21000,
        Valid_Until__c = c.day(14),
        Description__c = 'Ny huvudcentral med jordfelsbrytare.'
      ),
      'vq.1'
    );
    c.add(
      new PMS_Vendor_Quote__c(
        Work_Order__c = c.ref('wo.4'),
        Vendor_Account__c = c.ref('a.v1'),
        Status__c = 'Submitted',
        Amount__c = 215000,
        Tax_Amount__c = 53750,
        Valid_Until__c = c.day(-2),
        Description__c = 'Nytt kök inklusive vitvaror och rör.'
      ),
      'vq.2'
    );
    c.add(
      new PMS_Vendor_Quote__c(
        Work_Order__c = c.ref('wo.4'),
        Vendor_Account__c = c.ref('a.v3'),
        Status__c = 'Withdrawn',
        Amount__c = 240000,
        Tax_Amount__c = 60000,
        Valid_Until__c = c.day(10),
        Description__c = 'Alternativ offert, återkallad av leverantören.'
      ),
      'vq.3'
    );
    c.save();

    PMS_Vendor_Bill__c b1 = bill(
      c,
      's.prop',
      'wo.5',
      'a.v3',
      'RF-2026-0412',
      'Submitted',
      18500,
      4625,
      -4,
      10
    );
    c.add(b1, 'vb.1');
    c.add(
      bill(
        c,
        's.prop',
        'wo.7',
        'a.v1',
        'RV-7781',
        'Submitted',
        9600,
        2400,
        -26,
        -12
      ),
      'vb.2'
    );
    c.add(
      bill(
        c,
        's.prop',
        'wo.2',
        'a.v1',
        'RV-7802',
        'Approved',
        5200,
        1300,
        -6,
        5
      ),
      'vb.3'
    );
    PMS_Vendor_Bill__c paid = bill(
      c,
      's.prop',
      'wo.8',
      'a.v2',
      'EV-1190',
      'Paid',
      2100,
      525,
      -30,
      -10
    );
    paid.Paid_Date__c = c.day(-3);
    c.add(paid, 'vb.4');
    c.add(
      bill(
        c,
        's.hotel',
        'wo.10',
        'a.v3',
        'RF-2026-0433',
        'Submitted',
        1900,
        475,
        -1,
        8
      ),
      'vb.5'
    );
    c.save();

    // Online check-ins: hotel arrivals, a tenant move-in and clinic questionnaires
    c.add(
      checkIn(
        c,
        'bk.h8',
        'g6',
        'Karin Eriksson',
        'Hotel Stay',
        2,
        '16:30',
        c.nowDt.addHours(-3),
        'Email Link'
      ),
      'ci.h8'
    );
    c.add(
      checkIn(
        c,
        'bk.h7',
        'g7',
        'Johan Larsson',
        'Hotel Stay',
        2,
        '18:00',
        c.nowDt.addHours(-20),
        'Customer Portal'
      ),
      'ci.h7'
    );
    c.add(
      checkIn(
        c,
        'bk.u1',
        'g2',
        'Maria Johansson',
        'Hotel Stay',
        1,
        '15:00',
        c.nowDt.addHours(-1),
        'Email Link'
      ),
      'ci.u1'
    );
    PMS_Check_In__c move = checkIn(
      c,
      'bk.l6',
      't6',
      'Fredrik Lund',
      'Move-In',
      1,
      null,
      c.nowDt.addHours(-8),
      'Customer Portal'
    );
    move.Move_In_Date__c = c.day(4);
    move.Occupants__c = 1;
    move.Vehicle_Registration__c = 'ABC123';
    c.add(move, 'ci.l6');
    PMS_Check_In__c q1 = checkIn(
      c,
      'bk.a.n3',
      'c4',
      'Mikael Dahl',
      null,
      1,
      null,
      c.nowDt.addHours(-2),
      'Email Link'
    );
    q1.Special_Requests__c = 'Har ont i knät sedan två månader. Tar inga mediciner.';
    c.add(q1, 'ci.a1');
    PMS_Check_In__c q2 = checkIn(
      c,
      'bk.a.n2',
      'c1',
      'Ingrid Axelsson',
      null,
      1,
      null,
      c.nowDt.addHours(-30),
      'Customer Portal'
    );
    q2.Special_Requests__c = 'Behöver tillgänglig lokal.';
    c.add(q2, 'ci.a2');
    c.add(
      checkIn(
        c,
        'bk.a.n6',
        'c3',
        'Cecilia Ström',
        null,
        1,
        null,
        c.nowDt.addDays(-3),
        'Email Link'
      ),
      'ci.a3'
    );
    c.save();
  }

  private static PMS_Vendor_Bill__c bill(
    PMS_DemoData.Ctx c,
    String site,
    String wo,
    String vendor,
    String invoiceNo,
    String status,
    Decimal amount,
    Decimal tax,
    Integer billDay,
    Integer dueDay
  ) {
    return new PMS_Vendor_Bill__c(
      Site__c = c.ref(site),
      Work_Order__c = c.ref(wo),
      Vendor_Account__c = c.ref(vendor),
      Vendor_Invoice_Number__c = invoiceNo,
      Status__c = status,
      Amount__c = amount,
      Tax_Amount__c = tax,
      Bill_Date__c = c.day(billDay),
      Due_Date__c = c.day(dueDay),
      Notes__c = 'Faktura enligt arbetsorder.'
    );
  }

  private static PMS_Check_In__c checkIn(
    PMS_DemoData.Ctx c,
    String booking,
    String who,
    String fullName,
    String type,
    Integer guests,
    String arrival,
    Datetime submitted,
    String via
  ) {
    return new PMS_Check_In__c(
      Booking__c = c.ref(booking),
      Account__c = c.ref('a.' + who),
      Full_Name__c = fullName,
      Type__c = type,
      Guests__c = guests,
      Arrival_Time__c = arrival,
      Nationality__c = 'Svensk',
      Submitted_At__c = submitted,
      Submitted_Via__c = via,
      Terms_Accepted__c = true
    );
  }

  // ------------------------------------------------------------------ channel manager

  public static void channels(PMS_DemoData.Ctx c) {
    Id site = c.ref('s.hotel');
    for (String plan : new List<String>{ 'rp.bar', 'rp.nrf' }) {
      for (String type : new List<String>{ 'st.std', 'st.sup', 'st.fam' }) {
        c.add(
          new PMS_Channel_Mapping__c(
            Name = (plan == 'rp.bar' ? 'BAR' : 'NRF') +
              ' ' +
              type.substringAfter('.'),
            Site__c = site,
            Room_Type__c = c.ref(type),
            Rate_Plan__c = c.ref(plan),
            Channex_Rate_Plan_Id__c = 'demo-' +
              plan.substringAfter('.') +
              '-' +
              type.substringAfter('.'),
            Active__c = true
          ),
          'cm.' + plan + '.' + type
        );
      }
    }
    c.save();

    c.add(
      log(
        c,
        'Outbound',
        'Availability',
        'Success',
        'Tillgänglighet för 30 dagar skickad.',
        null
      ),
      'cl.1'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Rates',
        'Success',
        'Priser för 30 dagar skickade.',
        null
      ),
      'cl.2'
    );
    c.add(
      log(
        c,
        'Inbound',
        'Booking New',
        'Success',
        'Ny bokning från Booking.com mottagen.',
        'bk.o2'
      ),
      'cl.3'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Acknowledge',
        'Success',
        'Bokningsrevision bekräftad.',
        'bk.o2'
      ),
      'cl.4'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Availability',
        'Success',
        'Tillgänglighet uppdaterad efter ny bokning.',
        null
      ),
      'cl.5'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Stop Sell',
        'Success',
        'Stoppförsäljning för rum 204 skickad.',
        null
      ),
      'cl.6'
    );
    c.add(
      log(
        c,
        'Inbound',
        'Booking Modified',
        'Success',
        'Ändrad bokning från Expedia mottagen.',
        'bk.o2'
      ),
      'cl.7'
    );
    c.add(
      log(c, 'Outbound', 'Rates', 'Success', 'Helgpriser uppdaterade.', null),
      'cl.8'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Rates',
        'Warning',
        'Pris under minimipris, justerat till 900 SEK.',
        null
      ),
      'cl.9'
    );
    c.add(
      log(
        c,
        'Inbound',
        'Booking New',
        'Warning',
        'Bokning utan rumstyp, placerad på Standard dubbelrum.',
        'bk.o1'
      ),
      'cl.10'
    );
    c.add(
      log(
        c,
        'Inbound',
        'Booking New',
        'Error',
        'Bokning BDC-4821937650 kunde inte tilldelas rum: fullbelagt.',
        'bk.o1'
      ),
      'cl.11'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Availability',
        'Error',
        'Channex svarade 429: för många anrop. Försöker igen senare.',
        null
      ),
      'cl.12'
    );
    c.add(
      log(
        c,
        'Outbound',
        'Rates',
        'Error',
        'Channex svarade 422: okänd prisplan i kopplingen.',
        null
      ),
      'cl.13'
    );
    c.save();
  }

  /** One channel log row. Also used by the channel-incident pack. */
  public static PMS_Channel_Log__c log(
    PMS_DemoData.Ctx c,
    String direction,
    String kind,
    String status,
    String message,
    String booking
  ) {
    return new PMS_Channel_Log__c(
      Site__c = c.ref('s.hotel'),
      Direction__c = direction,
      Kind__c = kind,
      Status__c = status,
      Message__c = message,
      Booking__c = booking == null ? null : c.ref(booking),
      Revision_Id__c = 'demo-' +
        String.valueOf(Math.abs(message.hashCode())).left(8),
      Details__c = '{"demo":true,"message":"' + message.replace('"', '') + '"}'
    );
  }
}
