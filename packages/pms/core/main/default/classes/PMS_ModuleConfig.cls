/**
 * Reads the PMS_Module__mdt switchboard and resolves record types per module.
 * Everything that behaves differently per module (Property, Hotel, Project, Practice)
 * should ask this class instead of hard-coding names.
 */
@NamespaceAccessible
public inherited sharing class PMS_ModuleConfig {
  @NamespaceAccessible
  public static final String PROPERTY = 'Property';
  @NamespaceAccessible
  public static final String HOTEL = 'Hotel';
  @NamespaceAccessible
  public static final String PROJECT = 'Project';
  @NamespaceAccessible
  public static final String PRACTICE = 'Practice';

  private static Map<String, PMS_Module__mdt> cache;

  @NamespaceAccessible
  public static Map<String, PMS_Module__mdt> all() {
    if (cache == null) {
      cache = new Map<String, PMS_Module__mdt>();
      for (PMS_Module__mdt m : PMS_Module__mdt.getAll().values()) {
        cache.put(m.DeveloperName, m);
      }
    }
    return cache;
  }

  @NamespaceAccessible
  public static PMS_Module__mdt get(String module) {
    return all().get(module);
  }

  @NamespaceAccessible
  public static Boolean isEnabled(String module) {
    PMS_Module__mdt m = get(module);
    return m != null && m.Enabled__c == true;
  }

  @NamespaceAccessible
  public static List<String> enabledModules() {
    List<String> result = new List<String>();
    for (String name : new List<String>{ PROPERTY, HOTEL, PROJECT, PRACTICE }) {
      if (isEnabled(name)) {
        result.add(name);
      }
    }
    return result;
  }

  @NamespaceAccessible
  public static Id recordTypeId(
    Schema.SObjectType objType,
    String developerName
  ) {
    if (String.isBlank(developerName)) {
      return null;
    }
    Schema.RecordTypeInfo info = objType.getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get(developerName);
    return info == null ? null : info.getRecordTypeId();
  }

  @NamespaceAccessible
  public static Id bookingRecordTypeId(String module) {
    PMS_Module__mdt m = get(module);
    return m == null
      ? null
      : recordTypeId(PMS_Booking__c.SObjectType, m.Booking_Record_Type__c);
  }

  @NamespaceAccessible
  public static Id invoiceRecordTypeId(String module) {
    PMS_Module__mdt m = get(module);
    return m == null
      ? null
      : recordTypeId(PMS_Invoice__c.SObjectType, m.Invoice_Record_Type__c);
  }

  @NamespaceAccessible
  public static Decimal defaultTaxRate(String module) {
    PMS_Module__mdt m = get(module);
    return (m == null ||
      m.Default_Tax_Rate__c == null)
      ? 0
      : m.Default_Tax_Rate__c;
  }

  @NamespaceAccessible
  public static Integer invoiceDueDays(String module) {
    PMS_Module__mdt m = get(module);
    return (m == null ||
      m.Invoice_Due_Days__c == null)
      ? 30
      : m.Invoice_Due_Days__c.intValue();
  }

  @NamespaceAccessible
  public static String pricingBasis(String module) {
    PMS_Module__mdt m = get(module);
    return (m == null || String.isBlank(m.Pricing_Basis__c))
      ? 'Per Night'
      : m.Pricing_Basis__c;
  }

  /** Maps a Booking record type id back to its module name (Lease -> Property, etc.). */
  @NamespaceAccessible
  public static String moduleForBookingRecordType(Id recordTypeId) {
    if (recordTypeId == null) {
      return null;
    }
    Schema.RecordTypeInfo info = PMS_Booking__c.SObjectType.getDescribe()
      .getRecordTypeInfosById()
      .get(recordTypeId);
    if (info == null) {
      return null;
    }
    String devName = info.getDeveloperName();
    for (PMS_Module__mdt m : all().values()) {
      if (m.Booking_Record_Type__c == devName) {
        return m.DeveloperName;
      }
    }
    return null;
  }
}
