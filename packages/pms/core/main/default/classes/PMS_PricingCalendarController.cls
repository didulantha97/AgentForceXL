/**
 * Pricing calendar (LWC pmsPricingCalendar) for a Pricing Strategy or Rate Plan record page:
 * nights x room types with the daily rate, base, occupancy and the factors that applied.
 * Staff can recalculate now, set a rate by hand (which locks it) and unlock it again.
 */
public with sharing class PMS_PricingCalendarController {
  public class RoomType {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  public class Night {
    @AuraEnabled
    public Date night;
    @AuraEnabled
    public String dayName;
    @AuraEnabled
    public List<PMS_DynamicPricingService.Cell> cells = new List<PMS_DynamicPricingService.Cell>();
  }

  public class Calendar {
    @AuraEnabled
    public Id strategyId;
    @AuraEnabled
    public String strategyName;
    @AuraEnabled
    public String ratePlanName;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Datetime lastRunAt;
    @AuraEnabled
    public String lastRunResult;
    @AuraEnabled
    public List<RoomType> roomTypes = new List<RoomType>();
    @AuraEnabled
    public List<Night> nights = new List<Night>();
  }

  @AuraEnabled
  public static Calendar getCalendar(Id recordId, Integer days) {
    try {
      PMS_Pricing_Strategy__c s = strategyFor(recordId);
      Calendar c = new Calendar();
      c.strategyId = s.Id;
      c.strategyName = s.Name;
      c.ratePlanName = s.Rate_Plan__r == null ? null : s.Rate_Plan__r.Name;
      c.currencyCode = s.Rate_Plan__r == null ||
        String.isBlank(s.Rate_Plan__r.Currency_Code__c)
        ? 'SEK'
        : s.Rate_Plan__r.Currency_Code__c;
      c.lastRunAt = s.Last_Run_At__c;
      c.lastRunResult = s.Last_Run_Result__c;
      if (s.Rate_Plan__r == null || s.Rate_Plan__r.Site__c == null) {
        return c;
      }
      Integer n = days == null ? 30 : Math.max(7, Math.min(days, 120));
      Date fromDate = Date.today();
      Date toDate = fromDate.addDays(n - 1);
      List<PMS_Space_Type__c> types = [
        SELECT Id, Name
        FROM PMS_Space_Type__c
        WHERE Site__c = :s.Rate_Plan__r.Site__c
        WITH USER_MODE
        ORDER BY Name
      ];
      for (PMS_Space_Type__c t : types) {
        RoomType rt = new RoomType();
        rt.id = t.Id;
        rt.name = t.Name;
        c.roomTypes.add(rt);
      }
      Map<String, PMS_Rate__c> rates = new Map<String, PMS_Rate__c>();
      for (PMS_Rate__c r : [
        SELECT
          Id,
          Space_Type__c,
          Date_From__c,
          Amount__c,
          Base_Amount__c,
          Occupancy__c,
          Pricing_Notes__c,
          Locked__c,
          Dynamic_Key__c
        FROM PMS_Rate__c
        WHERE
          Rate_Plan__c = :s.Rate_Plan__c
          AND Dynamic__c = TRUE
          AND Date_From__c >= :fromDate
          AND Date_From__c <= :toDate
        WITH USER_MODE
      ]) {
        rates.put(r.Dynamic_Key__c, r);
      }
      for (Integer i = 0; i < n; i++) {
        Date d = fromDate.addDays(i);
        Night night = new Night();
        night.night = d;
        night.dayName = PMS_DynamicPricingService.dayName(d).left(3);
        for (PMS_Space_Type__c t : types) {
          PMS_DynamicPricingService.Cell cell = new PMS_DynamicPricingService.Cell();
          cell.roomTypeId = t.Id;
          cell.night = d;
          PMS_Rate__c r = rates.get(
            PMS_DynamicPricingService.key(s.Rate_Plan__c, t.Id, d)
          );
          if (r != null) {
            cell.rateId = r.Id;
            cell.amount = r.Amount__c;
            cell.base = r.Base_Amount__c;
            cell.occupancy = r.Occupancy__c;
            cell.notes = r.Pricing_Notes__c;
            cell.locked = r.Locked__c == true;
          }
          night.cells.add(cell);
        }
        c.nights.add(night);
      }
      return c;
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static PMS_DynamicPricingService.RunResult recalculate(Id recordId) {
    try {
      return PMS_DynamicPricingService.recalculate(strategyFor(recordId).Id);
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static void setPrice(Id rateId, Decimal amount) {
    try {
      checkRate(rateId);
      PMS_DynamicPricingService.setPrice(rateId, amount);
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static void unlock(Id rateId) {
    try {
      checkRate(rateId);
      PMS_DynamicPricingService.unlock(rateId);
    } catch (Exception e) {
      throw fail(e);
    }
  }

  private static void checkRate(Id rateId) {
    if (
      [
        SELECT COUNT()
        FROM PMS_Rate__c
        WHERE Id = :rateId AND Dynamic__c = TRUE
        WITH USER_MODE
      ] == 0
    ) {
      throw new PMS_Exception('Daily rate not found.');
    }
  }

  /** Accepts a strategy Id or a rate plan Id (its active strategy). */
  private static PMS_Pricing_Strategy__c strategyFor(Id recordId) {
    List<PMS_Pricing_Strategy__c> s;
    if (recordId.getSObjectType() == PMS_Pricing_Strategy__c.SObjectType) {
      s = [
        SELECT
          Id,
          Name,
          Rate_Plan__c,
          Rate_Plan__r.Name,
          Rate_Plan__r.Site__c,
          Rate_Plan__r.Currency_Code__c,
          Last_Run_At__c,
          Last_Run_Result__c
        FROM PMS_Pricing_Strategy__c
        WHERE Id = :recordId
        WITH USER_MODE
      ];
    } else {
      s = [
        SELECT
          Id,
          Name,
          Rate_Plan__c,
          Rate_Plan__r.Name,
          Rate_Plan__r.Site__c,
          Rate_Plan__r.Currency_Code__c,
          Last_Run_At__c,
          Last_Run_Result__c
        FROM PMS_Pricing_Strategy__c
        WHERE Rate_Plan__c = :recordId
        WITH USER_MODE
        ORDER BY Active__c DESC, CreatedDate DESC
        LIMIT 1
      ];
    }
    if (s.isEmpty()) {
      throw new PMS_Exception(
        'No pricing strategy for this record. Create a Pricing Strategy for the rate plan first.'
      );
    }
    return s[0];
  }

  private static AuraHandledException fail(Exception e) {
    AuraHandledException ex = new AuraHandledException(e.getMessage());
    ex.setMessage(e.getMessage());
    return ex;
  }
}
