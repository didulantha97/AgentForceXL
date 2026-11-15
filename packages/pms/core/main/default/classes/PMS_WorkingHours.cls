/**
 * Parses a practitioner's Working Hours text, one rule for the whole org (staff diary and public booking site).
 *
 *   "Mon-Fri 08:00-16:00"                    weekdays only
 *   "Tue-Sat 09:00-17:00; Sun 10:00-14:00"   several parts, separated by ; , or a new line
 *   "Fri-Mon 10:00-18:00"                    ranges may wrap past Sunday
 *   "08:00-16:00"                            no days given: Monday to Friday
 *   blank                                    Mon-Fri 09:00-17:00
 *
 * The first part that covers the day wins. forDay returns null when the practitioner does not work that day.
 */
public inherited sharing class PMS_WorkingHours {
  public static final String DEFAULT_SPEC = 'Mon-Fri 09:00-17:00';
  private static final Pattern HOURS = Pattern.compile(
    '(?i)^\\s*(?:([a-z]{3})[a-z]*(?:\\s*-\\s*([a-z]{3})[a-z]*)?\\s+)?(\\d{1,2})[:.](\\d{2})\\s*-\\s*(\\d{1,2})[:.](\\d{2})\\s*$'
  );
  private static final List<String> DAYS = new List<String>{
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun'
  };

  /** Opening and closing time on the given date, or null when not working that day. */
  public static List<Time> forDay(String spec, Date d) {
    if (d == null) {
      return null;
    }
    String text = String.isBlank(spec) ? DEFAULT_SPEC : spec;
    Integer dayIdx = DAYS.indexOf(
      PMS_DateUtil.dayName(d).left(3).toLowerCase()
    );
    for (String part : text.split('[;,\\n]')) {
      Matcher m = HOURS.matcher(part);
      if (!m.matches()) {
        continue;
      }
      Boolean applies;
      if (m.group(1) == null) {
        applies = dayIdx <= 4;
      } else {
        Integer first = DAYS.indexOf(m.group(1).toLowerCase());
        Integer last = m.group(2) == null
          ? first
          : DAYS.indexOf(m.group(2).toLowerCase());
        if (first < 0 || last < 0) {
          continue;
        }
        applies = first <= last
          ? (dayIdx >= first && dayIdx <= last)
          : (dayIdx >= first || dayIdx <= last);
      }
      if (applies) {
        Integer oh = Integer.valueOf(m.group(3));
        Integer om = Integer.valueOf(m.group(4));
        Integer ch = Integer.valueOf(m.group(5));
        Integer cm = Integer.valueOf(m.group(6));
        if (oh > 23 || ch > 24 || om > 59 || cm > 59) {
          continue;
        }
        Time open = Time.newInstance(oh, om, 0, 0);
        Time close = ch == 24
          ? Time.newInstance(23, 59, 0, 0)
          : Time.newInstance(ch, cm, 0, 0);
        return close > open ? new List<Time>{ open, close } : null;
      }
    }
    return null;
  }

  public static Boolean worksOn(String spec, Date d) {
    return forDay(spec, d) != null;
  }
}
