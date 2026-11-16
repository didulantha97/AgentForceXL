/**
 * "Channel Manager" panel on the hotel's Site page (LWC pmsChannexPanel): connection status, mapping
 * check, recent sync log, a preview of what would be sent, and Sync now.
 */
public with sharing class PMS_ChannexController {
  public class LogRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Datetime at;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingName;
  }

  public class State {
    @AuraEnabled
    public Boolean enabled = false;
    @AuraEnabled
    public String propertyId;
    @AuraEnabled
    public Boolean pricesIncludeVat = false;
    @AuraEnabled
    public Datetime lastPush;
    @AuraEnabled
    public Datetime lastPull;
    @AuraEnabled
    public Integer roomTypes = 0;
    @AuraEnabled
    public Integer mappedRoomTypes = 0;
    @AuraEnabled
    public Integer activeMappings = 0;
    @AuraEnabled
    public List<String> problems = new List<String>();
    @AuraEnabled
    public Integer availabilityValues = 0;
    @AuraEnabled
    public Integer rateValues = 0;
    @AuraEnabled
    public List<LogRow> logs = new List<LogRow>();
  }

  @AuraEnabled
  public static State getState(Id siteId) {
    try {
      PMS_Site__c site = [
        SELECT
          Id,
          Channex_Property_Id__c,
          Channex_Prices_Include_VAT__c,
          Channex_Last_Push__c,
          Channex_Last_Pull__c
        FROM PMS_Site__c
        WHERE Id = :siteId
        WITH USER_MODE
      ];
      State s = new State();
      s.enabled = PMS_ChannexSync.enabled();
      s.propertyId = site.Channex_Property_Id__c;
      s.pricesIncludeVat = site.Channex_Prices_Include_VAT__c == true;
      s.lastPush = site.Channex_Last_Push__c;
      s.lastPull = site.Channex_Last_Pull__c;
      for (PMS_Space_Type__c t : [
        SELECT Channex_Room_Type_Id__c
        FROM PMS_Space_Type__c
        WHERE Site__c = :siteId
        WITH USER_MODE
      ]) {
        s.roomTypes++;
        if (String.isNotBlank(t.Channex_Room_Type_Id__c)) {
          s.mappedRoomTypes++;
        }
      }
      s.activeMappings = [
        SELECT COUNT()
        FROM PMS_Channel_Mapping__c
        WHERE Site__c = :siteId AND Active__c = TRUE
        WITH USER_MODE
      ];
      if (String.isNotBlank(site.Channex_Property_Id__c)) {
        PMS_ChannexAri.Payload p = PMS_ChannexAri.build(
          siteId,
          Date.today(),
          PMS_ChannexAri.horizon()
        );
        s.problems = p.problems;
        s.availabilityValues = p.availability.size();
        s.rateValues = p.restrictions.size();
      } else {
        s.problems.add(
          'Enter the Channex Property ID on this site to connect it.'
        );
      }
      if (!s.enabled) {
        s.problems.add(
          'The sync is switched off (PMS Settings > Channex Enabled).'
        );
      }
      for (PMS_Channel_Log__c l : [
        SELECT
          Id,
          Name,
          CreatedDate,
          Direction__c,
          Kind__c,
          Status__c,
          Message__c,
          Booking__c,
          Booking__r.Name
        FROM PMS_Channel_Log__c
        WHERE Site__c = :siteId OR Site__c = NULL
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 25
      ]) {
        LogRow r = new LogRow();
        r.id = l.Id;
        r.name = l.Name;
        r.at = l.CreatedDate;
        r.direction = l.Direction__c;
        r.kind = l.Kind__c;
        r.status = l.Status__c;
        r.message = l.Message__c;
        r.bookingId = l.Booking__c;
        r.bookingName = l.Booking__r == null ? null : l.Booking__r.Name;
        s.logs.add(r);
      }
      return s;
    } catch (Exception e) {
      throw fail(e);
    }
  }

  /** Sends availability and rates for this site now (bookings are fetched by the 15-minute run). */
  @AuraEnabled
  public static String pushNow(Id siteId) {
    try {
      if (!PMS_ChannexSync.enabled()) {
        throw new PMS_Exception(
          'The sync is switched off (PMS Settings > Channex Enabled).'
        );
      }
      PMS_Site__c visible = [
        SELECT Id
        FROM PMS_Site__c
        WHERE Id = :siteId
        WITH USER_MODE
      ];
      List<String> parts = new List<String>();
      for (PMS_Channel_Log__c l : PMS_ChannexSync.runPush(siteId)) {
        parts.add(l.Kind__c + ': ' + l.Message__c);
      }
      return parts.isEmpty() ? 'Nothing to send.' : String.join(parts, ' | ');
    } catch (Exception e) {
      throw fail(e);
    }
  }

  /** Queues a full run (fetch bookings, acknowledge, send ARI) right away. */
  @AuraEnabled
  public static void syncNow() {
    try {
      if (!PMS_ChannexSync.enabled()) {
        throw new PMS_Exception(
          'The sync is switched off (PMS Settings > Channex Enabled).'
        );
      }
      System.enqueueJob(new PMS_ChannexSync.Runner(PMS_ChannexSync.PULL));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  private static AuraHandledException fail(Exception e) {
    AuraHandledException ex = new AuraHandledException(e.getMessage());
    ex.setMessage(e.getMessage());
    return ex;
  }
}
