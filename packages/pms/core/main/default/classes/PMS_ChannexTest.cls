@isTest
private class PMS_ChannexTest {
  private static final String PROPERTY = '716305c4-561a-4561-a187-7f5b8aeb5920';
  private static final String ROOM_TYPE = 'bab451e7-9ab1-4cc4-aa16-107bf7bbabb2';
  private static final String RATE_PLAN = '445835fb-7956-42ac-9efc-3e6f331f0808';

  private class ChannexMock implements HttpCalloutMock {
    public List<HttpRequest> calls = new List<HttpRequest>();
    public String feed = '{"data":[],"meta":{"total":0}}';
    public Boolean warn = false;
    public HttpResponse respond(HttpRequest req) {
      calls.add(req);
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String ep = req.getEndpoint();
      if (ep.contains('/booking_revisions/feed')) {
        res.setBody(feed);
      } else if (ep.endsWith('/ack')) {
        res.setBody('{"meta":{"message":"Success"}}');
      } else if (ep.endsWith('/availability') || ep.endsWith('/restrictions')) {
        res.setBody(
          warn
            ? '{"data":[],"meta":{"message":"Success","warnings":[{"rate":"0","warning":{"rate":["must be greater than 0"]}}]}}'
            : '{"data":[{"id":"t1","type":"task"}],"meta":{"message":"Success","warnings":[]}}'
        );
      } else {
        res.setStatusCode(404);
        res.setBody('{"errors":{"code":"not_found","title":"Not found"}}');
      }
      return res;
    }
    String bodyOf(String suffix) {
      for (HttpRequest r : calls) {
        if (r.getEndpoint().endsWith(suffix)) {
          return r.getBody();
        }
      }
      return null;
    }
  }

