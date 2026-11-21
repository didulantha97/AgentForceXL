/** Agent action: "Get Price" quote for a stay, lease or service. */
public with sharing class PMS_GetQuoteAction {
  public class Request {
    @InvocableVariable(
      required=true
      label='Module'
      description='Property, Hotel, Project or Practice'
    )
    public String module;
    @InvocableVariable(label='Rate Plan Id')
    public Id ratePlanId;
    @InvocableVariable(label='Space Type Id')
    public Id spaceTypeId;
    @InvocableVariable(label='Service Id')
    public Id serviceId;
    @InvocableVariable(required=true label='Start Date')
    public Date startDate;
    @InvocableVariable(label='End Date')
    public Date endDate;
    @InvocableVariable(label='Hours')
    public Decimal hours;
  }

  public class Result {
    @InvocableVariable(label='Net Amount')
    public Decimal net;
    @InvocableVariable(label='Tax Amount')
    public Decimal tax;
    @InvocableVariable(label='Total Amount')
    public Decimal gross;
    @InvocableVariable(label='Summary')
    public String summary;
  }

  @InvocableMethod(
    label='PMS: Get Price'
    description='Calculates the price including tax for a stay, lease period or service using the rate plan.'
    category='Unified PMS'
  )
  public static List<Result> run(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request r : requests) {
      PMS_PricingService.QuoteRequest qr = new PMS_PricingService.QuoteRequest();
      qr.module = r.module;
      qr.ratePlanId = r.ratePlanId;
      qr.spaceTypeId = r.spaceTypeId;
      qr.serviceId = r.serviceId;
      qr.startDate = r.startDate;
      qr.endDate = r.endDate == null ? r.startDate : r.endDate;
      qr.hours = r.hours;
      PMS_PricingService.Quote q = PMS_PricingService.quote(qr);
      Result res = new Result();
      res.net = q.getNet();
      res.tax = q.getTax();
      res.gross = q.getGross();
      res.summary =
        q.getUnits() +
        ' x ' +
        q.getPricingBasis().toLowerCase() +
        ' at ' +
        q.getUnitPrice() +
        ' = ' +
        q.getNet() +
        ' + tax ' +
        q.getTax() +
        ' = ' +
        q.getGross() +
        (q.getCurrencyCode() == null ? '' : ' ' + q.getCurrencyCode());
      results.add(res);
    }
    return results;
  }
}
