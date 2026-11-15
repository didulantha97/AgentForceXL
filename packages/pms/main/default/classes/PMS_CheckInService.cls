/**
 * Online check-in, shared by the customer portal (PMS_PortalV2Controller) and the emailed link on the
 * public booking site (PMS_GuestCheckInController).
 *
 *   hotel   Confirmed hotel stays arriving within 14 days: arrival time and registration details.
 *           Creates a PMS_Check_In__c, ticks Checked In Online and adds a line to Special Requests,
 *           so the front desk sees it on the booking.
 *   clinic  Confirmed appointments within 30 days: health questionnaire, saved as a PMS_Intake_Form__c
 *           (Health Questionnaire) linked to the appointment.
 *   movein  Leases starting within 60 days (or started in the last 14): move-in details and meter
 *           readings for the unit's meters (PMS_Meter_Reading__c).
 * The site manager is emailed when a check-in arrives.
 */
public without sharing class PMS_CheckInService {
  public static final String HOTEL = 'hotel';
  public static final String CLINIC = 'clinic';
  public static final String MOVEIN = 'movein';
  private static final Set<String> OK_STATUSES = new Set<String>{
    'Confirmed',
    'Active'
  };

  public class Question {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String type; // text, textarea, select
    @AuraEnabled
    public List<String> options;
    @AuraEnabled
    public Boolean required = false;
    Question(
      String key,
      String label,
      String type,
      List<String> options,
      Boolean required
    ) {
      this.key = key;
      this.label = label;
      this.type = type;
      this.options = options;
      this.required = required;
    }
  }

  public static final List<Question> CLINIC_QUESTIONS = new List<Question>{
    new Question(
      'reason',
      'What brings you in? Where is the problem, and how long have you had it?',
      'textarea',
      null,
      true
    ),
    new Question(
      'pain',
      'How bad is it today, from 0 (none) to 10 (worst)?',
      'select',
      new List<String>{
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10'
      },
      false
    ),
    new Question(
      'conditions',
      'Medical conditions, injuries or operations we should know about',
      'textarea',
      null,
      false
    ),
    new Question(
      'medications',
      'Medicines you take regularly',
      'textarea',
      null,
      false
    ),
    new Question(
      'allergies',
      'Allergies (for example to medicines, latex or massage oils)',
      'text',
      null,
      false
    ),
    new Question(
      'pregnant',
      'Are you pregnant, or could you be?',
      'select',
      new List<String>{ 'No', 'Yes', 'Not applicable' },
      false
    ),
    new Question(
      'emergency',
      'Emergency contact (name and phone)',
      'text',
      null,
      false
    ),
    new Question(
      'other',
      'Anything else you would like us to know?',
      'textarea',
      null,
      false
    )
  };

  public class MeterInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String meterType;
    @AuraEnabled
    public Decimal lastReading;
  }

  public class Eligible {
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public Boolean done = false;
    @AuraEnabled
    public Integer guests;
    @AuraEnabled
    public String fullName;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public List<MeterInfo> meters = new List<MeterInfo>();
    @AuraEnabled
    public List<Question> questions;
  }

  /** Sent by the page as JSON. Fields not used by a form are ignored. */
  public class Form {
    public String arrivalTime;
    public Integer guests;
    public String fullName;
    public String phone;
    public String nationality;
    public String dateOfBirth;
    public String address;
    public String idType;
    public String idNumber;
    public String vehicle;
    public String requests;
    public Boolean terms;
    public String moveInDate;
    public Integer occupants;
    public String emergencyContact;
    public List<Reading> readings;
    public Map<String, String> answers;
    public Boolean consentTreatment;
    public Boolean consentData;
  }

  public class Reading {
    public Id meterId;
    public Decimal value;
  }

  // ------------------------------------------------------------------ finding bookings

  private static final String FIELDS =
    'Id, Name, Account__c, Start__c, End__c, Status__c, Adults__c, Children__c, ' +
    'Online_Check_In__c, Check_In_Key__c, Practitioner__c, Space__c, Space__r.Name, Room_Type_Requested__r.Name, ' +
    'Service__r.Name, Practitioner__r.Name, RecordType.DeveloperName, Primary_Contact__c, Primary_Contact__r.Name, ' +
    'Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone, Primary_Contact__r.Email, Site__c, Site__r.Name, ' +
    'Site__r.Module__c, Site__r.Time_Zone__c, Site__r.Check_In_Time__c, Site__r.Manager__c, Special_Requests__c, ' +
    '(SELECT Id FROM Intake_Forms__r LIMIT 1)';

  public static PMS_Booking__c load(Id bookingId) {
    List<PMS_Booking__c> bs = Database.queryWithBinds(
      'SELECT ' + FIELDS + ' FROM PMS_Booking__c WHERE Id = :bookingId LIMIT 1',
      new Map<String, Object>{ 'bookingId' => bookingId },
      AccessLevel.SYSTEM_MODE
    );
    return bs.isEmpty() ? null : bs[0];
  }

  public static List<PMS_Booking__c> loadMany(Set<Id> bookingIds) {
    return (List<PMS_Booking__c>) Database.queryWithBinds(
      'SELECT ' + FIELDS + ' FROM PMS_Booking__c WHERE Id IN :ids',
      new Map<String, Object>{ 'ids' => bookingIds },
      AccessLevel.SYSTEM_MODE
    );
  }

  /** Upcoming bookings of an account that offer online check-in (done ones included, marked done). */
  public static List<Eligible> forAccount(Id accountId) {
    Datetime fromDt = Datetime.now().addDays(-14);
    Datetime toDt = Datetime.now().addDays(60);
    List<Eligible> result = new List<Eligible>();
    for (
      PMS_Booking__c b : (List<PMS_Booking__c>) Database.queryWithBinds(
        'SELECT ' +
          FIELDS +
          ' FROM PMS_Booking__c WHERE Account__c = :accountId AND Status__c IN :statuses ' +
          'AND Start__c >= :fromDt AND Start__c <= :toDt ORDER BY Start__c LIMIT 50',
        new Map<String, Object>{
          'accountId' => accountId,
          'statuses' => OK_STATUSES,
          'fromDt' => fromDt,
          'toDt' => toDt
        },
        AccessLevel.SYSTEM_MODE
      )
    ) {
      Eligible e = describe(b);
      if (e != null) {
        result.add(e);
      }
    }
    return result;
  }

  public static String kindOf(PMS_Booking__c b) {
    if (b.Site__r == null) {
      return null;
    }
    if (b.Site__r.Module__c == 'Hotel') {
      return HOTEL;
    }
    if (b.Site__r.Module__c == 'Practice' && b.Practitioner__c != null) {
      return CLINIC;
    }
    if (b.RecordType?.DeveloperName == 'Lease') {
      return MOVEIN;
    }
    return null;
  }

  /** The check-in form for a booking, or null when it doesn't offer one (wrong type, status or timing). */
  public static Eligible describe(PMS_Booking__c b) {
    String kind = kindOf(b);
    if (
      kind == null ||
      !OK_STATUSES.contains(b.Status__c) ||
      b.Start__c == null
    ) {
      return null;
    }
    Datetime now = Datetime.now();
    Boolean inWindow;
    if (kind == HOTEL) {
      inWindow =
        b.Status__c == 'Confirmed' &&
        b.Start__c <= now.addDays(14) &&
        (b.End__c == null ||
        b.End__c > now);
    } else if (kind == CLINIC) {
      inWindow =
        b.Status__c == 'Confirmed' &&
        b.Start__c > now &&
        b.Start__c <= now.addDays(30);
    } else {
      inWindow =
        b.Start__c <= now.addDays(60) &&
        b.Start__c >= now.addDays(-14);
    }
    if (!inWindow) {
      return null;
    }
    String zone = String.isBlank(b.Site__r.Time_Zone__c)
      ? 'Europe/Stockholm'
      : b.Site__r.Time_Zone__c;
    Eligible e = new Eligible();
    e.bookingId = b.Id;
    e.bookingNumber = b.Name;
    e.kind = kind;
    e.siteName = b.Site__r.Name;
    e.fullName = b.Primary_Contact__r?.Name;
    e.phone = b.Primary_Contact__r == null
      ? null
      : (String.isNotBlank(b.Primary_Contact__r.MobilePhone)
          ? b.Primary_Contact__r.MobilePhone
          : b.Primary_Contact__r.Phone);
    e.startDate = String.valueOf(PMS_DateUtil.toLocalDate(b.Start__c, zone));
    if (kind == HOTEL) {
      e.done = b.Online_Check_In__c;
      e.title = 'Your stay at ' + b.Site__r.Name;
      e.subtitle =
        b.Start__c.format('EEE d MMM', zone) +
        ' – ' +
        (b.End__c == null ? '' : b.End__c.format('EEE d MMM yyyy', zone)) +
        (b.Room_Type_Requested__r == null
          ? ''
          : ', ' + b.Room_Type_Requested__r.Name) +
        (b.Site__r.Check_In_Time__c == null
          ? ''
          : '. Check-in from ' +
            String.valueOf(b.Site__r.Check_In_Time__c).left(5));
      e.guests =
        (b.Adults__c == null ? 1 : b.Adults__c.intValue()) +
        (b.Children__c == null ? 0 : b.Children__c.intValue());
    } else if (kind == CLINIC) {
      e.done = !b.Intake_Forms__r.isEmpty();
      e.title =
        (b.Service__r == null ? 'Your appointment' : b.Service__r.Name) +
        ' at ' +
        b.Site__r.Name;
      e.subtitle =
        b.Start__c.format('EEEE d MMMM, HH:mm', zone) +
        (b.Practitioner__r == null ? '' : ' with ' + b.Practitioner__r.Name);
      e.questions = CLINIC_QUESTIONS;
    } else {
      e.done = b.Online_Check_In__c;
      e.title =
        'Moving in: ' +
        (b.Space__r == null ? '' : b.Space__r.Name + ', ') +
        b.Site__r.Name;
      e.subtitle =
        'Lease starts ' + b.Start__c.format('EEEE d MMMM yyyy', zone);
      if (b.Space__c != null) {
        for (PMS_Meter__c m : [
          SELECT
            Id,
            Name,
            Meter_Type__c,
            (
              SELECT Reading_Value__c
              FROM Readings__r
              ORDER BY Reading_Date__c DESC
              LIMIT 1
            )
          FROM PMS_Meter__c
          WHERE Space__c = :b.Space__c
          ORDER BY Name
        ]) {
          MeterInfo mi = new MeterInfo();
          mi.id = m.Id;
          mi.name = m.Name;
          mi.meterType = m.Meter_Type__c;
          mi.lastReading = m.Readings__r.isEmpty()
            ? null
            : m.Readings__r[0].Reading_Value__c;
          e.meters.add(mi);
        }
      }
    }
    return e;
  }

  // ------------------------------------------------------------------ submitting

  public static void submit(PMS_Booking__c b, String formJson, String via) {
    Eligible e = describe(b);
    if (e == null) {
      throw new PMS_Exception('Online check-in is not open for this booking.');
    }
    if (e.done) {
      throw new PMS_Exception(
        'Online check-in is already done for this booking. Thank you!'
      );
    }
    Form f;
    try {
      f = (Form) JSON.deserialize(formJson, Form.class);
    } catch (Exception ex) {
      f = null;
    }
    if (f == null) {
      throw new PMS_Exception('Please fill in the form.');
    }
    if (e.kind == CLINIC) {
      submitClinic(b, f);
    } else if (e.kind == HOTEL) {
      submitHotel(b, f, via);
    } else {
      submitMoveIn(b, f, via, e);
    }
    alertManager(b, e);
  }

  private static void submitHotel(PMS_Booking__c b, Form f, String via) {
    if (String.isBlank(f.fullName) || String.isBlank(f.arrivalTime)) {
      throw new PMS_Exception(
        'Enter your full name and expected arrival time.'
      );
    }
    if (f.terms != true) {
      throw new PMS_Exception('Please accept the house rules to check in.');
    }
    insert new PMS_Check_In__c(
      Booking__c = b.Id,
      Account__c = b.Account__c,
      Type__c = 'Hotel Stay',
      Submitted_At__c = Datetime.now(),
      Submitted_Via__c = via,
      Arrival_Time__c = clip(f.arrivalTime, 20),
      Guests__c = f.guests,
      Full_Name__c = clip(f.fullName, 120),
      Phone__c = clip(f.phone, 40),
      Nationality__c = clip(f.nationality, 60),
      Date_Of_Birth__c = optionalDate(f.dateOfBirth),
      Address__c = clip(f.address, 1000),
      ID_Type__c = new Set<String>{
            'Passport',
            'National ID Card',
            'Driving Licence'
          }
          .contains(f.idType)
        ? f.idType
        : null,
      ID_Number__c = clip(f.idNumber, 40),
      Vehicle_Registration__c = clip(f.vehicle, 20),
      Special_Requests__c = clip(f.requests, 5000),
      Terms_Accepted__c = true
    );
    String note =
      'Online check-in ' +
      Datetime.now().format('d MMM HH:mm') +
      ': arriving around ' +
      clip(f.arrivalTime, 20) +
      '.' +
      (String.isBlank(f.requests) ? '' : ' Requests: ' + clip(f.requests, 500));
    markDone(b, note);
  }

  private static void submitMoveIn(
    PMS_Booking__c b,
    Form f,
    String via,
    Eligible e
  ) {
    if (String.isBlank(f.fullName)) {
      throw new PMS_Exception('Enter your full name.');
    }
    if (f.terms != true) {
      throw new PMS_Exception('Please confirm the details are correct.');
    }
    Date moveIn = optionalDate(f.moveInDate);
    insert new PMS_Check_In__c(
      Booking__c = b.Id,
      Account__c = b.Account__c,
      Type__c = 'Move-In',
      Submitted_At__c = Datetime.now(),
      Submitted_Via__c = via,
      Full_Name__c = clip(f.fullName, 120),
      Phone__c = clip(f.phone, 40),
      Move_In_Date__c = moveIn,
      Occupants__c = f.occupants,
      Emergency_Contact__c = clip(f.emergencyContact, 255),
      Vehicle_Registration__c = clip(f.vehicle, 20),
      Special_Requests__c = clip(f.requests, 5000),
      Terms_Accepted__c = true
    );
    Set<Id> allowed = new Set<Id>();
    for (MeterInfo mi : e.meters) {
      allowed.add(mi.id);
    }
    List<PMS_Meter_Reading__c> readings = new List<PMS_Meter_Reading__c>();
    for (Reading r : f.readings == null ? new List<Reading>() : f.readings) {
      if (r == null || r.value == null || !allowed.contains(r.meterId)) {
        continue;
      }
      if (r.value < 0) {
        throw new PMS_Exception('Meter readings can\'t be negative.');
      }
      readings.add(
        new PMS_Meter_Reading__c(
          Meter__c = r.meterId,
          Reading_Date__c = moveIn == null ? Date.today() : moveIn,
          Reading_Value__c = r.value
        )
      );
    }
    insert readings;
    markDone(
      b,
      'Online move-in details ' +
        Datetime.now().format('d MMM HH:mm') +
        (readings.isEmpty()
          ? ''
          : ', ' + readings.size() + ' meter reading(s)') +
        '.'
    );
  }

  private static void submitClinic(PMS_Booking__c b, Form f) {
    Map<String, String> a = f.answers == null
      ? new Map<String, String>()
      : f.answers;
    List<String> lines = new List<String>();
    for (Question q : CLINIC_QUESTIONS) {
      String v = a.get(q.key);
      if (q.required && String.isBlank(v)) {
        throw new PMS_Exception('Please answer: ' + q.label);
      }
      lines.add(
        q.label + '\n' + (String.isBlank(v) ? '-' : v.trim().left(4000))
      );
    }
    if (f.consentTreatment != true) {
      throw new PMS_Exception(
        'Please confirm your consent to assessment and treatment.'
      );
    }
    lines.add('Consent to assessment and treatment: Yes');
    lines.add(
      'Consent to storing health information for my care: ' +
      (f.consentData == true ? 'Yes' : 'No')
    );
    insert new PMS_Intake_Form__c(
      Booking__c = b.Id,
      Contact__c = b.Primary_Contact__c,
      Form_Type__c = 'Health Questionnaire',
      Responses__c = String.join(lines, '\n\n').left(131072),
      Consent_Given__c = true,
      Signed_Date__c = Date.today()
    );
  }

  private static void markDone(PMS_Booking__c b, String note) {
    update new PMS_Booking__c(
      Id = b.Id,
      Online_Check_In__c = true,
      Online_Check_In_At__c = Datetime.now(),
      Special_Requests__c = ((String.isBlank(b.Special_Requests__c)
          ? ''
          : b.Special_Requests__c + '\n') + note)
        .left(32000)
    );
  }

  private static void alertManager(PMS_Booking__c b, Eligible e) {
    if (b.Site__r?.Manager__c == null) {
      return;
    }
    String what = e.kind == CLINIC
      ? 'Health questionnaire'
      : (e.kind == HOTEL ? 'Online check-in' : 'Move-in details');
    PMS_CustomerNotifications.emailUser(
      b.Site__r.Manager__c,
      what + ' received: ' + b.Name,
      what + ' received for ' + e.title + ' (' + e.subtitle + ').',
      b.Id
    );
  }

  // ------------------------------------------------------------------ helpers

  private static String clip(String s, Integer n) {
    return s == null ? null : s.trim().left(n);
  }

  private static Date optionalDate(String s) {
    if (String.isBlank(s)) {
      return null;
    }
    try {
      return Date.valueOf(s.trim());
    } catch (Exception e) {
      throw new PMS_Exception('Check the dates you entered.');
    }
  }

  /** A new random secret for the emailed check-in link. */
  public static String newKey() {
    return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
  }
}
