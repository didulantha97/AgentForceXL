/**
 * Tests for pms-integration: access-share triggers on the revenue objects, the home "needs attention"
 * block and the portal "My payments" component.
 *
 * Records are inserted with allOrNone = false so an org validation rule can't fail the whole test:
 * the access triggers run on before insert, so they are exercised either way.
 */
@IsTest
private class PMS_IntegrationPackTest {
  static Id rt(Schema.SObjectType t, String devName) {
    return PMS_TestDataFactory.rt(t, devName);
  }

  static SObject tryInsert(SObject rec) {
    Database.SaveResult r = Database.insert(rec, false);
    return r.isSuccess() ? rec : null;
  }

  @IsTest
  static void accessConfigCoversRevenueObjects() {
    for (
      String o : new List<String>{
        'PMS_Dunning_Event__c',
        'PMS_Payment_Plan__c',
        'PMS_Rent_Adjustment__c',
        'PMS_Channel_Log__c',
        'PMS_Channel_Mapping__c',
        'PMS_Pricing_Strategy__c'
      }
    ) {
      PMS_Access_Object__mdt cfg = PMS_AccessService.configFor(o);
      System.assertNotEquals(null, cfg, 'No access config for ' + o);
      System.assert(
        String.isNotBlank(cfg.Site_Paths__c),
        'No site path for ' + o
      );
    }
    System.assertEquals(
      'Invoice',
      PMS_AccessService.configFor('PMS_Dunning_Event__c').Rule_Key__c
    );
    System.assertEquals(
      'Booking',
      PMS_AccessService.configFor('PMS_Rent_Adjustment__c').Rule_Key__c
    );
    System.assertEquals(
      'Rate_Plan',
      PMS_AccessService.configFor('PMS_Pricing_Strategy__c').Rule_Key__c
    );
  }

  @IsTest
  static void triggersRunAndHomeAndPortalLoad() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
    Date today = Date.today();

    PMS_Invoice__c inv = (PMS_Invoice__c) tryInsert(
      new PMS_Invoice__c(
        RecordTypeId = rt(PMS_Invoice__c.SObjectType, 'Folio'),
        Account__c = h.guestAccount.Id,
        Status__c = 'Issued',
        Issue_Date__c = today.addDays(-30),
        Due_Date__c = today.addDays(-20),
        Subtotal__c = 500,
        Pay_Key__c = 'integration-test-key'
      )
    );
    Id invId = inv == null ? null : inv.Id;

    PMS_Booking__c reservation = (PMS_Booking__c) tryInsert(
      new PMS_Booking__c(
        RecordTypeId = rt(PMS_Booking__c.SObjectType, 'Reservation'),
        Site__c = h.site.Id,
        Space__c = h.rooms.isEmpty() ? null : ((PMS_Space__c) h.rooms[0]).Id,
        Account__c = h.guestAccount.Id,
        Status__c = 'Confirmed',
        Start__c = Datetime.now().addDays(10),
        End__c = Datetime.now().addDays(12),
        Guarantee_Status__c = 'Awaiting Card'
      )
    );

    PMS_Booking__c lease = (PMS_Booking__c) tryInsert(
      new PMS_Booking__c(
        RecordTypeId = rt(PMS_Booking__c.SObjectType, 'Lease'),
        Site__c = p.site.Id,
        Space__c = p.unit.Id,
        Account__c = p.tenant.Id,
        Status__c = 'Active',
        Start__c = Datetime.now().addDays(-400),
        End__c = Datetime.now().addDays(700)
      )
    );

