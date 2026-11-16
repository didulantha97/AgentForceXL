/**
 * "Rent Review" tab (LWC pmsRentReview): index values, preparing index and negotiated adjustments,
 * and approving, notifying and cancelling them. Lists only leases the user can see (user mode).
 */
public with sharing class PMS_RentReviewController {
  public class Row {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id leaseId;
    @AuraEnabled
    public String lease;
    @AuraEnabled
    public String tenant;
    @AuraEnabled
    public String premises;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date effectiveDate;
    @AuraEnabled
    public Decimal oldRent;
    @AuraEnabled
    public Decimal newRent;
    @AuraEnabled
    public Decimal changePercent;
    @AuraEnabled
    public String warning;
    @AuraEnabled
    public Datetime noticeSentAt;
  }

  public class IndexRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String series;
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public Integer month;
    @AuraEnabled
    public Decimal value;
    @AuraEnabled
    public String source;
  }

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class Data {
    @AuraEnabled
    public List<Row> rows = new List<Row>();
    @AuraEnabled
    public List<IndexRow> indexValues = new List<IndexRow>();
    @AuraEnabled
    public List<Option> sites = new List<Option>();
  }

  @AuraEnabled
  public static Data load(Integer year) {
    try {
      Data d = new Data();
      Date fromDate = Date.newInstance(year, 1, 1);
      Date toDate = Date.newInstance(year, 12, 31);
      for (PMS_Rent_Adjustment__c a : [
        SELECT
          Id,
          Name,
          Lease__c,
          Lease__r.Name,
          Lease__r.Account__r.Name,
          Lease__r.Site__r.Name,
          Lease__r.Space__r.Name,
          Kind__c,
          Status__c,
          Effective_Date__c,
          Old_Rent__c,
          New_Rent__c,
          Change_Percent__c,
          Warning__c,
          Notice_Sent_At__c
        FROM PMS_Rent_Adjustment__c
        WHERE Effective_Date__c >= :fromDate AND Effective_Date__c <= :toDate
        WITH USER_MODE
        ORDER BY Status__c, Lease__r.Name
        LIMIT 1000
      ]) {
        Row r = new Row();
        r.id = a.Id;
        r.name = a.Name;
        r.leaseId = a.Lease__c;
        r.lease = a.Lease__r.Name;
        r.tenant = a.Lease__r.Account__r == null
          ? null
          : a.Lease__r.Account__r.Name;
        r.premises = ((a.Lease__r.Site__r == null
            ? ''
            : a.Lease__r.Site__r.Name) +
          (a.Lease__r.Space__r == null ? '' : ', ' + a.Lease__r.Space__r.Name))
          .removeStart(', ');
        r.kind = a.Kind__c;
        r.status = a.Status__c;
        r.effectiveDate = a.Effective_Date__c;
        r.oldRent = a.Old_Rent__c;
        r.newRent = a.New_Rent__c;
        r.changePercent = a.Change_Percent__c;
        r.warning = a.Warning__c;
        r.noticeSentAt = a.Notice_Sent_At__c;
        d.rows.add(r);
      }
      for (PMS_Index_Value__c v : [
        SELECT Id, Series__c, Year__c, Month__c, Value__c, Source__c
        FROM PMS_Index_Value__c
        WITH USER_MODE
        ORDER BY Year__c DESC, Month__c DESC
        LIMIT 24
      ]) {
        IndexRow r = new IndexRow();
        r.id = v.Id;
        r.series = v.Series__c;
        r.year = v.Year__c == null ? null : v.Year__c.intValue();
        r.month = v.Month__c == null ? null : v.Month__c.intValue();
        r.value = v.Value__c;
        r.source = v.Source__c;
        d.indexValues.add(r);
      }
      d.sites.add(new Option('All property sites', ''));
      for (PMS_Site__c s : [
        SELECT Id, Name
        FROM PMS_Site__c
        WHERE Module__c = 'Property'
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]) {
        d.sites.add(new Option(s.Name, s.Id));
      }
      return d;
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static void saveIndexValue(
    String series,
    Integer year,
    Integer month,
    Decimal value,
    String source
  ) {
    try {
      if (
        String.isBlank(series) ||
        year == null ||
        month == null ||
        month < 1 ||
        month > 12 ||
        value == null ||
        value <= 0
      ) {
        throw new PMS_Exception(
          'Enter the series, year, month (1-12) and a positive value.'
        );
      }
      List<PMS_Index_Value__c> existing = [
        SELECT Id
        FROM PMS_Index_Value__c
        WHERE Series__c = :series AND Year__c = :year AND Month__c = :month
        WITH USER_MODE
        LIMIT 1
      ];
      PMS_Index_Value__c v = existing.isEmpty()
        ? new PMS_Index_Value__c()
        : existing[0];
      v.Series__c = series;
      v.Year__c = year;
      v.Month__c = month;
      v.Value__c = value;
      v.Source__c = source;
      upsert as user v;
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static PMS_RentIndexService.Result prepareIndex(
    Integer year,
    String siteId
  ) {
    try {
      return PMS_RentIndexService.prepareIndex(
        year,
        String.isBlank(siteId) ? null : (Id) siteId
      );
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static PMS_RentIndexService.Result prepareNegotiated(
    String siteId,
    Decimal percent,
    Date effectiveDate,
    String note
  ) {
    try {
      return PMS_RentIndexService.prepareNegotiated(
        String.isBlank(siteId) ? null : (Id) siteId,
        percent,
        effectiveDate,
        note
      );
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static Integer approve(List<Id> ids) {
    try {
      return PMS_RentIndexService.approve(visible(ids));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static List<String> sendNotices(List<Id> ids) {
    try {
      return PMS_RentIndexService.sendNotices(visible(ids));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  @AuraEnabled
  public static Integer cancel(List<Id> ids) {
    try {
      return PMS_RentIndexService.cancel(visible(ids));
    } catch (Exception e) {
      throw fail(e);
    }
  }

  /** Changes the proposed rent of a draft (for example after rounding agreed with the tenant). */
  @AuraEnabled
  public static void updateNewRent(Id id, Decimal newRent) {
    try {
      List<PMS_Rent_Adjustment__c> a = [
        SELECT Id, Status__c, Old_Rent__c
        FROM PMS_Rent_Adjustment__c
        WHERE Id = :id
        WITH USER_MODE
      ];
      if (a.isEmpty() || a[0].Status__c != 'Draft') {
        throw new PMS_Exception('Only draft adjustments can be changed.');
      }
      if (newRent == null || newRent <= 0) {
        throw new PMS_Exception('Enter a positive rent.');
      }
      a[0].New_Rent__c = newRent;
      a[0].Change_Percent__c = PMS_RentIndexService.changePercent(
        a[0].Old_Rent__c,
        newRent
      );
      update a;
    } catch (Exception e) {
      throw fail(e);
    }
  }

  private static Set<Id> visible(List<Id> ids) {
    return new Map<Id, PMS_Rent_Adjustment__c>(
        [SELECT Id FROM PMS_Rent_Adjustment__c WHERE Id IN :ids WITH USER_MODE]
      )
      .keySet();
  }

  private static AuraHandledException fail(Exception e) {
    AuraHandledException ex = new AuraHandledException(e.getMessage());
    ex.setMessage(e.getMessage());
    return ex;
  }
}
