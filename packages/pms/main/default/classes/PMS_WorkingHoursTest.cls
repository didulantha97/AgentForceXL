@isTest
private class PMS_WorkingHoursTest {
  private static Date next(String dayName) {
    Date d = PMS_TestDataFactory.futureMonday();
    while (PMS_DateUtil.dayName(d) != dayName) {
      d = d.addDays(1);
    }
    return d;
  }

  @isTest
  static void dayRangesAreRespected() {
    String anna = 'Mon-Fri 08:00-16:00';
    Assert.areEqual(
      Time.newInstance(8, 0, 0, 0),
      PMS_WorkingHours.forDay(anna, next('Monday'))[0]
    );
    Assert.areEqual(
      Time.newInstance(16, 0, 0, 0),
      PMS_WorkingHours.forDay(anna, next('Friday'))[1]
    );
    Assert.isNull(
      PMS_WorkingHours.forDay(anna, next('Saturday')),
      'Anna does not work Saturdays'
    );
    Assert.isNull(PMS_WorkingHours.forDay(anna, next('Sunday')));

    String erik = 'Tue-Sat 09:00-17:00';
    Assert.isNull(PMS_WorkingHours.forDay(erik, next('Monday')));
    Assert.areEqual(
      Time.newInstance(9, 0, 0, 0),
      PMS_WorkingHours.forDay(erik, next('Saturday'))[0]
    );
  }

  @isTest
  static void severalPartsAndWrapAround() {
    String spec = 'Tue-Sat 09:00-17:00; Sun 10:00-14:00';
    Assert.areEqual(
      Time.newInstance(10, 0, 0, 0),
      PMS_WorkingHours.forDay(spec, next('Sunday'))[0]
    );
    Assert.areEqual(
      Time.newInstance(14, 0, 0, 0),
      PMS_WorkingHours.forDay(spec, next('Sunday'))[1]
    );
    Assert.isNull(PMS_WorkingHours.forDay(spec, next('Monday')));

    String wrap = 'Fri-Mon 10:00-18:00';
    Assert.isTrue(PMS_WorkingHours.worksOn(wrap, next('Sunday')));
    Assert.isTrue(PMS_WorkingHours.worksOn(wrap, next('Monday')));
    Assert.isFalse(PMS_WorkingHours.worksOn(wrap, next('Wednesday')));

    Assert.isTrue(
      PMS_WorkingHours.worksOn(
        'Monday-Thursday 07:30 - 15:45',
        next('Thursday')
      ),
      'Full day names'
    );
    Assert.isTrue(
      PMS_WorkingHours.worksOn(
        'Wed 08.00-12.00\nThu 13:00-17:00',
        next('Thursday')
      ),
      'New lines and dots'
    );
  }

  @isTest
  static void defaultsAndBadInput() {
    Assert.areEqual(
      Time.newInstance(9, 0, 0, 0),
      PMS_WorkingHours.forDay(null, next('Monday'))[0]
    );
    Assert.isNull(
      PMS_WorkingHours.forDay('', next('Saturday')),
      'Blank means weekdays'
    );
    Assert.isTrue(PMS_WorkingHours.worksOn('08:00-16:00', next('Wednesday')));
    Assert.isFalse(
      PMS_WorkingHours.worksOn('08:00-16:00', next('Saturday')),
      'Hours without days are weekdays'
    );
    Assert.isNull(PMS_WorkingHours.forDay('flexible', next('Monday')));
    Assert.isNull(
      PMS_WorkingHours.forDay('Mon-Fri 17:00-09:00', next('Monday')),
      'Close before open'
    );
    Assert.isNull(PMS_WorkingHours.forDay('Xyz 09:00-17:00', next('Monday')));
    Assert.isNull(PMS_WorkingHours.forDay('Mon 25:00-26:00', next('Monday')));
    Assert.isNull(PMS_WorkingHours.forDay('Mon-Fri 09:00-17:00', null));
    Assert.areEqual(
      Time.newInstance(23, 59, 0, 0),
      PMS_WorkingHours.forDay('Mon 18:00-24:00', next('Monday'))[1]
    );
  }
}
