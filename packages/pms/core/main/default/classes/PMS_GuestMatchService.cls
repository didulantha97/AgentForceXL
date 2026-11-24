/**
 * Guest matching. Decides whether an incoming guest is an existing contact, and flags (never merges)
 * contacts that may be the same person.
 *
 *   a) Masked OTA relay emails (see MASKED_DOMAINS) are never match keys. They are kept in
 *      Contact.PMS_OTA_Alias_Email__c and Email is left blank on new contacts.
 *   b) Exact unmasked email, case-insensitive: oldest contact with an account wins.
 *   c) Normalised phone + same last name, only when PMS_Settings__c.Guest_Match_Phone_Name__c is on.
 *   d) Same first + last name and an overlapping or adjacent stay (or the same phone when c is off):
 *      no match, the result carries possibleDuplicateOf and a reason.
 *
 * Bulk-safe: three queries for the whole list (email, last name, bookings), no SOQL or DML in loops.
 * Sharing is inherited from the caller: the Channex sync (without sharing, integration user) must see
 * every guest to avoid duplicates; the agent flow runs with the user's record access.
 */
public inherited sharing class PMS_GuestMatchService {
  public static final String EXACT_EMAIL = 'EXACT_EMAIL';
  public static final String PHONE_NAME = 'PHONE_NAME';
  public static final String NONE = 'NONE';

  /** Relay domains used by booking channels. Subdomains also count as masked. */
  @TestVisible
  private static final Set<String> MASKED_DOMAINS = new Set<String>{
    'guest.booking.com',
    'm.expediapartnercentral.com',
    'guest.airbnb.com',
    'm.airbnb.com',
    'reply.airbnb.com'
  };
  private static final Integer QUERY_CAP = 2000;
  private static final String FOLD_FROM = 'àáâãäåāăąçćčďéèêëēěęìíîïīłñńňòóôõöøōőřśšşťùúûüūůűýÿźżž';
  private static final String FOLD_TO = 'aaaaaaaaacccdeeeeeeeiiiiilnnnooooooooorsssstuuuuuuuyyzzz';

  public class GuestInput {
    public String firstName;
    public String lastName;
    public String email;
    public String phone;
    public Id accountId;
    public Date arrival;
    public Date departure;
  }

  public class Result {
    public Id contactId;
    public String confidence = NONE;
    public Id possibleDuplicateOf;
    public String reason;
    /** Masked relay email, to store in PMS_OTA_Alias_Email__c. */
    public String aliasEmail;
    /** Unmasked email, safe to store in Email. */
    public String cleanEmail;
    public String normalisedPhone;
  }

  public static Boolean isMasked(String email) {
    if (String.isBlank(email) || !email.contains('@')) {
      return false;
    }
    String domain = email.substringAfterLast('@').trim().toLowerCase();
    for (String d : MASKED_DOMAINS) {
      if (domain == d || domain.endsWith('.' + d)) {
        return true;
      }
    }
    return false;
  }

  /** E.164-ish: digits and a leading +, 00 becomes +, national numbers stay as digits. Null when too short. */
  public static String normalisePhone(String phone) {
    if (String.isBlank(phone)) {
      return null;
    }
    String s = phone.trim();
    Boolean plus = s.startsWith('+');
    String digits = s.replaceAll('[^0-9]', '');
    if (!plus && digits.startsWith('00')) {
      plus = true;
      digits = digits.substring(2);
    }
    if (digits.length() < 6) {
      return null;
    }
    return (plus ? '+' : '') + digits;
  }

  /** Lower-cases and strips common diacritics. */
  public static String fold(String s) {
    if (s == null) {
      return '';
    }
    String low = s.trim().toLowerCase();
    String out = '';
    for (Integer i = 0; i < low.length(); i++) {
      String ch = low.substring(i, i + 1);
      Integer at = FOLD_FROM.indexOf(ch);
      out += at >= 0 ? FOLD_TO.substring(at, at + 1) : ch;
    }
    return out;
  }

  public static Boolean phoneNameMatchingOn() {
    return PMS_Settings__c.getOrgDefaults().Guest_Match_Phone_Name__c == true;
  }

  /** One result per input, same order. */
  public static List<Result> match(List<GuestInput> inputs) {
    List<Result> results = new List<Result>();
    if (inputs == null || inputs.isEmpty()) {
      return results;
    }
    Boolean phoneRule = phoneNameMatchingOn();
    Set<String> emails = new Set<String>();
    Set<String> lastNames = new Set<String>();
    Date minArr;
    Date maxDep;
    for (GuestInput g : inputs) {
      Result r = new Result();
      results.add(r);
      if (String.isNotBlank(g.email)) {
        if (isMasked(g.email)) {
          r.aliasEmail = g.email.trim();
        } else {
          r.cleanEmail = g.email.trim();
          emails.add(r.cleanEmail.toLowerCase());
        }
      }
      r.normalisedPhone = normalisePhone(g.phone);
      if (String.isNotBlank(g.lastName)) {
        lastNames.add(g.lastName.trim());
        lastNames.add(fold(g.lastName));
      }
      if (g.arrival != null && (minArr == null || g.arrival < minArr)) {
        minArr = g.arrival;
      }
      if (g.departure != null && (maxDep == null || g.departure > maxDep)) {
        maxDep = g.departure;
      }
    }

    Map<String, Contact> byEmail = new Map<String, Contact>();
    if (!emails.isEmpty()) {
      for (Contact c : [
        SELECT Id, AccountId, Email
        FROM Contact
        WHERE Email IN :emails AND AccountId != NULL
        ORDER BY CreatedDate
        LIMIT :QUERY_CAP
      ]) {
        String k = c.Email.toLowerCase();
        if (!byEmail.containsKey(k)) {
          byEmail.put(k, c);
        }
      }
    }

    List<Contact> sameLast = new List<Contact>();
    if (!lastNames.isEmpty()) {
      sameLast = [
        SELECT Id, AccountId, FirstName, LastName, Phone
        FROM Contact
        WHERE LastName IN :lastNames
        ORDER BY CreatedDate
        LIMIT :QUERY_CAP
      ];
    }

    Map<Id, List<PMS_Booking__c>> stays = new Map<Id, List<PMS_Booking__c>>();
    if (!sameLast.isEmpty() && minArr != null && maxDep != null) {
      Set<Id> ids = new Map<Id, Contact>(sameLast).keySet();
      Datetime windowStart = Datetime.newInstance(
        minArr.addDays(-2),
        Time.newInstance(0, 0, 0, 0)
      );
      Datetime windowEnd = Datetime.newInstance(
        maxDep.addDays(3),
        Time.newInstance(0, 0, 0, 0)
      );
      for (PMS_Booking__c b : [
        SELECT Primary_Contact__c, Start__c, End__c
        FROM PMS_Booking__c
        WHERE
          Primary_Contact__c IN :ids
          AND Start__c <= :windowEnd
          AND End__c >= :windowStart
          AND Status__c != 'Cancelled'
        LIMIT :QUERY_CAP
      ]) {
        if (!stays.containsKey(b.Primary_Contact__c)) {
          stays.put(b.Primary_Contact__c, new List<PMS_Booking__c>());
        }
        stays.get(b.Primary_Contact__c).add(b);
      }
    }

    for (Integer i = 0; i < inputs.size(); i++) {
      GuestInput g = inputs[i];
      Result r = results[i];
      if (r.cleanEmail != null) {
        Contact hit = byEmail.get(r.cleanEmail.toLowerCase());
        if (hit != null) {
          r.contactId = hit.Id;
          r.confidence = EXACT_EMAIL;
          continue;
        }
      }
      String lastKey = fold(g.lastName);
      String firstKey = fold(g.firstName);
      if (String.isBlank(lastKey)) {
        continue;
      }
      for (Contact c : sameLast) {
        if (fold(c.LastName) != lastKey) {
          continue;
        }
        Boolean samePhone =
          r.normalisedPhone != null &&
          normalisePhone(c.Phone) == r.normalisedPhone;
        if (phoneRule && samePhone && c.AccountId != null) {
          r.contactId = c.Id;
          r.confidence = PHONE_NAME;
          r.possibleDuplicateOf = null;
          r.reason = null;
          break;
        }
        if (r.possibleDuplicateOf == null && fold(c.FirstName) == firstKey) {
          if (overlaps(g, stays.get(c.Id))) {
            r.possibleDuplicateOf = c.Id;
            r.reason = 'Same name with an overlapping or adjacent stay.';
          } else if (!phoneRule && samePhone) {
            r.possibleDuplicateOf = c.Id;
            r.reason = 'Same name and phone number.';
          }
        }
      }
    }
    return results;
  }

  /** Builds an unsaved contact for a guest with no match, with alias and duplicate flag set. */
  public static Contact newContact(GuestInput g, Result r) {
    String last = String.isBlank(g.lastName)
      ? (String.isBlank(g.firstName) ? 'Guest' : g.firstName)
      : g.lastName;
    return new Contact(
      AccountId = g.accountId,
      FirstName = g.firstName,
      LastName = last,
      Email = r.cleanEmail,
      PMS_OTA_Alias_Email__c = r.aliasEmail,
      Phone = g.phone,
      PMS_Possible_Duplicate_Of__c = r.possibleDuplicateOf,
      PMS_Duplicate_Reason__c = r.reason
    );
  }

  private static Boolean overlaps(GuestInput g, List<PMS_Booking__c> bookings) {
    if (bookings == null || g.arrival == null || g.departure == null) {
      return false;
    }
    for (PMS_Booking__c b : bookings) {
      if (
        b.Start__c != null &&
        b.End__c != null &&
        b.Start__c.date() <= g.departure.addDays(1) &&
        b.End__c.date() >= g.arrival.addDays(-1)
      ) {
        return true;
      }
    }
    return false;
  }
}
