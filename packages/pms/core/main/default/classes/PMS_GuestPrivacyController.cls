/**
 * Guest privacy actions for the Contact record page: right-of-access export and anonymisation.
 * Runs WITH sharing; both actions need the custom permission PMS_Guest_Privacy. The export reads through
 * Security.stripInaccessible, so a user only exports what their own FLS allows (the export is therefore only as
 * complete as the privacy admin's access: grant the Guest Privacy Admin permission set read access to every object
 * listed below). Files: names only, never contents. Party-only bookings are exported without amounts or special requests.
 */
public with sharing class PMS_GuestPrivacyController {
  // setMessage so the text reaches the LWC and is also readable in Apex tests.
  private static AuraHandledException fail(String msg) {
    AuraHandledException e = new AuraHandledException(msg);
    e.setMessage(msg);
    return e;
  }

  private static final Integer ROW_LIMIT = 2000;

  @AuraEnabled(cacheable=true)
  public static Boolean canManage() {
    return PMS_GuestErasureService.hasPermission();
  }

  /** Returns pretty-printed JSON of everything held about the guest. */
  @AuraEnabled
  public static String exportGuestData(Id contactId) {
    requirePermission();
    if (contactId == null) {
      throw fail('No guest selected.');
    }
    try {
      Map<String, Object> out = new Map<String, Object>();
      out.put('exportedOn', Datetime.now());
      out.put('contactId', contactId);
      List<Contact> c = (List<Contact>) strip(
        [
          SELECT FIELDS(STANDARD)
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ]
      );
      if (c.isEmpty()) {
        throw fail('Guest not found.');
      }
      out.put('contact', c[0]);
      Set<Id> accountIds = new Set<Id>();
      if (c[0].AccountId != null) {
        accountIds.add(c[0].AccountId);
      }
      out.put(
        'contactCustomFields',
        strip(
          [
            SELECT
              PMS_Language__c,
              PMS_Dietary__c,
              PMS_Accessibility_Needs__c,
              PMS_VIP_Level__c,
              PMS_VIP_Notes__c,
              PMS_OTA_Alias_Email__c,
              PMS_Marketing_Consent__c,
              PMS_Consent_Date__c,
              PMS_Consent_Source__c,
              PMS_Do_Not_Contact__c,
              PMS_ID_Verified__c,
              PMS_Total_Stays__c,
              PMS_Lifetime_Nights__c,
              PMS_First_Stay__c,
              PMS_Last_Stay__c,
              PMS_Next_Arrival__c,
              PMS_Room_Revenue__c,
              PMS_Extras_Revenue__c
            FROM Contact
            WHERE Id = :contactId
          ]
        )
      );
      out.put(
        'accounts',
        strip(
          [
            SELECT Id, Name, Phone, BillingAddress, ShippingAddress
            FROM Account
            WHERE Id IN :accountIds
          ]
        )
      );
      out.put(
        'preferences',
        strip(
          [
            SELECT Category__c, Value__c, Source__c, Captured_On__c, Active__c
            FROM PMS_Guest_Preference__c
            WHERE Contact__c = :contactId
            LIMIT :ROW_LIMIT
          ]
        )
      );
      out.put(
        'bookingParties',
        strip(
          [
            SELECT Booking__c, Role__c, Is_Primary__c
            FROM PMS_Booking_Party__c
            WHERE Contact__c = :contactId
            LIMIT :ROW_LIMIT
          ]
        )
      );
      Set<Id> partyBookings = new Set<Id>();
      for (PMS_Booking_Party__c p : [
        SELECT Booking__c
        FROM PMS_Booking_Party__c
        WHERE Contact__c = :contactId
        LIMIT :ROW_LIMIT
      ]) {
        partyBookings.add(p.Booking__c);
      }
      List<PMS_Booking__c> primary = [
        SELECT
          Id,
          Name,
          Status__c,
          Start__c,
          End__c,
          Adults__c,
          Children__c,
          Channel__c,
          OTA_Name__c,
          Special_Requests__c,
          Total_Amount__c,
          Amount_Paid__c,
          Card_Brand__c,
          Card_Last4__c
        FROM PMS_Booking__c
        WHERE Primary_Contact__c = :contactId
        LIMIT :ROW_LIMIT
      ];
      Set<Id> primaryIds = new Map<Id, PMS_Booking__c>(primary).keySet();
      partyBookings.removeAll(primaryIds);
      out.put('bookingsAsPrimaryGuest', strip(primary));
      out.put(
        'bookingsAsPartyMember',
        strip(
          [
            SELECT Id, Name, Status__c, Start__c, End__c
            FROM PMS_Booking__c
            WHERE Id IN :partyBookings
            LIMIT :ROW_LIMIT
          ]
        )
      );
      out.put(
        'charges',
        strip(
          [
            SELECT
              Id,
              Charge_Type__c,
              Description__c,
              Service_Date__c,
              Quantity__c,
              Unit_Price__c,
              Gross_Amount__c,
              Status__c,
              Booking__c,
              Invoice__c
            FROM PMS_Charge__c
            WHERE Booking__c IN :primaryIds
            LIMIT :ROW_LIMIT
          ]
        )
      );
      out.put(
        'invoices',
        strip(
          [
            SELECT
              Id,
              Name,
              Issue_Date__c,
              Due_Date__c,
              Status__c,
              Total__c,
              Amount_Paid__c,
              Booking__c
            FROM PMS_Invoice__c
            WHERE Booking__c IN :primaryIds
            LIMIT :ROW_LIMIT
          ]
        )
      );
      out.put(
        'payments',
        strip(
          [
            SELECT
              Id,
              Amount__c,
              Method__c,
              Payment_Type__c,
              Status__c,
              Received_Date__c,
              Booking__c,
              Invoice__c
            FROM PMS_Payment__c
            WHERE Booking__c IN :primaryIds
            LIMIT :ROW_LIMIT
          ]
        )
      );
      out.put(
        'checkIns',
        strip(
          [
            SELECT
              Id,
              Booking__c,
              Full_Name__c,
              Address__c,
              Date_Of_Birth__c,
              Emergency_Contact__c,
              ID_Type__c,
              ID_Number__c,
              Nationality__c,
              Phone__c,
              Special_Requests__c,
              Vehicle_Registration__c,
              Arrival_Time__c,
              Guests__c,
              Occupants__c,
              Terms_Accepted__c,
              Submitted_At__c,
              Submitted_Via__c
            FROM PMS_Check_In__c
            WHERE Booking__c IN :primaryIds
            LIMIT :ROW_LIMIT
          ]
        )
      );
      List<PMS_Intake_Form__c> forms = (List<PMS_Intake_Form__c>) strip(
        [
          SELECT
            Id,
            Form_Type__c,
            Signed_Date__c,
            Consent_Given__c,
            Responses__c,
            Booking__c
          FROM PMS_Intake_Form__c
          WHERE Contact__c = :contactId OR Booking__c IN :primaryIds
          LIMIT :ROW_LIMIT
        ]
      );
      out.put('intakeForms', forms);
      List<Case> cases = (List<Case>) strip(
        [
          SELECT
            Id,
            CaseNumber,
            Subject,
            Description,
            Status,
            CreatedDate,
            SuppliedName,
            SuppliedEmail,
            SuppliedPhone
          FROM Case
          WHERE ContactId = :contactId OR PMS_Booking__c IN :primaryIds
          LIMIT :ROW_LIMIT
        ]
      );
      out.put('cases', cases);
      Set<Id> entities = new Set<Id>{ contactId };
      for (PMS_Intake_Form__c f : forms) {
        entities.add(f.Id);
      }
      for (Case cs : cases) {
        entities.add(cs.Id);
      }
      for (PMS_Check_In__c ci : [
        SELECT Id
        FROM PMS_Check_In__c
        WHERE Booking__c IN :primaryIds
        LIMIT :ROW_LIMIT
      ]) {
        entities.add(ci.Id);
      }
      List<Map<String, Object>> files = new List<Map<String, Object>>();
      for (ContentDocumentLink l : [
        SELECT
          LinkedEntityId,
          ContentDocument.Title,
          ContentDocument.FileExtension,
          ContentDocument.CreatedDate
        FROM ContentDocumentLink
        WHERE LinkedEntityId IN :entities
        LIMIT :ROW_LIMIT
      ]) {
        files.add(
          new Map<String, Object>{
            'linkedTo' => l.LinkedEntityId,
            'title' => l.ContentDocument.Title,
            'extension' => l.ContentDocument.FileExtension,
            'created' => l.ContentDocument.CreatedDate
          }
        );
      }
      out.put('fileNames', files);
      return JSON.serializePretty(out, true);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw fail('Export failed: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static PMS_GuestErasureService.Result anonymiseGuest(
    Id contactId,
    String reason
  ) {
    requirePermission();
    return PMS_GuestErasureService.anonymise(contactId, reason);
  }

  private static void requirePermission() {
    if (!PMS_GuestErasureService.hasPermission()) {
      throw fail('You do not have permission to manage guest privacy.');
    }
  }

  private static List<SObject> strip(List<SObject> rows) {
    return Security.stripInaccessible(AccessType.READABLE, rows).getRecords();
  }
}