  private class RawMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    RawMock(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statusCode);
      res.setBody(responseBody);
      return res;
    }
  }

  @TestSetup
  static void setup() {
    insert new PMS_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Channex_Enabled__c = true,
      Channex_Horizon_Days__c = 14
    );
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
    update new PMS_Site__c(
      Id = h.site.Id,
      Channex_Property_Id__c = PROPERTY,
      Channex_Prices_Include_VAT__c = true
    );
    update new PMS_Space_Type__c(
      Id = h.doubleRoom.Id,
      Channex_Room_Type_Id__c = ROOM_TYPE
    );
    insert new PMS_Channel_Mapping__c(
      Name = 'BAR Double',
      Site__c = h.site.Id,
      Rate_Plan__c = h.plan.Id,
      Room_Type__c = h.doubleRoom.Id,
      Channex_Rate_Plan_Id__c = RATE_PLAN,
      Active__c = true
    );
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'PMS_Channex'
      ];
      if (
        [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :ps.Id AND AssigneeId = :me.Id
          ]
          .isEmpty()
      ) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps.Id,
          AssigneeId = me.Id
        );
      }
    }
  }

  private static PMS_Site__c site() {
    return [SELECT Id FROM PMS_Site__c LIMIT 1];
  }

  private static String revision(
    String revId,
    String status,
    Integer rooms,
    Date arrive,
    Integer nights
  ) {
    List<Object> roomList = new List<Object>();
    for (Integer i = 0; i < rooms; i++) {
      Map<String, Object> days = new Map<String, Object>();
      for (Integer n = 0; n < nights; n++) {
        days.put(String.valueOf(arrive.addDays(n)), '1344.00');
      }
      roomList.add(
        new Map<String, Object>{
          'room_type_id' => ROOM_TYPE,
          'rate_plan_id' => RATE_PLAN,
          'checkin_date' => String.valueOf(arrive),
          'checkout_date' => String.valueOf(arrive.addDays(nights)),
          'amount' => String.valueOf(1344 * nights) + '.00',
          'days' => days,
          'occupancy' => new Map<String, Object>{
            'adults' => 2,
            'children' => 0,
            'infants' => 0
          }
        }
      );
    }
    Map<String, Object> attrs = new Map<String, Object>{
      'id' => revId,
      'booking_id' => 'b0000000-0000-0000-0000-000000000001',
      'property_id' => PROPERTY,
      'status' => status,
      'ota_name' => 'Booking.com',
      'ota_reservation_code' => '4711',
      'arrival_date' => String.valueOf(arrive),
      'departure_date' => String.valueOf(arrive.addDays(nights)),
      'amount' => String.valueOf(1344 * nights * rooms) + '.00',
      'currency' => 'SEK',
      'payment_collect' => 'ota',
      'notes' => 'Late arrival',
      'customer' => new Map<String, Object>{
        'name' => 'Anna',
        'surname' => 'Svensson',
        'mail' => 'anna@guest.example.com',
        'phone' => '+46701234567'
      },
      'rooms' => roomList
    };
    return JSON.serialize(
      new Map<String, Object>{
        'data' => new List<Object>{
          new Map<String, Object>{
            'id' => revId,
            'type' => 'booking_revision',
            'attributes' => attrs
          }
        }
      }
    );
  }

  private static List<Map<String, Object>> parse(String feedJson) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    for (
      Object o : (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
          feedJson
        ))
        .get('data')
    ) {
      out.add(
        (Map<String, Object>) ((Map<String, Object>) o).get('attributes')
      );
    }
    return out;
  }

  // ---------------------------------------------------------------- outbound

  @isTest
  static void pushSendsAvailabilityAndVatInclusiveRates() {
    ChannexMock mock = new ChannexMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<PMS_Channel_Log__c> logs = PMS_ChannexSync.runPush(null);
    Test.stopTest();
    Assert.areEqual(2, logs.size(), JSON.serialize(logs));
    String avail = mock.bodyOf('/availability');
    Assert.isTrue(avail.contains('"availability":2'), avail);
    Assert.isTrue(avail.contains(ROOM_TYPE), avail);
    String rates = mock.bodyOf('/restrictions');
    Assert.isTrue(
      rates.contains('"rate":"1344.00"'),
      'BAR 1200 + 12% VAT: ' + rates
    );
    Assert.isTrue(
      rates.contains('"rate":"1680.00"'),
      'Fri/Sat 1500 + 12% VAT: ' + rates
    );
    Assert.isTrue(rates.contains(RATE_PLAN), rates);
    Assert.isNotNull(
      [SELECT Channex_Last_Push__c FROM PMS_Site__c LIMIT 1]
      .Channex_Last_Push__c
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Status__c = 'Success']
    );
  }

  @isTest
  static void rejectedValuesAreLoggedAsWarnings() {
    ChannexMock mock = new ChannexMock();
    mock.warn = true;
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    PMS_ChannexSync.runPush(site().Id);
    Test.stopTest();
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Status__c = 'Warning']
    );
  }

  @isTest
  static void rangesAreCompressed() {
    Date d = Date.newInstance(2027, 3, 1);
    List<PMS_ChannexAri.Night> nights = new List<PMS_ChannexAri.Night>{
      new PMS_ChannexAri.Night(d, '5', false),
      new PMS_ChannexAri.Night(d.addDays(1), '5', false),
      new PMS_ChannexAri.Night(d.addDays(2), '4', false),
      new PMS_ChannexAri.Night(d.addDays(3), '4', true),
      new PMS_ChannexAri.Night(d.addDays(5), '4', true)
    };
    List<PMS_ChannexAri.Night> out = PMS_ChannexAri.compress(nights);
    Assert.areEqual(4, out.size());
    Assert.areEqual(d.addDays(1), out[0].endNight);
    Assert.areEqual(d.addDays(2), out[1].endNight);
    Assert.areEqual(
      d.addDays(3),
      out[2].endNight,
      'stop sell starts a new range'
    );
    Assert.areEqual(d.addDays(5), out[3].night, 'gap starts a new range');
  }

  @isTest
  static void problemsAreReported() {
    update new PMS_Space_Type__c(
      Id = [SELECT Id FROM PMS_Space_Type__c LIMIT 1]
      .Id,
      Channex_Room_Type_Id__c = null
    );
    delete [SELECT Id FROM PMS_Channel_Mapping__c];
    PMS_ChannexAri.Payload p = PMS_ChannexAri.build(site().Id, Date.today(), 7);
    Assert.areEqual(0, p.availability.size());
    Assert.areEqual(0, p.restrictions.size());
    Assert.areEqual(2, p.problems.size(), String.join(p.problems, ' | '));
  }

  // ---------------------------------------------------------------- inbound

  @isTest
  static void newModifiedAndCancelledBookings() {
    Date arrive = Date.today().addDays(10);
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision('r1', 'new', 1, arrive, 2))
    );
    Assert.areEqual(1, o.ackIds.size(), JSON.serialize(o.logs));
    PMS_Booking__c b = [
      SELECT
        Id,
        Channel__c,
        Status__c,
        Total_Amount__c,
        OTA_Name__c,
        OTA_Reservation_Code__c,
        Guarantee__c,
        Space__c,
        Primary_Contact__r.Email,
        Channex_Room_Key__c,
        Adults__c
      FROM PMS_Booking__c
      WHERE Channex_Booking_Id__c != NULL
    ];
    Assert.areEqual('OTA', b.Channel__c);
    Assert.areEqual('Confirmed', b.Status__c);
    PMS_TestDataFactory.num(2688, b.Total_Amount__c, 'OTA amount');
    Assert.areEqual('Booking.com', b.OTA_Name__c);
    Assert.areEqual('4711', b.OTA_Reservation_Code__c);
    Assert.areEqual('Prepaid', b.Guarantee__c);
    Assert.isNotNull(b.Space__c, 'a free room was assigned');
    Assert.areEqual('anna@guest.example.com', b.Primary_Contact__r.Email);
    for (PMS_Room_Night__c n : [
      SELECT Rate__c
      FROM PMS_Room_Night__c
      WHERE Reservation__c = :b.Id AND Status__c != 'Posted'
    ]) {
      PMS_TestDataFactory.num(1200, n.Rate__c, 'OTA night net of 12% VAT');
    }

    o = PMS_ChannexBookings.process(
      parse(revision('r2', 'modified', 1, arrive.addDays(1), 3))
    );
    Assert.areEqual(1, o.ackIds.size(), JSON.serialize(o.logs));
    PMS_Booking__c after = [
      SELECT Total_Amount__c, Channex_Revision_Id__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    PMS_TestDataFactory.num(4032, after.Total_Amount__c, 'modified amount');
    Assert.areEqual('r2', after.Channex_Revision_Id__c);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Contact WHERE Email = 'anna@guest.example.com'],
      'guest reused'
    );

    o = PMS_ChannexBookings.process(
      parse(revision('r3', 'cancelled', 1, arrive.addDays(1), 3))
    );
    Assert.areEqual(1, o.ackIds.size());
    PMS_Booking__c cancelled = [
      SELECT Status__c, Policy_Pending__c
      FROM PMS_Booking__c
      WHERE Id = :b.Id
    ];
    Assert.areEqual('Cancelled', cancelled.Status__c);
    Assert.isFalse(
      cancelled.Policy_Pending__c == true,
      'no PMS fee on OTA cancellations'
    );
    Assert.areEqual('Booking Cancelled', o.logs[0].Kind__c);
  }

  // ---- guestFor / guest matching

  private static Map<String, Object> guestRev(
    String first,
    String last,
    String mail,
    String phone
  ) {
    return new Map<String, Object>{
      'arrival_date' => String.valueOf(Date.today().addDays(10)),
      'departure_date' => String.valueOf(Date.today().addDays(12)),
      'customer' => new Map<String, Object>{
        'name' => first,
        'surname' => last,
        'mail' => mail,
        'phone' => phone
      }
    };
  }

  @isTest
  static void guestForFillsBlankPhoneAndAliasOnMatch() {
    Account a = PMS_TestDataFactory.account('Match');
    Contact c = new Contact(
      AccountId = a.Id,
      LastName = 'Match',
      Email = 'match@guest.example.com'
    );
    insert c;
    Contact hit = PMS_ChannexBookings.guestFor(
      guestRev('M', 'Match', 'MATCH@guest.example.com', '+46701230000')
    );
    Assert.areEqual(c.Id, hit.Id);
    Contact after = [
      SELECT Phone, PMS_OTA_Alias_Email__c
      FROM Contact
      WHERE Id = :c.Id
    ];
    Assert.areEqual('+46701230000', after.Phone);
    Assert.isNull(
      after.PMS_OTA_Alias_Email__c,
      'unmasked email gives no alias'
    );

    // Existing phone is never overwritten.
    PMS_ChannexBookings.guestFor(
      guestRev('M', 'Match', 'match@guest.example.com', '+46709999999')
    );
    Assert.areEqual(
      '+46701230000',
      [SELECT Phone FROM Contact WHERE Id = :c.Id].Phone
    );
  }

  @isTest
  static void guestForFillsAliasWhenMatchedByPhoneAndName() {
    PMS_Settings__c st = PMS_Settings__c.getOrgDefaults();
    st.Guest_Match_Phone_Name__c = true;
    upsert st;
    Account a = PMS_TestDataFactory.account('Pn');
    Contact c = new Contact(
      AccountId = a.Id,
      FirstName = 'P',
      LastName = 'Pn',
      Phone = '+46705550000'
    );
    insert c;
    String relay = 'pn99@guest.booking.com';
    Contact hit = PMS_ChannexBookings.guestFor(
      guestRev('P', 'Pn', relay, '0046705550000')
    );
    Assert.areEqual(c.Id, hit.Id);
    Contact after = [
      SELECT Email, PMS_OTA_Alias_Email__c
      FROM Contact
      WHERE Id = :c.Id
    ];
    Assert.areEqual(relay, after.PMS_OTA_Alias_Email__c);
    Assert.isNull(after.Email);
    // Alias already set is not overwritten.
    PMS_ChannexBookings.guestFor(
      guestRev('P', 'Pn', 'other@guest.booking.com', '+46705550000')
    );
    Assert.areEqual(
      relay,
      [SELECT PMS_OTA_Alias_Email__c FROM Contact WHERE Id = :c.Id]
      .PMS_OTA_Alias_Email__c
    );
  }

  @isTest
  static void guestForMaskedEmailCreatesContactWithAliasOnly() {
    Contact ct = PMS_ChannexBookings.guestFor(
      guestRev('Nora', 'Relay', 'nr1@guest.booking.com', '+46701119999')
    );
    Contact r = [
      SELECT Email, PMS_OTA_Alias_Email__c, Account.Name
      FROM Contact
      WHERE Id = :ct.Id
    ];
    Assert.isNull(r.Email);
    Assert.areEqual('nr1@guest.booking.com', r.PMS_OTA_Alias_Email__c);
    Assert.areEqual('Nora Relay', r.Account.Name);
    // Second booking with same relay does not match the first contact.
    Contact second = PMS_ChannexBookings.guestFor(
      guestRev('Nora', 'Relay', 'nr1@guest.booking.com', null)
    );
    Assert.areNotEqual(ct.Id, second.Id);
  }

  @isTest
  static void guestForFlagsPossibleDuplicateOnNewContact() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Flag');
    Contact orig = new Contact(
      AccountId = a.Id,
      FirstName = 'Fia',
      LastName = 'Flag',
      Email = 'fia@guest.example.com'
    );
    insert orig;
    insert new PMS_Booking__c(
      Primary_Contact__c = orig.Id,
      Status__c = 'Confirmed',
      Start__c = Datetime.newInstance(
        Date.today().addDays(10),
        Time.newInstance(12, 0, 0, 0)
      ),
      End__c = Datetime.newInstance(
        Date.today().addDays(12),
        Time.newInstance(12, 0, 0, 0)
      )
    );
    Contact ct = PMS_ChannexBookings.guestFor(
      guestRev('Fia', 'Flag', 'fia@guest.booking.com', null)
    );
    Contact r = [
      SELECT PMS_Possible_Duplicate_Of__c, PMS_Duplicate_Reason__c
      FROM Contact
      WHERE Id = :ct.Id
    ];
    Assert.areNotEqual(orig.Id, ct.Id);
    Assert.areEqual(orig.Id, r.PMS_Possible_Duplicate_Of__c);
    Assert.isNotNull(r.PMS_Duplicate_Reason__c);
  }

  @isTest
  static void guestForPlainEmailBookingStillCreatesThenReusesGuest() {
    Contact first = PMS_ChannexBookings.guestFor(
      guestRev('Ivar', 'Plain', 'ivar@guest.example.com', null)
    );
    Contact r = [
      SELECT
        Email,
        PMS_OTA_Alias_Email__c,
        PMS_Possible_Duplicate_Of__c,
        AccountId
      FROM Contact
      WHERE Id = :first.Id
    ];
    Assert.areEqual('ivar@guest.example.com', r.Email);
    Assert.isNull(r.PMS_OTA_Alias_Email__c);
    Assert.isNull(r.PMS_Possible_Duplicate_Of__c);
    Assert.isNotNull(r.AccountId);
    Contact again = PMS_ChannexBookings.guestFor(
      guestRev('Ivar', 'Plain', 'IVAR@guest.example.com', null)
    );
    Assert.areEqual(first.Id, again.Id);
  }

  @isTest
  static void inboundBookingIsAcceptedAndAckedWhenLicenceSuspended() {
    PMS_Entitlements.forceManaged = true;
    PMS_Entitlements.enforcementOverride = true;
    PMS_Entitlements.sandboxOverride = false;
    PMS_Entitlements.pilotDaysOverride = 90;
    PMS_Entitlements.installDateOverride = Date.today().addDays(-400);
    PMS_Entitlements.tokenOverride = '';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision('r1', 'new', 1, Date.today().addDays(10), 2))
    );
    Assert.areEqual(1, o.ackIds.size(), JSON.serialize(o.logs));
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Channex_Booking_Id__c != NULL]
    );
    Assert.isFalse(
      PMS_Entitlements.allowInbound,
      'Flag is restored after the create path'
    );
  }

  private static void suspend() {
    PMS_Entitlements.forceManaged = true;
    PMS_Entitlements.enforcementOverride = true;
    PMS_Entitlements.sandboxOverride = false;
    PMS_Entitlements.pilotDaysOverride = 90;
    PMS_Entitlements.installDateOverride = Date.today().addDays(-400);
    PMS_Entitlements.tokenOverride = '';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  // ---------------------------------------------------------------- licence suspended

  @isTest
  static void suspendedPullSavesBookingMarksPulledAndQueuesTheAck() {
    ChannexMock mock = new ChannexMock();
    mock.feed = revision('r1', 'new', 1, Date.today().addDays(7), 1);
    Test.setMock(HttpCalloutMock.class, mock);
    suspend();
    Test.startTest();
    new PMS_ChannexSync.Runner(PMS_ChannexSync.PULL).execute(null);
    Test.stopTest();
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Booking__c
        WHERE OTA_Reservation_Code__c = '4711'
      ],
      'the OTA booking is saved even though PMS is locked'
    );
    Assert.isNotNull(
      [SELECT Channex_Last_Pull__c FROM PMS_Site__c LIMIT 1]
      .Channex_Last_Pull__c,
      'markPulled is not blocked by the lock'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Kind__c = 'Booking New']
    );
    PMS_ChannexSync.Runner next = PMS_ChannexSync.lastChained;
    Assert.areEqual(PMS_ChannexSync.ACK, next.stage);
    Assert.areEqual(new List<String>{ 'r1' }, next.ackIds);
    Assert.isFalse(PMS_Entitlements.allowInbound, 'flag restored');
  }

  @isTest
  static void suspendedAckStageStillAcknowledgesAndRestoresTheFlag() {
    ChannexMock mock = new ChannexMock();
    Test.setMock(HttpCalloutMock.class, mock);
    suspend();
    PMS_ChannexSync.Runner ack = new PMS_ChannexSync.Runner(
      PMS_ChannexSync.ACK
    );
    ack.ackIds = new List<String>{ 'r1', 'r2' };
    Test.startTest();
    ack.execute(null);
    Test.stopTest();
    Assert.areEqual(2, mock.calls.size());
    Assert.isTrue(
      mock.calls[1].getEndpoint().endsWith('/booking_revisions/r2/ack')
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Status__c = 'Error']
    );
    Assert.areEqual(PMS_ChannexSync.PUSH, PMS_ChannexSync.lastChained.stage);
    Assert.isFalse(PMS_Entitlements.allowInbound);
  }

  @isTest
  static void suspendedPullIsSkippedWhenTheOwnerRefusesInbound() {
    ChannexMock mock = new ChannexMock();
    mock.feed = revision('r1', 'new', 1, Date.today().addDays(7), 1);
    Test.setMock(HttpCalloutMock.class, mock);
    suspend();
    PMS_Entitlements.allowInboundConfigOverride = false;
    PMS_Entitlements.reset();
    Test.startTest();
    new PMS_ChannexSync.Runner(PMS_ChannexSync.PULL).execute(null);
    Test.stopTest();
    Assert.areEqual(0, mock.calls.size(), 'nothing is fetched or saved');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Channex_Booking_Id__c != NULL]
    );
    Assert.areEqual(
      PMS_ChannexSync.PUSH,
      PMS_ChannexSync.lastChained.stage,
      'goes on to the stop-sell'
    );
  }

  @isTest
  static void suspendedPushSendsOneStopSellThenPauses() {
    ChannexMock mock = new ChannexMock();
    Test.setMock(HttpCalloutMock.class, mock);
    suspend();
    Test.startTest();
    List<PMS_Channel_Log__c> first = PMS_ChannexSync.runPush(null);
    Assert.areEqual(1, first.size(), JSON.serialize(first));
    Assert.areEqual('Stop Sell', first[0].Kind__c);
    Assert.areEqual('Success', first[0].Status__c, first[0].Details__c);
    Assert.areEqual(2, mock.calls.size(), 'availability and restrictions');
    String avail = mock.bodyOf('/availability');
    Assert.isTrue(avail.contains('"availability":0'), avail);
    Assert.isTrue(avail.contains(ROOM_TYPE), avail);
    String rates = mock.bodyOf('/restrictions');
    Assert.isTrue(rates.contains('"stop_sell":true'), rates);
    Assert.isTrue(rates.contains(RATE_PLAN), rates);
    Assert.isFalse(rates.contains('"rate"'), 'no prices are pushed: ' + rates);
    List<PMS_Channel_Log__c> second = PMS_ChannexSync.runPush(null);
    Test.stopTest();
    Assert.isTrue(second.isEmpty(), 'not repeated on the next run');
    Assert.areEqual(2, mock.calls.size(), 'no further callouts');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Kind__c = 'Stop Sell']
    );
    Assert.isNull(
      [SELECT Channex_Last_Push__c FROM PMS_Site__c LIMIT 1]
      .Channex_Last_Push__c,
      'the locked site is not stamped'
    );
  }

  @isTest
  static void failedStopSellIsNotMarkedAsSentSoItIsRetried() {
    Test.setMock(
      HttpCalloutMock.class,
      new RawMock(500, '{"errors":{"title":"boom"}}')
    );
    suspend();
    Test.startTest();
    List<PMS_Channel_Log__c> logs = PMS_ChannexSync.runPush(null);
    Test.stopTest();
    Assert.areEqual(1, logs.size());
    Assert.areEqual('Error', logs[0].Status__c);
    Assert.isTrue(
      PMS_ChannexAri.stopSellSent(new Set<Id>{ site().Id }).isEmpty(),
      'an error is not a sent marker'
    );
  }

  @isTest
  static void stopSellMarkerEndsWhenANormalPushIsLoggedAfterIt() {
    Id siteId = site().Id;
    insert PMS_ChannexAri.log(siteId, 'Stop Sell', 'Success', 'closed', null);
    Assert.isTrue(
      PMS_ChannexAri.stopSellSent(new Set<Id>{ siteId }).contains(siteId)
    );
    // licence active again: the normal push logs Availability and Rates, so a later suspension stop-sells again
    insert PMS_ChannexAri.log(siteId, 'Availability', 'Success', 'ok', null);
    Assert.isFalse(
      PMS_ChannexAri.stopSellSent(new Set<Id>{ siteId }).contains(siteId)
    );
  }

  @isTest
  static void unlockedPushStillSendsLiveAvailabilityAndRates() {
    ChannexMock mock = new ChannexMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<PMS_Channel_Log__c> logs = PMS_ChannexSync.runPush(null);
    Test.stopTest();
    Assert.areEqual(2, logs.size());
    Assert.isTrue(mock.bodyOf('/availability').contains('"availability":2'));
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Kind__c = 'Stop Sell']
    );
  }

  @isTest
  static void overbookingIsSavedWithoutRoom() {
    Date arrive = Date.today().addDays(20);
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision('r9', 'new', 3, arrive, 1))
    );
    Assert.areEqual(1, o.ackIds.size(), JSON.serialize(o.logs));
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Channex_Booking_Id__c != NULL]
    );
    PMS_Booking__c over = [
      SELECT Space__c, Special_Requests__c
      FROM PMS_Booking__c
      WHERE Channex_Room_Key__c LIKE '%#3'
    ];
    Assert.isNull(over.Space__c);
    Assert.isTrue(over.Special_Requests__c.startsWith('OVERBOOKED'));
    Assert.areEqual('Warning', o.logs[0].Status__c);
  }

  // PMS_TriggerBypass.policyFees: Core sets it while writing OTA cancellations (so Experience's
  // guarantee trigger skips policy fees) and must always restore it. The Experience side of the
  // contract is covered in PMS_PolicyFeeBypassTest.
  @isTest
  static void policyFeeBypassIsRestoredAfterProcess() {
    Date arrive = Date.today().addDays(10);
    PMS_ChannexBookings.process(parse(revision('r1', 'new', 1, arrive, 2)));
    Assert.isFalse(PMS_TriggerBypass.policyFees, 'not set by create');
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision('r2', 'cancelled', 1, arrive, 2))
    );
    Assert.areEqual(1, o.ackIds.size(), JSON.serialize(o.logs));
    Assert.areEqual(
      'Cancelled',
      [SELECT Status__c FROM PMS_Booking__c WHERE Channex_Booking_Id__c != NULL]
      .Status__c
    );
    Assert.isFalse(
      PMS_TriggerBypass.policyFees,
      'flag restored after the cancel'
    );
  }

  @isTest
  static void policyFeeBypassIsRestoredWhenTheUpdateThrows() {
    Date arrive = Date.today().addDays(10);
    PMS_ChannexBookings.process(parse(revision('r1', 'new', 1, arrive, 2)));
    // Channex_Revision_Id__c holds 36 characters, so this revision id makes the cancel update fail.
    String tooLong = 'r2-' + 'x'.repeat(60);
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision(tooLong, 'cancelled', 1, arrive, 2))
    );
    Assert.isTrue(o.ackIds.isEmpty(), 'a failed revision is not acknowledged');
    Assert.areEqual(1, o.logs.size());
    Assert.areEqual('Error', o.logs[0].Kind__c);
    Assert.areEqual(
      'Confirmed',
      [SELECT Status__c FROM PMS_Booking__c WHERE Channex_Booking_Id__c != NULL]
      .Status__c,
      'rolled back'
    );
    Assert.isFalse(
      PMS_TriggerBypass.policyFees,
      'flag restored after the exception'
    );
  }

  @isTest
  static void policyFeeBypassRestoresThePreviousValueNotJustFalse() {
    Date arrive = Date.today().addDays(10);
    PMS_ChannexBookings.process(parse(revision('r1', 'new', 2, arrive, 2)));
    PMS_TriggerBypass.policyFees = true;
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision('r2', 'modified', 1, arrive, 2)) // drops a room, which cancels it
    );
    Assert.areEqual(1, o.ackIds.size(), JSON.serialize(o.logs));
    Assert.isTrue(PMS_TriggerBypass.policyFees, 'an outer bypass stays on');
    PMS_TriggerBypass.policyFees = false;
  }

  @isTest
  static void unmappedRoomIsNotAcknowledged() {
    update new PMS_Space_Type__c(
      Id = [SELECT Id FROM PMS_Space_Type__c LIMIT 1]
      .Id,
      Channex_Room_Type_Id__c = 'other'
    );
    PMS_ChannexBookings.Outcome o = PMS_ChannexBookings.process(
      parse(revision('r5', 'new', 1, Date.today().addDays(5), 1))
    );
    Assert.areEqual(0, o.ackIds.size());
    Assert.areEqual('Error', o.logs[0].Status__c);
    Assert.isFalse(
      o.logs[0].Details__c.contains('anna@guest'),
      'no guest details in error logs'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Channex_Booking_Id__c != NULL],
      'rolled back'
    );
  }

  // ---------------------------------------------------------------- sync chain and panel

  @isTest
  static void syncStages() {
    ChannexMock mock = new ChannexMock();
    mock.feed = revision('r7', 'new', 1, Date.today().addDays(7), 1);
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    System.enqueueJob(new PMS_ChannexSync.Runner(PMS_ChannexSync.PULL));
    Test.stopTest();
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PMS_Booking__c
        WHERE OTA_Reservation_Code__c = '4711'
      ]
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Channel_Log__c WHERE Kind__c = 'Booking New']
    );
    Assert.isNotNull(
      [SELECT Channex_Last_Pull__c FROM PMS_Site__c LIMIT 1]
      .Channex_Last_Pull__c
    );
  }

  @isTest
  static void acknowledgeAndSchedule() {
    ChannexMock mock = new ChannexMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<PMS_Channel_Log__c> logs = PMS_ChannexBookings.acknowledge(
      new List<String>{ 'r1', 'r2' }
    );
    new PMS_ChannexSync.Runner(PMS_ChannexSync.ACK).execute(null);
    PMS_ChannexSync.scheduleAll();
    Test.stopTest();
    Assert.areEqual(0, logs.size(), 'no errors');
    Assert.areEqual(2, mock.calls.size());
    Assert.isTrue(
      mock.calls[0].getEndpoint().endsWith('/booking_revisions/r1/ack')
    );
    Assert.areEqual(
      4,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name LIKE 'PMS Channex Sync%'
      ]
    );
  }

  @isTest
  static void clientReportsInvalidAndRateLimitedResponses() {
    Test.setMock(HttpCalloutMock.class, new RawMock(200, 'not json'));
    Test.startTest();
    try {
      PMS_ChannexClient.get('/invalid');
      Assert.fail('invalid JSON should fail');
    } catch (PMS_ChannexClient.ChannexException e) {
      Assert.areEqual(200, e.httpStatus);
      Assert.isTrue(e.getMessage().contains('unexpected response'));
    }

    Test.setMock(
      HttpCalloutMock.class,
      new RawMock(
        429,
        '{"errors":{"title":"Slow down","details":{"limit":10}}}'
      )
    );
    try {
      PMS_ChannexClient.post('/limited', null);
      Assert.fail('rate limit should fail');
    } catch (PMS_ChannexClient.ChannexException e) {
      Assert.areEqual(429, e.httpStatus);
      Assert.isTrue(e.getMessage().contains('rate limit'));
    }
    Test.stopTest();
  }

  @isTest
  static void panel() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      ChannexMock mock = new ChannexMock();
      Test.setMock(HttpCalloutMock.class, mock);
      PMS_ChannexController.State s = PMS_ChannexController.getState(site().Id);
      Assert.isTrue(s.enabled);
      Assert.areEqual(1, s.mappedRoomTypes);
      Assert.areEqual(1, s.activeMappings);
      Assert.isTrue(s.availabilityValues > 0);
      Assert.isTrue(s.rateValues > 0);
      Test.startTest();
      String r = PMS_ChannexController.pushNow(site().Id);
      PMS_ChannexController.syncNow();
      Test.stopTest();
      Assert.isTrue(r.contains('Availability'), r);
      update new PMS_Site__c(Id = site().Id, Channex_Property_Id__c = null);
      PMS_ChannexController.State disconnected = PMS_ChannexController.getState(
        site().Id
      );
      Assert.isTrue(disconnected.problems[0].contains('Property ID'));
      PMS_Settings__c st = PMS_Settings__c.getOrgDefaults();
      st.Channex_Enabled__c = false;
      update st;
      try {
        PMS_ChannexController.syncNow();
        Assert.fail('switched off');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('switched off'), e.getMessage());
      }
    }
  }
}
