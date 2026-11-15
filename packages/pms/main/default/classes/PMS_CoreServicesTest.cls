@isTest
private class PMS_CoreServicesTest {
  @isTest
  static void dateUtilBasics() {
    Date monday = PMS_TestDataFactory.futureMonday();
    Assert.areEqual('Monday', PMS_DateUtil.dayName(monday));
    Assert.areEqual('Saturday', PMS_DateUtil.dayName(monday.addDays(5)));
    Assert.isTrue(PMS_DateUtil.isWeekend(monday.addDays(6)));
    Assert.isFalse(PMS_DateUtil.isWeekend(monday));
    Assert.areEqual(3, PMS_DateUtil.nightsBetween(monday, monday.addDays(3)));
    Assert.areEqual(0, PMS_DateUtil.nightsBetween(null, monday));
    Assert.areEqual(
      12,
      PMS_DateUtil.monthsBetween(
        Date.newInstance(2027, 1, 1),
        Date.newInstance(2028, 1, 1)
      )
    );
    Assert.areEqual(
      2,
      PMS_DateUtil.monthsBetween(
        Date.newInstance(2027, 1, 1),
        Date.newInstance(2027, 2, 15)
      )
    );
    Assert.areEqual(
      Date.newInstance(2027, 2, 1),
      PMS_DateUtil.addFrequency(Date.newInstance(2027, 1, 1), 'Monthly')
    );
    Assert.areEqual(
      Date.newInstance(2027, 4, 1),
      PMS_DateUtil.addFrequency(Date.newInstance(2027, 1, 1), 'Quarterly')
    );
    Assert.areEqual(
      Date.newInstance(2027, 1, 8),
      PMS_DateUtil.addFrequency(Date.newInstance(2027, 1, 1), 'Weekly')
    );
    Assert.areEqual(
      Date.newInstance(2028, 1, 1),
      PMS_DateUtil.addFrequency(Date.newInstance(2027, 1, 1), 'Annually')
    );

    Datetime dt = PMS_DateUtil.toDatetime(
      Date.newInstance(2027, 1, 15),
      Time.newInstance(15, 0, 0, 0),
      'Europe/Stockholm'
    );
    Assert.areEqual(
      '2027-01-15 14:00',
      dt.formatGmt('yyyy-MM-dd HH:mm'),
      'Stockholm is UTC+1 in winter'
    );
    Assert.areEqual(
      Date.newInstance(2027, 1, 15),
      PMS_DateUtil.toLocalDate(dt, 'Europe/Stockholm')
    );
    Assert.isNotNull(PMS_DateUtil.toDatetime(Date.today(), null, null));
    Assert.isNull(PMS_DateUtil.toLocalDate(null, 'Europe/Stockholm'));
  }

  @isTest
  static void moduleConfigReadsSwitchboard() {
    Assert.isTrue(PMS_ModuleConfig.enabledModules().size() > 0);
    Assert.isNotNull(PMS_ModuleConfig.bookingRecordTypeId('Hotel'));
    Assert.isNotNull(PMS_ModuleConfig.invoiceRecordTypeId('Property'));
    Assert.areEqual(
      'Hotel',
      PMS_ModuleConfig.moduleForBookingRecordType(
        PMS_ModuleConfig.bookingRecordTypeId('Hotel')
      )
    );
    Assert.isNull(PMS_ModuleConfig.moduleForBookingRecordType(null));
    Assert.areEqual(30, PMS_ModuleConfig.invoiceDueDays('NoSuchModule'));
    Assert.areEqual(0, PMS_ModuleConfig.defaultTaxRate('NoSuchModule'));
    Assert.areEqual('Per Night', PMS_ModuleConfig.pricingBasis('NoSuchModule'));
    Assert.isNull(PMS_ModuleConfig.recordTypeId(PMS_Site__c.SObjectType, ''));
  }

