/**
 * Post-install script for PMS Core. Records the install date once; it starts the pilot period.
 * Upgrades never restart it: the date is only written when blank (first install, or an org that
 * upgraded from a version that pre-dates licensing).
 */
global with sharing class PMS_InstallHandler implements InstallHandler {
  @TestVisible
  private static Boolean failForTest = false;

  global void onInstall(InstallContext context) {
    try {
      if (failForTest) {
        throw new IllegalArgumentException('forced');
      }
      PMS_Entitlements.ensureInstallDate();
    } catch (Exception e) {
      // Never fail an install over licensing; the daily job records the date later.
      System.debug(
        LoggingLevel.ERROR,
        'PMS install date not recorded: ' + e.getMessage()
      );
    }
  }
}
