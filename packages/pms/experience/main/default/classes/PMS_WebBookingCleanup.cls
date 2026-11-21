/**
 * Releases unpaid public-site bookings (see PMS_WebBookingHold).
 * Schedule once with: PMS_WebBookingCleanup.scheduleEvery15Minutes();
 */
public without sharing class PMS_WebBookingCleanup implements Schedulable {
  public static final String JOB_PREFIX = 'PMS Web Booking Cleanup';

  public void execute(SchedulableContext sc) {
    if (PMS_Entitlements.jobsBlocked('PMS_WebBookingCleanup')) {
      return; // licence suspended: PMS is read-only
    }
    PMS_WebBookingHold.releaseExpired();
  }

  /** Four hourly jobs at :05, :20, :35 and :50. Returns the job ids. */
  public static List<Id> scheduleEvery15Minutes() {
    List<Id> ids = new List<Id>();
    for (Integer minute : new List<Integer>{ 5, 20, 35, 50 }) {
      ids.add(
        System.schedule(
          JOB_PREFIX + ' :' + String.valueOf(minute).leftPad(2, '0'),
          '0 ' + minute + ' * * * ?',
          new PMS_WebBookingCleanup()
        )
      );
    }
    return ids;
  }
}
