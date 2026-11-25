/**
 * GDPR erasure (anonymisation) of a guest. Core package.
 *
 * LEGAL REVIEW NEEDED. This class encodes assumptions that have NOT been reviewed by counsel:
 *  1. Anonymise, do not delete. The Contact (and its lookups from bookings, charges, invoices, payments) stays so that
 *     bookkeeping / tax records remain intact (typically a statutory retention duty, e.g. 6-10 years). Charges,
 *     invoices, payments, dunning events and payment plans are NOT modified. They hold no guest name themselves; they
 *     link to the (now anonymised) Contact / Account. Payment.Gateway_Reference__c (processor reference) is kept.
 *  2. Blocked (nothing changed) while the guest has: a primary or party booking in Tentative/Confirmed/Active with End__c
 *     in the future; any booking with Balance_Due__c > 0 or Refund_Due__c > 0; any Issued/Partially Paid/Overdue invoice with a
 *     balance on their bookings (legitimate interest / contract performance / debt collection outweigh erasure).
 *  3. DELETED: PMS_Guest_Preference__c; PMS_Intake_Form__c other than 'GDPR Consent'; CaseComment, Task, Event and
 *     EmailMessage (best effort) tied to the guest / their cases; Files linked to the Contact, their check-ins, intake forms
 *     and cases (a File that is also linked to another non-user record is only UNLINKED, not deleted).
 *  4. BLANKED (record kept): Contact PII (name -> Anonymised Guest, all contact/address/birthdate/free text/profile
 *     fields); personal guest Account (role exactly 'Guest', not Business, only this Contact) -> 'Anonymised Guest';
 *     GDPR Consent intake forms keep only Form_Type, Signed_Date, Consent_Given (evidence that consent was given, Art. 7(1));
 *     PMS_Check_In__c on the guest's primary bookings keep only Type/Guests/Occupants/Submitted_At/Terms_Accepted;
 *     Booking Special_Requests__c, access keys and saved-card references of the guest's PRIMARY bookings; Case
 *     Subject/Description/Supplied*; PMS_Channel_Log__c Details/Message of the guest's primary bookings;
 *     PMS_Document_Request__c signer name/email/IP/user agent (hash and signed status are kept, signature evidence is
 *     weakened: counsel to confirm).
 *  5. KEPT: stats numbers (non-identifying), Do-Not-Contact stays TRUE (suppression list), audit fields on Contact.
 *  6. NOT HANDLED: other people on shared bookings (party members keep their own data; check-ins on party-only
 *     bookings are not touched), Company Accounts, Stripe customer record (must be deleted in Stripe), backups, email
 *     archives outside Salesforce, EmailMessageRelation, Channex/OTA copies, Setup Audit / field history.
 *  7. Retention default: 36 months since last activity (see PMS_GuestRetentionBatch), FLAG mode by default.
 *
 * Security: runs WITHOUT sharing so it can reach every related record, so every public entry point requires the custom
 * permission PMS_Guest_Privacy. The only exception is anonymiseTrusted, used by the retention batch, which is an
 * admin-configured system job (mode ANONYMISE) and is not reachable from the UI.
 * Atomic: all DML for one call is in one transaction with a savepoint; any failure rolls everything back. Idempotent.
 */
