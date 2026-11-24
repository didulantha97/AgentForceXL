@isTest
private class PMS_GuestStatsServiceTest {
  private static Contact guest(String lastName) {
    return PMS_TestDataFactory.contact(
      PMS_TestDataFactory.account('Acc ' + lastName).Id,
      lastName
    );
  }

  /** Noon local time on today + offset, so DATEVALUE() in the Nights formula is stable. */
  private static Datetime at(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(12, 0, 0, 0)
    );
  }

  private static PMS_Booking__c booking(
    Id primary,
    String status,
    Integer startOffset,
    Integer endOffset
  ) {
    return new PMS_Booking__c(
      Primary_Contact__c = primary,
      Status__c = status,
      Start__c = at(startOffset),
      End__c = at(endOffset)
    );
  }

  private static PMS_Charge__c charge(
    Id bookingId,
    String type,
    Decimal qty,
    Decimal price,
    String status
  ) {
    return new PMS_Charge__c(
      Booking__c = bookingId,
      Charge_Type__c = type,
      Quantity__c = qty,
      Unit_Price__c = price,
      Status__c = status
    );
  }

  private static Contact reload(Id id) {
    return [
      SELECT
        PMS_Total_Stays__c,
        PMS_Lifetime_Nights__c,
        PMS_Room_Revenue__c,
        PMS_Extras_Revenue__c,
        PMS_First_Stay__c,
        PMS_Last_Stay__c,
        PMS_Next_Arrival__c,
        PMS_Stats_Refreshed__c
      FROM Contact
      WHERE Id = :id
    ];
  }

  private static void recalc(Id id) {
    Test.startTest();
    PMS_GuestStatsService.recalc(new Set<Id>{ id });
    Test.stopTest();
  }

  @isTest
  static void primaryOnlyGuestGetsCompletedStayStats() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('PrimaryOnly');
    insert new List<PMS_Booking__c>{
      booking(c.Id, 'Completed', -10, -7), // 3 nights
      booking(c.Id, 'Completed', -5, -3) // 2 nights
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(2, r.PMS_Total_Stays__c);
    Assert.areEqual(5, r.PMS_Lifetime_Nights__c);
    Assert.areEqual(Date.today().addDays(-10), r.PMS_First_Stay__c);
    Assert.areEqual(Date.today().addDays(-3), r.PMS_Last_Stay__c);
    Assert.isNull(r.PMS_Next_Arrival__c);
    Assert.isNotNull(r.PMS_Stats_Refreshed__c);
  }

  @isTest
  static void partyOnlyGuestGetsStaysButNoRevenue() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact primary = guest('Payer');
    Contact member = guest('Member');
    PMS_Booking__c b = booking(primary.Id, 'Completed', -4, -2);
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = member.Id);
    insert charge(b.Id, 'Room Night', 2, 1000, 'Pending');
    Test.startTest();
    PMS_GuestStatsService.recalc(new Set<Id>{ primary.Id, member.Id });
    Test.stopTest();
    Contact m = reload(member.Id);
    Assert.areEqual(1, m.PMS_Total_Stays__c);
    Assert.areEqual(2, m.PMS_Lifetime_Nights__c);
    Assert.areEqual(Date.today().addDays(-4), m.PMS_First_Stay__c);
    Assert.areEqual(Date.today().addDays(-2), m.PMS_Last_Stay__c);
    Assert.areEqual(0, m.PMS_Room_Revenue__c);
    Assert.areEqual(0, m.PMS_Extras_Revenue__c);
    Contact p = reload(primary.Id);
    Assert.areEqual(2000, p.PMS_Room_Revenue__c);
  }

  @isTest
  static void primaryAndPartyOnSameBookingCountedOnce() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Both');
    PMS_Booking__c b = booking(c.Id, 'Completed', -6, -3);
    insert b;
    insert new PMS_Booking_Party__c(Booking__c = b.Id, Contact__c = c.Id);
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(1, r.PMS_Total_Stays__c);
    Assert.areEqual(3, r.PMS_Lifetime_Nights__c);
  }

  @isTest
  static void primaryAndPartyOnDifferentBookingsBothCount() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Mixed');
    Contact other = guest('OtherPayer');
    insert new List<PMS_Booking__c>{
      booking(c.Id, 'Completed', -10, -9),
      booking(other.Id, 'Completed', -20, -17)
    };
    PMS_Booking__c otherBooking = [
      SELECT Id
      FROM PMS_Booking__c
      WHERE Primary_Contact__c = :other.Id
    ];
    insert new PMS_Booking_Party__c(
      Booking__c = otherBooking.Id,
      Contact__c = c.Id
    );
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(2, r.PMS_Total_Stays__c);
    Assert.areEqual(4, r.PMS_Lifetime_Nights__c);
    Assert.areEqual(Date.today().addDays(-20), r.PMS_First_Stay__c);
    Assert.areEqual(Date.today().addDays(-9), r.PMS_Last_Stay__c);
  }

  @isTest
  static void cancelledAndNoShowAreNotStaysButTheirChargesCountAsRevenue() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Excluded');
    Contact member = guest('ExcludedMember');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>{
      booking(c.Id, 'Cancelled', -10, -8),
      booking(c.Id, 'No Show', -7, -5),
      booking(c.Id, 'Cancelled', 3, 5),
      booking(c.Id, 'Completed', -3, -2)
    };
    insert bs;
    insert new List<PMS_Booking_Party__c>{
      new PMS_Booking_Party__c(Booking__c = bs[0].Id, Contact__c = member.Id),
      new PMS_Booking_Party__c(Booking__c = bs[2].Id, Contact__c = member.Id)
    };
    insert new List<PMS_Charge__c>{
      charge(bs[0].Id, 'Room Night', 1, 500, 'Pending'),
      charge(bs[3].Id, 'Room Night', 1, 100, 'Pending')
    };
    Test.startTest();
    PMS_GuestStatsService.recalc(new Set<Id>{ c.Id, member.Id });
    Test.stopTest();
    Contact r = reload(c.Id);
    Assert.areEqual(1, r.PMS_Total_Stays__c);
    Assert.areEqual(1, r.PMS_Lifetime_Nights__c);
    Assert.areEqual(Date.today().addDays(-3), r.PMS_First_Stay__c);
    Assert.isNull(r.PMS_Next_Arrival__c, 'cancelled future booking ignored');
    Assert.areEqual(
      600,
      r.PMS_Room_Revenue__c,
      'charges on a cancelled booking (e.g. cancellation fee) still count'
    );
    Contact m = reload(member.Id);
    Assert.areEqual(0, m.PMS_Total_Stays__c);
    Assert.isNull(m.PMS_Next_Arrival__c);
  }

  @isTest
  static void bookingEndingTodayIsNotYetCompleted() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('EndsToday');
    insert new List<PMS_Booking__c>{
      booking(c.Id, 'Active', -2, 0), // departs today: counts from tomorrow
      booking(c.Id, 'Completed', -9, -7) // 2 nights, departed
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(1, r.PMS_Total_Stays__c, 'departing today excluded');
    Assert.areEqual(2, r.PMS_Lifetime_Nights__c);
    Assert.areEqual(Date.today().addDays(-7), r.PMS_Last_Stay__c);
    Assert.isNull(r.PMS_Next_Arrival__c);
  }

  @isTest
  static void bookingEndedYesterdayCountsAsCompleted() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('EndedYesterday');
    insert booking(c.Id, 'Active', -3, -1);
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(1, r.PMS_Total_Stays__c);
    Assert.areEqual(2, r.PMS_Lifetime_Nights__c);
    Assert.areEqual(Date.today().addDays(-1), r.PMS_Last_Stay__c);
  }

  @isTest
  static void tentativeAndInquiryAreNeverStaysButTentativeIsNextArrival() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Tentative');
    insert new List<PMS_Booking__c>{
      booking(c.Id, 'Tentative', -6, -4), // past tentative: not a stay
      booking(c.Id, 'Inquiry', -3, -2), // past inquiry: not a stay
      booking(c.Id, 'Tentative', 4, 6), // live hold: next arrival
      booking(c.Id, 'Inquiry', 1, 2), // never an arrival
      booking(c.Id, 'Confirmed', 9, 10)
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(0, r.PMS_Total_Stays__c);
    Assert.areEqual(0, r.PMS_Lifetime_Nights__c);
    Assert.isNull(r.PMS_First_Stay__c);
    Assert.isNull(r.PMS_Last_Stay__c);
    Assert.areEqual(Date.today().addDays(4), r.PMS_Next_Arrival__c);
  }

  @isTest
  static void futureBookingsSetEarliestNextArrival() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Future');
    Contact member = guest('FutureMember');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>{
      booking(c.Id, 'Confirmed', 20, 22),
      booking(c.Id, 'Confirmed', 5, 7)
    };
    insert bs;
    PMS_Booking__c earlierForMember = booking(c.Id, 'Confirmed', 2, 4);
    insert earlierForMember;
    insert new PMS_Booking_Party__c(
      Booking__c = earlierForMember.Id,
      Contact__c = member.Id
    );
    Test.startTest();
    PMS_GuestStatsService.recalc(new Set<Id>{ c.Id, member.Id });
    Test.stopTest();
    Contact r = reload(c.Id);
    Assert.areEqual(Date.today().addDays(2), r.PMS_Next_Arrival__c);
    Assert.areEqual(0, r.PMS_Total_Stays__c, 'future stays are not completed');
    Assert.isNull(r.PMS_First_Stay__c);
    Contact m = reload(member.Id);
    Assert.areEqual(Date.today().addDays(2), m.PMS_Next_Arrival__c);
    Assert.areEqual(0, m.PMS_Total_Stays__c);
  }

  @isTest
  static void arrivingTodayIsNextArrival() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('ArrivesToday');
    insert booking(c.Id, 'Confirmed', 0, 2);
    recalc(c.Id);
    Assert.areEqual(Date.today(), reload(c.Id).PMS_Next_Arrival__c);
  }

  @isTest
  static void revenueSplitsRoomExtrasAndExcludesVoidAndCityTax() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Revenue');
    PMS_Booking__c b = booking(c.Id, 'Completed', -5, -2);
    insert b;
    insert new List<PMS_Charge__c>{
      charge(b.Id, 'Room Night', 3, 1000, 'Pending'), // 3000
      charge(b.Id, 'Room Night', 1, 250, 'Invoiced'), // 250
      charge(b.Id, 'Room Night', 1, 9999, 'Void'), // excluded
      charge(b.Id, 'Food and Beverage', 2, 150, 'Pending'), // 300
      charge(b.Id, 'Extra', 1, 80, 'Invoiced'), // 80
      charge(b.Id, 'Extra', 1, 7777, 'Void'), // excluded
      charge(b.Id, 'City Tax', 3, 25, 'Pending') // excluded
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(3250, r.PMS_Room_Revenue__c, 'room: net sum, no void');
    Assert.areEqual(380, r.PMS_Extras_Revenue__c, 'extras: no void, no tax');
  }

  @isTest
  static void rentIsRoomRevenueAndParkingIsExtras() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('RentParking');
    PMS_Booking__c b = booking(c.Id, 'Completed', -5, -2);
    insert b;
    insert new List<PMS_Charge__c>{
      charge(b.Id, 'Rent', 1, 700, 'Pending'),
      charge(b.Id, 'Room Night', 1, 100, 'Pending'),
      charge(b.Id, 'Parking', 2, 40, 'Pending')
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(800, r.PMS_Room_Revenue__c);
    Assert.areEqual(80, r.PMS_Extras_Revenue__c);
  }

  @isTest
  static void utilitiesServiceChargeAndExpenseAreExcluded() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('NonRevenue');
    PMS_Booking__c b = booking(c.Id, 'Completed', -5, -2);
    insert b;
    insert new List<PMS_Charge__c>{
      charge(b.Id, 'Utilities', 1, 300, 'Pending'),
      charge(b.Id, 'Service Charge', 1, 200, 'Pending'),
      charge(b.Id, 'Expense', 1, 100, 'Pending'),
      charge(b.Id, 'City Tax', 1, 50, 'Pending'),
      charge(b.Id, 'Extra', 1, 10, 'Pending')
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(0, r.PMS_Room_Revenue__c);
    Assert.areEqual(10, r.PMS_Extras_Revenue__c);
  }

  @isTest
  static void revenueOnCancelledAndNoShowBookingsCounts() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('CancelFee');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>{
      booking(c.Id, 'Cancelled', 5, 7),
      booking(c.Id, 'No Show', -5, -3)
    };
    insert bs;
    insert new List<PMS_Charge__c>{
      charge(bs[0].Id, 'Room Night', 1, 300, 'Pending'),
      charge(bs[0].Id, 'Extra', 1, 20, 'Pending'),
      charge(bs[1].Id, 'Room Night', 1, 150, 'Invoiced'),
      charge(bs[1].Id, 'Room Night', 1, 999, 'Void')
    };
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(450, r.PMS_Room_Revenue__c);
    Assert.areEqual(20, r.PMS_Extras_Revenue__c);
    Assert.areEqual(0, r.PMS_Total_Stays__c);
    Assert.isNull(r.PMS_Next_Arrival__c);
  }

  @isTest
  static void recalcWithErrorsReportsUnsavableContact() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact good = guest('GoodE');
    Contact gone = guest('GoneE');
    delete gone;
    Test.startTest();
    List<String> errors = PMS_GuestStatsService.recalcWithErrors(
      new Set<Id>{ good.Id, gone.Id }
    );
    Test.stopTest();
    Assert.areEqual(1, errors.size());
    Assert.isTrue(errors[0].contains(String.valueOf(gone.Id)), errors[0]);
    Assert.isNotNull(reload(good.Id).PMS_Stats_Refreshed__c);
    Assert.isTrue(PMS_GuestStatsService.recalcWithErrors(null).isEmpty());
  }

  @isTest
  static void revenueSumsAcrossBookingsOfPrimaryOnly() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('MultiBooking');
    List<PMS_Booking__c> bs = new List<PMS_Booking__c>{
      booking(c.Id, 'Completed', -9, -8),
      booking(c.Id, 'Confirmed', 4, 5)
    };
    insert bs;
    insert new List<PMS_Charge__c>{
      charge(bs[0].Id, 'Room Night', 1, 100, 'Pending'),
      charge(bs[1].Id, 'Room Night', 2, 100, 'Pending')
    };
    recalc(c.Id);
    Assert.areEqual(300, reload(c.Id).PMS_Room_Revenue__c);
  }

  @isTest
  static void contactWithNoBookingsIsResetToZeroAndNull() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact c = guest('Empty');
    c.PMS_Total_Stays__c = 9;
    c.PMS_Lifetime_Nights__c = 40;
    c.PMS_Room_Revenue__c = 123;
    c.PMS_Extras_Revenue__c = 45;
    c.PMS_First_Stay__c = Date.today().addDays(-100);
    c.PMS_Last_Stay__c = Date.today().addDays(-50);
    c.PMS_Next_Arrival__c = Date.today().addDays(10);
    update c;
    recalc(c.Id);
    Contact r = reload(c.Id);
    Assert.areEqual(0, r.PMS_Total_Stays__c);
    Assert.areEqual(0, r.PMS_Lifetime_Nights__c);
    Assert.areEqual(0, r.PMS_Room_Revenue__c);
    Assert.areEqual(0, r.PMS_Extras_Revenue__c);
    Assert.isNull(r.PMS_First_Stay__c);
    Assert.isNull(r.PMS_Last_Stay__c);
    Assert.isNull(r.PMS_Next_Arrival__c);
    Assert.isNotNull(r.PMS_Stats_Refreshed__c);
  }

  @isTest
  static void nullAndEmptyInputsDoNothing() {
    Contact c = guest('Untouched');
    Test.startTest();
    PMS_GuestStatsService.recalc(null);
    PMS_GuestStatsService.recalc(new Set<Id>());
    PMS_GuestStatsService.recalc(new Set<Id>{ null });
    Test.stopTest();
    Assert.isNull(reload(c.Id).PMS_Stats_Refreshed__c);
  }

  @isTest
  static void partialUpdateFailureDoesNotThrow() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Contact good = guest('Good');
    Contact gone = guest('Gone');
    insert booking(good.Id, 'Completed', -3, -1);
    delete gone; // update of a deleted Contact fails per record (allOrNone = false)
    Test.startTest();
    PMS_GuestStatsService.recalc(new Set<Id>{ good.Id, gone.Id });
    Test.stopTest();
    Assert.areEqual(1, reload(good.Id).PMS_Total_Stays__c);
  }

  @isTest
  static void bulkRecalcKeepsQueryCountBounded() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.DEV);
    Account a = PMS_TestDataFactory.account('Bulk Co');
    List<Contact> contacts = new List<Contact>();
    for (Integer i = 0; i < 200; i++) {
      contacts.add(new Contact(AccountId = a.Id, LastName = 'Bulk' + i));
    }
    insert contacts;
    List<PMS_Booking__c> bookings = new List<PMS_Booking__c>();
    for (Contact c : contacts) {
      bookings.add(booking(c.Id, 'Completed', -4, -2));
      bookings.add(booking(c.Id, 'Confirmed', 6, 8));
    }
    insert bookings;
    List<PMS_Booking_Party__c> parties = new List<PMS_Booking_Party__c>();
    List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
    for (Integer i = 0; i < 200; i++) {
      // each contact is also a party member on the next contact's completed booking
      parties.add(
        new PMS_Booking_Party__c(
          Booking__c = bookings[Math.mod(i + 1, 200) * 2].Id,
          Contact__c = contacts[i].Id
        )
      );
      charges.add(charge(bookings[i * 2].Id, 'Room Night', 2, 100, 'Pending'));
    }
    insert parties;
    insert charges;
    Set<Id> ids = new Map<Id, Contact>(contacts).keySet();
    Test.startTest();
    Integer before = Limits.getQueries();
    PMS_GuestStatsService.recalc(ids);
    Integer used = Limits.getQueries() - before;
    Test.stopTest();
    Assert.isTrue(
      used <= 6,
      'recalc used ' + used + ' queries for 200 contacts'
    );
    Integer ok = 0;
    for (Contact c : [
      SELECT
        PMS_Total_Stays__c,
        PMS_Lifetime_Nights__c,
        PMS_Room_Revenue__c,
        PMS_Next_Arrival__c
      FROM Contact
      WHERE Id IN :ids
    ]) {
      if (
        c.PMS_Total_Stays__c == 2 &&
        c.PMS_Lifetime_Nights__c == 4 &&
        c.PMS_Room_Revenue__c == 200 &&
        c.PMS_Next_Arrival__c == Date.today().addDays(6)
      ) {
        ok++;
      }
    }
    Assert.areEqual(200, ok, 'every bulk contact has correct stats');
  }
}
