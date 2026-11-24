/**
 * Guest 360 read-only controller. Runs with sharing; field/object access is
 * enforced via describe checks and Security.stripInaccessible so that a user
 * lacking access gets null fields / empty sections (with accessible=false)
 * instead of an exception. Fixed query budget: Guest360 = 8 (Contact, party,
 * upcoming, past, primary booking ids, preferences, cases, intake form;
 * party and booking queries only when Booking is readable), GuestCard = 3 (balance counts primary bookings only).
 *
 * Security-review notes (filter-only fields, used in WHERE/ORDER BY, never returned):
 *   PMS_Booking__c: Primary_Contact__c (also read to compute viaParty), End__c (filter),
 *     Status__c (card filter); PMS_Booking_Party__c: Contact__c, Booking__c (ORDER BY Booking__r.End__c);
 *   PMS_Guest_Preference__c: Contact__c, Active__c; PMS_Intake_Form__c: Contact__c, Form_Type__c;
 *   Case: ContactId, PMS_Booking__c, IsClosed (ORDER BY). Result fields are stripped via
 *   Security.stripInaccessible. Party-only bookings return no amounts or special requests.
 */
public with sharing class PMS_Guest360Controller {
  private static final Integer UPCOMING_LIMIT = 5;
  private static final Integer PAST_LIMIT = 10;
  private static final Integer PREF_LIMIT = 50;
  private static final Integer CASE_LIMIT = 10;
  private static final Integer CARD_PREF_LIMIT = 3;
  private static final Integer PARTY_LIMIT = 500;
  private static final Integer CARD_BOOKING_LIMIT = 200;
  private static final String GDPR_FORM = 'GDPR Consent';
  private static final String GENERIC_ERROR = 'Guest information is not available.';

  // ---------- DTOs ----------
  public class Guest360 {
    @AuraEnabled
    public Identity identity;
    @AuraEnabled
    public Stats stats;
    @AuraEnabled
    public StaySection upcomingStays = new StaySection();
    @AuraEnabled
    public StaySection pastStays = new StaySection();
    @AuraEnabled
    public PrefSection preferences = new PrefSection();
    @AuraEnabled
    public CaseSection service = new CaseSection();
    @AuraEnabled
    public Consent consent;
  }
  public class Identity {
    @AuraEnabled
    public Id contactId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String language;
    @AuraEnabled
    public String vipLevel;
    @AuraEnabled
    public String vipNotes;
    @AuraEnabled
    public String dietary;
    @AuraEnabled
    public String accessibilityNeeds;
    @AuraEnabled
    public Boolean idVerified;
  }
  public class Stats {
    @AuraEnabled
    public Boolean accessible = false;
    @AuraEnabled
    public Decimal totalStays;
    @AuraEnabled
    public Decimal lifetimeNights;
    @AuraEnabled
    public Decimal roomRevenue;
    @AuraEnabled
    public Decimal extrasRevenue;
    @AuraEnabled
    public Date firstStay;
    @AuraEnabled
    public Date lastStay;
    @AuraEnabled
    public Date nextArrival;
    @AuraEnabled
    public Datetime refreshedOn;
  }
  public class Stay {
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String spaceName;
    @AuraEnabled
    public String channel;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public Decimal balanceDue;
    @AuraEnabled
    public String specialRequests;
    @AuraEnabled
    public Boolean viaParty = false;
  }
  public class StaySection {
    @AuraEnabled
    public Boolean accessible = false;
    @AuraEnabled
    public List<Stay> items = new List<Stay>();
  }
  public class Preference {
    @AuraEnabled
    public Id preferenceId;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Date capturedOn;
  }
  public class PrefSection {
    @AuraEnabled
    public Boolean accessible = false;
    @AuraEnabled
    public List<Preference> items = new List<Preference>();
  }
  public class ServiceCase {
    @AuraEnabled
    public Id caseId;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String priority;
    @AuraEnabled
    public Boolean isClosed;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public Id bookingId;
  }
  public class CaseSection {
    @AuraEnabled
    public Boolean accessible = false;
    @AuraEnabled
    public List<ServiceCase> items = new List<ServiceCase>();
  }
  public class Consent {
    @AuraEnabled
    public Boolean accessible = false;
    @AuraEnabled
    public Boolean marketingConsent;
    @AuraEnabled
    public Datetime consentDate;
    @AuraEnabled
    public String consentSource;
    @AuraEnabled
    public Boolean doNotContact;
    @AuraEnabled
    public Boolean formAccessible = false;
    @AuraEnabled
    public Boolean gdprFormConsentGiven;
    @AuraEnabled
    public Datetime gdprFormDate;
  }
  public class GuestCard {
    @AuraEnabled
    public Id contactId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String vipLevel;
    @AuraEnabled
    public String dietary;
    @AuraEnabled
    public String accessibilityNeeds;
    @AuraEnabled
    public Boolean idVerified;
    @AuraEnabled
    public List<Preference> topPreferences = new List<Preference>();
    @AuraEnabled
    public Decimal balanceDue;
    @AuraEnabled
    public Boolean balanceAccessible = false;
    @AuraEnabled
    public Date nextArrival;
  }

  // ---------- Entry points ----------
  @AuraEnabled(cacheable=true)
  public static Guest360 getGuest360(Id contactId) {
    Map<String, Object> c = loadContact(contactId);
    Guest360 g = new Guest360();
    g.identity = buildIdentity(contactId, c);
    g.stats = buildStats(c);
    g.consent = buildConsent(c);

    Datetime todayStart = Datetime.newInstance(
      Date.today(),
      Time.newInstance(0, 0, 0, 0)
    );
    Set<Id> guestBookingIds = new Set<Id>();

    if (canRead(PMS_Booking__c.SObjectType)) {
      Set<Id> partyBookingIds = partyBookingIds(contactId);
      g.upcomingStays.accessible = true;
      g.pastStays.accessible = true;
      for (
        SObject r : strip(
          [
            SELECT
              Name,
              Primary_Contact__c,
              Start__c,
              End__c,
              Status__c,
              Space__r.Name,
              Channel__c,
              Total_Amount__c,
              Balance_Due__c,
              Special_Requests__c
            FROM PMS_Booking__c
            WHERE
              (Primary_Contact__c = :contactId
              OR Id IN :partyBookingIds)
              AND End__c >= :todayStart
            ORDER BY Start__c ASC
            LIMIT :UPCOMING_LIMIT
          ]
        )
      ) {
        g.upcomingStays.items.add(toStay(r, contactId));
      }
      for (
        SObject r : strip(
          [
            SELECT
              Name,
              Primary_Contact__c,
              Start__c,
              End__c,
              Status__c,
              Space__r.Name,
              Channel__c,
              Total_Amount__c,
              Balance_Due__c,
              Special_Requests__c
            FROM PMS_Booking__c
            WHERE
              (Primary_Contact__c = :contactId
              OR Id IN :partyBookingIds)
              AND End__c < :todayStart
            ORDER BY End__c DESC
            LIMIT :PAST_LIMIT
          ]
        )
      ) {
        g.pastStays.items.add(toStay(r, contactId));
      }
    }

    if (canRead(PMS_Guest_Preference__c.SObjectType)) {
      g.preferences.accessible = true;
      g.preferences.items = toPrefs(
        strip(
          [
            SELECT Category__c, Value__c, Source__c, Captured_On__c
            FROM PMS_Guest_Preference__c
            WHERE Contact__c = :contactId AND Active__c = TRUE
            ORDER BY Category__c ASC, Captured_On__c DESC
            LIMIT :PREF_LIMIT
          ]
        )
      );
    }

    if (canRead(Case.SObjectType)) {
      g.service.accessible = true;
      // Only bookings where the guest is primary link cases; party-only bookings
      // contribute cases solely via Case.ContactId (data minimisation).
      if (canRead(PMS_Booking__c.SObjectType)) {
        for (PMS_Booking__c b : [
          SELECT Id
          FROM PMS_Booking__c
          WHERE Primary_Contact__c = :contactId
          LIMIT :PARTY_LIMIT
        ]) {
          guestBookingIds.add(b.Id);
        }
      }
      for (
        SObject r : strip(
          [
            SELECT
              CaseNumber,
              Subject,
              Status,
              Priority,
              IsClosed,
              CreatedDate,
              PMS_Booking__c
            FROM Case
            WHERE ContactId = :contactId OR PMS_Booking__c IN :guestBookingIds
            ORDER BY IsClosed ASC, CreatedDate DESC
            LIMIT :CASE_LIMIT
          ]
        )
      ) {
        Map<String, Object> m = r.getPopulatedFieldsAsMap();
        ServiceCase sc = new ServiceCase();
        sc.caseId = r.Id;
        sc.caseNumber = (String) m.get('CaseNumber');
        sc.subject = (String) m.get('Subject');
        sc.status = (String) m.get('Status');
        sc.priority = (String) m.get('Priority');
        sc.isClosed = (Boolean) m.get('IsClosed');
        sc.createdDate = (Datetime) m.get('CreatedDate');
        sc.bookingId = (Id) m.get('PMS_Booking__c');
        g.service.items.add(sc);
      }
    }

    if (canRead(PMS_Intake_Form__c.SObjectType)) {
      g.consent.formAccessible = true;
      for (
        SObject r : strip(
          [
            SELECT Consent_Given__c, CreatedDate
            FROM PMS_Intake_Form__c
            WHERE Contact__c = :contactId AND Form_Type__c = :GDPR_FORM
            ORDER BY CreatedDate DESC
            LIMIT 1
          ]
        )
      ) {
        Map<String, Object> m = r.getPopulatedFieldsAsMap();
        g.consent.gdprFormConsentGiven = (Boolean) m.get('Consent_Given__c');
        g.consent.gdprFormDate = (Datetime) m.get('CreatedDate');
      }
    }
    return g;
  }

  @AuraEnabled(cacheable=true)
  public static GuestCard getGuestCard(Id contactId) {
    Map<String, Object> c = loadContact(contactId);
    GuestCard card = new GuestCard();
    card.contactId = contactId;
    card.name = (String) c.get('Name');
    card.vipLevel = (String) c.get('PMS_VIP_Level__c');
    card.dietary = (String) c.get('PMS_Dietary__c');
    card.accessibilityNeeds = (String) c.get('PMS_Accessibility_Needs__c');
    card.idVerified = (Boolean) c.get('PMS_ID_Verified__c');
    card.nextArrival = (Date) c.get('PMS_Next_Arrival__c');

    if (canRead(PMS_Guest_Preference__c.SObjectType)) {
      card.topPreferences = toPrefs(
        strip(
          [
            SELECT Category__c, Value__c, Source__c, Captured_On__c
            FROM PMS_Guest_Preference__c
            WHERE Contact__c = :contactId AND Active__c = TRUE
            ORDER BY Captured_On__c DESC NULLS LAST
            LIMIT :CARD_PREF_LIMIT
          ]
        )
      );
    }

    if (canRead(PMS_Booking__c.SObjectType)) {
      Datetime todayStart = Datetime.newInstance(
        Date.today(),
        Time.newInstance(0, 0, 0, 0)
      );
      Decimal total = 0;
      Boolean hasAny = false;
      for (
        SObject r : strip(
          [
            SELECT Balance_Due__c
            FROM PMS_Booking__c
            WHERE
              Primary_Contact__c = :contactId
              AND End__c >= :todayStart
              AND Status__c IN ('Tentative', 'Confirmed', 'Active')
            LIMIT :CARD_BOOKING_LIMIT
          ]
        )
      ) {
        Object b = r.getPopulatedFieldsAsMap().get('Balance_Due__c');
        if (b != null) {
          hasAny = true;
          total += (Decimal) b;
        }
      }
      card.balanceAccessible = hasAny || r_hasBalanceAccess();
      card.balanceDue = card.balanceAccessible ? total : null;
    }
    return card;
  }

  // ---------- Helpers ----------
  private static Boolean r_hasBalanceAccess() {
    return PMS_Booking__c.Balance_Due__c.getDescribe().isAccessible();
  }

  private static Boolean canRead(Schema.SObjectType t) {
    return t.getDescribe().isAccessible();
  }

  private static List<SObject> strip(List<SObject> rows) {
    if (rows.isEmpty()) {
      return rows;
    }
    return Security.stripInaccessible(AccessType.READABLE, rows).getRecords();
  }

  private static Map<String, Object> loadContact(Id contactId) {
    if (
      contactId == null ||
      contactId.getSObjectType() != Contact.SObjectType ||
      !canRead(Contact.SObjectType)
    ) {
      throw new AuraHandledException(GENERIC_ERROR);
    }
    List<Contact> rows = [
      SELECT
        Name,
        Email,
        Phone,
        Account.Name,
        PMS_Language__c,
        PMS_VIP_Level__c,
        PMS_VIP_Notes__c,
        PMS_Dietary__c,
        PMS_Accessibility_Needs__c,
        PMS_ID_Verified__c,
        PMS_Total_Stays__c,
        PMS_Lifetime_Nights__c,
        PMS_Room_Revenue__c,
        PMS_Extras_Revenue__c,
        PMS_First_Stay__c,
        PMS_Last_Stay__c,
        PMS_Next_Arrival__c,
        PMS_Stats_Refreshed__c,
        PMS_Marketing_Consent__c,
        PMS_Consent_Date__c,
        PMS_Consent_Source__c,
        PMS_Do_Not_Contact__c
      FROM Contact
      WHERE Id = :contactId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException(GENERIC_ERROR);
    }
    SObject stripped = strip(rows)[0];
    Map<String, Object> m = new Map<String, Object>(
      stripped.getPopulatedFieldsAsMap()
    );
    // Parent relationship is only trustworthy if the user can read Account.
    if (!canRead(Account.SObjectType)) {
      m.remove('Account');
    }
    return m;
  }

  private static Set<Id> partyBookingIds(Id contactId) {
    Set<Id> ids = new Set<Id>();
    if (!canRead(PMS_Booking_Party__c.SObjectType)) {
      return ids;
    }
    for (PMS_Booking_Party__c p : [
      SELECT Booking__c
      FROM PMS_Booking_Party__c
      WHERE Contact__c = :contactId
      ORDER BY Booking__r.End__c DESC
      LIMIT :PARTY_LIMIT
    ]) {
      ids.add(p.Booking__c);
    }
    return ids;
  }

  private static Identity buildIdentity(Id contactId, Map<String, Object> c) {
    Identity i = new Identity();
    i.contactId = contactId;
    i.name = (String) c.get('Name');
    i.email = (String) c.get('Email');
    i.phone = (String) c.get('Phone');
    SObject acct = (SObject) c.get('Account');
    if (acct != null) {
      i.accountName = (String) acct.get('Name');
    }
    i.language = (String) c.get('PMS_Language__c');
    i.vipLevel = (String) c.get('PMS_VIP_Level__c');
    i.vipNotes = (String) c.get('PMS_VIP_Notes__c');
    i.dietary = (String) c.get('PMS_Dietary__c');
    i.accessibilityNeeds = (String) c.get('PMS_Accessibility_Needs__c');
    i.idVerified = (Boolean) c.get('PMS_ID_Verified__c');
    return i;
  }

  private static Stats buildStats(Map<String, Object> c) {
    Stats s = new Stats();
    s.totalStays = (Decimal) c.get('PMS_Total_Stays__c');
    s.lifetimeNights = (Decimal) c.get('PMS_Lifetime_Nights__c');
    s.roomRevenue = (Decimal) c.get('PMS_Room_Revenue__c');
    s.extrasRevenue = (Decimal) c.get('PMS_Extras_Revenue__c');
    s.firstStay = (Date) c.get('PMS_First_Stay__c');
    s.lastStay = (Date) c.get('PMS_Last_Stay__c');
    s.nextArrival = (Date) c.get('PMS_Next_Arrival__c');
    s.refreshedOn = (Datetime) c.get('PMS_Stats_Refreshed__c');
    s.accessible =
      c.containsKey('PMS_Total_Stays__c') ||
      c.containsKey('PMS_Lifetime_Nights__c') ||
      c.containsKey('PMS_Room_Revenue__c') ||
      c.containsKey('PMS_Extras_Revenue__c') ||
      c.containsKey('PMS_First_Stay__c') ||
      c.containsKey('PMS_Last_Stay__c') ||
      c.containsKey('PMS_Next_Arrival__c') ||
      c.containsKey('PMS_Stats_Refreshed__c');
    return s;
  }

  private static Consent buildConsent(Map<String, Object> c) {
    Consent k = new Consent();
    k.marketingConsent = (Boolean) c.get('PMS_Marketing_Consent__c');
    k.consentDate = (Datetime) c.get('PMS_Consent_Date__c');
    k.consentSource = (String) c.get('PMS_Consent_Source__c');
    k.doNotContact = (Boolean) c.get('PMS_Do_Not_Contact__c');
    k.accessible =
      c.containsKey('PMS_Marketing_Consent__c') ||
      c.containsKey('PMS_Consent_Date__c') ||
      c.containsKey('PMS_Consent_Source__c') ||
      c.containsKey('PMS_Do_Not_Contact__c');
    return k;
  }

  private static Stay toStay(SObject r, Id contactId) {
    Map<String, Object> m = r.getPopulatedFieldsAsMap();
    Stay s = new Stay();
    s.bookingId = r.Id;
    s.name = (String) m.get('Name');
    // Start__c / End__c are Datetime: show the local (user time zone) date.
    Datetime startDt = (Datetime) m.get('Start__c');
    Datetime endDt = (Datetime) m.get('End__c');
    s.startDate = startDt == null ? null : startDt.date();
    s.endDate = endDt == null ? null : endDt.date();
    s.status = (String) m.get('Status__c');
    SObject space = (SObject) m.get('Space__r');
    if (space != null && canRead(PMS_Space__c.SObjectType)) {
      s.spaceName = (String) space.get('Name');
    }
    s.channel = (String) m.get('Channel__c');
    // Party-only guests (not the primary contact) must not see financials or requests.
    s.viaParty = (Id) m.get('Primary_Contact__c') != contactId;
    if (!s.viaParty) {
      s.totalAmount = (Decimal) m.get('Total_Amount__c');
      s.balanceDue = (Decimal) m.get('Balance_Due__c');
      s.specialRequests = (String) m.get('Special_Requests__c');
    }
    return s;
  }

  private static List<Preference> toPrefs(List<SObject> rows) {
    List<Preference> out = new List<Preference>();
    for (SObject r : rows) {
      Map<String, Object> m = r.getPopulatedFieldsAsMap();
      Preference p = new Preference();
      p.preferenceId = r.Id;
      p.category = (String) m.get('Category__c');
      p.value = (String) m.get('Value__c');
      p.source = (String) m.get('Source__c');
      p.capturedOn = (Date) m.get('Captured_On__c');
      out.add(p);
    }
    return out;
  }
}
