/**
 * Pricing engine. Resolves the price for a space type or service from a rate plan,
 * honouring seasons (date ranges), days of the week and minimum stay.
 * Falls back to Space Base Rate, Space Type Default Rate or Service Price.
 *
 * Services without a rate plan are priced per session: one unit at the service's Price,
 * taxed at the service's own Tax Rate when set (else the module default). A rate plan can
 * still price services per hour by setting its Pricing Basis to Per Hour.
 *
 * Note: percent fields hold whole numbers in Apex (12 = 12%).
 */
public inherited sharing class PMS_PricingService {
  public static final String PER_SESSION = 'Per Session';

  public class QuoteLine {
    @AuraEnabled
    public Date serviceDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id rateId;
  }

  public class Quote {
    @AuraEnabled
    public String pricingBasis;
    @AuraEnabled
    public Decimal units = 0;
    @AuraEnabled
    public Decimal unitPrice = 0;
    @AuraEnabled
    public Decimal net = 0;
    @AuraEnabled
    public Decimal taxRate = 0;
    @AuraEnabled
    public Decimal tax = 0;
    @AuraEnabled
    public Decimal gross = 0;
    @AuraEnabled
    public Id ratePlanId;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public List<QuoteLine> lines = new List<QuoteLine>();
  }

  public class QuoteRequest {
    public String module;
    public Id ratePlanId;
    public Id spaceTypeId;
    public Id spaceId;
    public Id serviceId;
    public Date startDate;
    public Date endDate;
    public Decimal hours;
  }

  public static Quote quote(QuoteRequest req) {
    Quote q = new Quote();
    PMS_Rate_Plan__c plan = loadPlan(req.ratePlanId);
    PMS_Service__c service = loadService(req.serviceId);
    q.ratePlanId = plan == null ? null : plan.Id;
    if (plan != null && String.isNotBlank(plan.Pricing_Basis__c)) {
      q.pricingBasis = plan.Pricing_Basis__c;
    } else if (service != null) {
      q.pricingBasis = PER_SESSION;
    } else {
      q.pricingBasis = PMS_ModuleConfig.pricingBasis(req.module);
    }
    q.currencyCode = plan == null ? null : plan.Currency_Code__c;
    if (plan != null && plan.Tax_Rate__c != null) {
      q.taxRate = plan.Tax_Rate__c;
    } else if (service != null && service.Tax_Rate__c != null) {
      q.taxRate = service.Tax_Rate__c;
    } else {
      q.taxRate = PMS_ModuleConfig.defaultTaxRate(req.module);
    }

    Decimal fallback = fallbackPrice(req, service);
    List<PMS_Rate__c> rates = plan == null
      ? new List<PMS_Rate__c>()
      : plan.Rates__r;

    switch on q.pricingBasis {
      when 'Per Night' {
        Integer nights = PMS_DateUtil.nightsBetween(req.startDate, req.endDate);
        for (Integer i = 0; i < nights; i++) {
          Date d = req.startDate.addDays(i);
          PMS_Rate__c r = bestRate(rates, req, d, nights);
          QuoteLine line = new QuoteLine();
          line.serviceDate = d;
          line.amount = r == null ? fallback : r.Amount__c;
          line.rateId = r == null ? null : r.Id;
          line.label = 'Night of ' + String.valueOf(d);
          q.lines.add(line);
          q.net += line.amount;
        }
        q.units = nights;
        q.unitPrice = nights == 0 ? 0 : (q.net / nights).setScale(2);
      }
      when 'Per Month', 'Per Week' {
        Integer units = q.pricingBasis == 'Per Month'
          ? PMS_DateUtil.monthsBetween(req.startDate, req.endDate)
          : (Decimal.valueOf(
                PMS_DateUtil.nightsBetween(req.startDate, req.endDate)
              ) / 7)
              .round(System.RoundingMode.CEILING)
              .intValue();
        PMS_Rate__c r = bestRate(rates, req, req.startDate, units);
        q.units = units;
        q.unitPrice = r == null ? fallback : r.Amount__c;
        q.net = q.unitPrice * units;
      }
      when 'Per Hour' {
        PMS_Rate__c r = bestRate(rates, req, req.startDate, 0);
        q.units = req.hours == null ? 1 : req.hours;
        q.unitPrice = r == null ? fallback : r.Amount__c;
        q.net = q.unitPrice * q.units;
      }
      when else {
        PMS_Rate__c r = bestRate(rates, req, req.startDate, 0);
        q.units = 1;
        q.unitPrice = r == null ? fallback : r.Amount__c;
        q.net = q.unitPrice;
      }
    }
    q.net = nz(q.net).setScale(2);
    q.tax = (q.net * nz(q.taxRate) / 100).setScale(2);
    q.gross = q.net + q.tax;
    return q;
  }

  private static PMS_Rate_Plan__c loadPlan(Id ratePlanId) {
    if (ratePlanId == null) {
      return null;
    }
    List<PMS_Rate_Plan__c> plans = [
      SELECT
        Id,
        Pricing_Basis__c,
        Tax_Rate__c,
        Currency_Code__c,
        Active__c,
        Valid_From__c,
        Valid_To__c,
        (
          SELECT
            Id,
            Space_Type__c,
            Service__c,
            Date_From__c,
            Date_To__c,
            Days_Of_Week__c,
            Amount__c,
            Min_Stay__c
          FROM Rates__r
        )
      FROM PMS_Rate_Plan__c
      WHERE Id = :ratePlanId AND Active__c = TRUE
    ];
    return plans.isEmpty() ? null : plans[0];
  }

  private static PMS_Service__c loadService(Id serviceId) {
    if (serviceId == null) {
      return null;
    }
    List<PMS_Service__c> services = [
      SELECT Id, Price__c, Tax_Rate__c
      FROM PMS_Service__c
      WHERE Id = :serviceId
    ];
    return services.isEmpty() ? null : services[0];
  }

  /** Most specific matching rate: the narrowest season wins; undated rates are the fallback. */
  @TestVisible
  private static PMS_Rate__c bestRate(
    List<PMS_Rate__c> rates,
    QuoteRequest req,
    Date d,
    Integer stayLength
  ) {
    PMS_Rate__c best;
    Integer bestSpan;
    String day = d == null ? null : PMS_DateUtil.dayName(d);
    for (PMS_Rate__c r : rates) {
      if (
        req.spaceTypeId != null &&
        r.Space_Type__c != null &&
        r.Space_Type__c != req.spaceTypeId
      ) {
        continue;
      }
      if (
        req.serviceId != null &&
        r.Service__c != null &&
        r.Service__c != req.serviceId
      ) {
        continue;
      }
      if (
        req.spaceTypeId == null &&
        req.serviceId == null &&
        (r.Space_Type__c != null ||
        r.Service__c != null)
      ) {
        continue;
      }
      if (d != null && r.Date_From__c != null && d < r.Date_From__c) {
        continue;
      }
      if (d != null && r.Date_To__c != null && d > r.Date_To__c) {
        continue;
      }
      if (
        String.isNotBlank(r.Days_Of_Week__c) &&
        day != null &&
        !r.Days_Of_Week__c.split(';').contains(day)
      ) {
        continue;
      }
      if (
        r.Min_Stay__c != null &&
        stayLength > 0 &&
        stayLength < r.Min_Stay__c
      ) {
        continue;
      }
      Integer span = (r.Date_From__c != null &&
        r.Date_To__c != null)
        ? r.Date_From__c.daysBetween(r.Date_To__c)
        : 1000000;
      if (String.isNotBlank(r.Days_Of_Week__c)) {
        span -= 1; // a weekday-specific rate beats an all-week rate for the same season
      }
      if (best == null || span < bestSpan) {
        best = r;
        bestSpan = span;
      }
    }
    return best;
  }

  private static Decimal fallbackPrice(
    QuoteRequest req,
    PMS_Service__c service
  ) {
    if (req.spaceId != null) {
      List<PMS_Space__c> spaces = [
        SELECT Base_Rate__c, Space_Type__r.Default_Rate__c
        FROM PMS_Space__c
        WHERE Id = :req.spaceId
      ];
      if (!spaces.isEmpty()) {
        if (spaces[0].Base_Rate__c != null) {
          return spaces[0].Base_Rate__c;
        }
        if (
          spaces[0].Space_Type__r != null &&
          spaces[0].Space_Type__r.Default_Rate__c != null
        ) {
          return spaces[0].Space_Type__r.Default_Rate__c;
        }
      }
    }
    if (req.spaceTypeId != null) {
      List<PMS_Space_Type__c> types = [
        SELECT Default_Rate__c
        FROM PMS_Space_Type__c
        WHERE Id = :req.spaceTypeId
      ];
      if (!types.isEmpty() && types[0].Default_Rate__c != null) {
        return types[0].Default_Rate__c;
      }
    }
    if (service != null && service.Price__c != null) {
      return service.Price__c;
    }
    return 0;
  }

  private static Decimal nz(Decimal d) {
    return d == null ? 0 : d;
  }
}