public without sharing class PMS_GuestErasureService {
  public static final String PERMISSION = 'PMS_Guest_Privacy';
  private static final List<String> OPEN_STATUSES = new List<String>{
    'Tentative',
    'Confirmed',
    'Active'
  };
  private static final List<String> OPEN_INVOICE_STATUSES = new List<String>{
    'Issued',
    'Partially Paid',
    'Overdue'
  };
  private static final String GDPR_FORM = 'GDPR Consent';
  private static final String ANON_FIRST = 'Anonymised';
  private static final String ANON_LAST = 'Guest';
  private static final String ANON_ACCOUNT = 'Anonymised Guest';
  private static final String USER_PREFIX = '005';

  @TestVisible
  private static Boolean permissionOverride; // tests only: null = real check

  public class Result {
    @AuraEnabled
    public Boolean success = false;
    @AuraEnabled
    public Boolean blocked = false;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Map<String, Integer> counts = new Map<String, Integer>();
    @AuraEnabled
    public List<String> warnings = new List<String>();
  }

  public static Boolean hasPermission() {
    return permissionOverride != null
      ? permissionOverride
      : FeatureManagement.checkPermission(PERMISSION);
  }

  /** Single guest. Checks PMS_Guest_Privacy. */
  public static Result anonymise(Id contactId, String reason) {
    if (contactId == null) {
      return fail('No guest selected.');
    }
    return anonymise(new Set<Id>{ contactId }, reason).get(contactId);
  }

  /** Bulk. Checks PMS_Guest_Privacy. Every id gets a Result. */
  public static Map<Id, Result> anonymise(Set<Id> contactIds, String reason) {
    if (!hasPermission()) {
      Map<Id, Result> denied = new Map<Id, Result>();
      for (Id i : contactIds) {
        denied.put(i, fail('You do not have permission to anonymise guests.'));
      }
      return denied;
    }
    return run(contactIds, reason);
  }

  /** For PMS_GuestRetentionBatch only (system job, no UI user). */
  public static Map<Id, Result> anonymiseTrusted(
    Set<Id> contactIds,
    String reason
  ) {
    return run(contactIds, reason);
  }

  private static Result fail(String msg) {
    Result r = new Result();
    r.message = msg;
    return r;
  }

  private static Result blockedResult(String msg) {
    Result r = fail(msg);
    r.blocked = true;
    return r;
  }

  private static Map<Id, Result> run(Set<Id> contactIds, String reason) {
    Map<Id, Result> results = new Map<Id, Result>();
    if (contactIds == null || contactIds.isEmpty()) {
      return results;
    }
    String cleanReason = String.isBlank(reason)
      ? null
      : reason.trim().left(255);
    if (cleanReason == null) {
      for (Id i : contactIds) {
        results.put(i, fail('A reason is required.'));
      }
      return results;
    }

    Map<Id, Contact> contacts = new Map<Id, Contact>(
      [
        SELECT Id, AccountId, PMS_Anonymised__c
        FROM Contact
        WHERE Id IN :contactIds
      ]
    );
    Set<Id> work = new Set<Id>();
    for (Id i : contactIds) {
      Contact c = contacts.get(i);
      if (c == null) {
        results.put(i, fail('Guest not found.'));
      } else if (c.PMS_Anonymised__c == true) {
        Result r = new Result();
        r.success = true;
        r.message = 'Already anonymised. No changes made.';
        results.put(i, r);
      } else {
        work.add(i);
      }
    }
    if (work.isEmpty()) {
      return results;
    }

    // ---- bookings: primary and party ----
    Map<Id, Set<Id>> bookingContacts = new Map<Id, Set<Id>>(); // booking -> guests in work
    Map<Id, Set<Id>> primaryBookingsOf = new Map<Id, Set<Id>>(); // guest -> primary bookings
    Set<Id> partyBookingIds = new Set<Id>();
    for (PMS_Booking_Party__c p : [
      SELECT Booking__c, Contact__c
      FROM PMS_Booking_Party__c
      WHERE Contact__c IN :work
    ]) {
      addTo(bookingContacts, p.Booking__c, p.Contact__c);
      partyBookingIds.add(p.Booking__c);
    }
    Map<Id, PMS_Booking__c> bookings = new Map<Id, PMS_Booking__c>(
      [
        SELECT
          Id,
          Primary_Contact__c,
          Status__c,
          End__c,
          Balance_Due__c,
          Refund_Due__c
        FROM PMS_Booking__c
        WHERE Primary_Contact__c IN :work OR Id IN :partyBookingIds
      ]
    );
    for (PMS_Booking__c b : bookings.values()) {
      if (b.Primary_Contact__c != null && work.contains(b.Primary_Contact__c)) {
        addTo(bookingContacts, b.Id, b.Primary_Contact__c);
        addTo(primaryBookingsOf, b.Primary_Contact__c, b.Id);
      }
    }

    // ---- block rules ----
    Map<Id, String> blockedBy = new Map<Id, String>();
    Datetime nowTs = Datetime.now();
    for (PMS_Booking__c b : bookings.values()) {
      Set<Id> guests = bookingContacts.get(b.Id);
      if (guests == null) {
        continue;
      }
      String why = null;
      if (
        OPEN_STATUSES.contains(b.Status__c) &&
        b.End__c != null &&
        b.End__c >= nowTs
      ) {
        why = 'The guest has an in-house or upcoming booking.';
      } else if (b.Balance_Due__c != null && b.Balance_Due__c > 0) {
        why = 'The guest has an unpaid booking balance.';
      } else if (b.Refund_Due__c != null && b.Refund_Due__c > 0) {
        why = 'A refund is still owed to the guest.';
      }
      if (why != null) {
        for (Id g : guests) {
          if (!blockedBy.containsKey(g)) {
            blockedBy.put(g, why);
          }
        }
      }
    }
    for (PMS_Invoice__c inv : [
      SELECT Booking__c
      FROM PMS_Invoice__c
      WHERE
        Booking__c IN :bookings.keySet()
        AND Status__c IN :OPEN_INVOICE_STATUSES
        AND Balance__c > 0
    ]) {
      for (Id g : bookingContacts.get(inv.Booking__c)) {
        if (!blockedBy.containsKey(g)) {
          blockedBy.put(g, 'The guest has an unpaid invoice.');
        }
      }
    }
    for (Id g : blockedBy.keySet()) {
      results.put(g, blockedResult(blockedBy.get(g)));
      work.remove(g);
    }
    if (work.isEmpty()) {
      return results;
    }

    // ---- gather everything to touch (only for unblocked guests) ----
    Set<Id> primaryIds = new Set<Id>();
    for (Id g : work) {
      if (primaryBookingsOf.containsKey(g)) {
        primaryIds.addAll(primaryBookingsOf.get(g));
      }
    }
    Savepoint sp = Database.setSavepoint();
    Map<String, Integer> total = new Map<String, Integer>();
    List<String> warnings = new List<String>();
    try {
      scrub(work, contacts, primaryIds, cleanReason, total, warnings);
    } catch (Exception e) {
      Database.rollback(sp);
      for (Id g : work) {
        results.put(
          g,
          fail('Anonymisation failed and was rolled back: ' + e.getMessage())
        );
      }
      return results;
    }
    for (Id g : work) {
      Result r = new Result();
      r.success = true;
      r.message = 'Guest anonymised.';
      r.counts = total; // chunk totals (not per guest) - no PII
      r.warnings = warnings;
      results.put(g, r);
    }
    return results;
  }

  private static void scrub(
    Set<Id> work,
    Map<Id, Contact> contacts,
    Set<Id> primaryIds,
    String reason,
    Map<String, Integer> total,
    List<String> warnings
  ) {
    // Contacts
    List<Contact> cUpd = new List<Contact>();
    Set<Id> accountIds = new Set<Id>();
    for (Id g : work) {
      Contact src = contacts.get(g);
      if (src.AccountId != null) {
        accountIds.add(src.AccountId);
      }
      cUpd.add(
        new Contact(
          Id = g,
          Salutation = null,
          FirstName = ANON_FIRST,
          LastName = ANON_LAST,
          Title = null,
          Department = null,
          Email = null,
          Phone = null,
          MobilePhone = null,
          HomePhone = null,
          OtherPhone = null,
          Fax = null,
          AssistantName = null,
          AssistantPhone = null,
          Birthdate = null,
          Description = null,
          MailingStreet = null,
          MailingCity = null,
          MailingState = null,
          MailingPostalCode = null,
          MailingCountry = null,
          OtherStreet = null,
          OtherCity = null,
          OtherState = null,
          OtherPostalCode = null,
          OtherCountry = null,
          HasOptedOutOfEmail = true,
          DoNotCall = true,
          PMS_Do_Not_Contact__c = true,
          PMS_Marketing_Consent__c = false,
          PMS_Consent_Date__c = null,
          PMS_Consent_Source__c = null,
          PMS_ID_Verified__c = false,
          PMS_VIP_Level__c = null,
          PMS_VIP_Notes__c = null,
          PMS_Dietary__c = null,
          PMS_Accessibility_Needs__c = null,
          PMS_Language__c = null,
          PMS_OTA_Alias_Email__c = null,
          PMS_Possible_Duplicate_Of__c = null,
          PMS_Duplicate_Reason__c = null,
          PMS_Retention_Due__c = null,
          PMS_Anonymised__c = true,
          PMS_Anonymised_On__c = Datetime.now(),
          PMS_Anonymisation_Reason__c = reason,
          PMS_Anonymised_By__c = UserInfo.getUserId()
        )
      );
    }
    update cUpd;
    note(total, 'Contacts anonymised', cUpd.size());

    // Personal guest accounts: role exactly Guest, not Business, and only these contacts under it
    if (!accountIds.isEmpty()) {
      Map<Id, Integer> contactCount = new Map<Id, Integer>();
      for (AggregateResult ar : [
        SELECT AccountId a, COUNT(Id) n
        FROM Contact
        WHERE AccountId IN :accountIds
        GROUP BY AccountId
      ]) {
        contactCount.put((Id) ar.get('a'), (Integer) ar.get('n'));
      }
      Map<Id, Integer> workCount = new Map<Id, Integer>();
      for (Id g : work) {
        Id a = contacts.get(g).AccountId;
        if (a != null) {
          workCount.put(
            a,
            (workCount.containsKey(a) ? workCount.get(a) : 0) + 1
          );
        }
      }
      List<Account> aUpd = new List<Account>();
      for (Account a : [
        SELECT Id
        FROM Account
        WHERE
          Id IN :accountIds
          AND PMS_Party_Role__c = 'Guest'
          AND PMS_Customer_Type__c != 'Business'
      ]) {
        if (contactCount.get(a.Id) == workCount.get(a.Id)) {
          aUpd.add(
            new Account(
              Id = a.Id,
              Name = ANON_ACCOUNT,
              Phone = null,
              Fax = null,
              Website = null,
              Description = null,
              BillingStreet = null,
              BillingCity = null,
              BillingState = null,
              BillingPostalCode = null,
              BillingCountry = null,
              ShippingStreet = null,
              ShippingCity = null,
              ShippingState = null,
              ShippingPostalCode = null,
              ShippingCountry = null,
              Stripe_Customer_Id__c = null
            )
          );
        }
      }
      update aUpd;
      note(total, 'Personal guest accounts anonymised', aUpd.size());
    }

    // Preferences: deleted
    List<PMS_Guest_Preference__c> prefs = [
      SELECT Id
      FROM PMS_Guest_Preference__c
      WHERE Contact__c IN :work
    ];
    delete prefs;
    note(total, 'Guest preferences deleted', prefs.size());

    // Intake forms: GDPR Consent forms blanked (evidence), others deleted
    List<PMS_Intake_Form__c> forms = [
      SELECT Id, Form_Type__c
      FROM PMS_Intake_Form__c
      WHERE Contact__c IN :work OR Booking__c IN :primaryIds
    ];
    List<PMS_Intake_Form__c> formsDel = new List<PMS_Intake_Form__c>();
    List<PMS_Intake_Form__c> formsBlank = new List<PMS_Intake_Form__c>();
    Set<Id> formIds = new Set<Id>();
    for (PMS_Intake_Form__c f : forms) {
      formIds.add(f.Id);
      if (f.Form_Type__c == GDPR_FORM) {
        formsBlank.add(new PMS_Intake_Form__c(Id = f.Id, Responses__c = null));
      } else {
        formsDel.add(f);
      }
    }
    update formsBlank;
    note(
      total,
      'GDPR consent forms blanked (kept as evidence)',
      formsBlank.size()
    );

    // Check-ins on primary bookings: blank
    List<PMS_Check_In__c> cis = [
      SELECT Id
      FROM PMS_Check_In__c
      WHERE Booking__c IN :primaryIds
    ];
    List<PMS_Check_In__c> ciUpd = new List<PMS_Check_In__c>();
    Set<Id> ciIds = new Set<Id>();
    for (PMS_Check_In__c ci : cis) {
      ciIds.add(ci.Id);
      ciUpd.add(
        new PMS_Check_In__c(
          Id = ci.Id,
          Full_Name__c = null,
          Address__c = null,
          Date_Of_Birth__c = null,
          Emergency_Contact__c = null,
          ID_Number__c = null,
          ID_Type__c = null,
          Nationality__c = null,
          Phone__c = null,
          Special_Requests__c = null,
          Vehicle_Registration__c = null,
          Arrival_Time__c = null
        )
      );
    }
    update ciUpd;
    note(total, 'Check-ins blanked', ciUpd.size());

    // Primary bookings: free text, access keys, saved-card references
    List<PMS_Booking__c> bUpd = new List<PMS_Booking__c>();
    for (Id b : primaryIds) {
      bUpd.add(
        new PMS_Booking__c(
          Id = b,
          Special_Requests__c = null,
          Web_Access_Key__c = null,
          Check_In_Key__c = null,
          Card_Last4__c = null,
          Card_Expiry__c = null,
          Stripe_Payment_Method__c = null
        )
      );
    }
    update bUpd;
    note(total, 'Bookings blanked', bUpd.size());

    // Channel payloads
    List<PMS_Channel_Log__c> logs = [
      SELECT Id
      FROM PMS_Channel_Log__c
      WHERE Booking__c IN :primaryIds
    ];
    for (PMS_Channel_Log__c l : logs) {
      l.Details__c = null;
      l.Message__c = null;
    }
    update logs;
    note(total, 'Channel log payloads purged', logs.size());

    // Cases
    List<Case> cases = [
      SELECT Id
      FROM Case
      WHERE ContactId IN :work OR PMS_Booking__c IN :primaryIds
    ];
    Set<Id> caseIds = new Map<Id, Case>(cases).keySet();
    for (Case c : cases) {
      c.Subject = ANON_FIRST;
      c.Description = null;
      c.SuppliedName = null;
      c.SuppliedEmail = null;
      c.SuppliedPhone = null;
      c.SuppliedCompany = null;
    }
    update cases;
    note(total, 'Cases blanked', cases.size());
    List<CaseComment> comments = [
      SELECT Id
      FROM CaseComment
      WHERE ParentId IN :caseIds
    ];
    delete comments;
    note(total, 'Case comments deleted', comments.size());

    // Document requests (signer details)
    List<PMS_Document_Request__c> docs = [
      SELECT Id
      FROM PMS_Document_Request__c
      WHERE Contact__c IN :work
    ];
    for (PMS_Document_Request__c d : docs) {
      d.Signer_Name__c = ANON_FIRST;
      d.Signer_Email__c = null;
      d.Signer_IP__c = null;
      d.Signer_User_Agent__c = null;
      d.Message__c = null;
    }
    update docs;
    note(total, 'Document requests: signer details blanked', docs.size());

    delete formsDel;
    note(total, 'Intake forms deleted', formsDel.size());

    // Activities / email: best effort, failures reported (not silent)
    bestEffortDelete(
      [SELECT Id FROM Task WHERE WhoId IN :work],
      'Tasks',
      total,
      warnings
    );
    bestEffortDelete(
      [SELECT Id FROM Event WHERE WhoId IN :work],
      'Events',
      total,
      warnings
    );
    bestEffortDelete(
      [SELECT Id FROM EmailMessage WHERE ParentId IN :caseIds],
      'Case emails',
      total,
      warnings
    );

    // Files
    Set<Id> entities = new Set<Id>(work);
    entities.addAll(ciIds);
    entities.addAll(formIds);
    entities.addAll(caseIds);
    deleteFiles(entities, total);
  }

  private static void deleteFiles(
    Set<Id> entities,
    Map<String, Integer> total
  ) {
    List<ContentDocumentLink> mine = [
      SELECT Id, ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :entities
    ];
    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink l : mine) {
      docIds.add(l.ContentDocumentId);
    }
    if (docIds.isEmpty()) {
      return;
    }
    Set<Id> shared = new Set<Id>();
    for (ContentDocumentLink l : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE ContentDocumentId IN :docIds AND LinkedEntityId NOT IN :entities
    ]) {
      if (!String.valueOf(l.LinkedEntityId).startsWith(USER_PREFIX)) {
        shared.add(l.ContentDocumentId);
      }
    }
    Set<Id> toDelete = docIds.clone();
    toDelete.removeAll(shared);
    List<ContentDocumentLink> unlink = new List<ContentDocumentLink>();
    for (ContentDocumentLink l : mine) {
      if (shared.contains(l.ContentDocumentId)) {
        unlink.add(l);
      }
    }
    delete unlink;
    List<ContentDocument> del = new List<ContentDocument>();
    for (Id d : toDelete) {
      del.add(new ContentDocument(Id = d));
    }
    delete del;
    note(total, 'Files deleted', del.size());
    note(total, 'Shared files unlinked only', unlink.size());
  }

  private static void bestEffortDelete(
    List<SObject> rows,
    String label,
    Map<String, Integer> total,
    List<String> warnings
  ) {
    if (rows.isEmpty()) {
      return;
    }
    Integer ok = 0;
    for (Database.DeleteResult dr : Database.delete(rows, false)) {
      if (dr.isSuccess()) {
        ok++;
      }
    }
    note(total, label + ' deleted', ok);
    if (ok < rows.size()) {
      warnings.add(
        label +
          ': ' +
          (rows.size() - ok) +
          ' could not be deleted; remove manually.'
      );
    }
  }

  private static void note(Map<String, Integer> m, String key, Integer n) {
    m.put(key, (m.containsKey(key) ? m.get(key) : 0) + n);
  }

  private static void addTo(Map<Id, Set<Id>> m, Id key, Id val) {
    if (!m.containsKey(key)) {
      m.put(key, new Set<Id>());
    }
    m.get(key).add(val);
  }
}
