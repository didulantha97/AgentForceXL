/**
 * Server side of the public booking site (Experience site "PMS Booking", /book).
 *
 * Visitors are anonymous (site guest user). External sharing on every PMS object is Private and guest
 * users get no record access, so this class runs without sharing and is the only way in:
 *  - reads return a small set of display fields as DTOs, never raw records;
 *  - writes only create new Tentative "Website" bookings, guest contacts and enquiry cases;
 *  - a booking's pay link needs the random access key returned when it was made.
 *
 * Spam protection: hidden honeypot field, minimum time on the form, per-email and site-wide rate
 * limits, and strict input checks. Unpaid bookings are released by PMS_WebBookingCleanup.
 */
public without sharing class PMS_PublicBookingController {
  @TestVisible
  private static final Integer MAX_NIGHTS = 30;
  @TestVisible
  private static final Integer MAX_DAYS_AHEAD = 365;
  @TestVisible
  private static final Integer MAX_APPOINTMENT_DAYS_AHEAD = 90;
  @TestVisible
  private static final Integer MAX_GUESTS = 10;
  @TestVisible
  private static final Integer MIN_FORM_MILLIS = 3000;
  @TestVisible
  private static final Integer MAX_PER_EMAIL_PER_HOUR = 3;
  @TestVisible
  private static final Integer MAX_WEB_HOLDS_PER_10_MIN = 30;
  @TestVisible
  private static final Integer APPOINTMENT_LEAD_MINUTES = 120;
  private static final String FALLBACK_TZ = 'Europe/Stockholm';
  private static final String REJECTED = 'We couldn\'t accept this request. Please try again, or call us.';
  private static final Pattern EMAIL = Pattern.compile(
    '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$'
  );
  private static final Pattern HOURS = Pattern.compile(
    '(?i)^\\s*(?:([a-z]{3})(?:\\s*-\\s*([a-z]{3}))?\\s+)?(\\d{1,2})[:.](\\d{2})\\s*-\\s*(\\d{1,2})[:.](\\d{2})\\s*$'
  );
  private static final List<String> DAYS = new List<String>{
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun'
  };

  // ------------------------------------------------------------------ DTOs

  public class SiteInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String module;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String checkIn;
    @AuraEnabled
    public String checkOut;
    @AuraEnabled
    public String currencyCode;
  }

  public class ServiceInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String area;
    @AuraEnabled
    public Integer minutes;
    @AuraEnabled
    public Decimal price;
  }

  public class PractitionerInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String speciality;
    @AuraEnabled
    public String siteName;
  }

  public class ListingInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String floor;
    @AuraEnabled
    public Decimal sizeSqm;
    @AuraEnabled
    public Integer bedrooms;
    @AuraEnabled
    public Decimal rent;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public List<String> amenities;
  }

  public class Catalog {
    @AuraEnabled
    public List<SiteInfo> hotels = new List<SiteInfo>();
    @AuraEnabled
    public List<SiteInfo> clinics = new List<SiteInfo>();
    @AuraEnabled
    public List<ServiceInfo> services = new List<ServiceInfo>();
    @AuraEnabled
    public List<PractitionerInfo> practitioners = new List<PractitionerInfo>();
    @AuraEnabled
    public List<ListingInfo> listings = new List<ListingInfo>();
    @AuraEnabled
    public String clinicCurrency;
    @AuraEnabled
    public String today;
  }

  public class StayOption {
    @AuraEnabled
    public Id spaceTypeId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Integer maxGuests;
    @AuraEnabled
    public Integer available;
    @AuraEnabled
    public Integer nights;
    @AuraEnabled
    public Decimal perNight;
    @AuraEnabled
    public Decimal net;
    @AuraEnabled
    public Decimal tax;
    @AuraEnabled
    public Decimal gross;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String cancellationPolicy;
  }

  public class Slot {
    @AuraEnabled
    public Datetime startAt;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id practitionerId;
    @AuraEnabled
    public String practitionerName;
  }

  /** Sent by the page as JSON. "website" is the hidden honeypot; elapsedMs is time spent on the form. */
  public class GuestDetails {
    public String firstName;
    public String lastName;
    public String email;
    public String phone;
    public String notes;
    public String website;
    public Long elapsedMs;
  }

  public class BookingResult {
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String accessKey;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Integer holdMinutes;
    @AuraEnabled
    public String summary;
  }

  public class PayLink {
    @AuraEnabled
    public String url;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
  }

  // ------------------------------------------------------------------ catalogue

  @AuraEnabled(cacheable=true)
  public static Catalog getCatalog() {
    try {
      Catalog c = new Catalog();
      List<String> modules = PMS_ModuleConfig.enabledModules();
      Set<Id> propertySiteIds = new Set<Id>();
      Map<Id, PMS_Site__c> propertySites = new Map<Id, PMS_Site__c>();
      for (PMS_Site__c s : [
        SELECT
          Id,
          Name,
          Module__c,
          Street__c,
          Postal_Code__c,
          City__c,
          Phone__c,
          Check_In_Time__c,
          Check_Out_Time__c,
          Currency_Code__c
        FROM PMS_Site__c
        WHERE Status__c = 'Active' AND Module__c IN :modules
        ORDER BY Name
      ]) {
        if (s.Module__c == PMS_ModuleConfig.HOTEL) {
          c.hotels.add(toSite(s));
        } else if (s.Module__c == PMS_ModuleConfig.PRACTICE) {
          c.clinics.add(toSite(s));
          if (c.clinicCurrency == null) {
            c.clinicCurrency = s.Currency_Code__c;
          }
        } else if (s.Module__c == PMS_ModuleConfig.PROPERTY) {
          propertySites.put(s.Id, s);
        }
      }
      if (!c.clinics.isEmpty()) {
        for (PMS_Service__c sv : [
          SELECT
            Id,
            Name,
            Description__c,
            Practice_Area__c,
            Duration_Minutes__c,
            Price__c
          FROM PMS_Service__c
          WHERE Bookable_Online__c = TRUE
          ORDER BY Practice_Area__c, Name
          LIMIT 40
        ]) {
          ServiceInfo si = new ServiceInfo();
          si.id = sv.Id;
          si.name = sv.Name;
          si.description = sv.Description__c;
          si.area = sv.Practice_Area__c;
          si.minutes = sv.Duration_Minutes__c == null
            ? 60
            : sv.Duration_Minutes__c.intValue();
          si.price = servicePrice(sv.Id, si.minutes); // what the booking will actually charge, tax included
          c.services.add(si);
        }
        for (PMS_Practitioner__c p : [
          SELECT Id, Name, Speciality__c, Site__r.Name
          FROM PMS_Practitioner__c
          WHERE
            Active__c = TRUE
            AND Site__r.Status__c = 'Active'
            AND Site__r.Module__c = 'Practice'
          ORDER BY Name
          LIMIT 100
        ]) {
          PractitionerInfo pi = new PractitionerInfo();
          pi.id = p.Id;
          pi.name = p.Name;
          pi.speciality = p.Speciality__c;
          pi.siteName = p.Site__r.Name;
          c.practitioners.add(pi);
        }
      }
      if (!propertySites.isEmpty()) {
        c.listings = listings(propertySites);
      }
      c.today = String.valueOf(
        PMS_DateUtil.toLocalDate(Datetime.now(), FALLBACK_TZ)
      );
      return c;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  /** Units at active property sites that are bookable and free right now. */
  private static List<ListingInfo> listings(Map<Id, PMS_Site__c> sites) {
    Set<Id> siteIds = sites.keySet();
    Map<Id, PMS_Space__c> units = new Map<Id, PMS_Space__c>(
      [
        SELECT
          Id,
          Name,
          Site__c,
          Floor__c,
          Size_Sqm__c,
          Bedrooms__c,
          Base_Rate__c,
          Amenities__c
        FROM PMS_Space__c
        WHERE
          Site__c IN :siteIds
          AND Bookable__c = TRUE
          AND Operational_Status__c NOT IN :PMS_AvailabilityService.UNSELLABLE_SPACE_STATUSES
        ORDER BY Name
        LIMIT 200
      ]
    );
    Datetime now = Datetime.now();
    Set<Id> busy = PMS_AvailabilityService.busySpaceIds(
      units.keySet(),
      now,
      now.addDays(1),
      null
    );
    List<ListingInfo> result = new List<ListingInfo>();
    for (PMS_Space__c u : units.values()) {
      if (busy.contains(u.Id)) {
        continue;
      }
      PMS_Site__c s = sites.get(u.Site__c);
      ListingInfo l = new ListingInfo();
      l.id = u.Id;
      l.name = u.Name;
      l.siteName = s.Name;
      l.address = address(s);
      l.floor = u.Floor__c;
      l.sizeSqm = u.Size_Sqm__c;
      l.bedrooms = u.Bedrooms__c == null ? null : u.Bedrooms__c.intValue();
      l.rent = u.Base_Rate__c;
      l.currencyCode = s.Currency_Code__c;
      l.amenities = String.isBlank(u.Amenities__c)
        ? new List<String>()
        : u.Amenities__c.split(';');
      result.add(l);
    }
    return result;
  }

  // ------------------------------------------------------------------ hotel stays

  @AuraEnabled
  public static List<StayOption> searchStays(
    Id siteId,
    String checkIn,
    String checkOut,
    Integer guests
  ) {
    try {
      PMS_Site__c site = hotelSite(siteId);
      Date arrive = parseDate(checkIn, 'arrival date');
      Date depart = parseDate(checkOut, 'departure date');
      checkStayDates(site, arrive, depart);
      Integer g = guests == null ? 1 : guests;
      if (g < 1 || g > MAX_GUESTS) {
        throw new PMS_Exception(
          'Choose between 1 and ' + MAX_GUESTS + ' guests.'
        );
      }
      Datetime s = PMS_DateUtil.toDatetime(
        arrive,
        timeOr(site.Check_In_Time__c, 15),
        tz(site)
      );
      Datetime e = PMS_DateUtil.toDatetime(
        depart,
        timeOr(site.Check_Out_Time__c, 11),
        tz(site)
      );

      Map<Id, Integer> freeByType = new Map<Id, Integer>();
      Map<Id, Integer> maxOccByType = new Map<Id, Integer>();
      for (
        PMS_Space__c sp : PMS_AvailabilityService.findAvailableSpaces(
          site.Id,
          null,
          s,
          e,
          g
        )
      ) {
        if (sp.Space_Type__c == null) {
          continue;
        }
        freeByType.put(
          sp.Space_Type__c,
          (freeByType.containsKey(sp.Space_Type__c)
            ? freeByType.get(sp.Space_Type__c)
            : 0) + 1
        );
        Integer occ = sp.Max_Occupancy__c == null
          ? 0
          : sp.Max_Occupancy__c.intValue();
        if (
          !maxOccByType.containsKey(sp.Space_Type__c) ||
          occ > maxOccByType.get(sp.Space_Type__c)
        ) {
          maxOccByType.put(sp.Space_Type__c, occ);
        }
      }
      PMS_Rate_Plan__c plan = ratePlan(site.Id, PMS_ModuleConfig.HOTEL, arrive);
      List<StayOption> options = new List<StayOption>();
      for (PMS_Space_Type__c t : [
        SELECT Id, Name, Description__c, Default_Occupancy__c
        FROM PMS_Space_Type__c
        WHERE Site__c = :site.Id
        ORDER BY Default_Rate__c NULLS LAST, Name
      ]) {
        StayOption o = new StayOption();
        o.spaceTypeId = t.Id;
        o.name = t.Name;
        o.description = t.Description__c;
        o.available = freeByType.containsKey(t.Id) ? freeByType.get(t.Id) : 0;
        o.maxGuests = maxOccByType.containsKey(t.Id)
          ? maxOccByType.get(t.Id)
          : (t.Default_Occupancy__c == null
              ? null
              : t.Default_Occupancy__c.intValue());
        o.nights = arrive.daysBetween(depart);
        o.cancellationPolicy = plan == null
          ? null
          : plan.Cancellation_Policy__c;
        if (o.available > 0) {
          PMS_PricingService.Quote q = stayQuote(plan, t.Id, arrive, depart);
          o.net = q.getNet();
          o.tax = q.getTax();
          o.gross = q.getGross();
          o.perNight = q.getUnitPrice();
          o.currencyCode = String.isBlank(q.getCurrencyCode())
            ? site.Currency_Code__c
            : q.getCurrencyCode();
        }
        options.add(o);
      }
      return options;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static BookingResult bookStay(
    Id siteId,
    Id spaceTypeId,
    String checkIn,
    String checkOut,
    Integer adults,
    Integer children,
    String guestJson
  ) {
    try {
      GuestDetails g = guard(guestJson);
      PMS_Site__c site = hotelSite(siteId);
      Date arrive = parseDate(checkIn, 'arrival date');
      Date depart = parseDate(checkOut, 'departure date');
      checkStayDates(site, arrive, depart);
      Integer a = adults == null ? 1 : adults;
      Integer ch = children == null ? 0 : children;
      if (a < 1 || ch < 0 || a + ch > MAX_GUESTS) {
        throw new PMS_Exception('Check the number of guests.');
      }
      List<PMS_Space_Type__c> types = [
        SELECT Id, Name
        FROM PMS_Space_Type__c
        WHERE Id = :spaceTypeId AND Site__c = :site.Id
      ];
      if (types.isEmpty()) {
        throw new PMS_Exception('Choose a room type.');
      }
      Contact guest = findOrCreateGuest(g);
      PMS_Rate_Plan__c plan = ratePlan(site.Id, PMS_ModuleConfig.HOTEL, arrive);

      PMS_BookingService.BookingRequest br = new PMS_BookingService.BookingRequest();
      br.module = PMS_ModuleConfig.HOTEL;
      br.siteId = site.Id;
      br.spaceTypeId = spaceTypeId;
      br.ratePlanId = plan == null ? null : plan.Id;
      br.accountId = guest.AccountId;
      br.contactId = guest.Id;
      br.startDate = arrive;
      br.endDate = depart;
      br.adults = a;
      br.children = ch;
      br.channel = PMS_WebBookingHold.CHANNEL;
      br.status = 'Tentative';
      br.specialRequests = g.notes;
      PMS_Booking__c b = PMS_BookingService.createBooking(br);
      String key = stampKey(b.Id);
      PMS_Invoice__c inv = PMS_WebBookingHold.invoiceHotelStay(b.Id);
      return result(
        b.Id,
        key,
        inv.Id,
        types[0].Name +
          ', ' +
          arrive.daysBetween(depart) +
          ' night(s) from ' +
          String.valueOf(arrive) +
          ' at ' +
          site.Name
      );
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ appointments

  @AuraEnabled
  public static List<Slot> getAppointmentSlots(
    Id serviceId,
    Id practitionerId,
    String day
  ) {
    try {
      PMS_Service__c svc = onlineService(serviceId);
      Date d = parseDate(day, 'date');
      Date today = PMS_DateUtil.toLocalDate(Datetime.now(), FALLBACK_TZ);
      if (d < today || d > today.addDays(MAX_APPOINTMENT_DAYS_AHEAD)) {
        throw new PMS_Exception(
          'Choose a date within the next ' +
            MAX_APPOINTMENT_DAYS_AHEAD +
            ' days.'
        );
      }
      return slotsFor(svc, practitioners(practitionerId), d);
    } catch (Exception e) {
      throw handled(e);
    }
  }

  @AuraEnabled
  public static BookingResult bookAppointment(
    Id serviceId,
    Id practitionerId,
    String startAt,
    String guestJson
  ) {
    try {
      GuestDetails g = guard(guestJson);
      PMS_Service__c svc = onlineService(serviceId);
      if (practitionerId == null) {
        throw new PMS_Exception('Choose a time.');
      }
      List<PMS_Practitioner__c> prs = practitioners(practitionerId);
      Datetime startDt = parseDatetime(startAt);
      PMS_Practitioner__c pr = prs[0];
      Date localDay = PMS_DateUtil.toLocalDate(
        startDt,
        tz(pr.Site__r.Time_Zone__c)
      );
      Boolean stillFree = false;
      for (Slot s : slotsFor(svc, prs, localDay)) {
        if (s.startAt.getTime() == startDt.getTime()) {
          stillFree = true;
          break;
        }
      }
      if (!stillFree) {
        throw new PMS_Exception(
          'Sorry, that time has just been taken. Please pick another.'
        );
      }
      Contact guest = findOrCreateGuest(g);
      PMS_BookingService.BookingRequest br = new PMS_BookingService.BookingRequest();
      br.module = PMS_ModuleConfig.PRACTICE;
      br.siteId = pr.Site__c;
      br.serviceId = svc.Id;
      br.practitionerId = pr.Id;
      br.startDatetime = startDt;
      br.accountId = guest.AccountId;
      br.contactId = guest.Id;
      br.adults = 1;
      br.channel = PMS_WebBookingHold.CHANNEL;
      br.status = 'Tentative';
      br.specialRequests = g.notes;
      PMS_Booking__c b = PMS_BookingService.createBooking(br);
      String key = stampKey(b.Id);
      PMS_Invoice__c inv = PMS_WebBookingHold.invoiceAppointment(b.Id);
      return result(
        b.Id,
        key,
        inv.Id,
        svc.Name +
          ' with ' +
          pr.Name +
          ', ' +
          startDt.format('EEE d MMM yyyy HH:mm', tz(pr.Site__r.Time_Zone__c))
      );
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ property enquiries

  @AuraEnabled
  public static String submitEnquiry(Id unitId, String guestJson) {
    try {
      GuestDetails g = guard(guestJson);
      List<PMS_Space__c> units = [
        SELECT Id, Name, Site__c, Site__r.Name
        FROM PMS_Space__c
        WHERE
          Id = :unitId
          AND Bookable__c = TRUE
          AND Site__r.Status__c = 'Active'
          AND Site__r.Module__c = 'Property'
        LIMIT 1
      ];
      if (units.isEmpty()) {
        throw new PMS_Exception('That home is no longer listed.');
      }
      Datetime hourAgo = Datetime.now().addHours(-1);
      if (
        [
          SELECT COUNT()
          FROM Case
          WHERE SuppliedEmail = :g.email AND CreatedDate >= :hourAgo
        ] >= MAX_PER_EMAIL_PER_HOUR
      ) {
        throw new PMS_Exception(
          'We already have your enquiries. We\'ll be in touch soon.'
        );
      }
      Case c = new Case(
        Subject = ('Viewing request: ' +
          units[0].Name +
          ', ' +
          units[0].Site__r.Name)
          .left(255),
        Description = g.notes,
        Origin = 'Web',
        Status = 'New',
        Priority = 'Medium',
        SuppliedName = (g.firstName + ' ' + g.lastName).left(80),
        SuppliedEmail = g.email,
        SuppliedPhone = g.phone,
        PMS_Module__c = PMS_ModuleConfig.PROPERTY,
        PMS_Site__c = units[0].Site__c,
        PMS_Space__c = units[0].Id
      );
      Database.DMLOptions dmo = new Database.DMLOptions();
      dmo.assignmentRuleHeader.useDefaultRule = true;
      c.setOptions(dmo);
      insert c;
      return [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ payment

  /** Stripe Checkout link for a booking made on this site. Separate call: no DML may precede a callout. */
  @AuraEnabled
  public static PayLink getPayLink(Id bookingId, String accessKey) {
    try {
      if (
        bookingId == null ||
        String.isBlank(accessKey) ||
        accessKey.length() != 64
      ) {
        throw new PMS_Exception('Booking not found.');
      }
      Datetime holdStart = Datetime.now()
        .addMinutes(-PMS_WebBookingHold.HOLD_MINUTES);
      List<PMS_Booking__c> bs = [
        SELECT Id, Web_Access_Key__c
        FROM PMS_Booking__c
        WHERE
          Id = :bookingId
          AND Channel__c = :PMS_WebBookingHold.CHANNEL
          AND Status__c = 'Tentative'
          AND CreatedDate >= :holdStart
        LIMIT 1
      ];
      // SOQL text comparison ignores case, so compare the key exactly here.
      if (bs.isEmpty() || !accessKey.equals(bs[0].Web_Access_Key__c)) {
        throw new PMS_Exception(
          'This booking has expired or was not found. Please book again.'
        );
      }
      List<PMS_Invoice__c> invs = [
        SELECT Id
        FROM PMS_Invoice__c
        WHERE
          Booking__c = :bookingId
          AND Balance__c > 0
          AND Status__c NOT IN ('Void', 'Credited', 'Draft', 'Paid')
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (invs.isEmpty()) {
        throw new PMS_Exception(
          'There is nothing left to pay for this booking.'
        );
      }
      PMS_StripeCheckout.Result r = PMS_StripeCheckout.createForVerifiedInvoice(
        invs[0].Id,
        PMS_WebBookingHold.CHECKOUT_EXPIRY_MINUTES
      );
      PayLink p = new PayLink();
      p.url = r.url;
      p.amount = r.amount;
      p.currencyCode = r.currencyCode;
      return p;
    } catch (Exception e) {
      throw handled(e);
    }
  }

  // ------------------------------------------------------------------ slots

  @TestVisible
  private static List<Slot> slotsFor(
    PMS_Service__c svc,
    List<PMS_Practitioner__c> prs,
    Date d
  ) {
    Integer minutes = svc.Duration_Minutes__c == null
      ? 60
      : svc.Duration_Minutes__c.intValue();
    Integer step = Math.min(minutes, 30);
    Datetime earliest = Datetime.now().addMinutes(APPOINTMENT_LEAD_MINUTES);

    Map<Id, List<Datetime>> windows = new Map<Id, List<Datetime>>();
    Datetime dayStart;
    Datetime dayEnd;
    for (PMS_Practitioner__c p : prs) {
      List<Time> hours = workingHours(p.Working_Hours__c, d);
      if (hours == null) {
        continue;
      }
      String zone = tz(p.Site__r.Time_Zone__c);
      Datetime open = PMS_DateUtil.toDatetime(d, hours[0], zone);
      Datetime close = PMS_DateUtil.toDatetime(d, hours[1], zone);
      windows.put(p.Id, new List<Datetime>{ open, close });
      dayStart = dayStart == null || open < dayStart ? open : dayStart;
      dayEnd = dayEnd == null || close > dayEnd ? close : dayEnd;
    }
    List<Slot> slots = new List<Slot>();
    if (windows.isEmpty()) {
      return slots;
    }
    Map<Id, List<PMS_Booking__c>> busy = new Map<Id, List<PMS_Booking__c>>();
    Set<Id> ids = windows.keySet();
    for (PMS_Booking__c b : [
      SELECT Practitioner__c, Start__c, End__c
      FROM PMS_Booking__c
      WHERE
        Practitioner__c IN :ids
        AND Start__c < :dayEnd
        AND End__c > :dayStart
        AND Status__c NOT IN :PMS_AvailabilityService.NON_BLOCKING_STATUSES
    ]) {
      if (!busy.containsKey(b.Practitioner__c)) {
        busy.put(b.Practitioner__c, new List<PMS_Booking__c>());
      }
      busy.get(b.Practitioner__c).add(b);
    }
    for (PMS_Practitioner__c p : prs) {
      if (!windows.containsKey(p.Id)) {
        continue;
      }
      List<Datetime> w = windows.get(p.Id);
      String zone = tz(p.Site__r.Time_Zone__c);
      for (
        Datetime s = w[0]; s.addMinutes(minutes) <= w[1]; s = s.addMinutes(step)
      ) {
        Datetime e = s.addMinutes(minutes);
        if (s < earliest) {
          continue;
        }
        Boolean clash = false;
        if (busy.containsKey(p.Id)) {
          for (PMS_Booking__c b : busy.get(p.Id)) {
            if (b.Start__c < e && b.End__c > s) {
              clash = true;
              break;
            }
          }
        }
        if (clash) {
          continue;
        }
        Slot sl = new Slot();
        sl.startAt = s;
        sl.label = s.format('HH:mm', zone);
        sl.practitionerId = p.Id;
        sl.practitionerName = p.Name;
        slots.add(sl);
      }
    }
    return slots;
  }

  /**
   * Parses Working Hours such as "Mon-Fri 08:00-16:00", "Tue-Sat 09:00-17:00; Sun 10:00-14:00" or
   * "08:00-16:00" (weekdays). Blank means Mon-Fri 09:00-17:00. Returns null when not working that day.
   */
  @TestVisible
  private static List<Time> workingHours(String spec, Date d) {
    String text = String.isBlank(spec) ? 'Mon-Fri 09:00-17:00' : spec;
    Integer dayIdx = DAYS.indexOf(
      PMS_DateUtil.dayName(d).left(3).toLowerCase()
    );
    for (String part : text.split('[;,\\n]')) {
      Matcher m = HOURS.matcher(part);
      if (!m.matches()) {
        continue;
      }
      Boolean applies;
      if (m.group(1) == null) {
        applies = dayIdx <= 4;
      } else {
        Integer first = DAYS.indexOf(m.group(1).toLowerCase());
        Integer last = m.group(2) == null
          ? first
          : DAYS.indexOf(m.group(2).toLowerCase());
        if (first < 0 || last < 0) {
          continue;
        }
        applies = first <= last
          ? (dayIdx >= first && dayIdx <= last)
          : (dayIdx >= first || dayIdx <= last);
      }
      if (applies) {
        Time open = Time.newInstance(
          Integer.valueOf(m.group(3)),
          Integer.valueOf(m.group(4)),
          0,
          0
        );
        Time close = Time.newInstance(
          Integer.valueOf(m.group(5)),
          Integer.valueOf(m.group(6)),
          0,
          0
        );
        return close > open ? new List<Time>{ open, close } : null;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ guards and guests

  /** Honeypot, time-on-form, field checks and rate limits. Returns the cleaned details. */
  @TestVisible
  private static GuestDetails guard(String guestJson) {
    GuestDetails g;
    try {
      g = (GuestDetails) JSON.deserialize(guestJson, GuestDetails.class);
    } catch (Exception e) {
      g = null;
    }
    if (g == null) {
      throw new PMS_Exception('Please fill in your details.');
    }
    if (String.isNotBlank(g.website)) {
      throw new PMS_Exception(REJECTED);
    }
    if (g.elapsedMs == null || g.elapsedMs < MIN_FORM_MILLIS) {
      throw new PMS_Exception(
        'That was quick! Please check your details and try again.'
      );
    }
    g.firstName = clean(g.firstName, 40);
    g.lastName = clean(g.lastName, 80);
    g.email = clean(g.email, 80);
    g.phone = clean(g.phone, 40);
    g.notes = clean(g.notes, 2000);
    if (String.isBlank(g.firstName) || String.isBlank(g.lastName)) {
      throw new PMS_Exception('Please enter your first and last name.');
    }
    if (String.isBlank(g.email) || !EMAIL.matcher(g.email).matches()) {
      throw new PMS_Exception('Please enter a valid email address.');
    }
    g.email = g.email.toLowerCase();
    Datetime hourAgo = Datetime.now().addHours(-1);
    Datetime tenMinAgo = Datetime.now().addMinutes(-10);
    Integer mine = [
      SELECT COUNT()
      FROM PMS_Booking__c
      WHERE
        Channel__c = :PMS_WebBookingHold.CHANNEL
        AND CreatedDate >= :hourAgo
        AND Primary_Contact__r.Email = :g.email
    ];
    if (mine >= MAX_PER_EMAIL_PER_HOUR) {
      throw new PMS_Exception(
        'You have made several bookings in the last hour. Please call us to book more.'
      );
    }
    Integer recentHolds = [
      SELECT COUNT()
      FROM PMS_Booking__c
      WHERE
        Channel__c = :PMS_WebBookingHold.CHANNEL
        AND Status__c = 'Tentative'
        AND CreatedDate >= :tenMinAgo
    ];
    if (recentHolds >= MAX_WEB_HOLDS_PER_10_MIN) {
      throw new PMS_Exception(
        'We are very busy right now. Please try again in a few minutes.'
      );
    }
    return g;
  }

  /** Reuses a contact with the same email and last name; otherwise creates an account and contact. */
  @TestVisible
  private static Contact findOrCreateGuest(GuestDetails g) {
    List<Contact> existing = [
      SELECT Id, AccountId
      FROM Contact
      WHERE Email = :g.email AND LastName = :g.lastName AND AccountId != NULL
      ORDER BY CreatedDate
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.duplicateRuleHeader.allowSave = true;
    Account a = new Account(Name = (g.firstName + ' ' + g.lastName).left(255));
    Database.insert(a, dml);
    Contact c = new Contact(
      AccountId = a.Id,
      FirstName = g.firstName,
      LastName = g.lastName,
      Email = g.email,
      Phone = g.phone,
      LeadSource = 'Web'
    );
    Database.insert(c, dml);
    return c;
  }

  // ------------------------------------------------------------------ helpers

  private static String stampKey(Id bookingId) {
    String key = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    update new PMS_Booking__c(Id = bookingId, Web_Access_Key__c = key);
    return key;
  }

  private static BookingResult result(
    Id bookingId,
    String key,
    Id invoiceId,
    String summary
  ) {
    PMS_Booking__c b = [SELECT Name FROM PMS_Booking__c WHERE Id = :bookingId];
    PMS_Invoice__c inv = [
      SELECT Balance__c, Currency_Code__c
      FROM PMS_Invoice__c
      WHERE Id = :invoiceId
    ];
    BookingResult r = new BookingResult();
    r.bookingId = bookingId;
    r.bookingNumber = b.Name;
    r.accessKey = key;
    r.amount = inv.Balance__c;
    r.currencyCode = inv.Currency_Code__c;
    r.holdMinutes = PMS_WebBookingHold.CHECKOUT_EXPIRY_MINUTES;
    r.summary = summary;
    return r;
  }

  private static PMS_Site__c hotelSite(Id siteId) {
    List<PMS_Site__c> sites = [
      SELECT
        Id,
        Name,
        Module__c,
        Time_Zone__c,
        Check_In_Time__c,
        Check_Out_Time__c,
        Currency_Code__c
      FROM PMS_Site__c
      WHERE Id = :siteId AND Status__c = 'Active' AND Module__c = 'Hotel'
      LIMIT 1
    ];
    if (
      sites.isEmpty() || !PMS_ModuleConfig.isEnabled(PMS_ModuleConfig.HOTEL)
    ) {
      throw new PMS_Exception('Choose a hotel.');
    }
    return sites[0];
  }

  private static void checkStayDates(
    PMS_Site__c site,
    Date arrive,
    Date depart
  ) {
    Date today = PMS_DateUtil.toLocalDate(Datetime.now(), tz(site));
    if (arrive < today) {
      throw new PMS_Exception('The arrival date is in the past.');
    }
    if (arrive > today.addDays(MAX_DAYS_AHEAD)) {
      throw new PMS_Exception(
        'We take bookings up to ' + MAX_DAYS_AHEAD + ' days ahead.'
      );
    }
    if (depart <= arrive) {
      throw new PMS_Exception(
        'The departure date must be after the arrival date.'
      );
    }
    if (arrive.daysBetween(depart) > MAX_NIGHTS) {
      throw new PMS_Exception(
        'For stays longer than ' + MAX_NIGHTS + ' nights, please contact us.'
      );
    }
  }

  private static PMS_Service__c onlineService(Id serviceId) {
    List<PMS_Service__c> svcs = [
      SELECT Id, Name, Duration_Minutes__c
      FROM PMS_Service__c
      WHERE Id = :serviceId AND Bookable_Online__c = TRUE
      LIMIT 1
    ];
    if (
      svcs.isEmpty() || !PMS_ModuleConfig.isEnabled(PMS_ModuleConfig.PRACTICE)
    ) {
      throw new PMS_Exception('Choose a treatment.');
    }
    return svcs[0];
  }

  private static List<PMS_Practitioner__c> practitioners(Id practitionerId) {
    List<PMS_Practitioner__c> prs;
    if (practitionerId != null) {
      prs = [
        SELECT Id, Name, Working_Hours__c, Site__c, Site__r.Time_Zone__c
        FROM PMS_Practitioner__c
        WHERE
          Id = :practitionerId
          AND Active__c = TRUE
          AND Site__r.Status__c = 'Active'
          AND Site__r.Module__c = 'Practice'
      ];
      if (prs.isEmpty()) {
        throw new PMS_Exception('Choose a practitioner.');
      }
    } else {
      prs = [
        SELECT Id, Name, Working_Hours__c, Site__c, Site__r.Time_Zone__c
        FROM PMS_Practitioner__c
        WHERE
          Active__c = TRUE
          AND Site__r.Status__c = 'Active'
          AND Site__r.Module__c = 'Practice'
        ORDER BY Name
        LIMIT 50
      ];
    }
    return prs;
  }

  @TestVisible
  private static PMS_Rate_Plan__c ratePlan(Id siteId, String module, Date d) {
    List<PMS_Rate_Plan__c> plans = [
      SELECT Id, Cancellation_Policy__c
      FROM PMS_Rate_Plan__c
      WHERE
        Site__c = :siteId
        AND Active__c = TRUE
        AND (Module__c = :module
        OR Module__c = NULL)
        AND (Valid_From__c = NULL
        OR Valid_From__c <= :d)
        AND (Valid_To__c = NULL
        OR Valid_To__c >= :d)
      ORDER BY CreatedDate
      LIMIT 1
    ];
    return plans.isEmpty() ? null : plans[0];
  }

  private static PMS_PricingService.Quote stayQuote(
    PMS_Rate_Plan__c plan,
    Id spaceTypeId,
    Date arrive,
    Date depart
  ) {
    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = PMS_ModuleConfig.HOTEL;
    qr.ratePlanId = plan == null ? null : plan.Id;
    qr.spaceTypeId = spaceTypeId;
    qr.startDate = arrive;
    qr.endDate = depart;
    return PMS_PricingService.quote(qr);
  }

  /** Gross price of a service as PMS_BookingService prices an appointment of that length. */
  private static Decimal servicePrice(Id serviceId, Integer minutes) {
    Date today = Date.today();
    PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
    qr.module = PMS_ModuleConfig.PRACTICE;
    qr.serviceId = serviceId;
    qr.startDate = today;
    qr.endDate = today;
    qr.hours = Decimal.valueOf(minutes) / 60;
    return PMS_PricingService.quote(qr).getGross();
  }

  private static SiteInfo toSite(PMS_Site__c s) {
    SiteInfo i = new SiteInfo();
    i.id = s.Id;
    i.name = s.Name;
    i.module = s.Module__c;
    i.address = address(s);
    i.phone = s.Phone__c;
    i.checkIn = s.Check_In_Time__c == null
      ? null
      : String.valueOf(s.Check_In_Time__c).left(5);
    i.checkOut = s.Check_Out_Time__c == null
      ? null
      : String.valueOf(s.Check_Out_Time__c).left(5);
    i.currencyCode = s.Currency_Code__c;
    return i;
  }

  private static String address(PMS_Site__c s) {
    List<String> parts = new List<String>();
    for (
      String p : new List<String>{ s.Street__c, s.Postal_Code__c, s.City__c }
    ) {
      if (String.isNotBlank(p)) {
        parts.add(p.replace('\n', ', '));
      }
    }
    return String.join(parts, ', ');
  }

  private static Date parseDate(String value, String label) {
    try {
      return Date.valueOf(value.trim());
    } catch (Exception e) {
      throw new PMS_Exception('Choose a valid ' + label + '.');
    }
  }

  private static Datetime parseDatetime(String value) {
    try {
      return (Datetime) JSON.deserialize(
        '"' + value.trim() + '"',
        Datetime.class
      );
    } catch (Exception e) {
      throw new PMS_Exception('Choose a time.');
    }
  }

  private static Time timeOr(Time t, Integer hour) {
    return t == null ? Time.newInstance(hour, 0, 0, 0) : t;
  }

  private static String tz(PMS_Site__c s) {
    return tz(s.Time_Zone__c);
  }

  private static String tz(String zone) {
    return String.isBlank(zone) ? FALLBACK_TZ : zone;
  }

  private static String clean(String s, Integer maxLength) {
    return s == null ? null : s.normalizeSpace().left(maxLength);
  }

  private static AuraHandledException handled(Exception e) {
    String msg = e instanceof PMS_Exception
      ? e.getMessage()
      : 'Something went wrong. Please try again or contact us.';
    if (!(e instanceof PMS_Exception)) {
      System.debug(
        LoggingLevel.ERROR,
        'PMS booking site: ' + e.getMessage() + '\n' + e.getStackTraceString()
      );
    }
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    return ex;
  }
}
