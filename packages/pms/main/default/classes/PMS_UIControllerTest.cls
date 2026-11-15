@isTest
private class PMS_UIControllerTest {
  /** Runs as an admin holding the PMS permission sets, because the controller reads in user mode. */
  private static User pmsUser() {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      LastName = 'PMS Tester',
      Alias = 'pmstest',
      Email = 'pms.tester@example.com',
      Username = 'pms.tester.' + unique + '@example.com',
      ProfileId = admin.Id,
      TimeZoneSidKey = 'Europe/Stockholm',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert u;
    List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('PMS_Core_Admin', 'PMS_App_Access')
    ]) {
      psas.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    insert psas;
    return u;
  }

  @isTest
  static void bookingWizardFlow() {
    User u = pmsUser();
    System.runAs(u) {
      PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
      Date monday = PMS_TestDataFactory.futureMonday();
      Assert.isFalse(PMS_UIController.getEnabledModules().isEmpty());
      Assert.areEqual(1, PMS_UIController.getSites('Hotel').size());
      Assert.areEqual(1, PMS_UIController.getSpaceTypes(h.site.Id).size());
      Assert.areEqual(
        1,
        PMS_UIController.getRatePlans(h.site.Id, 'Hotel').size()
      );

      List<PMS_UIController.SearchResult> found = PMS_UIController.searchAvailability(
        'Hotel',
        h.site.Id,
        h.doubleRoom.Id,
        h.plan.Id,
        monday,
        monday.addDays(2),
        2
      );
      Assert.areEqual(2, found.size());
      PMS_TestDataFactory.num(2688, found[0].quote.gross, 'quoted total');

      Map<String, Object> req = new Map<String, Object>{
        'module' => 'Hotel',
        'siteId' => h.site.Id,
        'spaceId' => found[0].spaceId,
        'spaceTypeId' => h.doubleRoom.Id,
        'ratePlanId' => h.plan.Id,
        'accountId' => h.guestAccount.Id,
        'startDate' => String.valueOf(monday),
        'endDate' => String.valueOf(monday.addDays(2)),
        'adults' => 2
      };
      Id bookingId = PMS_UIController.createBooking(JSON.serialize(req));
      Assert.isNotNull(bookingId);
      try {
        PMS_UIController.createBooking(JSON.serialize(req));
        Assert.fail('Same room twice should fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('already booked'),
          e.getMessage()
        );
      }

      PMS_UIController.GridData grid = PMS_UIController.getRoomGrid(
        h.site.Id,
        monday.addDays(-1),
        14
      );
      Assert.areEqual(2, grid.rooms.size());
      Assert.areEqual(1, grid.bookings.size());
      Assert.areEqual(monday, grid.bookings[0].startDate);

      Id otherRoom = found[1].spaceId;
      PMS_UIController.moveBooking(bookingId, otherRoom, monday.addDays(1));
      Assert.areEqual(
        otherRoom,
        [SELECT Space__c FROM PMS_Booking__c WHERE Id = :bookingId].Space__c
      );
    }
  }

  @isTest
  static void frontDeskFlow() {
    User u = pmsUser();
    System.runAs(u) {
      PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
      Date today = PMS_DateUtil.toLocalDate(Datetime.now(), 'Europe/Stockholm');
      PMS_Booking__c b = PMS_BookingService.createBooking(
        PMS_TestDataFactory.hotelRequest(h, today, 1)
      );

      PMS_UIController.DeskData desk = PMS_UIController.getFrontDesk(
        h.site.Id,
        today
      );
      Assert.areEqual(1, desk.arrivals.size());
      Assert.areEqual(2, desk.totalRooms);

      PMS_UIController.checkIn(b.Id, null);
      desk = PMS_UIController.getFrontDesk(h.site.Id, today);
      Assert.areEqual(1, desk.inHouse.size());

      PMS_UIController.checkOut(b.Id);
      Assert.areEqual(
        'Completed',
        [SELECT Status__c FROM PMS_Booking__c WHERE Id = :b.Id].Status__c
      );
      try {
        PMS_UIController.checkOut(b.Id);
        Assert.fail('Already checked out');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
  }

  @isTest
  static void rentRollFlow() {
    User u = pmsUser();
    System.runAs(u) {
      PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
      insert new PMS_Space__c(
        Name = 'A-102',
        RecordTypeId = PMS_TestDataFactory.rt(PMS_Space__c.SObjectType, 'Unit'),
        Site__c = p.site.Id,
        Bookable__c = true
      );
      PMS_BookingService.BookingRequest r = new PMS_BookingService.BookingRequest();
      r.module = 'Property';
      r.siteId = p.site.Id;
      r.spaceId = p.unit.Id;
      r.accountId = p.tenant.Id;
      r.startDate = Date.today().addMonths(-1);
      r.endDate = Date.today().addMonths(11);
      r.status = 'Active';
      PMS_Booking__c lease = PMS_BookingService.createBooking(r);
      insert new PMS_Invoice__c(
        RecordTypeId = PMS_ModuleConfig.invoiceRecordTypeId('Property'),
        Account__c = p.tenant.Id,
        Booking__c = lease.Id,
        Issue_Date__c = Date.today().addDays(-20),
        Due_Date__c = Date.today().addDays(-10),
        Subtotal__c = 9000,
        Tax_Total__c = 0,
        Amount_Paid__c = 0,
        Status__c = 'Overdue'
      );
      PMS_UIController.RentRoll rr = PMS_UIController.getRentRoll(p.site.Id);
      Assert.areEqual(2, rr.units);
      Assert.areEqual(1, rr.occupied);
      PMS_TestDataFactory.num(50, rr.occupancyPct, 'occupancy');
      PMS_TestDataFactory.num(9000, rr.monthlyRent, 'monthly rent');
      PMS_TestDataFactory.num(9000, rr.totalArrears, 'arrears');
    }
  }

  @isTest
  static void ganttFlow() {
    User u = pmsUser();
    System.runAs(u) {
      PMS_Project__c p = PMS_TestDataFactory.projectWithTasks();
      PMS_UIController.GanttData g = PMS_UIController.getGantt(p.Id);
      Assert.areEqual(3, g.tasks.size(), 'Two tasks and one milestone');
      Assert.areEqual('Office Fit-out', g.projectName);
      PMS_UIController.GanttTask t = g.tasks[0];
      PMS_UIController.updateTaskDates(
        t.id,
        Date.today().addDays(1),
        Date.today().addDays(12)
      );
      Assert.areEqual(
        Date.today().addDays(12),
        [SELECT End_Date__c FROM PMS_Project_Task__c WHERE Id = :t.id]
        .End_Date__c
      );
      try {
        PMS_UIController.updateTaskDates(
          t.id,
          Date.today().addDays(5),
          Date.today()
        );
        Assert.fail('End before start');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
  }

  @isTest
  static void practiceDiaryFlow() {
    User u = pmsUser();
    System.runAs(u) {
      PMS_TestDataFactory.Practice pr = PMS_TestDataFactory.practice();
      Date monday = PMS_TestDataFactory.futureMonday();
      Assert.areEqual(1, PMS_UIController.getServices().size());

      List<Datetime> slots = PMS_UIController.getFreeSlots(
        pr.practitioner.Id,
        pr.service.Id,
        monday
      );
      Assert.areEqual(
        31,
        slots.size(),
        '08:00-16:00, 30 min service, 15 min steps'
      );
      Assert.areEqual(
        0,
        PMS_UIController.getFreeSlots(
            pr.practitioner.Id,
            pr.service.Id,
            monday.addDays(5)
          )
          .size(),
        'Hours without days apply on weekdays only'
      );

      Id apptId = PMS_UIController.bookAppointment(
        pr.practitioner.Id,
        pr.service.Id,
        pr.client.Id,
        null,
        slots[0],
        'Video'
      );
      Assert.isNotNull(apptId);
      Assert.areEqual(
        29,
        PMS_UIController.getFreeSlots(pr.practitioner.Id, pr.service.Id, monday)
          .size(),
        'Overlapping starts are gone'
      );

      PMS_UIController.CalData cal = PMS_UIController.getPractitionerWeek(
        pr.site.Id,
        monday
      );
      Assert.areEqual(1, cal.practitioners.size());
      Assert.areEqual(1, cal.appointments.size());
      Assert.areEqual('Video', cal.appointments[0].mode);

      Time[] defaults = PMS_UIController.workingHours(null);
      Assert.areEqual(Time.newInstance(9, 0, 0, 0), defaults[0]);
      Time[] parsed = PMS_UIController.workingHours('Mon-Thu 07:30 - 15:45');
      Assert.areEqual(Time.newInstance(7, 30, 0, 0), parsed[0]);
      Assert.areEqual(Time.newInstance(15, 45, 0, 0), parsed[1]);
      Assert.areEqual(
        Time.newInstance(17, 0, 0, 0),
        PMS_UIController.workingHours('flexible')[1]
      );
    }
  }

  @isTest
  static void diaryRespectsDayRanges() {
    User u = pmsUser();
    System.runAs(u) {
      PMS_TestDataFactory.Practice pr = PMS_TestDataFactory.practice();
      Date monday = PMS_TestDataFactory.futureMonday();
      Date friday = monday.addDays(4);
      Date saturday = monday.addDays(5);

      update new PMS_Practitioner__c(
        Id = pr.practitioner.Id,
        Working_Hours__c = 'Mon-Fri 08:00-16:00'
      );
      Assert.areEqual(
        31,
        PMS_UIController.getFreeSlots(pr.practitioner.Id, pr.service.Id, friday)
          .size(),
        'Friday is a working day'
      );
      Assert.areEqual(
        0,
        PMS_UIController.getFreeSlots(
            pr.practitioner.Id,
            pr.service.Id,
            saturday
          )
          .size(),
        'No Saturday slots for Mon-Fri'
      );

      update new PMS_Practitioner__c(
        Id = pr.practitioner.Id,
        Working_Hours__c = 'Tue-Sat 09:00-17:00'
      );
      Assert.areEqual(
        0,
        PMS_UIController.getFreeSlots(pr.practitioner.Id, pr.service.Id, monday)
          .size(),
        'No Monday slots for Tue-Sat'
      );
      List<Datetime> sat = PMS_UIController.getFreeSlots(
        pr.practitioner.Id,
        pr.service.Id,
        saturday
      );
      Assert.areEqual(31, sat.size(), 'Saturday 09:00-17:00');
      Assert.areEqual(
        Datetime.newInstance(saturday, Time.newInstance(9, 0, 0, 0)),
        sat[0]
      );

      update new PMS_Site__c(Id = pr.site.Id, Time_Zone__c = 'Asia/Colombo');
      sat = PMS_UIController.getFreeSlots(
        pr.practitioner.Id,
        pr.service.Id,
        saturday
      );
      Assert.areEqual(
        PMS_DateUtil.toDatetime(
          saturday,
          Time.newInstance(9, 0, 0, 0),
          'Asia/Colombo'
        ),
        sat[0],
        'Clinic time zone'
      );
    }
  }
}
