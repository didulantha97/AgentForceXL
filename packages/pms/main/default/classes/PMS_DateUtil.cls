/**
 * Date and time helpers that respect each Site's own time zone
 * (a hotel in Stockholm and an office in Colombo can live in the same org).
 */
public inherited sharing class PMS_DateUtil {
  private static final Date KNOWN_SUNDAY = Date.newInstance(1900, 1, 7);
  private static final List<String> DAY_NAMES = new List<String>{
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday'
  };

  /** English day name, independent of the running user's locale. */
  public static String dayName(Date d) {
    Integer idx = Math.mod(KNOWN_SUNDAY.daysBetween(d), 7);
    if (idx < 0) {
      idx += 7;
    }
    return DAY_NAMES[idx];
  }

  public static Boolean isWeekend(Date d) {
    String n = dayName(d);
    return n == 'Saturday' || n == 'Sunday';
  }

  /** Builds an absolute Datetime for a local date + time in the given IANA time zone. */
  public static Datetime toDatetime(Date d, Time t, String timeZoneId) {
    Time localTime = t == null ? Time.newInstance(12, 0, 0, 0) : t;
    Datetime asGmt = Datetime.newInstanceGmt(d, localTime);
    if (String.isBlank(timeZoneId)) {
      return Datetime.newInstance(d, localTime);
    }
    Integer offsetMs = TimeZone.getTimeZone(timeZoneId).getOffset(asGmt);
    return Datetime.newInstance(asGmt.getTime() - offsetMs);
  }

  /** Local calendar date of an instant in the given time zone. */
  public static Date toLocalDate(Datetime dt, String timeZoneId) {
    if (dt == null) {
      return null;
    }
    if (String.isBlank(timeZoneId)) {
      return dt.date();
    }
    return Date.valueOf(dt.format('yyyy-MM-dd', timeZoneId));
  }

  public static Integer nightsBetween(Date startDate, Date endDate) {
    if (startDate == null || endDate == null) {
      return 0;
    }
    return Math.max(0, startDate.daysBetween(endDate));
  }

  /** Whole months between two dates, rounded up for partial months (rent proration is handled by billing). */
  public static Integer monthsBetween(Date startDate, Date endDate) {
    if (startDate == null || endDate == null || endDate <= startDate) {
      return 0;
    }
    Integer months = startDate.monthsBetween(endDate);
    if (startDate.addMonths(months) < endDate) {
      months++;
    }
    return Math.max(1, months);
  }

  public static Date addFrequency(Date d, String frequency) {
    switch on frequency {
      when 'Weekly' {
        return d.addDays(7);
      }
      when 'Quarterly' {
        return d.addMonths(3);
      }
      when 'Annually' {
        return d.addYears(1);
      }
      when else {
        return d.addMonths(1);
      }
    }
  }
}
