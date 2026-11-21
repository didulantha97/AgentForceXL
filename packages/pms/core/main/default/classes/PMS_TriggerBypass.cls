/**
 * Core-level trigger bypass flags that Experience trigger handlers honour, so Core code never
 * references Experience classes. Set and restore in try/finally.
 */
@NamespaceAccessible
public with sharing class PMS_TriggerBypass {
  /** True while Core updates bookings that must not get automatic policy fees or guarantee links. */
  @NamespaceAccessible
  public static Boolean policyFees = false;
}
