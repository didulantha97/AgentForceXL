/**
 * Availability, rates and restrictions to Channex (ARI). One availability call and one restrictions
 * call per property per run: Channex allows 10 of each per minute per property, and Channex itself
 * prefers few large updates.
 *
 * Availability per room type and night = bookable rooms - unsellable rooms - nights sold (room nights
 * that are not cancelled or no-show).
 * Rates per mapped rate plan and night = the PMS rate plan's own rate for that night (dynamic daily
 * rates first, then seasons, weekdays and the room type default), plus VAT when the site sends
 * VAT-inclusive prices. Stop Sell on an Inventory Day closes the night on every mapped rate plan.
 * Equal consecutive nights are merged into date ranges.
 */
public without sharing class PMS_ChannexAri {
  private static final Set<String> GONE_NIGHT = new Set<String>{
    'Cancelled',
    'No Show'
  };

  public class Payload {
    public List<Map<String, Object>> availability = new List<Map<String, Object>>();
    public List<Map<String, Object>> restrictions = new List<Map<String, Object>>();
    public List<String> problems = new List<String>();
  }

  public class Night {
    public Date night;
    public String value;
    public Boolean stopSell = false;
    public Date endNight;
    public Night(Date night, String value, Boolean stopSell) {
      this.night = night;
      this.endNight = night;
      this.value = value;
      this.stopSell = stopSell == true;
    }
  }

  public static Integer horizon() {
    PMS_Settings__c s = PMS_Settings__c.getOrgDefaults();
    return s == null ||
      s.Channex_Horizon_Days__c == null
      ? 365
      : Math.max(1, Math.min(730, s.Channex_Horizon_Days__c.intValue()));
  }

  public static Payload build(Id siteId, Date fromDate, Integer days) {
    Payload p = new Payload();
    PMS_Site__c site = [
      SELECT Id, Name, Channex_Property_Id__c, Channex_Prices_Include_VAT__c
      FROM PMS_Site__c
      WHERE Id = :siteId
    ];
    if (String.isBlank(site.Channex_Property_Id__c)) {
      p.problems.add(site.Name + ' has no Channex Property ID.');
      return p;
    }
    Date toDate = fromDate.addDays(days - 1);
    Map<Id, PMS_Space_Type__c> types = new Map<Id, PMS_Space_Type__c>(
      [
        SELECT Id, Name, Default_Rate__c, Channex_Room_Type_Id__c
        FROM PMS_Space_Type__c
        WHERE Site__c = :siteId
      ]
    );

    // ---- availability
    Map<Id, Integer> sellable = new Map<Id, Integer>();
    for (PMS_Space__c s : [
      SELECT Space_Type__c, Operational_Status__c
      FROM PMS_Space__c
      WHERE Space_Type__c IN :types.keySet() AND Bookable__c = TRUE
    ]) {
      if (
        PMS_AvailabilityService.UNSELLABLE_SPACE_STATUSES.contains(
          s.Operational_Status__c
        )
      ) {
        continue;
      }
      sellable.put(
        s.Space_Type__c,
        (sellable.containsKey(s.Space_Type__c)
          ? sellable.get(s.Space_Type__c)
          : 0) + 1
      );
    }
    Map<String, Integer> sold = new Map<String, Integer>();
    for (AggregateResult ar : [
      SELECT Room_Type__c t, Stay_Date__c d, COUNT(Id) n
      FROM PMS_Room_Night__c
      WHERE
        Room_Type__c IN :types.keySet()
        AND Stay_Date__c >= :fromDate
        AND Stay_Date__c <= :toDate
        AND Status__c NOT IN :GONE_NIGHT
      GROUP BY Room_Type__c, Stay_Date__c
    ]) {
      sold.put(
        nightKey((Id) ar.get('t'), (Date) ar.get('d')),
        (Integer) ar.get('n')
      );
    }
    Map<String, Boolean> stopSell = new Map<String, Boolean>();
    for (PMS_Inventory_Day__c d : [
      SELECT Room_Type__c, Inventory_Date__c, Stop_Sell__c
      FROM PMS_Inventory_Day__c
      WHERE
        Room_Type__c IN :types.keySet()
        AND Inventory_Date__c >= :fromDate
        AND Inventory_Date__c <= :toDate
        AND Stop_Sell__c = TRUE
    ]) {
      stopSell.put(nightKey(d.Room_Type__c, d.Inventory_Date__c), true);
    }
    for (PMS_Space_Type__c t : types.values()) {
      if (String.isBlank(t.Channex_Room_Type_Id__c)) {
        p.problems.add(
          'Room type ' +
            t.Name +
            ' has no Channex Room Type ID, so it is not sent.'
        );
        continue;
      }
      Integer total = sellable.containsKey(t.Id) ? sellable.get(t.Id) : 0;
      List<Night> nights = new List<Night>();
      for (Integer i = 0; i < days; i++) {
        Date d = fromDate.addDays(i);
        Integer n = sold.get(nightKey(t.Id, d));
        Integer avail = Math.max(0, total - (n == null ? 0 : n));
        nights.add(new Night(d, String.valueOf(avail), false));
      }
      for (Night r : compress(nights)) {
        p.availability.add(
          new Map<String, Object>{
            'property_id' => site.Channex_Property_Id__c,
            'room_type_id' => t.Channex_Room_Type_Id__c,
            'date_from' => String.valueOf(r.night),
            'date_to' => String.valueOf(rangeEnd(r)),
            'availability' => Integer.valueOf(r.value)
          }
        );
      }
    }

    // ---- rates and stop sell
    List<PMS_Channel_Mapping__c> mappings = [
      SELECT
        Id,
        Name,
        Rate_Plan__c,
        Rate_Plan__r.Tax_Rate__c,
        Room_Type__c,
        Channex_Rate_Plan_Id__c
      FROM PMS_Channel_Mapping__c
      WHERE
        Site__c = :siteId
        AND Active__c = TRUE
        AND Channex_Rate_Plan_Id__c != NULL
        AND Rate_Plan__c != NULL
        AND Room_Type__c != NULL
    ];
    if (mappings.isEmpty()) {
      p.problems.add(
        'No active channel mappings for ' +
          site.Name +
          ', so no rates are sent.'
      );
    }
    Set<Id> planIds = new Set<Id>();
    for (PMS_Channel_Mapping__c m : mappings) {
      planIds.add(m.Rate_Plan__c);
    }
    Map<Id, List<PMS_Rate__c>> ratesByPlan = new Map<Id, List<PMS_Rate__c>>();
    for (PMS_Rate__c r : [
      SELECT
        Rate_Plan__c,
        Space_Type__c,
        Date_From__c,
        Date_To__c,
        Days_Of_Week__c,
        Amount__c
      FROM PMS_Rate__c
      WHERE
        Rate_Plan__c IN :planIds
        AND Service__c = NULL
        AND (Date_To__c = NULL
        OR Date_To__c >= :fromDate)
    ]) {
      if (!ratesByPlan.containsKey(r.Rate_Plan__c)) {
        ratesByPlan.put(r.Rate_Plan__c, new List<PMS_Rate__c>());
      }
      ratesByPlan.get(r.Rate_Plan__c).add(r);
    }
    Decimal moduleTax = PMS_ModuleConfig.defaultTaxRate(PMS_ModuleConfig.HOTEL);
    for (PMS_Channel_Mapping__c m : mappings) {
      PMS_Space_Type__c t = types.get(m.Room_Type__c);
      if (t == null) {
        p.problems.add(
          'Mapping ' + m.Name + ': the room type is not at this site.'
        );
        continue;
      }
      Decimal tax = m.Rate_Plan__r.Tax_Rate__c != null
        ? m.Rate_Plan__r.Tax_Rate__c
        : moduleTax;
      Decimal factor = site.Channex_Prices_Include_VAT__c == true
        ? 1 + (tax == null ? 0 : tax) / 100
        : 1;
      List<PMS_Rate__c> rates = ratesByPlan.containsKey(m.Rate_Plan__c)
        ? ratesByPlan.get(m.Rate_Plan__c)
        : new List<PMS_Rate__c>();
      List<Night> nights = new List<Night>();
      for (Integer i = 0; i < days; i++) {
        Date d = fromDate.addDays(i);
        Decimal net = PMS_DynamicPricingService.baseRate(rates, t, d);
        if (net == null || net <= 0) {
          continue;
        }
        String rate = (net * factor)
          .setScale(2, RoundingMode.HALF_UP)
          .toPlainString();
        nights.add(new Night(d, rate, stopSell.get(nightKey(t.Id, d))));
      }
      if (nights.isEmpty()) {
        p.problems.add('Mapping ' + m.Name + ': no rate found for any night.');
        continue;
      }
      for (Night r : compress(nights)) {
        p.restrictions.add(
          new Map<String, Object>{
            'property_id' => site.Channex_Property_Id__c,
            'rate_plan_id' => m.Channex_Rate_Plan_Id__c,
            'date_from' => String.valueOf(r.night),
            'date_to' => String.valueOf(rangeEnd(r)),
            'rate' => r.value,
            'stop_sell' => r.stopSell
          }
        );
      }
    }
    return p;
  }

  /** Sends the payload; makes no DML so it can be followed by more callouts. Returns log rows to insert later. */
  public static List<PMS_Channel_Log__c> push(Id siteId, Payload p) {
    List<PMS_Channel_Log__c> logs = new List<PMS_Channel_Log__c>();
    if (!p.availability.isEmpty()) {
      logs.add(
        send(
          siteId,
          'Availability',
          '/availability',
          p.availability,
          p.problems
        )
      );
    }
    if (!p.restrictions.isEmpty()) {
      logs.add(
        send(siteId, 'Rates', '/restrictions', p.restrictions, p.problems)
      );
    }
    if (p.availability.isEmpty() && p.restrictions.isEmpty()) {
      logs.add(
        log(
          siteId,
          'Availability',
          'Error',
          'Nothing to send.',
          String.join(p.problems, '\n')
        )
      );
    }
    return logs;
  }

  private static PMS_Channel_Log__c send(
    Id siteId,
    String kind,
    String path,
    List<Map<String, Object>> values,
    List<String> problems
  ) {
    try {
      Map<String, Object> res = PMS_ChannexClient.post(
        path,
        new Map<String, Object>{ 'values' => values }
      );
      List<Object> warnings = PMS_ChannexClient.asList(
        PMS_ChannexClient.asMap(res.get('meta')).get('warnings')
      );
      String details =
        (problems.isEmpty() ? '' : String.join(problems, '\n') + '\n') +
        (warnings.isEmpty() ? '' : JSON.serialize(warnings));
      return log(
        siteId,
        kind,
        warnings.isEmpty() ? 'Success' : 'Warning',
        values.size() +
          ' ' +
          kind.toLowerCase() +
          ' values sent' +
          (warnings.isEmpty() ? '.' : ', ' + warnings.size() + ' rejected.'),
        details
      );
    } catch (Exception e) {
      return log(
        siteId,
        kind,
        'Error',
        e.getMessage(),
        String.join(problems, '\n')
      );
    }
  }

  // ---------------------------------------------------------------- helpers

  /** Merges consecutive nights with the same value and stop sell into ranges (night .. endNight). */
  @TestVisible
  private static List<Night> compress(List<Night> nights) {
    List<Night> out = new List<Night>();
    Night current;
    for (Night n : nights) {
      if (
        current != null &&
        n.value == current.value &&
        n.stopSell == current.stopSell &&
        current.endNight.addDays(1) == n.night
      ) {
        current.endNight = n.night;
        continue;
      }
      current = new Night(n.night, n.value, n.stopSell);
      out.add(current);
    }
    return out;
  }

  private static Date rangeEnd(Night n) {
    return n.endNight == null ? n.night : n.endNight;
  }

  public static String nightKey(Id typeId, Date d) {
    return String.valueOf(typeId) + '|' + String.valueOf(d);
  }

  public static PMS_Channel_Log__c log(
    Id siteId,
    String kind,
    String status,
    String message,
    String details
  ) {
    return new PMS_Channel_Log__c(
      Direction__c = 'Outbound',
      Kind__c = kind,
      Status__c = status,
      Site__c = siteId,
      Message__c = message == null ? null : message.left(255),
      Details__c = details == null ? null : details.left(32000)
    );
  }
}
