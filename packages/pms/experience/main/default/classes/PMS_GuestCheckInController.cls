/**
 * Online check-in from the emailed link, on the public booking site (no login):
 *   https://<site>/book?checkin=<booking id>&key=<64-char secret>
 * The secret is PMS_Booking__c.Check_In_Key__c, set when the invitation is sent
 * (PMS_CustomerNotifications.sendCheckInInvitations). Clearing the field invalidates the link.
 * Runs as the site guest user, without sharing; only the booking matching id + key is touched, and only
 * through PMS_CheckInService (one check-in per booking).
 */
public without sharing class PMS_GuestCheckInController {
  public class GuestView {
    @AuraEnabled
    public PMS_CheckInService.Eligible checkIn;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled
  public static GuestView getCheckIn(Id bookingId, String key) {
    try {
      PMS_Booking__c b = verified(bookingId, key);
      GuestView v = new GuestView();
      v.checkIn = PMS_CheckInService.describe(b);
      if (v.checkIn == null) {
        v.message = 'Online check-in is closed for this booking. If you need help, please contact us.';
      }
      return v;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static GuestView submitCheckIn(
    Id bookingId,
    String key,
    String formJson
  ) {
    try {
      PMS_Booking__c b = verified(bookingId, key);
      PMS_CheckInService.submit(b, formJson, 'Email Link');
      GuestView v = new GuestView();
      v.checkIn = PMS_CheckInService.describe(PMS_CheckInService.load(b.Id));
      v.message = 'Thank you! We have your details.';
      return v;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  private static PMS_Booking__c verified(Id bookingId, String key) {
    if (bookingId == null || String.isBlank(key) || key.length() != 64) {
      throw new PMS_Exception('This check-in link is not valid.');
    }
    PMS_Booking__c b = PMS_CheckInService.load(bookingId);
    // SOQL comparisons ignore case, so compare the secret exactly here.
    if (
      b == null ||
      String.isBlank(b.Check_In_Key__c) ||
      !key.equals(b.Check_In_Key__c)
    ) {
      throw new PMS_Exception(
        'This check-in link is not valid or has expired.'
      );
    }
    return b;
  }

  private static AuraHandledException handled(Exception e) {
    String msg = e instanceof PMS_Exception
      ? e.getMessage()
      : 'Something went wrong. Please try again or contact us.';
    if (!(e instanceof PMS_Exception)) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS guest check-in: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
    }
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    return ex;
  }
}
