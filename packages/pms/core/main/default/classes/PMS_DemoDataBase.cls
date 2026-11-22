/**
 * Demo data steps: people, policies and sites (core), the hotel and the rental building (property).
 * Called by PMS_DemoData, one step per transaction. See PMS_DemoData for how packs are run and tracked.
 */
public with sharing class PMS_DemoDataBase {
  // ------------------------------------------------------------------ core: people, policies, sites

  public static void core(PMS_DemoData.Ctx c) {
    // Hotel guests
    c.account(
      'a.g1',
      'Familjen Lindqvist',
      'Consumer',
      'Guest',
      'Sveavägen 41',
      'Stockholm',
      '111 34'
    );
    c.account(
      'a.g2',
      'Maria Johansson',
      'Consumer',
      'Guest',
      'Storgatan 8',
      'Uppsala',
      '753 31'
    );
    c.account(
      'a.g3',
      'Nordic Consulting Group AB',
      'Business',
      'Corporate Client;Guest',
      'Kungsgatan 12',
      'Göteborg',
      '411 19'
    );
    c.account(
      'a.g4',
      'Sofia Andersson',
      'Consumer',
      'Guest',
      'Östra Hamngatan 20',
      'Göteborg',
      '411 09'
    );
    c.account(
      'a.g5',
      'Henrik Nilsson',
      'Consumer',
      'Guest',
      'Drottninggatan 5',
      'Örebro',
      '702 10'
    );
    c.account(
      'a.g6',
      'Karin Eriksson',
      'Consumer',
      'Guest',
      'Hamngatan 3',
      'Linköping',
      '582 18'
    );
    c.account(
      'a.g7',
      'Johan Larsson',
      'Consumer',
      'Guest',
      'Kyrkogatan 14',
      'Västerås',
      '722 12'
    );
    c.account(
      'a.g8',
      'Resebyrån Svea Resor AB',
      'Business',
      'Travel Agent',
      'Vasagatan 16',
      'Stockholm',
      '111 20'
    );
    // Tenants, applicants and the building owner
    c.account(
      'a.t1',
      'Anna Svensson',
      'Consumer',
      'Tenant',
      'Hantverkargatan 20',
      'Stockholm',
      '112 21'
    );
    c.account(
      'a.t2',
      'Nordic Design AB',
      'Business',
      'Tenant',
      'Hantverkargatan 20',
      'Stockholm',
      '112 21'
    );
    c.account(
      'a.t3',
      'Oskar Persson',
      'Consumer',
      'Tenant',
      'Hantverkargatan 20',
      'Stockholm',
      '112 21'
    );
    c.account(
      'a.t4',
      'Elin Gustafsson',
      'Consumer',
      'Tenant',
      'Hantverkargatan 20',
      'Stockholm',
      '112 21'
    );
    c.account(
      'a.t5',
      'Café Vasa AB',
      'Business',
      'Tenant',
      'Hantverkargatan 20',
      'Stockholm',
      '112 21'
    );
    c.account(
      'a.t6',
      'Fredrik Lund',
      'Consumer',
      'Tenant',
      'Tulegatan 9',
      'Stockholm',
      '113 53'
    );
    c.account(
      'a.t7',
      'Jonas Bergström',
      'Consumer',
      'Tenant',
      'Rörstrandsgatan 30',
      'Stockholm',
      '113 40'
    );
    c.account(
      'a.apps',
      'Bostadssökande (demo)',
      'Consumer',
      'Tenant',
      'Fleminggatan 18',
      'Stockholm',
      '112 26'
    );
    c.account(
      'a.owner',
      'Kungsholmen Fastigheter KB',
      'Business',
      'Owner',
      'Fridhemsgatan 33',
      'Stockholm',
      '112 40'
    );
    // Vendors
    c.account(
      'a.v1',
      'Rör & Värme Stockholm AB',
      'Business',
      'Vendor',
      'Industrivägen 7',
      'Solna',
      '171 48'
    );
    c.account(
      'a.v2',
      'Elfirman Volt AB',
      'Business',
      'Vendor',
      'Elektrikervägen 3',
      'Sundbyberg',
      '172 67'
    );
    c.account(
      'a.v3',
      'Städbolaget Rent & Fint AB',
      'Business',
      'Vendor',
      'Städargränd 2',
      'Stockholm',
      '120 54'
    );
    c.account(
      'a.v4',
      'Hissmontage Norr AB',
      'Business',
      'Vendor',
      'Hissvägen 11',
      'Upplands Väsby',
      '194 61'
    );
    // Project clients
    c.account(
      'a.p1',
      'Brf Solgläntan',
      'Business',
      'Project Client',
      'Solgläntevägen 4',
      'Nacka',
      '131 54'
    );
    c.account(
      'a.p2',
      'Tallen Fastigheter AB',
      'Business',
      'Project Client',
      'Tallvägen 12',
      'Täby',
      '183 50'
    );
    // Practice clients
    c.account(
      'a.c1',
      'Ingrid Axelsson',
      'Consumer',
      'Practice Client',
      'Vasagatan 40',
      'Stockholm',
      '111 20'
    );
    c.account(
      'a.c2',
      'Gustav Holmberg',
      'Consumer',
      'Practice Client',
      'Odengatan 62',
      'Stockholm',
      '113 22'
    );
    c.account(
      'a.c3',
      'Cecilia Ström',
      'Consumer',
      'Practice Client',
      'Torsgatan 25',
      'Stockholm',
      '111 23'
    );
    c.account(
      'a.c4',
      'Mikael Dahl',
      'Consumer',
      'Practice Client',
      'Rörstrandsgatan 12',
      'Stockholm',
      '113 40'
    );
    c.account(
      'a.c5',
      'Helena Forsman',
      'Consumer',
      'Practice Client',
      'Sankt Eriksgatan 77',
      'Stockholm',
      '112 33'
    );
    c.account(
      'a.c6',
      'Peter Åkesson',
      'Consumer',
      'Practice Client',
      'Dalagatan 15',
      'Stockholm',
      '113 24'
    );
    c.save();

    c.person('c.g1', 'a.g1', 'Erik', 'Lindqvist');
    c.person('c.g2', 'a.g2', 'Maria', 'Johansson');
    c.person('c.g3', 'a.g3', 'Anders', 'Karlsson');
    c.person('c.g4', 'a.g4', 'Sofia', 'Andersson');
    c.person('c.g5', 'a.g5', 'Henrik', 'Nilsson');
    c.person('c.g6', 'a.g6', 'Karin', 'Eriksson');
    c.person('c.g7', 'a.g7', 'Johan', 'Larsson');
    c.person('c.g8', 'a.g8', 'Lena', 'Olsson');
    c.person('c.t1', 'a.t1', 'Anna', 'Svensson');
    c.person('c.t2', 'a.t2', 'Petra', 'Holm');
    c.person('c.t3', 'a.t3', 'Oskar', 'Persson');
    c.person('c.t4', 'a.t4', 'Elin', 'Gustafsson');
    c.person('c.t5', 'a.t5', 'Mats', 'Berglund');
    c.person('c.t6', 'a.t6', 'Fredrik', 'Lund');
    c.person('c.t7', 'a.t7', 'Jonas', 'Bergström');
    c.person('c.ap1', 'a.apps', 'Emma', 'Forsberg');
    c.person('c.ap2', 'a.apps', 'Viktor', 'Sjöberg');
    c.person('c.ap3', 'a.apps', 'Linnea', 'Wallin');
    c.person('c.p1', 'a.p1', 'Lars', 'Wikström');
    c.person('c.p2', 'a.p2', 'Åsa', 'Lindgren');
    c.person('c.c1', 'a.c1', 'Ingrid', 'Axelsson');
    c.person('c.c2', 'a.c2', 'Gustav', 'Holmberg');
    c.person('c.c3', 'a.c3', 'Cecilia', 'Ström');
    c.person('c.c4', 'a.c4', 'Mikael', 'Dahl');
    c.person('c.c5', 'a.c5', 'Helena', 'Forsman');
    c.person('c.c6', 'a.c6', 'Peter', 'Åkesson');
    c.save();

    // Policies
    c.add(
      new PMS_Payment_Policy__c(
        Name = 'Demo - Flexibel avbokning',
        Active__c = true,
        Guarantee_Method__c = 'Card on File',
        Deposit_Basis__c = 'None',
        Free_Cancellation_Hours__c = 48,
        Late_Cancel_Basis__c = 'First Night',
        No_Show_Basis__c = 'Full Stay',
        Fee_Tax_Rate__c = 12,
        Preauth_Hours_Before__c = 24,
        Auto_Send_Card_Link__c = false,
        Auto_Charge_Fees__c = false,
        Release_Hold_On_Checkout__c = true,
        Guest_Terms__c = 'Gratis avbokning till 48 timmar före ankomst. Därefter debiteras första natten. Vid utebliven ankomst debiteras hela vistelsen.'
      ),
      'pp.std'
    );
    c.add(
      new PMS_Payment_Policy__c(
        Name = 'Demo - Förskottsbetalning',
        Active__c = true,
        Guarantee_Method__c = 'Deposit',
        Deposit_Basis__c = 'Percent of Total',
        Deposit_Value__c = 30,
        Deposit_Due_Days__c = 3,
        Late_Cancel_Basis__c = 'Percent of Total',
        Late_Cancel_Value__c = 50,
        No_Show_Basis__c = 'Full Stay',
        Fee_Tax_Rate__c = 12,
        Auto_Send_Card_Link__c = false,
        Auto_Charge_Fees__c = false,
        Guest_Terms__c = '30 procent betalas som förskott inom tre dagar. Vid sen avbokning debiteras 50 procent.'
      ),
      'pp.dep'
    );
    c.add(
      new PMS_Dunning_Policy__c(
        Name = 'Demo - Standard påminnelser',
        Active__c = true,
        Is_Default__c = false,
        Reminder_1_Days__c = 10,
        Reminder_2_Days__c = 20,
        Plan_Offer_Days__c = 30,
        Plan_Instalments__c = 3,
        Plan_Grace_Days__c = 5,
        Collections_Days__c = 60,
        Min_Days_Between__c = 7,
        Minimum_Balance__c = 100,
        Consumer_Reminder_Fee__c = 60,
        Business_Late_Fee__c = 450,
        Fee_In_Terms__c = true,
        Charge_Interest__c = true,
        Reference_Rate__c = 2,
        Interest_Margin__c = 8,
        Sender_Name__c = 'PMS Ekonomi',
        Collections_Agency_Email__c = 'inkasso@example.com',
        Payment_Instructions__c = 'Betala till bankgiro 123-4567 och ange fakturanummer som referens.'
      ),
      'dp.std'
    );
    c.save();

    // Sites
    c.add(
      new PMS_Site__c(
        Name = 'Hotell Strandviken',
        RecordTypeId = c.rt(PMS_Site__c.SObjectType, 'Hotel'),
        Module__c = 'Hotel',
        Site_Type__c = 'Hotel',
        Status__c = 'Active',
        Street__c = 'Strandvägen 12',
        Postal_Code__c = '114 56',
        City__c = 'Stockholm',
        Country__c = 'Sweden',
        Phone__c = '+46 8 555 010 10',
        Currency_Code__c = 'SEK',
        Time_Zone__c = 'Europe/Stockholm',
        Check_In_Time__c = Time.newInstance(15, 0, 0, 0),
        Check_Out_Time__c = Time.newInstance(11, 0, 0, 0),
        Payment_Policy__c = c.ref('pp.std'),
        Dunning_Policy__c = c.ref('dp.std')
      ),
      's.hotel'
    );
    c.add(
      new PMS_Site__c(
        Name = 'Kungsholmen Bostäder',
        RecordTypeId = c.rt(PMS_Site__c.SObjectType, 'Property'),
        Module__c = 'Property',
        Site_Type__c = 'Residential Building',
        Status__c = 'Active',
        Street__c = 'Hantverkargatan 20',
        Postal_Code__c = '112 21',
        City__c = 'Stockholm',
        Country__c = 'Sweden',
        Phone__c = '+46 8 555 020 20',
        Currency_Code__c = 'SEK',
        Time_Zone__c = 'Europe/Stockholm',
        Owner_Account__c = c.ref('a.owner'),
        Management_Fee_Percent__c = 6,
        Payment_Policy__c = c.ref('pp.dep'),
        Dunning_Policy__c = c.ref('dp.std')
      ),
      's.prop'
    );
    c.add(
      new PMS_Site__c(
        Name = 'Projektkontor Hammarby Sjöstad',
        RecordTypeId = c.rt(PMS_Site__c.SObjectType, 'Project_Location'),
        Module__c = 'Project',
        Site_Type__c = 'Project Location',
        Status__c = 'Active',
        Street__c = 'Hammarby Allé 45',
        Postal_Code__c = '120 61',
        City__c = 'Stockholm',
        Country__c = 'Sweden',
        Currency_Code__c = 'SEK',
        Time_Zone__c = 'Europe/Stockholm',
        Dunning_Policy__c = c.ref('dp.std')
      ),
      's.proj'
    );
    c.add(
      new PMS_Site__c(
        Name = 'Vasastans Vårdcentral',
        RecordTypeId = c.rt(PMS_Site__c.SObjectType, 'Practice_Branch'),
        Module__c = 'Practice',
        Site_Type__c = 'Clinic',
        Status__c = 'Active',
        Street__c = 'Sankt Eriksgatan 63',
        Postal_Code__c = '112 34',
        City__c = 'Stockholm',
        Country__c = 'Sweden',
        Phone__c = '+46 8 555 030 30',
        Currency_Code__c = 'SEK',
        Time_Zone__c = 'Europe/Stockholm',
        Dunning_Policy__c = c.ref('dp.std')
      ),
      's.prac'
    );
    c.save();
  }

  // ------------------------------------------------------------------ hotel

  private static final List<List<String>> ROOM_SPEC = new List<List<String>>{
    // name, type key, status, floor, max occupancy, amenities
    new List<String>{
      '101',
      'st.std',
      'Occupied',
      '1',
      '2',
      'WiFi;Air Conditioning'
    },
    new List<String>{
      '102',
      'st.std',
      'Occupied',
      '1',
      '2',
      'WiFi;Air Conditioning'
    },
    new List<String>{ '103', 'st.std', 'Occupied', '1', '2', 'WiFi' },
    new List<String>{
      '104',
      'st.std',
      'Occupied',
      '1',
      '2',
      'WiFi;Accessible'
    },
    new List<String>{
      '105',
      'st.std',
      'Dirty',
      '1',
      '2',
      'WiFi;Air Conditioning'
    },
    new List<String>{
      '106',
      'st.std',
      'Occupied',
      '1',
      '2',
      'WiFi;Pet Friendly'
    },
    new List<String>{
      '201',
      'st.sup',
      'Occupied',
      '2',
      '2',
      'WiFi;Balcony;Air Conditioning'
    },
    new List<String>{
      '202',
      'st.sup',
      'Inspected',
      '2',
      '2',
      'WiFi;Balcony;Sea View'
    },
    new List<String>{
      '203',
      'st.sup',
      'Inspected',
      '2',
      '2',
      'WiFi;Sea View;Air Conditioning'
    },
    new List<String>{
      '204',
      'st.sup',
      'Out of Order',
      '2',
      '2',
      'WiFi;Balcony'
    },
    new List<String>{
      '301',
      'st.fam',
      'Dirty',
      '3',
      '4',
      'WiFi;Kitchen;Air Conditioning'
    },
    new List<String>{
      '302',
      'st.fam',
      'Available',
      '3',
      '4',
      'WiFi;Kitchen;Balcony'
    }
  };

  /** Room name to room type key, so bookings can name the room type they were sold as. */
  private static Map<String, String> typeOfRoom() {
    Map<String, String> m = new Map<String, String>();
    for (List<String> r : ROOM_SPEC) {
      m.put(r[0], r[1]);
    }
    return m;
  }

  public static void hotel(PMS_DemoData.Ctx c) {
    Id site = c.ref('s.hotel');
    c.add(
      new PMS_Space_Type__c(
        Name = 'Standard dubbelrum',
        Site__c = site,
        Default_Rate__c = 1290,
        Default_Occupancy__c = 2,
        Description__c = 'Dubbelrum med dubbelsäng, 22 kvm.'
      ),
      'st.std'
    );
    c.add(
      new PMS_Space_Type__c(
        Name = 'Superior dubbelrum',
        Site__c = site,
        Default_Rate__c = 1690,
        Default_Occupancy__c = 2,
        Description__c = 'Större dubbelrum med balkong eller sjöutsikt, 30 kvm.'
      ),
      'st.sup'
    );
    c.add(
      new PMS_Space_Type__c(
        Name = 'Familjerum',
        Site__c = site,
        Default_Rate__c = 2190,
        Default_Occupancy__c = 4,
        Description__c = 'Rum med pentry och plats för fyra, 42 kvm.'
      ),
      'st.fam'
    );
    c.save();

    Id roomRt = c.rt(PMS_Space__c.SObjectType, 'Room');
    for (List<String> r : ROOM_SPEC) {
      c.add(
        new PMS_Space__c(
          Name = r[0],
          RecordTypeId = roomRt,
          Site__c = site,
          Space_Type__c = c.ref(r[1]),
          Operational_Status__c = r[2],
          Floor__c = r[3],
          Max_Occupancy__c = Decimal.valueOf(r[4]),
          Bedrooms__c = r[1] == 'st.fam' ? 2 : 1,
          Amenities__c = r[5],
          Bookable__c = true
        ),
        'r.' + r[0]
      );
    }
    c.save();

    c.add(
      new PMS_Rate_Plan__c(
        Name = 'BAR flexibel',
        Site__c = site,
        Module__c = 'Hotel',
        Pricing_Basis__c = 'Per Night',
        Tax_Rate__c = 12,
        Active__c = true,
        Currency_Code__c = 'SEK',
        Valid_From__c = c.day(-365),
        Valid_To__c = c.day(365),
        Payment_Policy__c = c.ref('pp.std'),
        Cancellation_Policy__c = 'Gratis avbokning till 48 timmar före ankomst.'
      ),
      'rp.bar'
    );
    c.add(
      new PMS_Rate_Plan__c(
        Name = 'Ej återbetalningsbar',
        Site__c = site,
        Module__c = 'Hotel',
        Pricing_Basis__c = 'Per Night',
        Tax_Rate__c = 12,
        Active__c = true,
        Currency_Code__c = 'SEK',
        Valid_From__c = c.day(-365),
        Valid_To__c = c.day(365),
        Payment_Policy__c = c.ref('pp.dep'),
        Cancellation_Policy__c = 'Ingen återbetalning vid avbokning. 10 procent lägre pris.'
      ),
      'rp.nrf'
    );
    c.save();

    Map<String, Decimal> weekday = new Map<String, Decimal>{
      'st.std' => 1290,
      'st.sup' => 1690,
      'st.fam' => 2190
    };
    Map<String, Decimal> weekend = new Map<String, Decimal>{
      'st.std' => 1590,
      'st.sup' => 1990,
      'st.fam' => 2490
    };
    for (String plan : new List<String>{ 'rp.bar', 'rp.nrf' }) {
      Decimal factor = plan == 'rp.nrf' ? 0.9 : 1.0;
      for (String type : new List<String>{ 'st.std', 'st.sup', 'st.fam' }) {
        c.add(
          new PMS_Rate__c(
            Rate_Plan__c = c.ref(plan),
            Space_Type__c = c.ref(type),
            Amount__c = (weekday.get(type) * factor).setScale(0)
          ),
          'rate.' + plan + '.' + type + '.wd'
        );
        c.add(
          new PMS_Rate__c(
            Rate_Plan__c = c.ref(plan),
            Space_Type__c = c.ref(type),
            Amount__c = (weekend.get(type) * factor).setScale(0),
            Days_Of_Week__c = 'Friday;Saturday'
          ),
          'rate.' + plan + '.' + type + '.we'
        );
      }
    }
    c.save();

    c.add(
      new PMS_Pricing_Strategy__c(
        Name = 'Dynamisk prissättning BAR',
        Rate_Plan__c = c.ref('rp.bar'),
        Active__c = true,
        Horizon_Days__c = 30,
        Min_Percent__c = 80,
        Max_Percent__c = 150,
        Min_Rate__c = 900,
        Max_Rate__c = 3500,
        Max_Change_Percent__c = 20,
        Round_To__c = 10
      ),
      'ps.bar'
    );
    c.save();
    Id strategy = c.ref('ps.bar');
    c.add(
      new PMS_Pricing_Factor__c(
        Name = 'Hög beläggning 70 procent',
        Strategy__c = strategy,
        Type__c = 'Occupancy',
        Min_Value__c = 70,
        Adjust_Percent__c = 15,
        Active__c = true
      ),
      'pf.occ70'
    );
    c.add(
      new PMS_Pricing_Factor__c(
        Name = 'Mycket hög beläggning 90 procent',
        Strategy__c = strategy,
        Type__c = 'Occupancy',
        Min_Value__c = 90,
        Adjust_Percent__c = 30,
        Active__c = true
      ),
      'pf.occ90'
    );
    c.add(
      new PMS_Pricing_Factor__c(
        Name = 'Helgpåslag',
        Strategy__c = strategy,
        Type__c = 'Day of Week',
        Days_Of_Week__c = 'Friday;Saturday',
        Adjust_Percent__c = 10,
        Active__c = true
      ),
      'pf.dow'
    );
    c.add(
      new PMS_Pricing_Factor__c(
        Name = 'Sista minuten',
        Strategy__c = strategy,
        Type__c = 'Lead Time',
        Max_Value__c = 3,
        Adjust_Percent__c = -10,
        Active__c = true
      ),
      'pf.lead'
    );
    c.save();

    c.add(
      new PMS_Group_Block__c(
        Name = 'Konferens: Nordic Tech Summit',
        Site__c = site,
        Account__c = c.ref('a.g3'),
        Rate_Plan__c = c.ref('rp.bar'),
        Arrival_Date__c = c.day(10),
        Departure_Date__c = c.day(13),
        Cutoff_Date__c = c.day(3),
        Rooms_Blocked__c = 6,
        Rooms_Picked_Up__c = 2,
        Status__c = 'Definite'
      ),
      'gb.nts'
    );
    c.save();

    addHotelBookings(c, site);
    c.save();
  }

  /** One hotel reservation. The caller may set more fields on the returned record. */
  public static PMS_Booking__c stay(
    PMS_DemoData.Ctx c,
    String key,
    String room,
    String guest,
    Integer fromDay,
    Integer fromHour,
    Integer toDay,
    Integer toHour,
    String status,
    String channel,
    Decimal rate
  ) {
    String typeKey = typeOfRoom().get(room);
    Integer nights = Math.max(1, toDay - fromDay);
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = c.rt(PMS_Booking__c.SObjectType, 'Reservation'),
      Site__c = c.ref('s.hotel'),
      Space__c = c.opt('r.' + room),
      Room_Type_Requested__c = c.ref(typeKey),
      Rate_Plan__c = c.ref('rp.bar'),
      Account__c = guest == null ? null : c.ref('a.' + guest),
      Primary_Contact__c = guest == null ? null : c.ref('c.' + guest),
      Start__c = c.at(fromDay, fromHour, 0),
      End__c = c.at(toDay, toHour, 0),
      Status__c = status,
      Channel__c = channel,
      Adults__c = typeKey == 'st.fam' ? 3 : 2,
      Rate_Amount__c = rate,
      Total_Amount__c = rate * nights
    );
    c.add(b, key);
    return b;
  }

  private static void addHotelBookings(PMS_DemoData.Ctx c, Id site) {
    Datetime now = c.nowDt;
    // In house (6): Active, started before today or today
    PMS_Booking__c h1 = stay(
      c,
      'bk.h1',
      '101',
      'g1',
      -1,
      15,
      2,
      11,
      'Active',
      'Direct',
      1290
    );
    h1.Special_Requests__c = 'Allergi mot nötter. Tyst rum.';
    stay(c, 'bk.h2', '102', 'g2', -2, 15, 1, 11, 'Active', 'Phone', 1290);
    stay(c, 'bk.h3', '201', 'g3', -3, 15, 4, 11, 'Active', 'Corporate', 1690);
    stay(c, 'bk.h4', '103', 'g4', -3, 15, 0, 11, 'Active', 'Website', 1290); // leaves today, balance due
    stay(c, 'bk.h5', '104', 'g5', -1, 15, 0, 11, 'Active', 'Direct', 1290); // leaves today, settled
    stay(c, 'bk.h9', '106', 'g7', 0, 13, 2, 11, 'Active', 'Walk-in', 1290); // arrived today
    // Left this morning
    stay(c, 'bk.h6', '105', 'g6', -2, 15, 0, 8, 'Completed', 'Direct', 1290);
    // Arriving today
    PMS_Booking__c a7 = stay(
      c,
      'bk.h7',
      '202',
      'g7',
      0,
      15,
      2,
      11,
      'Confirmed',
      'Website',
      1690
    );
    a7.Guarantee__c = 'Card on File';
    a7.Guarantee_Status__c = 'Awaiting Card';
    a7.Guarantee_Message__c = 'Kortlänk skickad, väntar på gästen.';
    a7.Card_Link_Sent_At__c = now.addHours(-20);
    PMS_Booking__c a8 = stay(
      c,
      'bk.h8',
      '203',
      'g6',
      0,
      15,
      3,
      11,
      'Confirmed',
      'Direct',
      1690
    );
    a8.Online_Check_In__c = true;
    a8.Online_Check_In_At__c = now.addHours(-3);
    stay(c, 'bk.h10', '302', 'g4', 0, 15, 1, 11, 'Tentative', 'Phone', 2190);
    // Upcoming
    PMS_Booking__c u1 = stay(
      c,
      'bk.u1',
      '104',
      'g2',
      1,
      15,
      3,
      11,
      'Confirmed',
      'Direct',
      1290
    );
    u1.Guarantee__c = 'Card on File';
    u1.Guarantee_Status__c = 'Hold Placed';
    u1.Preauth_Status__c = 'Authorized';
    u1.Preauth_Amount__c = 1500;
    u1.Preauth_Expires_At__c = now.addHours(20);
    u1.Card_Brand__c = 'Visa';
    u1.Card_Last4__c = '4242';
    u1.Card_Expiry__c = '12/2029';
    u1.Card_Saved_At__c = now.addDays(-2);
    PMS_Booking__c u2 = stay(
      c,
      'bk.u2',
      '101',
      'g5',
      5,
      15,
      7,
      11,
      'Confirmed',
      'Website',
      1290
    );
    u2.Guarantee__c = 'Card on File';
    u2.Guarantee_Status__c = 'Card Saved';
    u2.Card_Brand__c = 'Mastercard';
    u2.Card_Last4__c = '4444';
    u2.Card_Expiry__c = '09/2028';
    u2.Card_Saved_At__c = now.addDays(-1);
    PMS_Booking__c u3 = stay(
      c,
      'bk.u3',
      '105',
      'g3',
      3,
      15,
      4,
      11,
      'Confirmed',
      'Corporate',
      1290
    );
    u3.Guarantee__c = 'Card on File';
    u3.Guarantee_Status__c = 'Action Needed';
    u3.Guarantee_Message__c = 'Kortet nekades: otillräckligt saldo.';
    PMS_Booking__c u4 = stay(
      c,
      'bk.u4',
      '202',
      'g8',
      7,
      15,
      9,
      11,
      'Tentative',
      'Travel Agent',
      1690
    );
    u4.Guarantee__c = 'Deposit';
    u4.Guarantee_Status__c = 'Awaiting Card';
    stay(c, 'bk.u5', '203', 'g1', 14, 15, 16, 11, 'Confirmed', 'Direct', 1290);
    // Group block: two of the six rooms picked up
    PMS_Booking__c gb1 = stay(
      c,
      'bk.gb1',
      '301',
      'g3',
      10,
      15,
      13,
      11,
      'Confirmed',
      'Corporate',
      2190
    );
    gb1.Group_Block__c = c.ref('gb.nts');
    PMS_Booking__c gb2 = stay(
      c,
      'bk.gb2',
      '302',
      'g3',
      10,
      15,
      13,
      11,
      'Confirmed',
      'Corporate',
      2190
    );
    gb2.Group_Block__c = c.ref('gb.nts');
    // Cancelled and no-show: they do not block the room
    PMS_Booking__c c1 = stay(
      c,
      'bk.c1',
      '102',
      'g7',
      4,
      15,
      6,
      11,
      'Cancelled',
      'Website',
      1290
    );
    c1.Policy_Pending__c = true;
    c1.Policy_Fee_Amount__c = 1290;
    c1.Policy_Event_At__c = now.addHours(-2);
    PMS_Booking__c c2 = stay(
      c,
      'bk.c2',
      '103',
      'g8',
      9,
      15,
      11,
      11,
      'Cancelled',
      'Travel Agent',
      1290
    );
    c2.Deposit_Amount__c = 2400;
    c2.Refund_Due__c = 2400;
    stay(c, 'bk.ns', '103', 'g2', -1, 15, 0, 11, 'No Show', 'Phone', 1290);
    // Channel bookings: one overbooked without a room, one placed
    PMS_Booking__c o1 = stay(
      c,
      'bk.o1',
      '101',
      null,
      2,
      15,
      4,
      11,
      'Confirmed',
      'OTA',
      1290
    );
    o1.Space__c = null;
    o1.OTA_Name__c = 'Booking.com';
    o1.OTA_Reservation_Code__c = 'BDC-4821937650';
    PMS_Booking__c o2 = stay(
      c,
      'bk.o2',
      '106',
      null,
      6,
      15,
      8,
      11,
      'Confirmed',
      'OTA',
      1290
    );
    o2.OTA_Name__c = 'Expedia';
    o2.OTA_Reservation_Code__c = 'EXP-77310482';
    // Past stays, completed
    stay(
      c,
      'bk.p0',
      '204',
      'g3',
      -110,
      15,
      -108,
      11,
      'Completed',
      'Corporate',
      1690
    );
    stay(
      c,
      'bk.p1',
      '201',
      'g1',
      -60,
      15,
      -57,
      11,
      'Completed',
      'Direct',
      1690
    );
    stay(
      c,
      'bk.p2',
      '202',
      'g2',
      -32,
      15,
      -30,
      11,
      'Completed',
      'Website',
      1690
    );
    stay(c, 'bk.p3', '101', 'g5', -12, 15, -10, 11, 'Completed', 'Phone', 1290);
    stay(c, 'bk.p4', '103', 'g6', -8, 15, -6, 11, 'Completed', 'Direct', 1290);
  }

  // ------------------------------------------------------------------ property

  /** A lease. The caller may set more fields on the returned record. */
  private static PMS_Booking__c lease(
    PMS_DemoData.Ctx c,
    String key,
    String unit,
    String tenant,
    Integer fromDay,
    Integer toDay,
    String status,
    String type,
    Decimal rent,
    String renewal
  ) {
    PMS_Booking__c b = new PMS_Booking__c(
      RecordTypeId = c.rt(PMS_Booking__c.SObjectType, 'Lease'),
      Site__c = c.ref('s.prop'),
      Space__c = c.ref('u.' + unit),
      Account__c = c.ref('a.' + tenant),
      Primary_Contact__c = c.ref('c.' + tenant),
      Start__c = c.at(fromDay, 0, 0),
      End__c = c.at(toDay, 0, 0),
      Status__c = status,
      Lease_Type__c = type,
      Rate_Amount__c = rent,
      Total_Amount__c = rent * 12,
      Rent_Frequency__c = 'Monthly',
      Rent_Due_Day__c = 1,
      Notice_Period_Days__c = type == 'Commercial' ? 180 : 90,
      Renewal_Status__c = renewal,
      Adults__c = 1
    );
    c.add(b, key);
    return b;
  }

  public static void property(PMS_DemoData.Ctx c) {
    Id site = c.ref('s.prop');
    Id unitRt = c.rt(PMS_Space__c.SObjectType, 'Unit');
    // name, base rent, size, bedrooms, floor, status, amenities
    List<List<String>> units = new List<List<String>>{
      new List<String>{
        'A-101',
        '11900',
        '48',
        '2',
        '1',
        'Occupied',
        'WiFi;Balcony'
      },
      new List<String>{
        'A-102',
        '28500',
        '110',
        '0',
        '1',
        'Occupied',
        'WiFi;Air Conditioning;Projector'
      },
      new List<String>{
        'A-103',
        '14200',
        '62',
        '2',
        '2',
        'Occupied',
        'WiFi;Balcony;Parking'
      },
      new List<String>{ 'A-104', '9800', '38', '1', '2', 'Occupied', 'WiFi' },
      new List<String>{
        'A-105',
        '33000',
        '140',
        '0',
        '1',
        'Occupied',
        'WiFi;Air Conditioning;Accessible'
      },
      new List<String>{
        'A-106',
        '12500',
        '55',
        '2',
        '3',
        'Available',
        'WiFi;Balcony'
      },
      new List<String>{
        'A-107',
        '13900',
        '58',
        '2',
        '3',
        'Available',
        'WiFi;Balcony;Pet Friendly'
      },
      new List<String>{
        'A-108',
        '15800',
        '70',
        '3',
        '4',
        'Under Renovation',
        'WiFi;Balcony;Kitchen'
      }
    };
    for (List<String> u : units) {
      c.add(
        new PMS_Space__c(
          Name = u[0],
          RecordTypeId = unitRt,
          Site__c = site,
          Base_Rate__c = Decimal.valueOf(u[1]),
          Size_Sqm__c = Decimal.valueOf(u[2]),
          Bedrooms__c = Decimal.valueOf(u[3]),
          Floor__c = u[4],
          Operational_Status__c = u[5],
          Amenities__c = u[6],
          Bookable__c = true
        ),
        'u.' + u[0]
      );
    }
    c.save();

    // Leases: five let, one starting in four days, one cancelled
    PMS_Booking__c l1 = lease(
      c,
      'bk.l1',
      'A-101',
      't1',
      -380,
      350,
      'Active',
      'Residential',
      11900,
      'Not Due'
    );
    PMS_Booking__c l2 = lease(
      c,
      'bk.l2',
      'A-102',
      't2',
      -700,
      45,
      'Active',
      'Commercial',
      28500,
      'Offer Sent'
    );
    l2.Index_Clause__c = true;
    l2.Index_Series__c = 'KPI 2020=100';
    l2.Index_Base_Value__c = 118.4;
    l2.Index_Base_Rent__c = 26000;
    l2.Index_Share__c = 100;
    l2.Last_Rent_Adjustment__c = c.day(-365);
    lease(
      c,
      'bk.l3',
      'A-103',
      't3',
      -200,
      72,
      'Active',
      'Residential',
      14200,
      'Not Due'
    );
    lease(
      c,
      'bk.l4',
      'A-104',
      't4',
      -400,
      5,
      'Active',
      'Residential',
      9800,
      'Notice Given'
    );
    PMS_Booking__c l5 = lease(
      c,
      'bk.l5',
      'A-105',
      't5',
      -900,
      640,
      'Active',
      'Commercial',
      33000,
      'Not Due'
    );
    l5.Index_Clause__c = true;
    l5.Index_Series__c = 'KPI 1980=100';
    l5.Index_Base_Value__c = 318.2;
    l5.Index_Base_Rent__c = 30000;
    l5.Index_Share__c = 80;
    l5.Last_Rent_Adjustment__c = c.day(-400);
    PMS_Booking__c l6 = lease(
      c,
      'bk.l6',
      'A-106',
      't6',
      4,
      369,
      'Confirmed',
      'Residential',
      12500,
      'Not Due'
    );
    l6.Guarantee__c = 'Deposit';
    l6.Guarantee_Status__c = 'Awaiting Card';
    l6.Guarantee_Message__c = 'Depositionsavgift ej betald.';
    l6.Preauth_Status__c = 'Authorized';
    l6.Preauth_Amount__c = 12500;
    l6.Preauth_Expires_At__c = c.nowDt.addHours(10);
    PMS_Booking__c l7 = lease(
      c,
      'bk.l7',
      'A-107',
      't7',
      30,
      395,
      'Cancelled',
      'Residential',
      13900,
      'Not Due'
    );
    l7.Policy_Pending__c = true;
    l7.Policy_Fee_Amount__c = 6950;
    l7.Policy_Event_At__c = c.nowDt.addHours(-5);
    l7.Refund_Due__c = 13900;
    l7.Deposit_Amount__c = 13900;
    c.save();

    // Listings and applications
    c.add(
      new PMS_Listing__c(
        Name = 'A-107, 2 rok med balkong',
        Site__c = site,
        Space__c = c.ref('u.A-107'),
        Listing_Status__c = 'Published',
        Asking_Rent__c = 13900,
        Available_From__c = c.day(20),
        Description__c = 'Ljus tvåa på tredje våningen med balkong mot innergården. Husdjur välkomna.'
      ),
      'li.107'
    );
    c.add(
      new PMS_Listing__c(
        Name = 'A-106, 2 rok',
        Site__c = site,
        Space__c = c.ref('u.A-106'),
        Listing_Status__c = 'Under Offer',
        Asking_Rent__c = 12500,
        Available_From__c = c.day(4),
        Description__c = 'Tvåa med balkong, nyrenoverat kök.'
      ),
      'li.106'
    );
    c.add(
      new PMS_Listing__c(
        Name = 'A-108, 3 rok (renovering)',
        Site__c = site,
        Space__c = c.ref('u.A-108'),
        Listing_Status__c = 'Draft',
        Asking_Rent__c = 15800,
        Available_From__c = c.day(90),
        Description__c = 'Stor trea under renovering. Inflytt efter sommaren.'
      ),
      'li.108'
    );
    c.save();
    c.add(
      new PMS_Application__c(
        Applicant__c = c.ref('c.ap1'),
        Listing__c = c.ref('li.107'),
        Space__c = c.ref('u.A-107'),
        Screening_Status__c = 'In Progress',
        Monthly_Income__c = 41000,
        Employer__c = 'Region Stockholm',
        Desired_Move_In__c = c.day(25),
        Score__c = 72
      ),
      'ap.1'
    );
    c.add(
      new PMS_Application__c(
        Applicant__c = c.ref('c.ap2'),
        Listing__c = c.ref('li.107'),
        Space__c = c.ref('u.A-107'),
        Screening_Status__c = 'Not Started',
        Monthly_Income__c = 36500,
        Employer__c = 'Ekonomibyrån Söder AB',
        Desired_Move_In__c = c.day(30),
        Score__c = null
      ),
      'ap.2'
    );
    c.add(
      new PMS_Application__c(
        Applicant__c = c.ref('c.ap3'),
        Listing__c = c.ref('li.107'),
        Space__c = c.ref('u.A-107'),
        Screening_Status__c = 'Needs Review',
        Monthly_Income__c = 29000,
        Employer__c = 'Egen företagare',
        Desired_Move_In__c = c.day(21),
        Score__c = 55
      ),
      'ap.3'
    );
    c.add(
      new PMS_Application__c(
        Applicant__c = c.ref('c.t6'),
        Listing__c = c.ref('li.106'),
        Space__c = c.ref('u.A-106'),
        Lease__c = c.ref('bk.l6'),
        Decision__c = 'Approved',
        Screening_Status__c = 'Passed',
        Monthly_Income__c = 47000,
        Employer__c = 'Karolinska Universitetssjukhuset',
        Desired_Move_In__c = c.day(4),
        Score__c = 91
      ),
      'ap.4'
    );
    c.save();

    // Recurring charge schedules (MD on the lease)
    Date nextMonth = c.today.toStartOfMonth().addMonths(1);
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l1'),
        Charge_Type__c = 'Rent',
        Amount__c = 11900,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-380),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l1.rent'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l2'),
        Charge_Type__c = 'Rent',
        Amount__c = 28500,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-700),
        Next_Run_Date__c = nextMonth,
        Active__c = true,
        Escalation_Percent__c = 2
      ),
      'lcs.l2.rent'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l2'),
        Charge_Type__c = 'Service Charge',
        Amount__c = 3200,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-700),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l2.svc'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l3'),
        Charge_Type__c = 'Rent',
        Amount__c = 14200,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-200),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l3.rent'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l3'),
        Charge_Type__c = 'Parking',
        Amount__c = 1200,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-200),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l3.park'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l4'),
        Charge_Type__c = 'Rent',
        Amount__c = 9800,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-400),
        End_Date__c = c.day(5),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l4.rent'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l5'),
        Charge_Type__c = 'Rent',
        Amount__c = 33000,
        Frequency__c = 'Monthly',
        Start_Date__c = c.day(-900),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l5.rent'
    );
    c.add(
      new PMS_Lease_Charge_Schedule__c(
        Lease__c = c.ref('bk.l5'),
        Charge_Type__c = 'Service Charge',
        Amount__c = 4100,
        Frequency__c = 'Quarterly',
        Start_Date__c = c.day(-900),
        Next_Run_Date__c = nextMonth,
        Active__c = true
      ),
      'lcs.l5.svc'
    );
    c.save();

    // Index values: two series, the last 13 published months
    Date firstOfMonth = c.today.toStartOfMonth();
    for (Integer k = 14; k >= 2; k--) {
      Date d = firstOfMonth.addMonths(-k);
      c.add(
        new PMS_Index_Value__c(
          Series__c = 'KPI 2020=100',
          Year__c = d.year(),
          Month__c = d.month(),
          Value__c = 124.0 + (14 - k) * 0.35,
          Source__c = 'SCB (demo)'
        ),
        'iv.20.' + k
      );
      c.add(
        new PMS_Index_Value__c(
          Series__c = 'KPI 1980=100',
          Year__c = d.year(),
          Month__c = d.month(),
          Value__c = 335.0 + (14 - k) * 0.95,
          Source__c = 'SCB (demo)'
        ),
        'iv.80.' + k
      );
    }
    c.save();

    // Rent reviews: two to handle, one approved to send, one sent, one applied
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l2'),
        Kind__c = 'Index',
        Status__c = 'Draft',
        Effective_Date__c = c.day(30),
        Base_Rent__c = 26000,
        Old_Rent__c = 28500,
        New_Rent__c = 30300,
        Change_Percent__c = 6.32,
        Base_Index__c = 118.4,
        Current_Index__c = 128.9,
        Index_Period__c = 'KPI 2020=100, oktober',
        Warning__c = 'Uppsägningstiden på 180 dagar hinner inte löpa ut före ikraftträdandet.'
      ),
      'ra.l2'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l5'),
        Kind__c = 'Negotiated',
        Status__c = 'Approved',
        Effective_Date__c = c.day(60),
        Old_Rent__c = 33000,
        New_Rent__c = 33990,
        Change_Percent__c = 3,
        Negotiated_Percent__c = 3,
        Note__c = 'Överenskommet med Café Vasa AB vid avtalsmöte.'
      ),
      'ra.l5'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l1'),
        Kind__c = 'Manual',
        Status__c = 'Draft',
        Effective_Date__c = c.day(75),
        Old_Rent__c = 11900,
        New_Rent__c = 12200,
        Change_Percent__c = 2.52,
        Note__c = 'Årlig justering enligt hyresnämndens ram.'
      ),
      'ra.l1'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l3'),
        Kind__c = 'Manual',
        Status__c = 'Notice Sent',
        Effective_Date__c = c.day(90),
        Old_Rent__c = 14200,
        New_Rent__c = 14500,
        Change_Percent__c = 2.11,
        Notice_Sent_At__c = c.nowDt.addDays(-3),
        Notice_Sent_To__c = 'oskar.persson@example.com'
      ),
      'ra.l3'
    );
    c.add(
      new PMS_Rent_Adjustment__c(
        Lease__c = c.ref('bk.l1'),
        Kind__c = 'Manual',
        Status__c = 'Applied',
        Effective_Date__c = c.day(-380),
        Old_Rent__c = 11600,
        New_Rent__c = 11900,
        Change_Percent__c = 2.59,
        Applied_At__c = c.nowDt.addDays(-380)
      ),
      'ra.l1.old'
    );
    c.save();

    // Meters and readings
    c.add(
      new PMS_Meter__c(
        Name = 'EL A-101',
        Space__c = c.ref('u.A-101'),
        Meter_Type__c = 'Electricity',
        Unit_Price__c = 2.1
      ),
      'mt.101.el'
    );
    c.add(
      new PMS_Meter__c(
        Name = 'VV A-101',
        Space__c = c.ref('u.A-101'),
        Meter_Type__c = 'Hot Water',
        Unit_Price__c = 68
      ),
      'mt.101.hw'
    );
    c.add(
      new PMS_Meter__c(
        Name = 'EL A-103',
        Space__c = c.ref('u.A-103'),
        Meter_Type__c = 'Electricity',
        Unit_Price__c = 2.1
      ),
      'mt.103.el'
    );
    c.add(
      new PMS_Meter__c(
        Name = 'EL A-105',
        Space__c = c.ref('u.A-105'),
        Meter_Type__c = 'Electricity',
        Unit_Price__c = 2.1
      ),
      'mt.105.el'
    );
    c.save();
    Map<String, Decimal> start = new Map<String, Decimal>{
      'mt.101.el' => 8400,
      'mt.101.hw' => 120,
      'mt.103.el' => 15200,
      'mt.105.el' => 52100
    };
    Map<String, Decimal> step = new Map<String, Decimal>{
      'mt.101.el' => 310,
      'mt.101.hw' => 6,
      'mt.103.el' => 420,
      'mt.105.el' => 1850
    };
    for (String m : start.keySet()) {
      Decimal v = start.get(m);
      for (Integer k = 3; k >= 1; k--) {
        Decimal previous = v;
        v += step.get(m);
        c.add(
          new PMS_Meter_Reading__c(
            Meter__c = c.ref(m),
            Reading_Date__c = c.day(-30 * k + 5),
            Reading_Value__c = v,
            Consumption__c = v - previous,
            Billed__c = k > 1
          ),
          'mr.' + m + '.' + k
        );
      }
    }
    c.save();

    // Inspections: one done, two coming up
    c.add(
      new PMS_Inspection__c(
        Site__c = site,
        Space__c = c.ref('u.A-102'),
        Inspection_Type__c = 'Periodic',
        Inspection_Date__c = c.day(-20),
        Inspector__c = c.userId,
        Score__c = 86,
        Notes__c = 'Lokalen i gott skick. Mindre slitage på golvet vid entrén.'
      ),
      'in.1'
    );
    c.add(
      new PMS_Inspection__c(
        Site__c = site,
        Space__c = c.ref('u.A-106'),
        Booking__c = c.ref('bk.l6'),
        Inspection_Type__c = 'Move-In',
        Inspection_Date__c = c.day(3),
        Inspector__c = c.userId
      ),
      'in.2'
    );
    c.add(
      new PMS_Inspection__c(
        Site__c = site,
        Space__c = c.ref('u.A-104'),
        Booking__c = c.ref('bk.l4'),
        Inspection_Type__c = 'Move-Out',
        Inspection_Date__c = c.day(5),
        Inspector__c = c.userId
      ),
      'in.3'
    );
    c.save();
    c.add(
      new PMS_Inspection_Item__c(
        Inspection__c = c.ref('in.1'),
        Area__c = 'Golv entré',
        Condition__c = 'Fair',
        Repair_Required__c = false,
        Notes__c = 'Slitage men ingen åtgärd behövs.'
      ),
      'ii.1a'
    );
    c.add(
      new PMS_Inspection_Item__c(
        Inspection__c = c.ref('in.1'),
        Area__c = 'Ventilation',
        Condition__c = 'Good',
        Repair_Required__c = false
      ),
      'ii.1b'
    );
    c.add(
      new PMS_Inspection_Item__c(
        Inspection__c = c.ref('in.1'),
        Area__c = 'Belysning',
        Condition__c = 'Poor',
        Repair_Required__c = true,
        Notes__c = 'Två armaturer behöver bytas.'
      ),
      'ii.1c'
    );
    c.add(
      new PMS_Inspection_Item__c(
        Inspection__c = c.ref('in.1'),
        Area__c = 'Brandskydd',
        Condition__c = 'Excellent',
        Repair_Required__c = false
      ),
      'ii.1d'
    );
    c.add(
      new PMS_Inspection_Item__c(
        Inspection__c = c.ref('in.3'),
        Area__c = 'Kök',
        Condition__c = 'Good',
        Repair_Required__c = false
      ),
      'ii.3a'
    );
    c.add(
      new PMS_Inspection_Item__c(
        Inspection__c = c.ref('in.3'),
        Area__c = 'Badrum',
        Condition__c = 'Fair',
        Repair_Required__c = true,
        Notes__c = 'Fogar i duschen behöver göras om.'
      ),
      'ii.3b'
    );
    c.save();

    // Owner statements: last month's draft to publish, the month before already published
    Date thisMonth = c.today.toStartOfMonth();
    c.add(
      new PMS_Owner_Statement__c(
        Site__c = site,
        Owner_Account__c = c.ref('a.owner'),
        Period_Start__c = thisMonth.addMonths(-1),
        Period_End__c = thisMonth.addDays(-1),
        Gross_Rent__c = 97400,
        Management_Fee__c = 5844,
        Expenses__c = 12800,
        Arrears__c = 12200,
        Occupancy_Percent__c = 62.5,
        Occupancy_Basis__c = '5 av 8 enheter uthyrda',
        Generated_On__c = c.nowDt.addDays(-2),
        Status__c = 'Draft'
      ),
      'os.draft'
    );
    c.add(
      new PMS_Owner_Statement__c(
        Site__c = site,
        Owner_Account__c = c.ref('a.owner'),
        Period_Start__c = thisMonth.addMonths(-2),
        Period_End__c = thisMonth.addMonths(-1).addDays(-1),
        Gross_Rent__c = 97400,
        Management_Fee__c = 5844,
        Expenses__c = 8300,
        Arrears__c = 0,
        Occupancy_Percent__c = 62.5,
        Occupancy_Basis__c = '5 av 8 enheter uthyrda',
        Generated_On__c = c.nowDt.addDays(-33),
        Status__c = 'Published'
      ),
      'os.pub'
    );
    c.save();

    // Documents to sign
    c.add(
      new PMS_Document_Request__c(
        Title__c = 'Hyresavtal A-106',
        Account__c = c.ref('a.t6'),
        Contact__c = c.ref('c.t6'),
        Booking__c = c.ref('bk.l6'),
        Requires_Signature__c = true,
        Status__c = 'Viewed',
        Viewed_At__c = c.nowDt.addHours(-6),
        Due_Date__c = c.day(2),
        Signer_Name__c = 'Fredrik Lund',
        Signer_Email__c = 'fredrik.lund@example.com',
        Message__c = 'Hyresavtal för A-106 med tillträde om fyra dagar.'
      ),
      'doc.l6'
    );
    c.add(
      new PMS_Document_Request__c(
        Title__c = 'Förlängningsavtal Nordic Design AB',
        Account__c = c.ref('a.t2'),
        Contact__c = c.ref('c.t2'),
        Booking__c = c.ref('bk.l2'),
        Requires_Signature__c = true,
        Status__c = 'Draft',
        Due_Date__c = c.day(14),
        Signer_Name__c = 'Petra Holm',
        Message__c = 'Förslag till förlängning av lokalhyresavtalet.'
      ),
      'doc.l2'
    );
    c.save();
  }
}
