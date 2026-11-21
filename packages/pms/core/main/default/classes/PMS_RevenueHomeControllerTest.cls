@isTest
private class PMS_RevenueHomeControllerTest {
  static void assign(String permissionSetName) {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :permissionSetName
      ];
      if (
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE PermissionSetId = :ps.Id AND AssigneeId = :me.Id
        ] == 0
      ) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps.Id,
          AssigneeId = me.Id
        );
      }
    }
  }

  @TestSetup
  static void setup() {
    assign('PMS_Core_Admin');
    assign('PMS_App_Access');
  }

  static PMS_RevenueHomeController.Item find(
    PMS_RevenueHomeController.Result res,
    String key
  ) {
    for (PMS_RevenueHomeController.Item it : res.items) {
      if (it.key == key) {
        return it;
      }
    }
    return null;
  }

  static Boolean singleCurrency() {
    return !UserInfo.isMultiCurrencyOrganization();
  }

  /** Hotel data that triggers the five booking/invoice attention queries plus OTA and channel blocks. */
  static PMS_TestDataFactory.Hotel seedHotel() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
    Id resRt = PMS_TestDataFactory.rt(
      PMS_Booking__c.SObjectType,
      'Reservation'
    );
    List<PMS_Booking__c> bookings = new List<PMS_Booking__c>();
    // cards
    bookings.add(
      new PMS_Booking__c(
        RecordTypeId = resRt,
        Site__c = h.site.Id,
        Space__c = h.rooms[0].Id,
        Account__c = h.guestAccount.Id,
        Status__c = 'Confirmed',
        Start__c = Datetime.now().addDays(10),
        End__c = Datetime.now().addDays(12),
        Guarantee_Status__c = 'Action Needed'
      )
    );
    // holds
    bookings.add(
      new PMS_Booking__c(
        RecordTypeId = resRt,
        Site__c = h.site.Id,
        Space__c = h.rooms[1].Id,
        Account__c = h.guestAccount.Id,
        Status__c = 'Confirmed',
        Start__c = Datetime.now().addDays(1),
        End__c = Datetime.now().addDays(3),
        Preauth_Status__c = 'Authorized',
        Preauth_Amount__c = 750,
        Preauth_Expires_At__c = Datetime.now().addHours(5)
      )
    );
    // fees
    bookings.add(
      new PMS_Booking__c(
        RecordTypeId = resRt,
        Site__c = h.site.Id,
        Space__c = h.rooms[0].Id,
        Account__c = h.guestAccount.Id,
        Status__c = 'Cancelled',
        Start__c = Datetime.now().addDays(20),
        End__c = Datetime.now().addDays(22),
        Policy_Pending__c = true,
        Policy_Fee_Amount__c = 500,
        Policy_Event_At__c = Datetime.now()
      )
    );
    // refunds
    bookings.add(
      new PMS_Booking__c(
        RecordTypeId = resRt,
        Site__c = h.site.Id,
        Space__c = h.rooms[1].Id,
        Account__c = h.guestAccount.Id,
        Status__c = 'Cancelled',
        Start__c = Datetime.now().addDays(30),
        End__c = Datetime.now().addDays(32),
        Refund_Due__c = 250
      )
    );
    // OTA booking without a room
    bookings.add(
      new PMS_Booking__c(
        RecordTypeId = resRt,
        Site__c = h.site.Id,
        Account__c = h.guestAccount.Id,
        Status__c = 'Confirmed',
        Start__c = Datetime.now().addDays(40),
        End__c = Datetime.now().addDays(42),
        OTA_Name__c = 'Booking.com',
        OTA_Reservation_Code__c = '4711'
      )
    );
    insert bookings;

    PMS_Invoice__c inv = new PMS_Invoice__c(
      RecordTypeId = PMS_TestDataFactory.rt(
        PMS_Invoice__c.SObjectType,
        'Folio'
      ),
      Account__c = h.guestAccount.Id,
      Status__c = 'Issued',
      Issue_Date__c = Date.today().addDays(-60),
      Due_Date__c = Date.today().addDays(-45),
      Subtotal__c = 500,
      Currency_Code__c = 'NOK', // differs from the site (SEK) and from the org default
      Dunning_Stage__c = 'Collections'
    );
    insert inv;
    PMS_Payment_Plan__c plan = new PMS_Payment_Plan__c(
      Invoice__c = inv.Id,
      Account__c = h.guestAccount.Id
    );
    insert plan;
    insert new PMS_Payment_Plan_Instalment__c(
      Plan__c = plan.Id,
      Number__c = 1,
      Due_Date__c = Date.today().addDays(-3),
      Amount__c = 100
    );
    insert new PMS_Channel_Log__c(
      Site__c = h.site.Id,
      Status__c = 'Error',
      Kind__c = 'Availability',
      Message__c = 'Push failed'
    );
    return h;
  }

  @isTest
  static void hotelAttentionShowsEveryBlock() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      seedHotel();
      Test.startTest();
      PMS_RevenueHomeController.Result res = PMS_RevenueHomeController.getAttention(
        'Hotel'
      );
      Test.stopTest();
      Assert.isTrue(res.warnings.isEmpty(), 'Warnings: ' + res.warnings);
      Assert.isFalse(res.hideAmounts);
      for (
        String key : new List<String>{
          'cards',
          'holds',
          'fees',
          'refunds',
          'reminders',
          'instalments',
          'channelErrors',
          'otaUnassigned'
        }
      ) {
        PMS_RevenueHomeController.Item it = find(res, key);
        Assert.isNotNull(it, 'Missing item ' + key);
        Assert.isTrue(it.count >= 1, key + ' should count its record');
        Assert.isFalse(it.rows.isEmpty(), key + ' should list a row');
        Assert.isTrue(it.rows[0].url.startsWith('/lightning/r/'), key);
      }
      Assert.isNull(find(res, 'rent'), 'Hotel has no rent block');
      Assert.areEqual('error', find(res, 'cards').severity);
      Assert.areEqual('error', find(res, 'reminders').severity);
      Assert.areEqual('error', find(res, 'instalments').severity);
      Assert.areEqual('error', find(res, 'channelErrors').severity);
      Assert.areEqual('error', find(res, 'otaUnassigned').severity);
      Assert.isTrue(
        find(res, 'reminders').hintText.contains('Collections: 1'),
        find(res, 'reminders').hintText
      );
      // Booking rows use the site's currency, invoice rows the invoice's: neither is the org default.
      for (String key : new List<String>{ 'holds', 'fees', 'refunds' }) {
        Assert.isTrue(
          find(res, key).rows[0].detail.contains(' SEK'),
          key + ': ' + find(res, key).rows[0].detail
        );
      }
      for (String key : new List<String>{ 'reminders', 'instalments' }) {
        Assert.isTrue(
          find(res, key).rows[0].detail.contains(' NOK'),
          key + ': ' + find(res, key).rows[0].detail
        );
      }
    }
  }

  @isTest
  static void everyModuleLoadsWithoutWarnings() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      seedHotel();
      PMS_TestDataFactory.Property p = PMS_TestDataFactory.property();
      PMS_Booking__c lease = new PMS_Booking__c(
        RecordTypeId = PMS_TestDataFactory.rt(
          PMS_Booking__c.SObjectType,
          'Lease'
        ),
        Site__c = p.site.Id,
        Space__c = p.unit.Id,
        Account__c = p.tenant.Id,
        Status__c = 'Active',
        Start__c = Datetime.now().addDays(-400),
        End__c = Datetime.now().addDays(700)
      );
      insert lease;
      insert new PMS_Rent_Adjustment__c(
        Lease__c = lease.Id,
        Status__c = 'Draft',
        Kind__c = 'Index',
        Effective_Date__c = Date.today().addDays(60)
      );
      Test.startTest();
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
        Assert.isNotNull(res.items);
        Assert.isTrue(res.warnings.isEmpty(), m + ': ' + res.warnings);
        if (m == 'Projects') {
          Assert.isNull(find(res, 'cards'), 'Projects has no booking blocks');
        }
        if (m == 'Property' || m == 'Admin' || m == null) {
          Assert.isNotNull(find(res, 'rent'), 'rent block for ' + m);
        }
      }
      PMS_RevenueHomeController.Result prop = PMS_RevenueHomeController.getAttention(
        'Property'
      );
      Assert.areEqual(1, find(prop, 'rent').count);
      Test.stopTest();
    }
  }

  @isTest
  static void hideAmountsPermissionRemovesMoney() {
    assign('PMS_Hide_Amounts');
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      seedHotel();
      Test.startTest();
      PMS_RevenueHomeController.Result res = PMS_RevenueHomeController.getAttention(
        'Hotel'
      );
      Test.stopTest();
      Assert.isTrue(res.hideAmounts, 'permission is picked up');
      Assert.isTrue(res.warnings.isEmpty(), 'Warnings: ' + res.warnings);
      String cur = 'SEK'; // the site's currency
      for (String key : new List<String>{ 'holds', 'fees', 'refunds' }) {
        PMS_RevenueHomeController.Item it = find(res, key);
        Assert.isNotNull(it, key);
        for (PMS_RevenueHomeController.Row r : it.rows) {
          Assert.isFalse(
            String.isNotBlank(r.detail) && r.detail.contains(' ' + cur),
            key + ' must not show amounts: ' + r.detail
          );
        }
      }
    }
  }

  @isTest
  static void reportIdsNeverFails() {
    // Reports are not visible to tests without SeeAllData: the call must be safe and every
    // configured key must have a developer name and a report name.
    Map<String, Id> ids = PMS_RevenueHomeController.reportIds();
    Assert.isNotNull(ids);
    for (String key : PMS_RevenueHomeController.REPORTS.keySet()) {
      List<String> r = PMS_RevenueHomeController.REPORTS.get(key);
      Assert.areEqual(2, r.size(), 'Developer name and name for ' + key);
    }
    Assert.isTrue(
      PMS_RevenueHomeController.REPORTS.containsKey('channelErrors'),
      'The channel errors tile has a report'
    );
  }

  @isTest
  static void recordTypeHelpers() {
    Assert.areEqual(
      'Reservation',
      PMS_RevenueHomeController.bookingRecordType('Hotel')
    );
    Assert.areEqual(
      'Lease',
      PMS_RevenueHomeController.bookingRecordType('Property')
    );
    Assert.areEqual(
      'Appointment',
      PMS_RevenueHomeController.bookingRecordType('Practice')
    );
    Assert.isNull(PMS_RevenueHomeController.bookingRecordType('Admin'));
    Assert.areEqual(
      'Folio',
      PMS_RevenueHomeController.invoiceRecordType('Hotel')
    );
    Assert.areEqual(
      'Client_Bill',
      PMS_RevenueHomeController.invoiceRecordType('Practice')
    );
    Assert.areEqual(
      'Project_Invoice',
      PMS_RevenueHomeController.invoiceRecordType('Projects')
    );
    Assert.areEqual(
      'Rent_Invoice',
      PMS_RevenueHomeController.invoiceRecordType('Property')
    );
    Assert.isNull(PMS_RevenueHomeController.invoiceRecordType('Admin'));
  }

  @isTest
  static void formattingHelpers() {
    Assert.areEqual(
      'a · b',
      PMS_RevenueHomeController.join(new List<String>{ 'a', null, '', 'b' })
    );
    Assert.areEqual(
      '',
      PMS_RevenueHomeController.join(new List<String>{ null, '' })
    );
    Decimal amt = 12.5;
    String fmtAmount = amt.setScale(2).format();
    String expected = fmtAmount + ' SEK';
    Assert.areEqual(expected, PMS_RevenueHomeController.money(12.5, 'SEK'));
    Assert.areEqual(fmtAmount, PMS_RevenueHomeController.money(12.5, null));
    Assert.isNull(PMS_RevenueHomeController.money(null, 'SEK'));
    PMS_RevenueHomeController.hideAmounts = true;
    Assert.isNull(
      PMS_RevenueHomeController.money(12.5, 'SEK'),
      'Amounts are hidden'
    );
    PMS_RevenueHomeController.hideAmounts = false;
    Assert.isNull(PMS_RevenueHomeController.fmt((Date) null));
    Assert.isNull(PMS_RevenueHomeController.fmt((Datetime) null));
    Assert.isNotNull(PMS_RevenueHomeController.fmt(Date.today()));
    Assert.isNotNull(PMS_RevenueHomeController.fmt(Datetime.now()));
    if (singleCurrency()) {
      Assert.areEqual('', PMS_RevenueHomeController.cur());
    } else {
      Assert.areEqual(', CurrencyIsoCode', PMS_RevenueHomeController.cur());
    }
  }

  @isTest
  static void currencyPrefersRecordCodeThenIsoThenOrgDefault() {
    Assert.areEqual(
      'SEK',
      PMS_RevenueHomeController.iso(
        new PMS_Invoice__c(Currency_Code__c = 'SEK'),
        'Currency_Code__c'
      )
    );
    PMS_Booking__c b = new PMS_Booking__c(
      Site__r = new PMS_Site__c(Currency_Code__c = 'NOK')
    );
    Assert.areEqual(
      'NOK',
      PMS_RevenueHomeController.iso(b, 'Site__r.Currency_Code__c')
    );
    PMS_Payment_Plan_Instalment__c i = new PMS_Payment_Plan_Instalment__c(
      Plan__r = new PMS_Payment_Plan__c(
        Invoice__r = new PMS_Invoice__c(Currency_Code__c = 'DKK')
      )
    );
    Assert.areEqual(
      'DKK',
      PMS_RevenueHomeController.iso(i, 'Plan__r.Invoice__r.Currency_Code__c')
    );

    String expected = UserInfo.getDefaultCurrency();
    PMS_Invoice__c blank = new PMS_Invoice__c(Currency_Code__c = ' ');
    if (UserInfo.isMultiCurrencyOrganization()) {
      blank.put('CurrencyIsoCode', expected);
    }
    Assert.areEqual(
      expected,
      PMS_RevenueHomeController.iso(blank, 'Currency_Code__c')
    );
    Assert.areEqual(
      expected,
      PMS_RevenueHomeController.iso(
        new PMS_Booking__c(),
        'Site__r.Currency_Code__c'
      ),
      'no site loaded: falls back'
    );
  }
}
