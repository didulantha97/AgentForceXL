/**
 * Dynamic hotel pricing. For each active Pricing Strategy, writes one daily rate per room type and
 * night on the strategy's rate plan (PMS_Rate__c with Date From = Date To = the night, Dynamic = true).
 * PMS_PricingService already prefers the narrowest dated rate, so every quote (booking site, front
 * desk, agent, later the channel manager) uses these rates without any change to the quote engine.
 *
 *   base   = the plan's own (non-dynamic) rate for that room type and night, else the room type's
 *            default rate
 *   rate   = base x (1 + p1) x (1 + p2) ... + a1 + a2 ...   for every factor that applies
 *   then kept between the floor and the ceiling (percent of base and/or amounts), optionally limited to
 *   Max Change per Run against the current rate, and rounded to Round To.
 * Locked daily rates (set by staff) are never changed. Occupancy for a night comes from Inventory Days
 * when they exist, else from room nights against the room type's rooms.
 */
public without sharing class PMS_DynamicPricingService {
  public static final List<String> DAY_NAMES = new List<String>{
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  };
  private static final Set<String> SOLD_NIGHT = new Set<String>{
    'Reserved',
    'In House',
    'Posted'
  };

  public class Cell {
    @AuraEnabled
    public Id rateId;
    @AuraEnabled
    public Id roomTypeId;
    @AuraEnabled
    public Date night;
    @AuraEnabled
    public Decimal base;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal occupancy;
    @AuraEnabled
    public String notes;
    @AuraEnabled
    public Boolean locked = false;
  }

  public class RunResult {
    @AuraEnabled
    public Integer written = 0;
    @AuraEnabled
    public Integer locked = 0;
    @AuraEnabled
    public Integer removed = 0;
    @AuraEnabled
    public String summary;
  }

  public static String dayName(Date d) {
    // 1 Jan 1900 was a Monday
    Integer idx = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(d), 7);
    return DAY_NAMES[idx < 0 ? idx + 7 : idx];
  }

  public static String key(Id planId, Id roomTypeId, Date night) {
    return String.valueOf(planId).left(15) +
      '|' +
      String.valueOf(roomTypeId).left(15) +
      '|' +
      String.valueOf(night);
  }

  // ---------------------------------------------------------------- the formula

  public static Boolean applies(
    PMS_Pricing_Factor__c f,
    Id roomTypeId,
    Date night,
    Decimal occupancyPct,
    Integer leadDays
  ) {
    if (f.Active__c != true) {
      return false;
    }
    if (f.Room_Type__c != null && f.Room_Type__c != roomTypeId) {
      return false;
    }
    switch on f.Type__c {
      when 'Occupancy' {
        if (occupancyPct == null) {
          return false;
        }
        return (f.Min_Value__c == null || occupancyPct >= f.Min_Value__c) &&
          (f.Max_Value__c == null ||
          occupancyPct < f.Max_Value__c);
      }
      when 'Lead Time' {
        return (f.Min_Value__c == null || leadDays >= f.Min_Value__c) &&
          (f.Max_Value__c == null ||
          leadDays < f.Max_Value__c);
      }
      when 'Day of Week' {
        return String.isNotBlank(f.Days_Of_Week__c) &&
          f.Days_Of_Week__c.split(';').contains(dayName(night));
      }
      when 'Event' {
        return f.Date_From__c != null &&
          night >= f.Date_From__c &&
          (f.Date_To__c == null
            ? night == f.Date_From__c
            : night <= f.Date_To__c);
      }
      when else {
        return false;
      }
    }
  }

  /** Rate for one night. notes receives the factors that applied. */
  public static Decimal price(
    PMS_Pricing_Strategy__c s,
    List<PMS_Pricing_Factor__c> factors,
    Id roomTypeId,
    Date night,
    Decimal base,
    Decimal occupancyPct,
    Integer leadDays,
    Decimal current,
    List<String> notes
  ) {
    Decimal rate = base;
    Decimal added = 0;
    for (PMS_Pricing_Factor__c f : factors) {
      if (!applies(f, roomTypeId, night, occupancyPct, leadDays)) {
        continue;
      }
      if (f.Adjust_Percent__c != null && f.Adjust_Percent__c != 0) {
        rate = rate * (1 + f.Adjust_Percent__c / 100);
      }
      if (f.Adjust_Amount__c != null && f.Adjust_Amount__c != 0) {
        added += f.Adjust_Amount__c;
      }
      notes.add(f.Name + ' ' + describe(f));
    }
    rate += added;
    Decimal floor = s.Min_Percent__c == null
      ? null
      : base * s.Min_Percent__c / 100;
    if (s.Min_Rate__c != null && (floor == null || s.Min_Rate__c > floor)) {
      floor = s.Min_Rate__c;
    }
    Decimal ceiling = s.Max_Percent__c == null
      ? null
      : base * s.Max_Percent__c / 100;
    if (s.Max_Rate__c != null && (ceiling == null || s.Max_Rate__c < ceiling)) {
      ceiling = s.Max_Rate__c;
    }
    if (floor != null && rate < floor) {
      rate = floor;
      notes.add('floor');
    }
    if (ceiling != null && rate > ceiling) {
      rate = ceiling;
      notes.add('ceiling');
    }
    if (
      current != null &&
      current > 0 &&
      s.Max_Change_Percent__c != null &&
      s.Max_Change_Percent__c > 0
    ) {
      Decimal maxStep = current * s.Max_Change_Percent__c / 100;
      if (rate > current + maxStep) {
        rate = current + maxStep;
        notes.add('change limited');
      } else if (rate < current - maxStep) {
        rate = current - maxStep;
        notes.add('change limited');
      }
    }
    Decimal step = s.Round_To__c == null ||
      s.Round_To__c <= 0
      ? 1
      : s.Round_To__c;
    rate = (rate / step).setScale(0, RoundingMode.HALF_UP) * step;
    return rate < 0 ? 0 : rate;
  }

  private static String describe(PMS_Pricing_Factor__c f) {
    List<String> parts = new List<String>();
    if (f.Adjust_Percent__c != null && f.Adjust_Percent__c != 0) {
      parts.add(
        (f.Adjust_Percent__c > 0 ? '+' : '') +
          f.Adjust_Percent__c.setScale(0) +
          '%'
      );
    }
    if (f.Adjust_Amount__c != null && f.Adjust_Amount__c != 0) {
      parts.add(
        (f.Adjust_Amount__c > 0 ? '+' : '') + f.Adjust_Amount__c.setScale(0)
      );
    }
    return String.join(parts, ' ');
  }

  // ---------------------------------------------------------------- run

  public static PMS_Pricing_Strategy__c loadStrategy(Id strategyId) {
    List<PMS_Pricing_Strategy__c> s = [
      SELECT
        Id,
        Name,
        Active__c,
        Rate_Plan__c,
        Rate_Plan__r.Site__c,
        Rate_Plan__r.Name,
        Horizon_Days__c,
        Min_Percent__c,
        Max_Percent__c,
        Min_Rate__c,
        Max_Rate__c,
        Round_To__c,
        Max_Change_Percent__c,
        (
          SELECT
            Id,
            Name,
            Active__c,
            Type__c,
            Room_Type__c,
            Min_Value__c,
            Max_Value__c,
            Days_Of_Week__c,
            Date_From__c,
            Date_To__c,
            Adjust_Percent__c,
            Adjust_Amount__c
          FROM Factors__r
          ORDER BY Type__c, Name
        )
      FROM PMS_Pricing_Strategy__c
      WHERE Id = :strategyId
    ];
    if (s.isEmpty()) {
      throw new PMS_Exception('Pricing strategy not found.');
    }
    return s[0];
  }

  public static RunResult recalculate(Id strategyId) {
    PMS_Pricing_Strategy__c s = loadStrategy(strategyId);
    RunResult result = new RunResult();
    if (s.Rate_Plan__c == null || s.Rate_Plan__r.Site__c == null) {
      throw new PMS_Exception(
        'The strategy needs a rate plan that belongs to a site.'
      );
    }
    Id planId = s.Rate_Plan__c;
    Integer horizon = s.Horizon_Days__c == null
      ? 120
      : Math.min(366, s.Horizon_Days__c.intValue());
    Date today = Date.today();
    Date lastNight = today.addDays(horizon - 1);

    Map<Id, PMS_Space_Type__c> types = new Map<Id, PMS_Space_Type__c>(
      [
        SELECT Id, Name, Default_Rate__c
        FROM PMS_Space_Type__c
        WHERE Site__c = :s.Rate_Plan__r.Site__c
      ]
    );
    Map<Id, Integer> rooms = roomCounts(types.keySet());
    Map<String, Decimal> occupancy = occupancy(
      types.keySet(),
      rooms,
      today,
      lastNight
    );
    List<PMS_Rate__c> manual = [
      SELECT
        Id,
        Space_Type__c,
        Date_From__c,
        Date_To__c,
        Days_Of_Week__c,
        Amount__c,
        Min_Stay__c
      FROM PMS_Rate__c
      WHERE Rate_Plan__c = :planId AND Dynamic__c = FALSE AND Service__c = NULL
    ];
    Map<String, PMS_Rate__c> existing = new Map<String, PMS_Rate__c>();
    for (PMS_Rate__c r : [
      SELECT Id, Dynamic_Key__c, Amount__c, Locked__c
      FROM PMS_Rate__c
      WHERE
        Rate_Plan__c = :planId
        AND Dynamic__c = TRUE
        AND Date_From__c >= :today
        AND Date_From__c <= :lastNight
    ]) {
      existing.put(r.Dynamic_Key__c, r);
    }

    List<PMS_Rate__c> inserts = new List<PMS_Rate__c>();
    List<PMS_Rate__c> updates = new List<PMS_Rate__c>();
    for (PMS_Space_Type__c t : types.values()) {
      for (Integer i = 0; i < horizon; i++) {
        Date night = today.addDays(i);
        String k = key(planId, t.Id, night);
        PMS_Rate__c current = existing.get(k);
        if (current != null && current.Locked__c == true) {
          result.locked++;
          continue;
        }
        Decimal base = baseRate(manual, t, night);
        if (base == null || base <= 0) {
          continue;
        }
        Decimal occ = occupancy.get(t.Id + '|' + night);
        List<String> notes = new List<String>();
        Decimal amount = price(
          s,
          s.Factors__r,
          t.Id,
          night,
          base,
          occ,
          i,
          current == null ? null : current.Amount__c,
          notes
        );
        String noteText = cut(
          notes.isEmpty() ? 'base rate' : String.join(notes, ', '),
          255
        );
        if (current == null) {
          inserts.add(
            new PMS_Rate__c(
              Rate_Plan__c = planId,
              Space_Type__c = t.Id,
              Date_From__c = night,
              Date_To__c = night,
              Days_Of_Week__c = dayName(night),
              Amount__c = amount,
              Dynamic__c = true,
              Dynamic_Key__c = k,
              Base_Amount__c = base,
              Occupancy__c = occ,
              Pricing_Notes__c = noteText
            )
          );
        } else {
          updates.add(
            new PMS_Rate__c(
              Id = current.Id,
              Amount__c = amount,
              Base_Amount__c = base,
              Occupancy__c = occ,
              Pricing_Notes__c = noteText
            )
          );
        }
      }
    }
    if (!inserts.isEmpty()) {
      insert inserts;
    }
    if (!updates.isEmpty()) {
      update updates;
    }
    Date cutoff = today.addDays(-14);
    List<PMS_Rate__c> old = [
      SELECT Id
      FROM PMS_Rate__c
      WHERE
        Rate_Plan__c = :planId
        AND Dynamic__c = TRUE
        AND Date_To__c < :cutoff
      LIMIT 2000
    ];
    if (!old.isEmpty()) {
      delete old;
    }
    result.written = inserts.size() + updates.size();
    result.removed = old.size();
    result.summary =
      result.written +
      ' daily rates set for ' +
      types.size() +
      ' room types, ' +
      horizon +
      ' days' +
      (result.locked > 0 ? ' (' + result.locked + ' locked kept)' : '') +
      '.';
    update new PMS_Pricing_Strategy__c(
      Id = s.Id,
      Last_Run_At__c = Datetime.now(),
      Last_Run_Result__c = cut(result.summary, 255)
    );
    return result;
  }

  // ---------------------------------------------------------------- inputs

  /** The plan's own rate for the room type and night (narrowest season wins), else the default rate. */
  public static Decimal baseRate(
    List<PMS_Rate__c> manual,
    PMS_Space_Type__c t,
    Date night
  ) {
    PMS_Rate__c best;
    Integer bestSpan;
    String day = dayName(night);
    for (PMS_Rate__c r : manual) {
      if (r.Space_Type__c != null && r.Space_Type__c != t.Id) {
        continue;
      }
      if (r.Date_From__c != null && night < r.Date_From__c) {
        continue;
      }
      if (r.Date_To__c != null && night > r.Date_To__c) {
        continue;
      }
      if (
        String.isNotBlank(r.Days_Of_Week__c) &&
        !r.Days_Of_Week__c.split(';').contains(day)
      ) {
        continue;
      }
      Integer span = r.Date_From__c != null &&
        r.Date_To__c != null
        ? r.Date_From__c.daysBetween(r.Date_To__c)
        : 1000000;
      if (String.isNotBlank(r.Days_Of_Week__c)) {
        span -= 1;
      }
      if (r.Space_Type__c == null) {
        span += 1; // a room-type rate beats a plan-wide rate
      }
      if (best == null || span < bestSpan) {
        best = r;
        bestSpan = span;
      }
    }
    if (best != null && best.Amount__c != null) {
      return best.Amount__c;
    }
    return t.Default_Rate__c;
  }

  private static Map<Id, Integer> roomCounts(Set<Id> typeIds) {
    Map<Id, Integer> result = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Space_Type__c t, COUNT(Id) n
      FROM PMS_Space__c
      WHERE Space_Type__c IN :typeIds AND Bookable__c = TRUE
      GROUP BY Space_Type__c
    ]) {
      result.put((Id) ar.get('t'), (Integer) ar.get('n'));
    }
    return result;
  }

  /** "typeId|yyyy-mm-dd" -> occupancy % (0-100). */
  public static Map<String, Decimal> occupancy(
    Set<Id> typeIds,
    Map<Id, Integer> rooms,
    Date fromDate,
    Date toDate
  ) {
    Map<String, Decimal> result = new Map<String, Decimal>();
    for (PMS_Inventory_Day__c d : [
      SELECT
        Room_Type__c,
        Inventory_Date__c,
        Total_Rooms__c,
        Sold__c,
        Out_Of_Order__c
      FROM PMS_Inventory_Day__c
      WHERE
        Room_Type__c IN :typeIds
        AND Inventory_Date__c >= :fromDate
        AND Inventory_Date__c <= :toDate
    ]) {
      Decimal sellable = nz(d.Total_Rooms__c) - nz(d.Out_Of_Order__c);
      if (sellable > 0) {
        result.put(
          d.Room_Type__c + '|' + d.Inventory_Date__c,
          (nz(d.Sold__c) / sellable * 100).setScale(1, RoundingMode.HALF_UP)
        );
      }
    }
    for (AggregateResult ar : [
      SELECT Room_Type__c t, Stay_Date__c d, COUNT(Id) n
      FROM PMS_Room_Night__c
      WHERE
        Room_Type__c IN :typeIds
        AND Stay_Date__c >= :fromDate
        AND Stay_Date__c <= :toDate
        AND Status__c IN :SOLD_NIGHT
      GROUP BY Room_Type__c, Stay_Date__c
    ]) {
      Id t = (Id) ar.get('t');
      String k = t + '|' + (Date) ar.get('d');
      Integer total = rooms.get(t);
      if (!result.containsKey(k) && total != null && total > 0) {
        result.put(
          k,
          (Decimal.valueOf((Integer) ar.get('n')) /
            total *
            100)
            .setScale(1, RoundingMode.HALF_UP)
        );
      }
    }
    // nights with nothing sold yet
    for (Id t : typeIds) {
      if (rooms.get(t) == null || rooms.get(t) == 0) {
        continue;
      }
      for (Date d = fromDate; d <= toDate; d = d.addDays(1)) {
        String k = t + '|' + d;
        if (!result.containsKey(k)) {
          result.put(k, 0);
        }
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- staff overrides

  public static void setPrice(Id rateId, Decimal amount) {
    if (amount == null || amount <= 0) {
      throw new PMS_Exception('Enter a positive rate.');
    }
    update new PMS_Rate__c(
      Id = rateId,
      Amount__c = amount,
      Locked__c = true,
      Pricing_Notes__c = 'Set by ' + UserInfo.getName()
    );
  }

  public static void unlock(Id rateId) {
    update new PMS_Rate__c(Id = rateId, Locked__c = false);
  }

  private static Decimal nz(Decimal d) {
    return d == null ? 0 : d;
  }

  public static String cut(String s, Integer max) {
    if (s == null) {
      return null;
    }
    return s.length() <= max ? s : s.left(max - 3) + '...';
  }
}