  @isTest
  static void pricingUsesWeekdayAndWeekendRates() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Date monday = PMS_TestDataFactory.futureMonday();
    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = 'Hotel';
    qr.ratePlanId = h.plan.Id;
    qr.spaceTypeId = h.doubleRoom.Id;
    qr.startDate = monday.addDays(3); // Thursday
    qr.endDate = monday.addDays(6); // Sunday: Thu + Fri + Sat nights
    PMS_PricingService.Quote q = PMS_PricingService.quote(qr);
    PMS_TestDataFactory.num(3, q.units, 'units');
    PMS_TestDataFactory.num(4200, q.net, 'net');
    PMS_TestDataFactory.num(12, q.taxRate, 'tax rate');
    PMS_TestDataFactory.num(504, q.tax, 'tax');
    PMS_TestDataFactory.num(4704, q.gross, 'gross');
    Assert.areEqual(3, q.lines.size());
  }

  @isTest
  static void pricingFallsBackWithoutPlan() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = 'Hotel';
    qr.spaceTypeId = h.doubleRoom.Id;
    qr.spaceId = h.rooms[0].Id;
    qr.startDate = Date.today().addDays(10);
    qr.endDate = Date.today().addDays(12);
    PMS_PricingService.Quote q = PMS_PricingService.quote(qr);
    PMS_TestDataFactory.num(
      2000,
      q.net,
      'Space type default rate 1000 x 2 nights'
    );

    PMS_TestDataFactory.Practice pr = PMS_TestDataFactory.practice();
    PMS_PricingService.QuoteRequest sq = new PMS_PricingService.QuoteRequest();
    sq.module = 'Practice';
    sq.serviceId = pr.service.Id;
    sq.startDate = Date.today().addDays(5);
    sq.endDate = sq.startDate;
    sq.hours = 0.5;
    PMS_TestDataFactory.num(
      400,
      PMS_PricingService.quote(sq).net,
      'Per hour: 800 x 0.5'
    );

    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    PMS_PricingService.QuoteRequest lq = new PMS_PricingService.QuoteRequest();
    lq.module = 'Property';
    lq.spaceId = p.unit.Id;
    lq.startDate = Date.newInstance(2027, 1, 1);
    lq.endDate = Date.newInstance(2027, 7, 1);
    PMS_PricingService.Quote leaseQuote = PMS_PricingService.quote(lq);
    PMS_TestDataFactory.num(6, leaseQuote.units, 'months');
    PMS_TestDataFactory.num(9000, leaseQuote.unitPrice, 'rent');
  }

  @isTest
  static void availabilityExcludesBusyAndOutOfOrderRooms() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(3);
    Date d = Date.today().addDays(20);
    Datetime s = PMS_DateUtil.toDatetime(
      d,
      Time.newInstance(15, 0, 0, 0),
      'Europe/Stockholm'
    );
    Datetime e = PMS_DateUtil.toDatetime(
      d.addDays(2),
      Time.newInstance(11, 0, 0, 0),
      'Europe/Stockholm'
    );
    Assert.areEqual(
      3,
      PMS_AvailabilityService.findAvailableSpaces(
          h.site.Id,
          h.doubleRoom.Id,
          s,
          e,
          2
        )
        .size()
    );

    h.rooms[2].Operational_Status__c = 'Out of Order';
    update h.rooms[2];
    insert new PMS_Booking__c(
      RecordTypeId = PMS_ModuleConfig.bookingRecordTypeId('Hotel'),
      Site__c = h.site.Id,
      Space__c = h.rooms[0].Id,
      Start__c = s,
      End__c = e,
      Status__c = 'Confirmed'
    );
    Assert.areEqual(
      1,
      PMS_AvailabilityService.findAvailableSpaces(
          h.site.Id,
          h.doubleRoom.Id,
          s,
          e,
          2
        )
        .size()
    );
    Assert.isFalse(
      PMS_AvailabilityService.isSpaceAvailable(h.rooms[0].Id, s, e, null)
    );
    Assert.isTrue(
      PMS_AvailabilityService.isSpaceAvailable(
        h.rooms[0].Id,
        e,
        e.addDays(1),
        null
      ),
      'Back-to-back stays are allowed'
    );
    Assert.areEqual(
      1,
      PMS_AvailabilityService.availableCountByType(h.site.Id, s, e, 1)
        .get(h.doubleRoom.Id)
    );
    Assert.areEqual(
      0,
      PMS_AvailabilityService.findAvailableSpaces(
          h.site.Id,
          h.doubleRoom.Id,
          s,
          e,
          3
        )
        .size(),
      'Too many guests'
    );
    Assert.isTrue(
      PMS_AvailabilityService.busySpaceIds(null, s, e, null).isEmpty()
    );
  }
}
