// Minimal PMS sample data: one hotel, one room type, one room, one rate plan with a rate, one booking.
// Does nothing if any PMS site already exists, so it is safe to re-run.
// Run by `scripts/pms-package.sh bootstrap` (custom names are namespaced for the target org
// automatically); run by hand only in an org without a namespace:
//   sf apex run -o <org> -f packages/pms/scripts/apex/create-sample-data.apex
if ([SELECT COUNT() FROM PMS_Site__c] > 0) {
  System.debug('PMS_SAMPLE_SKIPPED: PMS sites already exist');
} else {
  Map<String, Schema.RecordTypeInfo> siteRt = Schema.SObjectType.PMS_Site__c.getRecordTypeInfosByDeveloperName();
  Map<String, Schema.RecordTypeInfo> spaceRt = Schema.SObjectType.PMS_Space__c.getRecordTypeInfosByDeveloperName();
  Map<String, Schema.RecordTypeInfo> bookingRt = Schema.SObjectType.PMS_Booking__c.getRecordTypeInfosByDeveloperName();

  PMS_Site__c site = new PMS_Site__c(
    Name = 'Sample Hotel',
    Module__c = 'Hotel',
    Site_Type__c = 'Hotel',
    Status__c = 'Active',
    City__c = 'Sample City',
    Country__c = 'United Kingdom',
    Currency_Code__c = 'GBP'
  );
  if (siteRt.containsKey('Hotel')) {
    site.RecordTypeId = siteRt.get('Hotel').getRecordTypeId();
  }
  insert site;

  PMS_Space_Type__c roomType = new PMS_Space_Type__c(
    Name = 'Standard Double',
    Site__c = site.Id,
    Default_Occupancy__c = 2,
    Default_Rate__c = 100
  );
  insert roomType;

  PMS_Space__c room = new PMS_Space__c(
    Name = '101',
    Site__c = site.Id,
    Space_Type__c = roomType.Id,
    Bookable__c = true,
    Max_Occupancy__c = 2,
    Operational_Status__c = 'Available'
  );
  if (spaceRt.containsKey('Room')) {
    room.RecordTypeId = spaceRt.get('Room').getRecordTypeId();
  }
  insert room;

  PMS_Rate_Plan__c plan = new PMS_Rate_Plan__c(
    Name = 'Sample Standard Rate',
    Site__c = site.Id,
    Module__c = 'Hotel',
    Pricing_Basis__c = 'Per Night',
    Currency_Code__c = 'GBP',
    Active__c = true
  );
  insert plan;

  insert new PMS_Rate__c(
    Rate_Plan__c = plan.Id,
    Space_Type__c = roomType.Id,
    Amount__c = 100,
    Date_From__c = Date.today(),
    Date_To__c = Date.today().addYears(1)
  );

  Account acc = new Account(Name = 'Sample Guest');
  insert acc;

  // Far enough ahead to avoid any same-day cut-offs; the booking trigger rejects overlaps per space.
  Datetime checkIn = Datetime.newInstance(Date.today().addDays(30), Time.newInstance(15, 0, 0, 0));
  PMS_Booking__c booking = new PMS_Booking__c(
    Site__c = site.Id,
    Space__c = room.Id,
    Rate_Plan__c = plan.Id,
    Account__c = acc.Id,
    Start__c = checkIn,
    End__c = checkIn.addDays(2),
    Status__c = 'Confirmed',
    Channel__c = 'Direct',
    Adults__c = 2,
    Rate_Amount__c = 100,
    Total_Amount__c = 200
  );
  if (bookingRt.containsKey('Reservation')) {
    booking.RecordTypeId = bookingRt.get('Reservation').getRecordTypeId();
  }
  insert booking;
  System.debug('PMS sample data created: site ' + site.Id + ', booking ' + booking.Id);
}
