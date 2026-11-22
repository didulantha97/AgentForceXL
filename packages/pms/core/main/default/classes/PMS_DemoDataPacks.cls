/**
 * Demo data steps for the small packs: busy-weekend, channel-incident and new-client.
 * (overdue-wave and month-end live in PMS_DemoDataBilling.) Called by PMS_DemoData, one step per transaction.
 * All of them need the baseline pack, which PMS_DemoData loads first when it is missing.
 */
public with sharing class PMS_DemoDataPacks {
  // ------------------------------------------------------------------ busy-weekend

  private static Boolean overlaps(
    PMS_Booking__c a,
    Id room,
    Datetime start,
    Datetime finish
  ) {
    return a.Space__c == room && a.Start__c < finish && a.End__c > start;
  }

  /**
   * About 14 hotel arrivals over the next three days. Each one gets the first sellable room that is really free
   * (the booking trigger would refuse a double booking, so this checks the same way first). Arrivals that find
   * no room are left out rather than overbooking.
   */
  public static void busy(PMS_DemoData.Ctx c) {
    Id hotel = c.ref('s.hotel');
    List<PMS_Space__c> rooms = [
      SELECT Id, Name, Space_Type__c, Space_Type__r.Default_Rate__c
      FROM PMS_Space__c
      WHERE
        Site__c = :hotel
        AND Bookable__c = TRUE
        AND Operational_Status__c NOT IN ('Out of Order', 'Under Renovation')
      WITH USER_MODE
      ORDER BY Name
    ];
    Datetime windowStart = c.at(0, 0, 0);
    Datetime windowEnd = c.at(9, 0, 0);
    List<PMS_Booking__c> taken = [
      SELECT Space__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Site__c = :hotel
        AND Space__c != NULL
        AND Status__c NOT IN :PMS_AvailabilityService.NON_BLOCKING_STATUSES
        AND Start__c < :windowEnd
        AND End__c > :windowStart
      WITH USER_MODE
    ];
    List<Integer> arrivals = new List<Integer>{
      1,
      1,
      1,
      1,
      1,
      2,
      2,
      2,
      2,
      2,
      3,
      3,
      3,
      3
    };
    List<Integer> nights = new List<Integer>{
      1,
      2,
      1,
      1,
      2,
      1,
      1,
      2,
      1,
      1,
      1,
      2,
      1,
      1
    };
    List<String> channels = new List<String>{
      'Direct',
      'Website',
      'OTA',
      'Phone',
      'Corporate',
      'Travel Agent',
      'AI Agent'
    };
    Id reservation = c.rt(PMS_Booking__c.SObjectType, 'Reservation');
    Integer made = 0;
    for (Integer k = 0; k < arrivals.size(); k++) {
      Datetime start = c.at(arrivals[k], 15, 0);
      Datetime finish = c.at(arrivals[k] + nights[k], 11, 0);
      PMS_Space__c room = null;
      for (PMS_Space__c candidate : rooms) {
        Boolean free = true;
        for (PMS_Booking__c t : taken) {
          if (overlaps(t, candidate.Id, start, finish)) {
            free = false;
            break;
          }
        }
        if (free) {
          room = candidate;
          break;
        }
      }
      if (room == null) {
        continue;
      }
      String guest = 'g' + (Math.mod(k, 8) + 1);
      String channel = channels[Math.mod(k, channels.size())];
      Decimal rate = room.Space_Type__r.Default_Rate__c;
      PMS_Booking__c b = new PMS_Booking__c(
        RecordTypeId = reservation,
        Site__c = hotel,
        Space__c = room.Id,
        Room_Type_Requested__c = room.Space_Type__c,
        Rate_Plan__c = c.ref('rp.bar'),
        Account__c = c.ref('a.' + guest),
        Primary_Contact__c = c.ref('c.' + guest),
        Start__c = start,
        End__c = finish,
        Status__c = Math.mod(k, 7) == 3 ? 'Tentative' : 'Confirmed',
        Channel__c = channel,
        Adults__c = 2,
        Rate_Amount__c = rate,
        Total_Amount__c = rate * nights[k]
      );
      if (channel == 'OTA') {
        b.OTA_Name__c = 'Booking.com';
        b.OTA_Reservation_Code__c = 'BDC-' + (5530100 + k);
      }
      taken.add(
        new PMS_Booking__c(
          Space__c = room.Id,
          Start__c = start,
          End__c = finish
        )
      );
      c.add(b, 'bk.bw.' + k);
      made++;
    }
    if (made == 0) {
      throw new PMS_DemoData.DemoException(
        'No free rooms in the next three days. Reset the pack and try again.'
      );
    }
    c.save();
  }

  // ------------------------------------------------------------------ channel-incident

  public static void incident(PMS_DemoData.Ctx c) {
    c.add(
      PMS_DemoDataWork.log(
        c,
        'Outbound',
        'Availability',
        'Error',
        'Channex svarade 503: tjänsten är tillfälligt otillgänglig.',
        null
      ),
      'cl.i1'
    );
    c.add(
      PMS_DemoDataWork.log(
        c,
        'Outbound',
        'Rates',
        'Error',
        'Channex svarade 401: API-nyckeln är ogiltig eller har återkallats.',
        null
      ),
      'cl.i2'
    );
    c.add(
      PMS_DemoDataWork.log(
        c,
        'Inbound',
        'Booking New',
        'Error',
        'Bokning EXP-88120033 kunde inte sparas: rumstyp saknas i kopplingen.',
        null
      ),
      'cl.i3'
    );
    c.add(
      PMS_DemoDataWork.log(
        c,
        'Inbound',
        'Booking Modified',
        'Error',
        'Ändring av BDC-4821937650 kunde inte tillämpas: bokningen är redan avbokad.',
        'bk.o1'
      ),
      'cl.i4'
    );
    c.add(
      PMS_DemoDataWork.log(
        c,
        'Outbound',
        'Stop Sell',
        'Error',
        'Timeout efter 30 sekunder när stoppförsäljning skickades.',
        null
      ),
      'cl.i5'
    );
    c.add(
      PMS_DemoDataWork.log(
        c,
        'Outbound',
        'Availability',
        'Error',
        'Channex svarade 422: okänt rumstyps-id för Familjerum.',
        null
      ),
      'cl.i6'
    );
    c.save();
  }

  // ------------------------------------------------------------------ new-client

  public static void newClient(PMS_DemoData.Ctx c) {
    c.account(
      'a.n1',
      'Mikael Ekström',
      'Consumer',
      'Practice Client',
      'Hornsgatan 71',
      'Stockholm',
      '118 49'
    );
    c.account(
      'a.n2',
      'Bergman & Partners AB',
      'Business',
      'Project Client;Practice Client',
      'Birger Jarlsgatan 57',
      'Stockholm',
      '113 56'
    );
    c.save();
    c.person('c.n1', 'a.n1', 'Mikael', 'Ekström');
    c.person('c.n2', 'a.n2', 'Sanna', 'Bergman');
    c.person('c.n3', 'a.n2', 'Per', 'Bergman');
    c.save();

    // Practice: two matters in intake, three tentative appointments, unsigned forms
    Id site = c.ref('s.prac');
    c.add(
      new PMS_Matter__c(
        Name = 'Ryggbesvär, M. Ekström',
        Account__c = c.ref('a.n1'),
        Primary_Contact__c = c.ref('c.n1'),
        Site__c = site,
        Status__c = 'Intake',
        Conflict_Check_Status__c = 'Not Started',
        Practice_Area__c = 'Physiotherapy',
        Fee_Arrangement__c = 'Per Appointment',
        Responsible_Practitioner__c = c.ref('pr.3'),
        Open_Date__c = c.day(-1)
      ),
      'mt.n1'
    );
    c.add(
      new PMS_Matter__c(
        Name = 'Företagshälsa, Bergman & Partners',
        Account__c = c.ref('a.n2'),
        Primary_Contact__c = c.ref('c.n2'),
        Site__c = site,
        Status__c = 'Intake',
        Conflict_Check_Status__c = 'Not Started',
        Practice_Area__c = 'General Medicine',
        Fee_Arrangement__c = 'Retainer',
        Responsible_Practitioner__c = c.ref('pr.1'),
        Open_Date__c = c.day(-2)
      ),
      'mt.n2'
    );
    c.save();
    PMS_DemoDataWork.appt(
      c,
      'bk.nc.1',
      'pr.3',
      'sv.2',
      'n1',
      2,
      10,
      0,
      60,
      'Tentative',
      'In Person',
      'Website',
      'mt.n1'
    );
    PMS_DemoDataWork.appt(
      c,
      'bk.nc.2',
      'pr.1',
      'sv.1',
      'n1',
      4,
      9,
      0,
      30,
      'Tentative',
      'In Person',
      'Phone',
      'mt.n1'
    );
    PMS_DemoDataWork.appt(
      c,
      'bk.nc.3',
      'pr.2',
      'sv.5',
      'n2',
      3,
      13,
      0,
      45,
      'Tentative',
      'In Person',
      'Direct',
      'mt.n2'
    );
    c.save();
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.nc.1'),
        Contact__c = c.ref('c.n1'),
        Matter__c = c.ref('mt.n1'),
        Form_Type__c = 'New Client Intake'
      ),
      'if.n1'
    );
    c.add(
      new PMS_Intake_Form__c(
        Booking__c = c.ref('bk.nc.3'),
        Contact__c = c.ref('c.n2'),
        Matter__c = c.ref('mt.n2'),
        Form_Type__c = 'KYC'
      ),
      'if.n2'
    );
    c.add(
      new PMS_Document_Request__c(
        Title__c = 'Engagemangsbrev: nyregistrering',
        Account__c = c.ref('a.n1'),
        Contact__c = c.ref('c.n1'),
        Booking__c = c.ref('bk.nc.1'),
        Requires_Signature__c = true,
        Status__c = 'Draft',
        Due_Date__c = c.day(3),
        Signer_Name__c = 'Mikael Ekström'
      ),
      'doc.n1'
    );
    c.save();

    // Projects: one new project in planning
    c.add(
      new PMS_Resource__c(
        Name = 'Elin Waller',
        Role__c = 'Interiörarkitekt',
        Resource_Type__c = 'Person',
        Bill_Rate__c = 1200,
        Cost_Rate__c = 760,
        Weekly_Capacity__c = 40,
        Active__c = true
      ),
      'rs.n1'
    );
    c.add(
      new PMS_Project__c(
        Name = 'Kontorsrenovering Bergman & Partners',
        Account__c = c.ref('a.n2'),
        Site__c = c.ref('s.proj'),
        Status__c = 'Planning',
        Health__c = 'Green',
        Billing_Type__c = 'Milestone',
        Budget__c = 650000,
        Actual_Cost__c = 0,
        Percent_Complete__c = 0,
        Start_Date__c = c.day(7),
        End_Date__c = c.day(90),
        Project_Manager__c = c.userId
      ),
      'pj.n1'
    );
    c.save();
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.n1'),
        Category__c = 'Materials',
        Budget_Amount__c = 350000,
        Committed__c = 0,
        Actual__c = 0
      ),
      'bl.n1'
    );
    c.add(
      new PMS_Budget_Line__c(
        Project__c = c.ref('pj.n1'),
        Category__c = 'Labour',
        Budget_Amount__c = 300000,
        Committed__c = 0,
        Actual__c = 0
      ),
      'bl.n2'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Ritningar godkända',
        Project__c = c.ref('pj.n1'),
        Status__c = 'Not Started',
        Due_Date__c = c.day(30),
        Amount__c = 150000,
        Invoiced__c = false
      ),
      'ms.n1'
    );
    c.add(
      new PMS_Milestone__c(
        Name = 'Inflyttning',
        Project__c = c.ref('pj.n1'),
        Status__c = 'Not Started',
        Due_Date__c = c.day(75),
        Amount__c = 500000,
        Invoiced__c = false
      ),
      'ms.n2'
    );
    c.save();
    c.add(
      PMS_DemoDataWork.task(
        c,
        'pj.n1',
        'rs.n1',
        'Programskiss och behovsanalys',
        'Not Started',
        0,
        7,
        21,
        40,
        'High',
        'ms.n1'
      ),
      't.n1'
    );
    c.add(
      PMS_DemoDataWork.task(
        c,
        'pj.n1',
        'rs.n1',
        'Ritningsunderlag',
        'Not Started',
        0,
        22,
        30,
        60,
        'Medium',
        'ms.n1'
      ),
      't.n2'
    );
    c.add(
      PMS_DemoDataWork.task(
        c,
        'pj.n1',
        'rs.n1',
        'Upphandling av entreprenör',
        'Not Started',
        0,
        31,
        50,
        50,
        'Medium',
        null
      ),
      't.n3'
    );
    c.add(
      new PMS_RAID_Item__c(
        Project__c = c.ref('pj.n1'),
        RAID_Type__c = 'Risk',
        Severity__c = 'Medium',
        Status__c = 'Open',
        Description__c = 'Hyresvärden har inte godkänt ombyggnaden.',
        Mitigation__c = 'Boka möte med hyresvärden innan ritningarna lämnas in.',
        Due_Date__c = c.day(10),
        Item_Owner__c = c.userId
      ),
      'rd.n1'
    );
    c.add(
      new PMS_Approval_Request__c(
        Project__c = c.ref('pj.n1'),
        Account__c = c.ref('a.n2'),
        Type__c = 'Design Choice',
        Status__c = 'Draft',
        Title__c = 'Val av golv',
        Details__c = 'Parkett eller linoleum i kontorsytorna.',
        Due_Date__c = c.day(12)
      ),
      'ar.n1'
    );
    c.save();
  }
}