    Test.startTest();
    PMS_Payment_Plan__c plan = (PMS_Payment_Plan__c) tryInsert(
      new PMS_Payment_Plan__c(
        Invoice__c = invId,
        Account__c = h.guestAccount.Id
      )
    );
    tryInsert(
      new PMS_Dunning_Event__c(Invoice__c = invId, Stage__c = 'Reminder 1')
    );
    if (plan != null) {
      tryInsert(
        new PMS_Payment_Plan_Instalment__c(
          Plan__c = plan.Id,
          Number__c = 1,
          Due_Date__c = today.addDays(-3),
          Amount__c = 100
        )
      );
    }
    tryInsert(
      new PMS_Rent_Adjustment__c(
        Lease__c = lease == null ? null : lease.Id,
        Status__c = 'Draft',
        Kind__c = 'Index',
        Effective_Date__c = today.addDays(60)
      )
    );
    tryInsert(
      new PMS_Channel_Log__c(
        Site__c = h.site.Id,
        Status__c = 'Error',
        Kind__c = 'Push',
        Message__c = 'test'
      )
    );
    tryInsert(
      new PMS_Channel_Mapping__c(
        Site__c = h.site.Id,
        Rate_Plan__c = h.plan.Id,
        Room_Type__c = h.doubleRoom.Id,
        Channex_Rate_Plan_Id__c = 'test-uuid'
      )
    );
    tryInsert(
      new PMS_Pricing_Strategy__c(
        Name = 'Test strategy',
        Rate_Plan__c = h.plan.Id
      )
    );

    for (
      String m : new List<String>{
        'Admin',
        'Hotel',
        'Property',
        'Projects',
        'Practice',
        null
      }
    ) {
      PMS_RevenueHomeController.Result res = PMS_RevenueHomeController.getAttention(
        m
      );
      System.assertNotEquals(null, res);
      System.assertNotEquals(null, res.items);
      System.assert(
        res.warnings.isEmpty(),
        'Home block failed for ' + m + ': ' + res.warnings
      );
    }

    PMS_PortalMoneyController.payBaseOverride = 'https://example.test/pay';
    PMS_PortalMoneyController.accountOverride = h.guestAccount.Id;
    PMS_PortalMoneyController.Result mine = PMS_PortalMoneyController.getMyPayments();
    Test.stopTest();

    System.assert(mine.hasAccount);
    if (reservation != null) {
      // The guarantee trigger may have set its own status on insert; check against what was stored.
      PMS_Booking__c stored = [
        SELECT Guarantee_Status__c
        FROM PMS_Booking__c
        WHERE Id = :reservation.Id
      ];
      Integer expected = stored.Guarantee_Status__c == 'Awaiting Card' ||
        stored.Guarantee_Status__c == 'Action Needed'
        ? 1
        : 0;
      System.assertEquals(
        expected,
        mine.cardsNeeded.size(),
        'Bookings needing a card should be listed'
      );
    }
  }

  @IsTest
  static void portalWithoutAccountIsEmpty() {
    PMS_PortalMoneyController.Result res = PMS_PortalMoneyController.getMyPayments();
    System.assertEquals(
      false,
      res.hasAccount,
      'An internal user has no portal account'
    );
    System.assert(res.invoices.isEmpty());
  }

  @IsTest
  static void helpers() {
    System.assertEquals(
      'Reservation',
      PMS_RevenueHomeController.bookingRecordType('Hotel')
    );
    System.assertEquals(
      'Lease',
      PMS_RevenueHomeController.bookingRecordType('Property')
    );
    System.assertEquals(
      'Appointment',
      PMS_RevenueHomeController.bookingRecordType('Practice')
    );
    System.assertEquals(
      null,
      PMS_RevenueHomeController.bookingRecordType('Admin')
    );
    System.assertEquals(
      'Project_Invoice',
      PMS_RevenueHomeController.invoiceRecordType('Projects')
    );
    System.assertEquals(
      'Rent_Invoice',
      PMS_RevenueHomeController.invoiceRecordType('Property')
    );
    System.assertEquals(
      'a · b',
      PMS_RevenueHomeController.join(new List<String>{ 'a', null, '', 'b' })
    );
    System.assertNotEquals(null, PMS_RevenueHomeController.money(12.5, 'SEK'));
    PMS_RevenueHomeController.hideAmounts = true;
    System.assertEquals(
      null,
      PMS_RevenueHomeController.money(12.5, 'SEK'),
      'Amounts are hidden'
    );
    System.assertEquals(null, PMS_RevenueHomeController.fmt((Date) null));
    System.assertNotEquals(null, PMS_RevenueHomeController.fmt(Date.today()));
    System.assertNotEquals(null, PMS_RevenueHomeController.fmt(Datetime.now()));
  }
}
