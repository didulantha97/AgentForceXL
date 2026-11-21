/**
 * Daily: emails guests and patients booked 1-3 days ahead a secure link to check in online
 * (PMS_CustomerNotifications.sendCheckInInvitations). Each booking is invited once.
 * Schedule once:  PMS_CheckInInvitationJob.scheduleDaily();   (10:15 every day)
 */
public without sharing class PMS_CheckInInvitationJob implements Schedulable {
  public static final String JOB_NAME = 'PMS Check-In Invitations (daily)';

  public void execute(SchedulableContext sc) {
    if (PMS_Entitlements.jobsBlocked('PMS_CheckInInvitationJob')) {
      return; // licence suspended: PMS is read-only
    }
    PMS_CustomerNotifications.sendCheckInInvitations();
  }

  public static Id scheduleDaily() {
    return System.schedule(
      JOB_NAME,
      '0 15 10 * * ?',
      new PMS_CheckInInvitationJob()
    );
  }
}
