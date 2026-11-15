/**
 * Hotel night audit for a business date:
 *  - posts the room charge for every in-house guest (one Charge per Room Night, never twice)
 *  - marks confirmed arrivals that never checked in as No Show
 */
public with sharing class PMS_NightAuditBatch implements Database.Batchable<SObject> {
  private final Date businessDate;

  public PMS_NightAuditBatch() {
    this(Date.today().addDays(-1));
  }

  public PMS_NightAuditBatch(Date businessDate) {
    this.businessDate = businessDate;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Date d = businessDate;
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Stay_Date__c,
          Rate__c,
          Status__c,
          Reservation__c,
          Reservation__r.Status__c,
          Reservation__r.Account__c,
          Reservation__r.Rate_Plan__r.Tax_Rate__c,
          Room__r.Name
        FROM PMS_Room_Night__c
        WHERE Stay_Date__c = :d AND Status__c IN ('Reserved', 'In House')
      ]
    );
  }

  public void execute(
    Database.BatchableContext bc,
    List<PMS_Room_Night__c> scope
  ) {
    process(scope);
  }

  public void finish(Database.BatchableContext bc) {
  }

  public static void process(List<PMS_Room_Night__c> nights) {
    Decimal defaultTax = PMS_ModuleConfig.defaultTaxRate(
      PMS_ModuleConfig.HOTEL
    );
    List<PMS_Charge__c> charges = new List<PMS_Charge__c>();
    List<PMS_Room_Night__c> nightUpdates = new List<PMS_Room_Night__c>();
    Set<Id> noShowIds = new Set<Id>();
    for (PMS_Room_Night__c rn : nights) {
      String stayStatus = rn.Reservation__r.Status__c;
      if (stayStatus == 'Active' || stayStatus == 'Completed') {
        Decimal tax = rn.Reservation__r.Rate_Plan__r?.Tax_Rate__c;
        charges.add(
          new PMS_Charge__c(
            Booking__c = rn.Reservation__c,
            Account__c = rn.Reservation__r.Account__c,
            Charge_Type__c = 'Room Night',
            Description__c = 'Room ' +
              (rn.Room__r == null ? '' : rn.Room__r.Name) +
              ' - night of ' +
              String.valueOf(rn.Stay_Date__c),
            Quantity__c = 1,
            Unit_Price__c = rn.Rate__c == null ? 0 : rn.Rate__c,
            Tax_Rate__c = tax == null ? defaultTax : tax,
            Service_Date__c = rn.Stay_Date__c,
            Status__c = 'Pending'
          )
        );
        nightUpdates.add(
          new PMS_Room_Night__c(Id = rn.Id, Status__c = 'Posted')
        );
      } else if (stayStatus == 'Confirmed' || stayStatus == 'Tentative') {
        noShowIds.add(rn.Reservation__c);
      }
    }
    if (!charges.isEmpty()) {
      insert charges;
    }
    if (!nightUpdates.isEmpty()) {
      update nightUpdates;
    }
    if (!noShowIds.isEmpty()) {
      List<PMS_Booking__c> noShows = new List<PMS_Booking__c>();
      for (Id bId : noShowIds) {
        noShows.add(new PMS_Booking__c(Id = bId, Status__c = 'No Show'));
      }
      update noShows; // trigger releases the remaining nights back to inventory
    }
  }
}
