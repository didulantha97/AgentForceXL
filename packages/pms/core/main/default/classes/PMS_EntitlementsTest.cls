/**
 * Tests for the licence layer. The tokens below were signed once with a throw-away RSA-2048 test key
 * (private key deleted) and are only valid against TEST_PUBLIC_KEY, org TEST_ORG and key id test-key-1.
 * All dates are driven through test hooks because the signatures cover the payload.
 *
 * Payload of every token: edition Standard, modules Hotel+Property (Finance/Staff/AI off),
 * caps maxRooms 3 / maxUnits unlimited / maxPortalUsers 50, validUntil 2027-06-30, graceDays 10,
 * unless noted in the name.
 */
@isTest
private class PMS_EntitlementsTest {
  private static final String TEST_ORG = '00D5g000000TEST1AAA';
  private static final String TEST_KEY_ID = 'test-key-1';
  private static final String TEST_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwDC/5/dQv5C0PcEAJefRj1uwG0RpM7xbpZcQ1cJLr6WemPNUtoKwc+qIVJEbdOtDOnmoR/7vza+L6Qycjnx3POt8gZF6EDmSds+R9gux54qM4haz8TgwhgZBZ962HFdnDHzNuONyVHibdpqLT4e2gAVD74ymsg6nkJzZwdhAnyE9qBsTq2SM3Z1h6fujz95eRT7Om8iF6oHOAt4qejWoxgpsh9I8pJpMmJK/sKv33Z4L9J9eaQM7HTAcpvx/Wxz4sOBkpYPjK/BF4JYQC51WeE8Cg23Ys4f1C6mp6Ub4kJ66aTr5XqDhs/mrs+WnpHzL5YTAKKp7chaRFR1wLzK8NwIDAQAB';
  // standard token
  private static final String TOKEN_OK = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQUEiLCJlZGl0aW9uIjoiU3RhbmRhcmQiLCJtb2R1bGVzIjp7IkhvdGVsIjp0cnVlLCJQcm9wZXJ0eSI6dHJ1ZSwiRmluYW5jZSI6ZmFsc2UsIlN0YWZmIjpmYWxzZSwiQUkiOmZhbHNlfSwiY2FwcyI6eyJtYXhSb29tcyI6MywibWF4VW5pdHMiOm51bGwsIm1heFBvcnRhbFVzZXJzIjo1MH0sInZhbGlkVW50aWwiOiIyMDI3LTA2LTMwIiwiZ3JhY2VEYXlzIjoxMCwiaXNzdWVkQXQiOiIyMDI3LTAxLTA1Iiwia2V5SWQiOiJ0ZXN0LWtleS0xIn0.WL40pary2E3RxqQI6k0oMPY6KBj0HYqnhottBsn8T5y7mmIafynf8w4gFeW3YYl75IjZTVl0RwVfMskDqjMHoUQzy5aDukixk8Zuic4v0HAiu_e6G8XC0xc7Vwrw3HLlP72DpgYI0TqhbW_C9n68e6R_O_x-dMpdm9UNxi5w8pAs6CvkvzqHFBG3cbGJC54q7enmyyUpPPc8xN4WF_306W-uUt8ras50SEeHxkrtz6gv2T2Y1jLNkv1n-BLb8_Nsz6kTxllVmF_xqBm6EGB7guYhP8R3cqjeCCoUtm9TbpvOmob2Fj3A09DJMRjMKEIDwi1Icovjz2tWhMujjct37Q';
  // same payload without graceDays (falls back to the default)
  private static final String TOKEN_NO_GRACE = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQUEiLCJlZGl0aW9uIjoiU3RhbmRhcmQiLCJtb2R1bGVzIjp7IkhvdGVsIjp0cnVlLCJQcm9wZXJ0eSI6dHJ1ZSwiRmluYW5jZSI6ZmFsc2UsIlN0YWZmIjpmYWxzZSwiQUkiOmZhbHNlfSwiY2FwcyI6eyJtYXhSb29tcyI6MywibWF4VW5pdHMiOm51bGwsIm1heFBvcnRhbFVzZXJzIjo1MH0sInZhbGlkVW50aWwiOiIyMDI3LTA2LTMwIiwiaXNzdWVkQXQiOiIyMDI3LTAxLTA1Iiwia2V5SWQiOiJ0ZXN0LWtleS0xIn0.qJ26XMxLvp5QTsmP7yKMjp2c0_IxhHWR0PW7SU8BRQ_owxP-_0LEzp3cao7arpWi0b0yfWZsd9L9g9k4jhE-eEvz6afXnxpksTXwB5rw5_Zck-uMCdi7nYcX6cDDqZ03Y38nexRJSeeAVd6sqn_geTPJaAaE7OZuaHMEV1hF7NLdc7VOoAit0fGNcx5smRX8Jb9da4DuJ22waBJ-Lnak1KOBNtHU_89PGJVbqUHCjr1APTjnS8-1y7nfpf6Qy_wAZ_alnzL8_Y21jG9Aba-zxNNWBiMlnaoqF0rgln38aCgSevpOr9bS19A2udVBD4udvhT74S44dMslJTt6N_eqOw';
  // orgId 00D5g000000OTHERAAA
  private static final String TOKEN_OTHER_ORG = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwT1RIRVJBQUEiLCJlZGl0aW9uIjoiU3RhbmRhcmQiLCJtb2R1bGVzIjp7IkhvdGVsIjp0cnVlLCJQcm9wZXJ0eSI6dHJ1ZSwiRmluYW5jZSI6ZmFsc2UsIlN0YWZmIjpmYWxzZSwiQUkiOmZhbHNlfSwiY2FwcyI6eyJtYXhSb29tcyI6MywibWF4VW5pdHMiOm51bGwsIm1heFBvcnRhbFVzZXJzIjo1MH0sInZhbGlkVW50aWwiOiIyMDI3LTA2LTMwIiwiZ3JhY2VEYXlzIjoxMCwiaXNzdWVkQXQiOiIyMDI3LTAxLTA1Iiwia2V5SWQiOiJ0ZXN0LWtleS0xIn0.sMSQhc1jJPSkLkrpd7Gd18SuDZ420hN34ANh68eh_sVH-XTqiEHsi6abVHgswAeuCXp-n0bB0-tJrptH_WxUX6wMfQWIY9lu5uxwcB6us2h5ByUyHmXeLtJVtCIHvLvj8gMoZBGOcCIhmDc-g35qTaaiIpHqOtBb8Sy2lDB6uLH9AGL4_EH5vV6S00vCHMWgjlFsj68gLguDMFVjESZLko6Z-5vHZX9kU5EMTKIm3GMMw3jOnOoVPueRgYZ4608m1I-SFZ_p3wqMS1ThzpGL7pPjcLeLrK6_999rG2Y0h5Bus9jEHcxqECKO2SycN3uB9s91zWA0f2g8KgCoOsxGsg';
  // keyId other-key
  private static final String TOKEN_BAD_KEY = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQUEiLCJlZGl0aW9uIjoiU3RhbmRhcmQiLCJtb2R1bGVzIjp7IkhvdGVsIjp0cnVlLCJQcm9wZXJ0eSI6dHJ1ZSwiRmluYW5jZSI6ZmFsc2UsIlN0YWZmIjpmYWxzZSwiQUkiOmZhbHNlfSwiY2FwcyI6eyJtYXhSb29tcyI6MywibWF4VW5pdHMiOm51bGwsIm1heFBvcnRhbFVzZXJzIjo1MH0sInZhbGlkVW50aWwiOiIyMDI3LTA2LTMwIiwiZ3JhY2VEYXlzIjoxMCwiaXNzdWVkQXQiOiIyMDI3LTAxLTA1Iiwia2V5SWQiOiJvdGhlci1rZXkifQ.Envni_yt6xeaw_Rdv20rWBCJXH9Nl6gKheREUzrtVGleAs9azLt1eoM4yVex0QTdpKuRkonAc-p8vVgyTutuF6bUc7pfrnx6czu9_1hg1EA6bgwshSZViChyvvqN_gc2TFrW0bKoWAwDn89wo4UdzumNC4EeeZruGbCad1qXMAmZJqk1kgPE9e4UvCc4qI1qnMswMh5t9I3CDSsARXHLlaUkDZfh_gnQvH4tzxqtDRz5r8SwoFCcXcaIqffm2Q4_YJPloo6PWY6E81PoBKbPnlLOpAG_XH0y5M_BLqo5OD9y8_YkFxDTovZPg3Wa0onqoVSVP9Ble-aA6UUqJlkekw';
  // edition Enterprise, all modules, all caps null
  private static final String TOKEN_FULL = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQUEiLCJlZGl0aW9uIjoiRW50ZXJwcmlzZSIsIm1vZHVsZXMiOnsiSG90ZWwiOnRydWUsIlByb3BlcnR5Ijp0cnVlLCJGaW5hbmNlIjp0cnVlLCJTdGFmZiI6dHJ1ZSwiQUkiOnRydWV9LCJjYXBzIjp7Im1heFJvb21zIjpudWxsLCJtYXhVbml0cyI6bnVsbCwibWF4UG9ydGFsVXNlcnMiOm51bGx9LCJ2YWxpZFVudGlsIjoiMjAyNy0wNi0zMCIsImdyYWNlRGF5cyI6MTAsImlzc3VlZEF0IjoiMjAyNy0wMS0wNSIsImtleUlkIjoidGVzdC1rZXktMSJ9.ITS1SJfNQHPeqoAGxOGTwkJkA3_-_YyCrUeKwWCoOJXuVdFg4Lpe4liQDoDU5ZMIPBzXzXaitWtiPFv7boGrWtcBft9MY1yc-W_asQ85VvgW0VDlqBbbvOwAaZayXrTEOfJ-lf-PZ_h4s177KQJM8J0V8saNN-YTc2l45KYhlIXEv_UrkidYFfl8CKFo2qYD8BK6kZ8hms829sDeDkCuurfeyGqOTBeBTRW7x0p9MTv6BJ579tOQJwSf6AnQ2pmCiNDxGoE5MgDiua_XOhQJvy70mgGrACP6jazjVMQoMb452zXnG_vVyqHdolWFpHoMcLRPfNHvTYWhGlYAskpFrw';
  // orgId in the 15-character form
  private static final String TOKEN_ORG15 = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVCIsImVkaXRpb24iOiJTdGFuZGFyZCIsIm1vZHVsZXMiOnsiSG90ZWwiOnRydWUsIlByb3BlcnR5Ijp0cnVlLCJGaW5hbmNlIjpmYWxzZSwiU3RhZmYiOmZhbHNlLCJBSSI6ZmFsc2V9LCJjYXBzIjp7Im1heFJvb21zIjozLCJtYXhVbml0cyI6bnVsbCwibWF4UG9ydGFsVXNlcnMiOjUwfSwidmFsaWRVbnRpbCI6IjIwMjctMDYtMzAiLCJncmFjZURheXMiOjEwLCJpc3N1ZWRBdCI6IjIwMjctMDEtMDUiLCJrZXlJZCI6InRlc3Qta2V5LTEifQ.PF8RRE_3CQBgodEUmgWoR2w0LG8q3WPg1B0jqagBJFKoVWxPqU21cYrd1VSBarE8vNYxWYoJttWshXH4QDNWvpXcWSs7uwon670qacwQe87D8AIMkZMDHOPBztA7SKSrw1ip9LdXmHmMiDiwa7OiNM1I4ZFx-Hz-sMFWqmnynyvyYUiA8eOmI-rLRaRJi4QsCpItf3dTOqH6diOJxRvPEmtU42_6--PdSopN_HPSBxrLmPpWkz2ZMuQtCHCSOHrszI0IkQ9V3PC3rsuyvuUQynU7urUc1PC5pVfH0sfIz1smYIvYRr4j9UVFmWmCwJLoWvnxt7k2L0f3LprJMq64Rw';

  private static final Date TODAY = Date.newInstance(2027, 3, 1);

  private static void managed(Date today, Date installDate, String token) {
    PMS_Entitlements.forceManaged = true;
    PMS_Entitlements.enforcementOverride = true;
    PMS_Entitlements.pilotDaysOverride = 90;
    PMS_Entitlements.defaultGraceOverride = 30;
    PMS_Entitlements.orgIdOverride = TEST_ORG;
    PMS_Entitlements.publicKeyOverride = TEST_PUBLIC_KEY;
    PMS_Entitlements.keyIdOverride = TEST_KEY_ID;
    PMS_Entitlements.todayOverride = today;
    PMS_Entitlements.installDateOverride = installDate;
    PMS_Entitlements.tokenOverride = token == null ? '' : token;
    PMS_Entitlements.sandboxOverride = false;
    PMS_Entitlements.reset();
  }

  private static void expired(String token) {
    managed(TODAY, TODAY.addDays(-200), token);
  }

  private static String expectError(String what, Integer adding) {
    try {
      PMS_Entitlements.assertCanCreate(what, adding);
    } catch (PMS_Entitlements.LicenceException e) {
      return e.getMessage();
    }
    return null;
  }

  @isTest
  static void devWhenEnforcementOff() {
    managed(TODAY, TODAY.addDays(-400), null);
    PMS_Entitlements.enforcementOverride = false;
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.DEV, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.isModuleEnabled('AI'));
    Assert.isNull(PMS_Entitlements.capFor('Room'));
    Assert.isNull(PMS_Entitlements.daysRemaining());
    Assert.isNull(expectError('Booking', 500));
    Assert.isNull(PMS_Entitlements.bannerText());
  }

  @isTest
  static void devWhenUnmanaged() {
    if (PMS_Entitlements.detectManaged()) {
      return; // namespaced org: unmanaged detection cannot be exercised here
    }
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.DEV, PMS_Entitlements.state());
  }

  @isTest
  static void managedDetectionMatchesTheOrg() {
    String name = PMS_License__c.SObjectType.getDescribe().getName();
    Boolean namespaced = name != 'PMS_License__c';
    Assert.areEqual(namespaced, PMS_Entitlements.detectManaged());
    if (!namespaced) {
      PMS_Entitlements.reset();
      Assert.areEqual(PMS_Entitlements.DEV, PMS_Entitlements.state());
    }
  }

  @isTest
  static void pilotIsFullAccessWithCountdown() {
    Date install = TODAY.addDays(-10);
    managed(TODAY, install, null);
    Assert.areEqual(PMS_Entitlements.PILOT, PMS_Entitlements.state());
    Assert.areEqual(80, PMS_Entitlements.daysRemaining());
    Assert.areEqual('Pilot', PMS_Entitlements.edition());
    Assert.isTrue(PMS_Entitlements.isModuleEnabled('Finance'));
    Assert.isNull(PMS_Entitlements.capFor('Room'));
    Assert.isNull(
      PMS_Entitlements.bannerText(),
      'No banner until 14 days before the end'
    );
    managed(TODAY.addDays(70), install, null);
    Assert.areEqual(10, PMS_Entitlements.daysRemaining());
    Assert.isTrue(PMS_Entitlements.bannerText().contains('10 days'));
  }

  @isTest
  static void pilotWithBlankInstallDateStartsToday() {
    managed(TODAY, null, null);
    Assert.areEqual(PMS_Entitlements.PILOT, PMS_Entitlements.state());
    Assert.areEqual(90, PMS_Entitlements.daysRemaining());
  }

  @isTest
  static void pilotEndsOnTheNinetiethDay() {
    Date install = TODAY.addDays(-89);
    managed(TODAY, install, null);
    Assert.areEqual(PMS_Entitlements.PILOT, PMS_Entitlements.state());
    Assert.areEqual(1, PMS_Entitlements.daysRemaining());
    managed(TODAY.addDays(1), install, null);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void expiredPilotWithoutKeyIsSuspended() {
    expired(null);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.areEqual(0, PMS_Entitlements.daysRemaining());
    Assert.isFalse(PMS_Entitlements.isModuleEnabled('Hotel'));
    Assert.isNotNull(expectError('Booking', 1));
    Assert.isNotNull(PMS_Entitlements.bannerText());
  }

  @isTest
  static void activeToken() {
    expired(TOKEN_OK);
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
    Assert.areEqual('Standard', PMS_Entitlements.edition());
    Assert.areEqual(
      TODAY.daysBetween(Date.newInstance(2027, 6, 30)),
      PMS_Entitlements.daysRemaining()
    );
    Assert.isTrue(PMS_Entitlements.isModuleEnabled('Hotel'));
    Assert.isTrue(PMS_Entitlements.isModuleEnabled('Property'));
    Assert.isFalse(PMS_Entitlements.isModuleEnabled('Finance'));
    Assert.isFalse(PMS_Entitlements.isModuleEnabled('AI'));
    Assert.areEqual(3, PMS_Entitlements.capFor('Room'));
    Assert.areEqual(3, PMS_Entitlements.capFor('maxRooms'));
    Assert.isNull(PMS_Entitlements.capFor('Unit'));
    Assert.areEqual(50, PMS_Entitlements.capFor('PortalUser'));
    Assert.isNull(PMS_Entitlements.bannerText());
    Assert.isNull(expectError('Booking', 1));
  }

  @isTest
  static void validKeyBeatsPilot() {
    managed(TODAY, TODAY.addDays(-5), TOKEN_OK);
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
    Assert.areEqual(3, PMS_Entitlements.capFor('Room'));
  }

  @isTest
  static void lastDayIsStillActive() {
    managed(Date.newInstance(2027, 6, 30), TODAY.addDays(-200), TOKEN_OK);
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
    Assert.areEqual(0, PMS_Entitlements.daysRemaining());
  }

  @isTest
  static void graceUsesTokenGraceDays() {
    managed(Date.newInstance(2027, 7, 5), TODAY.addDays(-400), TOKEN_OK);
    Assert.areEqual(PMS_Entitlements.GRACE, PMS_Entitlements.state());
    Assert.areEqual(5, PMS_Entitlements.daysRemaining());
    Assert.isTrue(PMS_Entitlements.bannerText().contains('Grace period'));
    Assert.isNull(expectError('Booking', 1), 'Grace is still fully usable');
    Assert.areEqual(3, PMS_Entitlements.capFor('Room'));
    managed(Date.newInstance(2027, 7, 10), TODAY.addDays(-400), TOKEN_OK);
    Assert.areEqual(
      PMS_Entitlements.GRACE,
      PMS_Entitlements.state(),
      'Last grace day'
    );
    managed(Date.newInstance(2027, 7, 11), TODAY.addDays(-400), TOKEN_OK);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void graceFallsBackToDefault() {
    managed(Date.newInstance(2027, 7, 30), TODAY.addDays(-400), TOKEN_NO_GRACE);
    Assert.areEqual(PMS_Entitlements.GRACE, PMS_Entitlements.state());
    managed(Date.newInstance(2027, 7, 31), TODAY.addDays(-400), TOKEN_NO_GRACE);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void expiredTokenInsidePilotKeepsPilot() {
    managed(
      Date.newInstance(2027, 7, 15),
      Date.newInstance(2027, 7, 1),
      TOKEN_OK
    );
    Assert.areEqual(PMS_Entitlements.PILOT, PMS_Entitlements.state());
  }

  @isTest
  static void tamperedPayloadIsRejected() {
    String tampered =
      'ey' +
      TOKEN_OK.substring(2, 20) +
      'X' +
      TOKEN_OK.substring(21);
    expired(tampered);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.lastError().contains('signature'));
  }

  @isTest
  static void wrongSignatureIsRejected() {
    Integer dot = TOKEN_OK.indexOf('.');
    String other = TOKEN_FULL.substring(TOKEN_FULL.indexOf('.'));
    expired(TOKEN_OK.substring(0, dot) + other);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.lastError().contains('signature'));
  }

  @isTest
  static void wrongOrgIsRejected() {
    expired(TOKEN_OTHER_ORG);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(
      PMS_Entitlements.lastError().contains('different Salesforce org')
    );
  }

  @isTest
  static void orgIdComparesFifteenAndEighteenCharForms() {
    expired(TOKEN_ORG15);
    Assert.areEqual(
      PMS_Entitlements.ACTIVE,
      PMS_Entitlements.state(),
      '15 in token, 18 in org'
    );
    expired(TOKEN_OK);
    PMS_Entitlements.orgIdOverride = TEST_ORG.substring(0, 15);
    PMS_Entitlements.reset();
    Assert.areEqual(
      PMS_Entitlements.ACTIVE,
      PMS_Entitlements.state(),
      '18 in token, 15 in org'
    );
  }

  @isTest
  static void wrongKeyIdIsRejected() {
    expired(TOKEN_BAD_KEY);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.lastError().contains('unrecognised key'));
    expired(TOKEN_OK);
    PMS_Entitlements.keyIdOverride = 'something-else';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void missingMalformedAndUnconfiguredKey() {
    for (
      String bad : new List<String>{
        '',
        '   ',
        'abc',
        'a.b.c',
        '.',
        'e30.AAAA'
      }
    ) {
      expired(bad);
      Assert.areEqual(
        PMS_Entitlements.SUSPENDED,
        PMS_Entitlements.state(),
        'Token: ' + bad
      );
    }
    expired(TOKEN_OK);
    PMS_Entitlements.publicKeyOverride = 'REPLACE_WITH_BASE64_X509_RSA_PUBLIC_KEY';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.lastError().contains('not configured'));
    PMS_Entitlements.publicKeyOverride = 'not base64 at all!';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void tokenWithWhitespaceIsAccepted() {
    expired(TOKEN_OK.substring(0, 100) + '\n' + TOKEN_OK.substring(100));
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
  }

  @isTest
  static void unlimitedCapsAndAllModules() {
    expired(TOKEN_FULL);
    Assert.areEqual('Enterprise', PMS_Entitlements.edition());
    Assert.isNull(PMS_Entitlements.capFor('Room'));
    Assert.isNull(PMS_Entitlements.remaining('Room'));
    Assert.isTrue(PMS_Entitlements.isModuleEnabled('AI'));
    Assert.isNull(expectError('Room', 100000));
  }

  @isTest
  static void roomCapCountsExistingRooms() {
    PMS_TestDataFactory.hotel(2);
    expired(TOKEN_OK);
    Assert.areEqual(1, PMS_Entitlements.remaining('Room'));
    Assert.isNull(expectError('Room', 1));
    String msg = expectError('Room', 2);
    Assert.isNotNull(msg);
    Assert.isTrue(msg.contains('3 rooms'), msg);
    Assert.isNull(expectError('Unit', 99), 'No unit cap in this token');
    Assert.isNotNull(
      // caller-supplied count for things Core cannot count (portal users)
      tryCreate('PortalUser', 1, 50)
    );
    Assert.isNull(tryCreate('PortalUser', 1, 49));
  }

  private static String tryCreate(
    String what,
    Integer adding,
    Integer existing
  ) {
    try {
      PMS_Entitlements.assertCanCreate(what, adding, existing);
    } catch (PMS_Entitlements.LicenceException e) {
      return e.getMessage();
    }
    return null;
  }

  @isTest
  static void roomInsertStopsAtTheCap() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(2);
    expired(TOKEN_OK);
    List<PMS_Space__c> more = new List<PMS_Space__c>();
    for (Integer i = 0; i < 3; i++) {
      more.add(
        new PMS_Space__c(
          Name = 'X' + i,
          RecordTypeId = PMS_TestDataFactory.rt(
            PMS_Space__c.SObjectType,
            'Room'
          ),
          Site__c = h.site.Id,
          Space_Type__c = h.doubleRoom.Id,
          Max_Occupancy__c = 2,
          Bookable__c = true,
          Operational_Status__c = 'Available'
        )
      );
    }
    Integer queriesBefore = Limits.getQueries();
    List<Database.SaveResult> results = Database.insert(more, false);
    Assert.isTrue(results[0].isSuccess(), 'Third room is within the cap');
    Assert.isFalse(results[1].isSuccess());
    Assert.isFalse(results[2].isSuccess());
    Assert.isTrue(results[1].getErrors()[0].getMessage().contains('3 rooms'));
    Assert.isTrue(
      Limits.getQueries() - queriesBefore < 15,
      'No query per record'
    );
  }

  @isTest
  static void suspendedLocksRoomInsertUpdateAndDelete() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    expired(null);
    PMS_Space__c extra = h.rooms[0].clone(false, true);
    extra.Name = 'Blocked';
    Database.SaveResult sr = Database.insert(extra, false);
    Assert.isFalse(sr.isSuccess());
    h.rooms[0].Operational_Status__c = 'Available';
    Assert.isFalse(
      Database.update(h.rooms[0], false).isSuccess(),
      'update locked'
    );
    Assert.isFalse(
      Database.delete(h.rooms[0], false).isSuccess(),
      'delete locked'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM PMS_Space__c WHERE Id = :h.rooms[0].Id]
    );
    // reads stay open
    Assert.areEqual(1, [SELECT COUNT() FROM PMS_Site__c]);
  }

  private static PMS_Booking__c booking(Id spaceId, Datetime start) {
    return new PMS_Booking__c(
      RecordTypeId = PMS_ModuleConfig.bookingRecordTypeId('Hotel'),
      Space__c = spaceId,
      Start__c = start,
      End__c = start.addDays(1),
      Status__c = 'Confirmed'
    );
  }

  @isTest
  static void suspendedLocksBookingInsertUpdateAndDelete() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Datetime start = Datetime.newInstance(2027, 3, 10, 15, 0, 0);
    PMS_Booking__c existing = booking(h.rooms[0].Id, start);
    insert existing; // dev context: allowed

    expired(null);
    Database.SaveResult blocked = Database.insert(
      booking(h.rooms[0].Id, start.addDays(5)),
      false
    );
    Assert.isFalse(blocked.isSuccess());
    Assert.isTrue(blocked.getErrors()[0].getMessage().contains('licence'));

    existing.Status__c = 'Cancelled';
    Database.SaveResult upd = Database.update(existing, false);
    Assert.isFalse(upd.isSuccess(), 'update locked');
    Assert.isTrue(upd.getErrors()[0].getMessage().contains('read-only'));
    Assert.isFalse(
      Database.delete(existing, false).isSuccess(),
      'delete locked'
    );
    Assert.areEqual(
      'Confirmed',
      [SELECT Status__c FROM PMS_Booking__c WHERE Id = :existing.Id].Status__c
    );
  }

  @isTest
  static void suspendedLocksTriggerlessAndSharedObjectsToo() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    List<PMS_Rate__c> rates = [SELECT Id FROM PMS_Rate__c LIMIT 1]; // generic lock trigger
    expired(null);
    h.site.Name = 'Renamed'; // PMS_AccessShare_Site trigger
    Assert.isFalse(Database.update(h.site, false).isSuccess());
    if (!rates.isEmpty()) {
      Assert.isFalse(Database.delete(rates, false)[0].isSuccess());
    }
    // the licence log and settings stay writable
    insert new PMS_Channel_Log__c(
      Direction__c = 'Outbound',
      Kind__c = 'Availability',
      Status__c = 'Warning',
      Site__c = h.site.Id
    );
  }

  @isTest
  static void suspendedLocksBudgetLineInspectionItemAndBookingParty() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Project__c project = new PMS_Project__c(Name = 'Locked project');
    insert project;
    PMS_Inspection__c inspection = new PMS_Inspection__c();
    insert inspection;
    PMS_Booking__c stay = booking(
      h.rooms[0].Id,
      Datetime.newInstance(2027, 3, 10, 15, 0, 0)
    );
    insert stay;
    // Control: all three inserts succeed while the licence is in pilot.
    managed(TODAY, TODAY.addDays(-10), null);
    PMS_Budget_Line__c line = new PMS_Budget_Line__c(Project__c = project.Id);
    PMS_Inspection_Item__c item = new PMS_Inspection_Item__c(
      Inspection__c = inspection.Id
    );
    PMS_Booking_Party__c party = new PMS_Booking_Party__c(Booking__c = stay.Id);
    insert new List<SObject>{ line, item, party };

    expired(null);
    List<SObject> blocked = new List<SObject>{
      new PMS_Budget_Line__c(Project__c = project.Id),
      new PMS_Inspection_Item__c(Inspection__c = inspection.Id),
      new PMS_Booking_Party__c(Booking__c = stay.Id)
    };
    for (SObject rec : blocked) {
      Database.SaveResult r = Database.insert(rec, false);
      Assert.isFalse(
        r.isSuccess(),
        'Insert must be locked: ' + rec.getSObjectType()
      );
      Assert.isTrue(
        r.getErrors()[0].getMessage().length() > 0,
        'Lock error message is set'
      );
    }
    Assert.isFalse(Database.update(line, false).isSuccess());
    Assert.isFalse(Database.delete(item, false).isSuccess());
    Assert.isFalse(Database.delete(party, false).isSuccess());
    // Nothing changed.
    Assert.areEqual(1, [SELECT COUNT() FROM PMS_Budget_Line__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM PMS_Inspection_Item__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM PMS_Booking_Party__c]);
  }

  @isTest
  static void lockDoesNotApplyInPilotGraceActiveOrSandbox() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    managed(TODAY, TODAY.addDays(-10), null); // pilot
    h.site.Name = 'Pilot edit';
    update h.site;
    expired(TOKEN_OK);
    h.site.Name = 'Active edit';
    update h.site;
    managed(Date.newInstance(2027, 7, 5), TODAY.addDays(-400), TOKEN_OK); // grace
    h.site.Name = 'Grace edit';
    update h.site;
    expired(null);
    PMS_Entitlements.sandboxOverride = true; // sandbox
    PMS_Entitlements.reset();
    h.site.Name = 'Sandbox edit';
    update h.site;
  }

  @isTest
  static void suspendedStillAcceptsInboundBookingChangesAndHonoursOwnerSwitch() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Datetime start = Datetime.newInstance(2027, 3, 10, 15, 0, 0);
    PMS_Booking__c existing = booking(h.rooms[0].Id, start);
    insert existing;
    expired(null);
    PMS_Entitlements.allowInbound = true;
    existing.Status__c = 'Cancelled'; // an OTA cancellation
    Assert.isTrue(Database.update(existing, false).isSuccess());
    PMS_Entitlements.allowInboundConfigOverride = false; // owner turns the exception off
    PMS_Entitlements.reset();
    Assert.isFalse(
      Database.insert(booking(h.rooms[0].Id, start.addDays(3)), false)
        .isSuccess()
    );
    PMS_Entitlements.allowInbound = false;
  }

  @isTest
  static void keyEntryStaysOpenWhenSuspendedUnlessOwnerSwitchesItOff() {
    saveSetup();
    Assert.isTrue(PMS_Entitlements.keyEntryAllowed());
    PMS_LicenceController.saveLicenceKey(TOKEN_OK);
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
    PMS_Entitlements.tokenOverride = ''; // ignore the stored key: back to an expired, unlicensed org
    PMS_Entitlements.allowKeyEntryOverride = false;
    PMS_Entitlements.reset();
    Assert.isFalse(PMS_Entitlements.keyEntryAllowed());
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_OK);
      Assert.fail('Owner switch is off');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage());
    }
  }

  @isTest
  static void jobsAreSkippedAndLoggedWhenSuspended() {
    expired(null);
    Test.startTest();
    new PMS_DailyJob().execute(null);
    Test.stopTest();
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'PMS_NightAuditBatch'
      ]
    );
    Assert.isTrue(
      PMS_License__c.getOrgDefaults().Last_Error__c.contains('PMS_DailyJob')
    );
    managed(TODAY, TODAY.addDays(-10), null);
    Assert.isFalse(PMS_Entitlements.jobsBlocked('X'), 'pilot runs jobs');
  }

  // Signed with a third throw-away key (KEY_C, made by scripts/pms-licence.js; key id KEY_C_ID).
  // Same entitlements as TOKEN_OK for org 00D5g000000TEST1AA. TOKEN_C_PLAIN has no extension;
  // TOKEN_C_EXT adds extensionUntil 2027-09-30, reason "Awaiting PO".
  private static final String KEY_C = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr8qZbFzEGn+O7kNF4dL8Rpo82N9wDFARFq8xYXSHt8Z9A96kQFcs9/evOpGvhdcTXZt41TFigNRDmqFd+wfYpR3T5+dU4nXsTZpxzn5v3fwGsJBgahiECXozbdzEUihd52Eul8usEc1NTKct33dz1Wy7aN1ainekJTPDwdgzOvdGAi3sNF8B+Z9Fgy+d9a414NOlPZVC5QXFFnFFSafl43eEbShiQUWDoBZQt6WYwdEKy2ibjP1aQunXMXzzcz2Bizz0jM3Yrsv3wN12AGeyXz05hkCcZs62+PD24bngYjHIKknEHMxV7JwKdxROpXazyQY+Umh0Y3KRAJu21ZNj/QIDAQAB';
  private static final String KEY_C_ID = 'pms-20261121-ccc1fd';
  private static final String TOKEN_C_PLAIN = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQSIsImVkaXRpb24iOiJTdGFuZGFyZCIsIm1vZHVsZXMiOnsiSG90ZWwiOnRydWUsIlByb3BlcnR5Ijp0cnVlLCJGaW5hbmNlIjpmYWxzZSwiU3RhZmYiOmZhbHNlLCJBSSI6ZmFsc2V9LCJjYXBzIjp7Im1heFJvb21zIjozLCJtYXhVbml0cyI6bnVsbCwibWF4UG9ydGFsVXNlcnMiOjUwfSwidmFsaWRVbnRpbCI6IjIwMjctMDYtMzAiLCJncmFjZURheXMiOjEwLCJpc3N1ZWRBdCI6IjIwMjctMDEtMDUiLCJrZXlJZCI6InBtcy0yMDI2MTEyMS1jY2MxZmQifQ.C5n0oW2_auwmCp0eLpsp7j_vtfvbyTg4E4LdKxFd4ol3lyz5acfBSNDZFHtvAgKw3W-WCYaOLPVw2EKxfL7i4kULFl2gEJ46ol8wMkiIsoICvT3I4kd5V5CE23GUnu6kjhsqV2MBvpzaOJnV5Siw_lKaYRUpMiEbOs8_IGtf8s1so27fXHf9FKAW37-saWBrGVxC0k6srzj5_UDuOM1aoLklIDt9ChisaOgX8SzywdE5UJV1uAGgOV71uuLnHKCQU1ZzR6Rrf6KMASMj-uIF6fKqVGy95tjulWAVjU7SAtlUZuagk4hugtT9p8r12jb86WIWnSRWbeZ45L7cK8mCpw';
  private static final String TOKEN_C_EXT = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQSIsImVkaXRpb24iOiJTdGFuZGFyZCIsIm1vZHVsZXMiOnsiSG90ZWwiOnRydWUsIlByb3BlcnR5Ijp0cnVlLCJGaW5hbmNlIjpmYWxzZSwiU3RhZmYiOmZhbHNlLCJBSSI6ZmFsc2V9LCJjYXBzIjp7Im1heFJvb21zIjozLCJtYXhVbml0cyI6bnVsbCwibWF4UG9ydGFsVXNlcnMiOjUwfSwidmFsaWRVbnRpbCI6IjIwMjctMDYtMzAiLCJncmFjZURheXMiOjEwLCJpc3N1ZWRBdCI6IjIwMjctMDItMDEiLCJleHRlbnNpb25VbnRpbCI6IjIwMjctMDktMzAiLCJleHRlbnNpb25SZWFzb24iOiJBd2FpdGluZyBQTyIsImtleUlkIjoicG1zLTIwMjYxMTIxLWNjYzFmZCJ9.C-_eFCxm1DK8NIQW2DWgofHqT_HG-uLwwqYKp-A3NF9LRrdKA5EC5oME5HdMXEUV9U71QdEOMUA9Rv3X2a1eNiUPdG68FIcDh8xkBAbxVIZ7rOdER2fZ3w6Z7-SvVWmWtlw0g7fzZQbqpFz60XyDaa9Yo710WSlVNFGe7eR5C92p0N8Jmc0g25jwlh4BX8-SyXi_hOUMNW5OPK3DHgdkUN59p2CrSD0LMAZYI2moOoO1VMjSN45qdM2pgGW7klsBs0ancRCqteeokQGusIYAfnIVtFgn5oOR7_z1l8y_oFoY4_ROYAPPChX6PaYf6Ens7jFDX6iibMKnobK_S853Iw';

  private static void keyC(Date today, String token) {
    managed(today, TODAY.addDays(-600), token);
    PMS_Entitlements.publicKeyOverride = KEY_C;
    PMS_Entitlements.keyIdOverride = KEY_C_ID;
    PMS_Entitlements.reset();
  }

  @isTest
  static void extensionUnlocksUntilItsDate() {
    keyC(Date.newInstance(2027, 9, 1), TOKEN_C_PLAIN);
    Assert.areEqual(
      PMS_Entitlements.SUSPENDED,
      PMS_Entitlements.state(),
      'no extension'
    );
    keyC(Date.newInstance(2027, 9, 1), TOKEN_C_EXT);
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
    Assert.areEqual(29, PMS_Entitlements.daysRemaining());
    Assert.areEqual(
      3,
      PMS_Entitlements.capFor('Room'),
      'keeps the licence entitlements'
    );
    Assert.isTrue(
      PMS_Entitlements.bannerText().startsWith('Temporary access until')
    );
    Assert.isNull(expectError('Booking', 1));
    keyC(Date.newInstance(2027, 9, 30), TOKEN_C_EXT);
    Assert.areEqual(
      PMS_Entitlements.ACTIVE,
      PMS_Entitlements.state(),
      'last day'
    );
    keyC(Date.newInstance(2027, 10, 1), TOKEN_C_EXT);
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void extensionKeyCanBePastedAfterGraceAndIsNotAReplay() {
    keyC(Date.newInstance(2027, 9, 1), null);
    PMS_Entitlements.tokenOverride = null;
    PMS_Entitlements.reset();
    PMS_LicenceController.manageOverride = true;
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    s.Token_Issued_At__c = Datetime.newInstanceGmt(2027, 1, 5); // the earlier plain key
    upsert s;
    PMS_LicenceController.Status st = PMS_LicenceController.saveLicenceKey(
      TOKEN_C_EXT
    );
    Assert.areEqual(PMS_Entitlements.ACTIVE, st.state);
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 2, 1),
      PMS_License__c.getOrgDefaults().Token_Issued_At__c
    );
  }

  @isTest
  static void bookingInsertAllowedWhenActive() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    expired(TOKEN_OK);
    insert booking(h.rooms[0].Id, Datetime.newInstance(2027, 3, 10, 15, 0, 0));
    Assert.areEqual(1, [SELECT COUNT() FROM PMS_Booking__c]);
  }

  @isTest
  static void bulkBookingInsertBlockedWithoutQueryPerRecord() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    expired(null);
    List<PMS_Booking__c> many = new List<PMS_Booking__c>();
    for (Integer i = 0; i < 200; i++) {
      many.add(
        booking(
          h.rooms[0].Id,
          Datetime.newInstance(2027, 3, 10, 15, 0, 0).addDays(i)
        )
      );
    }
    Integer queriesBefore = Limits.getQueries();
    List<Database.SaveResult> results = Database.insert(many, false);
    for (Database.SaveResult sr : results) {
      Assert.isFalse(sr.isSuccess());
    }
    Assert.isTrue(
      Limits.getQueries() - queriesBefore < 20,
      'Constant queries for 200 records'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM PMS_Booking__c]);
  }

  @isTest
  static void evaluationIsCachedPerTransaction() {
    expired(TOKEN_OK);
    PMS_Entitlements.state();
    PMS_Entitlements.tokenOverride = '';
    Assert.areEqual(
      PMS_Entitlements.ACTIVE,
      PMS_Entitlements.state(),
      'Cached until reset'
    );
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
  }

  @isTest
  static void installHandlerSetsDateOnFirstInstallOnly() {
    managed(Date.today(), null, null); // production-like: DEV records no install date
    Test.testInstall(new PMS_InstallHandler(), null);
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    Assert.areEqual(Date.today(), s.Install_Date__c);

    s.Install_Date__c = Date.newInstance(2020, 1, 1);
    upsert s;
    Test.testInstall(new PMS_InstallHandler(), new Version(1, 0));
    Assert.areEqual(
      Date.newInstance(2020, 1, 1),
      PMS_License__c.getOrgDefaults().Install_Date__c
    );
    Test.testInstall(new PMS_InstallHandler(), null);
    Assert.areEqual(
      Date.newInstance(2020, 1, 1),
      PMS_License__c.getOrgDefaults().Install_Date__c,
      'Never overwritten'
    );
  }

  @isTest
  static void installHandlerSwallowsFailures() {
    PMS_InstallHandler.failForTest = true;
    Test.testInstall(new PMS_InstallHandler(), null);
    Assert.isNull(
      PMS_License__c.getOrgDefaults().Install_Date__c,
      'Failure must not fail the install nor write a date'
    );
  }

  @isTest
  static void controllerStatusAndSave() {
    expired(null);
    PMS_Entitlements.tokenOverride = null; // read the stored key, as production does
    PMS_Entitlements.reset();
    PMS_LicenceController.manageOverride = true;
    PMS_LicenceController.Status st = PMS_LicenceController.getStatus();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, st.state);
    Assert.isNotNull(st.bannerText);
    Assert.isTrue(st.canManage);
    Assert.isFalse(st.modules.get('Hotel'));

    PMS_LicenceController.Status after = PMS_LicenceController.saveLicenceKey(
      ' ' + TOKEN_OK + '\n'
    );
    Assert.areEqual(PMS_Entitlements.ACTIVE, after.state);
    Assert.areEqual('Standard', after.edition);
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    Assert.areEqual(255, s.Token_1__c.length());
    Assert.areEqual(255, s.Token_2__c.length());
    Assert.areEqual(TOKEN_OK.length() - 510, s.Token_3__c.length());
    Assert.isNull(s.Token_4__c);
    Assert.isNotNull(s.Last_Checked__c);
    // the stored parts re-assemble into the same token
    PMS_Entitlements.tokenOverride = null;
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
  }

  @isTest
  static void controllerRejectsBadKeysAndUnauthorisedUsers() {
    expired(null);
    PMS_LicenceController.manageOverride = false;
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_OK);
      Assert.fail('Needs PMS_Manage_License');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('permission'));
    }
    PMS_LicenceController.manageOverride = true;
    for (
      String bad : new List<String>{
        TOKEN_OTHER_ORG,
        TOKEN_BAD_KEY,
        'garbage',
        ''
      }
    ) {
      try {
        PMS_LicenceController.saveLicenceKey(bad);
        Assert.fail('Should reject: ' + bad);
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_OK + 'AAAA'.repeat(100));
      Assert.fail('Too long');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('too long'));
    }
    managed(Date.newInstance(2027, 8, 1), TODAY.addDays(-400), null);
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_OK);
      Assert.fail('Expired beyond grace');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('expired'));
    }
    Assert.isNull(
      PMS_License__c.getOrgDefaults().Token_1__c,
      'Nothing stored on failure'
    );
  }

  // Signed with a second throw-away key (KEY_B, private key deleted): payload of TOKEN_OK without issuedAt.
  private static final String KEY_B = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvnqrvJ0hC23C2zs5VDYRD1KjPCNm/PR/GTx+v9Ky4pE19fXpqMenvNtq0VUJIA/k8JCzJXj5p/M3/14j3A34JwtNSPk48+HDb5syb/4EAlNtDwZlSvUGvbfF/X/SBP6KXx2VVvDxvKJwS8FK/vMDvjVOdHW4R2knlfYOKKz0Oxt9qUFXOhiwJd6NuawyLblmEarWTjTB/lOHRpbd5QvvPwPSvcExR/AvvL238NX6oKJXY5RHIDVPfbRtmGCpZTB2t5C3XUa0XbtbZ/dOnlLvDJq/PnXA+EcST+OJ4ElMXB25+pA1joENAZY/jZTMh/HJ86gECmIX8/RWxiVWkl2zVwIDAQAB';
  private static final String TOKEN_NO_ISSUED = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQUEiLCJlZGl0aW9uIjoiU3RhbmRhcmQiLCJtb2R1bGVzIjp7IkhvdGVsIjp0cnVlLCJQcm9wZXJ0eSI6dHJ1ZSwiRmluYW5jZSI6ZmFsc2UsIlN0YWZmIjpmYWxzZSwiQUkiOmZhbHNlfSwiY2FwcyI6eyJtYXhSb29tcyI6MywibWF4VW5pdHMiOm51bGwsIm1heFBvcnRhbFVzZXJzIjo1MH0sInZhbGlkVW50aWwiOiIyMDI3LTA2LTMwIiwiZ3JhY2VEYXlzIjoxMCwia2V5SWQiOiJ0ZXN0LWtleS0xIn0.ZZoDiGGO5Aq7XQ44hfUdSfi83zeDgje4A2uSZVYE5YYI8VUPHyOBzE9MrM7sxuypBISxGXL1zuaqZmgcLK__br3QzDLbZB9D8MYbdtgxmz86qY7xqq66KgazUoU9qhFP-4aH8ZB4kPM51M0Jn2ZK-0lHFPwUEp5t2kna_ORzn-0cusqTqOf7oYH0Mj1z3SGics-9jzowLPGbhvLiIifiA8v7Vbw8Rr65H245RfDt4QVDFI3QMYxKfEv5EZ38E6MZzCHoF6c27c8tyArKKn4ZoObRyNjjOl60L30imFCXiEHbtjH_Kap3Lb_DtMqsXuc_0lxTVQ2rQeHXAFqol9X4og';

  private static void saveSetup() {
    expired(null);
    PMS_Entitlements.tokenOverride = null;
    PMS_Entitlements.reset();
    PMS_LicenceController.manageOverride = true;
  }

  @isTest
  static void inboundBookingAcceptedWhenSuspendedOnlyWithFlag() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    expired(null);
    Datetime start = Datetime.newInstance(2027, 3, 10, 15, 0, 0);
    PMS_Entitlements.allowInbound = true;
    Database.SaveResult ok = Database.insert(
      booking(h.rooms[0].Id, start),
      false
    );
    PMS_Entitlements.allowInbound = false;
    Assert.isTrue(ok.isSuccess(), 'Inbound OTA booking must be accepted');
    Database.SaveResult blocked = Database.insert(
      booking(h.rooms[0].Id, start.addDays(5)),
      false
    );
    Assert.isFalse(blocked.isSuccess());
  }

  @isTest
  static void ariPushIsSkippedAndLoggedWhenSuspended() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    expired(null);
    PMS_ChannexAri.Payload p = new PMS_ChannexAri.Payload();
    p.availability.add(new Map<String, Object>{ 'x' => 1 });
    List<PMS_Channel_Log__c> logs = PMS_ChannexAri.push(h.site.Id, p); // no callout mock: would fail if it sent
    Assert.areEqual(1, logs.size());
    Assert.areEqual('Stop Sell', logs[0].Kind__c);
    Assert.areEqual(
      'Warning',
      logs[0].Status__c,
      'a skipped push is never a stop-sell-sent marker'
    );
    Assert.isTrue(logs[0].Message__c.contains('licence'));
  }

  @isTest
  static void blankInstallDateFallsBackToOldestRecord() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Test.setCreatedDate(h.site.Id, Datetime.now().addDays(-300));
    delete [SELECT Id FROM PMS_License__c]; // the factory inserts recorded today's install date
    managed(Date.today(), null, null);
    Assert.areEqual(
      PMS_Entitlements.SUSPENDED,
      PMS_Entitlements.state(),
      'Pilot is measured from the oldest record, not from today'
    );
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    s.Install_Date__c = null;
    upsert s;
    PMS_Entitlements.ensureInstallDate();
    Assert.areEqual(
      Date.today().addDays(-300),
      PMS_License__c.getOrgDefaults().Install_Date__c
    );
  }

  @isTest
  static void blankInstallDateOnEmptyOrgStartsToday() {
    managed(TODAY, null, null);
    Assert.areEqual(90, PMS_Entitlements.daysRemaining());
  }

  @isTest
  static void firstSpaceInsertRecordsInstallDate() {
    managed(Date.today(), null, null); // production-like: DEV records no install date
    PMS_TestDataFactory.hotel(1);
    Assert.isNotNull(PMS_License__c.getOrgDefaults().Install_Date__c);
    Assert.areEqual(PMS_Entitlements.PILOT, PMS_Entitlements.state());
  }

  @isTest
  static void recordTypeChangeIntoCappedTypeIsCapped() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(3);
    PMS_Space__c unit = h.rooms[0].clone(false, true);
    unit.Name = 'U1';
    unit.RecordTypeId = PMS_TestDataFactory.rt(
      PMS_Space__c.SObjectType,
      'Unit'
    );
    insert unit; // dev context: allowed
    expired(TOKEN_OK); // 3 rooms exist, cap is 3
    unit.RecordTypeId = PMS_TestDataFactory.rt(
      PMS_Space__c.SObjectType,
      'Room'
    );
    Database.SaveResult sr = Database.update(unit, false);
    Assert.isFalse(sr.isSuccess());
    Assert.isTrue(sr.getErrors()[0].getMessage().contains('3 rooms'));
    // edits that do not change the type are never blocked
    h.rooms[0].Operational_Status__c = 'Available';
    update h.rooms[0];
  }

  @isTest
  static void orgIdComparisonIsCaseSensitive() {
    expired(TOKEN_OK);
    PMS_Entitlements.orgIdOverride = '00D5g000000test1AAA';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(
      PMS_Entitlements.lastError().contains('different Salesforce org')
    );
  }

  @isTest
  static void keyWithoutIssuedAtIsRejected() {
    expired(TOKEN_NO_ISSUED);
    PMS_Entitlements.publicKeyOverride = KEY_B;
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.lastError().contains('issue date'));
  }

  @isTest
  static void olderKeyIsRejectedAndSameDateAccepted() {
    saveSetup();
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    s.Token_Issued_At__c = Datetime.newInstanceGmt(2027, 2, 1);
    upsert s;
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_OK); // issued 2027-01-05
      Assert.fail('Older key must be rejected');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('older'), e.getMessage());
    }
    Assert.isNull(PMS_License__c.getOrgDefaults().Token_1__c);
    s.Token_Issued_At__c = Datetime.newInstanceGmt(2027, 1, 5);
    upsert s;
    PMS_LicenceController.saveLicenceKey(TOKEN_OK); // equal: re-paste is fine
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5),
      PMS_License__c.getOrgDefaults().Token_Issued_At__c,
      'a plain-date issuedAt counts as the start of that day (UTC)'
    );
  }

  @isTest
  static void previousKeyStillAcceptedAfterRotation() {
    expired(TOKEN_OK); // signed with TEST_PUBLIC_KEY / test-key-1
    PMS_Entitlements.publicKeyOverride = KEY_B;
    PMS_Entitlements.keyIdOverride = 'test-key-2';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    PMS_Entitlements.previousPublicKeyOverride = TEST_PUBLIC_KEY;
    PMS_Entitlements.previousKeyIdOverride = TEST_KEY_ID;
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
    PMS_Entitlements.previousKeyIdOverride = 'wrong-id';
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.SUSPENDED, PMS_Entitlements.state());
    Assert.isTrue(PMS_Entitlements.lastError().contains('unrecognised key'));
  }

  @isTest
  static void sandboxIsUnlimitedWithNotLicensedBanner() {
    expired(null); // pilot over, no key: would be SUSPENDED in production
    PMS_Entitlements.sandboxOverride = true;
    PMS_Entitlements.reset();
    Assert.areEqual(PMS_Entitlements.DEV, PMS_Entitlements.state());
    Assert.areEqual('Sandbox', PMS_Entitlements.edition());
    Assert.isNull(PMS_Entitlements.capFor('Room'));
    Assert.isNull(expectError('Booking', 500));
    Assert.areEqual(
      'Sandbox - not licensed for production use',
      PMS_Entitlements.bannerText()
    );
  }

  @isTest
  static void sandboxFlagIsQueriedOnceAndOnlyWhenNeeded() {
    managed(TODAY, TODAY.addDays(-200), null);
    PMS_Entitlements.sandboxOverride = null;
    PMS_Entitlements.reset();
    Integer before = Limits.getQueries();
    PMS_Entitlements.state();
    PMS_Entitlements.reset();
    PMS_Entitlements.state();
    Assert.areEqual(1, Limits.getQueries() - before, 'One cached query');
    PMS_Entitlements.enforcementOverride = false;
    PMS_Entitlements.reset();
    before = Limits.getQueries();
    PMS_Entitlements.state();
    Assert.areEqual(0, Limits.getQueries() - before, 'No query in DEV');
  }

  @isTest
  static void devStateLicensingPathsRunNoQueriesOrDml() {
    PMS_Entitlements.enforcementOverride = false;
    PMS_Entitlements.sandboxOverride = null; // would query Organization if reached
    PMS_Entitlements.reset();
    Integer q = Limits.getQueries();
    Integer d = Limits.getDmlStatements();
    for (Integer i = 0; i < 3; i++) {
      PMS_Entitlements.ensureInstallDate();
      PMS_Entitlements.reset(); // a fresh trigger transaction each time
    }
    Assert.areEqual(PMS_Entitlements.DEV, PMS_Entitlements.state());
    Assert.isNull(PMS_Entitlements.remaining('Room'));
    Assert.isNull(PMS_Entitlements.remaining('Unit'));
    PMS_Entitlements.assertCanCreate('Booking', 200);
    Assert.isFalse(PMS_Entitlements.jobsBlocked('Test'));
    Assert.areEqual(0, Limits.getQueries() - q, 'DEV must not query');
    Assert.areEqual(0, Limits.getDmlStatements() - d, 'DEV must not DML');
  }

  @isTest
  static void devStateBookingInsertAddsNoLicensingQueries() {
    PMS_Entitlements.enforcementOverride = false;
    PMS_Entitlements.reset();
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    Datetime start = Datetime.newInstance(2027, 3, 10, 15, 0, 0);
    Test.startTest();
    insert booking(h.rooms[0].Id, start);
    Integer withFirst = Limits.getQueries();
    Integer dmlFirst = Limits.getDmlStatements();
    insert booking(h.rooms[0].Id, start.addDays(3));
    Integer second = Limits.getQueries() - withFirst;
    insert booking(h.rooms[0].Id, start.addDays(6));
    Integer third = Limits.getQueries() - withFirst - second;
    Test.stopTest();
    Assert.areEqual(
      second,
      third,
      'Each further insert costs the same: no per-insert licensing queries'
    );
    Assert.isNull(
      PMS_License__c.getOrgDefaults().Install_Date__c,
      'DEV records no install date (no DML)'
    );
    Assert.isTrue(dmlFirst >= 1);
  }

  @isTest
  static void forceStateHookPinsStateAndIsTestOnly() {
    PMS_Entitlements.forceStateForTest(PMS_Entitlements.SUSPENDED);
    Assert.isTrue(PMS_Entitlements.isLocked());
    PMS_Entitlements.forceStateForTest(null);
    Assert.isFalse(PMS_Entitlements.isLocked());
    try {
      PMS_Entitlements.forceStateForTest(PMS_Entitlements.ACTIVE);
      Assert.fail('ACTIVE cannot be forced');
    } catch (PMS_Entitlements.LicenceException e) {
      Assert.isTrue(e.getMessage().contains('Only DEV'));
    }
  }

  // ---------------------------------------------------------------- second review: datetime tokens, scoped inbound, undelete

  // Signed with a fourth throw-away key (KEY_D, private key deleted; made by scripts/pms-licence.js).
  // Same entitlements as TOKEN_OK for org 00D5g000000TEST1AA. issuedAt is an ISO 8601 datetime:
  // TOKEN_D_AM 2027-01-05T09:00:00Z; TOKEN_D_PM 2027-01-05T15:30:00Z with extensionUntil 2027-09-30, reason "Awaiting PO".
  private static final String KEY_D = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArlmT5N7M2JJucRWvilbfXoJUQ2HDFJICdi1iX6GDgB183uMZyBVRw1Qn0zQo4j8q5YHDV9qJcjduMnKowovlc7JjE15vGSzp+xew08MPy4gHrSs1Q/ZZkTtM67ro4ydWPx1bOI+jfixDBMgrLhIlPxifeXhROs74EuGXwz4G/pUirC/DMxrIywNor847w4cSjZvRajZmusMAg/5sXddjpUbDDxQuWk4pF6lwydWrsuZeDPZ8neoXqvKcxm+rR09sWIfsWeATvBXJRsC7YZyH437vzHZDkFMaqIL/BEiWXNokLS3krIEZA+C+vH+Amc7GO6UzdkehDdLLYk944T5mOwIDAQAB';
  private static final String KEY_D_ID = 'pms-20261121-92001c';
  private static final String TOKEN_D_AM = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQSIsImVkaXRpb24iOiJTdGFuZGFyZCIsIm1vZHVsZXMiOnsiSG90ZWwiOnRydWUsIlByb3BlcnR5Ijp0cnVlLCJGaW5hbmNlIjpmYWxzZSwiU3RhZmYiOmZhbHNlLCJBSSI6ZmFsc2V9LCJjYXBzIjp7Im1heFJvb21zIjozLCJtYXhVbml0cyI6bnVsbCwibWF4UG9ydGFsVXNlcnMiOjUwfSwidmFsaWRVbnRpbCI6IjIwMjctMDYtMzAiLCJncmFjZURheXMiOjEwLCJpc3N1ZWRBdCI6IjIwMjctMDEtMDVUMDk6MDA6MDBaIiwia2V5SWQiOiJwbXMtMjAyNjExMjEtOTIwMDFjIn0.VgFIk9Jt_m9Wx-dkS_gvteKTV9eawAbXEkplKmHyEjvKZG57u9fjsIAwUZGI_PEf_tAu2JylnLdnssrJmqiBsqODOPyECmAgawOqIvlbPlk3h-gGr6kTrIdjNRvSeJza-4qZNA6bKRjDv-gON0uF7lE3ZPjecopvQzGPhnC--cGVWF-asVFA-ULaEuH2kiBtpR0ksJMoxU4E4PYuA3DS8-jt3Mlk37TBkN9XGY7FnD5eR3QwDV5ybnleIWj6wEZ_ZzlTX0q2idi3yH3mgXcOQtAGlRtOZlUHtPMAZGkwn4bSZKMGVUcbgz7mn0mHmjQP6b5h6S6FgYJzjY63tpN51A';
  private static final String TOKEN_D_PM = 'eyJvcmdJZCI6IjAwRDVnMDAwMDAwVEVTVDFBQSIsImVkaXRpb24iOiJTdGFuZGFyZCIsIm1vZHVsZXMiOnsiSG90ZWwiOnRydWUsIlByb3BlcnR5Ijp0cnVlLCJGaW5hbmNlIjpmYWxzZSwiU3RhZmYiOmZhbHNlLCJBSSI6ZmFsc2V9LCJjYXBzIjp7Im1heFJvb21zIjozLCJtYXhVbml0cyI6bnVsbCwibWF4UG9ydGFsVXNlcnMiOjUwfSwidmFsaWRVbnRpbCI6IjIwMjctMDYtMzAiLCJncmFjZURheXMiOjEwLCJpc3N1ZWRBdCI6IjIwMjctMDEtMDVUMTU6MzA6MDBaIiwiZXh0ZW5zaW9uVW50aWwiOiIyMDI3LTA5LTMwIiwiZXh0ZW5zaW9uUmVhc29uIjoiQXdhaXRpbmcgUE8iLCJrZXlJZCI6InBtcy0yMDI2MTEyMS05MjAwMWMifQ.Bs5o71YF3V9c6-NO8BFGTILuR5j0Q8rmjWw9PfR0Q6wfybfeZ7ea1sZJSfpH82eNX9Nc1hEnHIA1VBABm0kHo3lTyJAGH0HtTfaBZDKZ2rqDqgj2JB17K7QqfaaCQav2Mk4XUZWJy4JZE4c059Yg3-BrXIiDyT_EbSueXv-XXc3ru3o_67Fjxzk7SaDqTpMSTQ_1lnMbAI_c5juBE0Cpamd0JrH_ZU6yfFhkh_qrsaCScgW_fzrdQpD9dyMXlJ_pXu42ldSEweCAG0wRnSJYZJOmBXsjbWc1Ir-x3cT5kNiWcf8iFvdOwdOoEde3i6votVti6905nFBH10XbZyHwbA';

  private static void keyD(Date today, String token) {
    managed(today, TODAY.addDays(-600), token);
    PMS_Entitlements.publicKeyOverride = KEY_D;
    PMS_Entitlements.keyIdOverride = KEY_D_ID;
    PMS_Entitlements.reset();
  }

  @isTest
  static void issuedAtAcceptsIsoDatetimeAndPlainDate() {
    keyD(Date.newInstance(2027, 3, 1), TOKEN_D_AM);
    PMS_Entitlements.TokenInfo info = PMS_Entitlements.inspect(TOKEN_D_AM);
    Assert.isTrue(info.valid, 'token valid: ' + info.error);
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5, 9, 0, 0),
      info.issuedAt
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5, 9, 0, 0),
      PMS_Entitlements.parseIssuedAt('2027-01-05T09:00:00Z')
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5, 9, 0, 0),
      PMS_Entitlements.parseIssuedAt('2027-01-05T09:00:00.000Z')
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5, 0, 0, 0),
      PMS_Entitlements.parseIssuedAt('2027-01-05'),
      'date-only keys stay valid: start of day'
    );
    expired(TOKEN_OK); // date-only issuedAt, signed with the old key
    Assert.areEqual(PMS_Entitlements.ACTIVE, PMS_Entitlements.state());
  }

  @isTest
  static void sameDayReplayIsDetectedWithDatetimeIssuedAt() {
    keyD(Date.newInstance(2027, 3, 1), null);
    PMS_Entitlements.tokenOverride = null;
    PMS_Entitlements.reset();
    PMS_LicenceController.manageOverride = true;
    PMS_LicenceController.saveLicenceKey(TOKEN_D_PM); // 15:30 installed
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5, 15, 30, 0),
      PMS_License__c.getOrgDefaults().Token_Issued_At__c
    );
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_D_AM); // same day, earlier
      Assert.fail('A key issued earlier the same day is a replay');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('older'), e.getMessage());
    }
    PMS_LicenceController.saveLicenceKey(TOKEN_D_PM); // re-paste of the same key is fine
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    s.Token_Issued_At__c = Datetime.newInstanceGmt(2027, 1, 5, 9, 0, 0);
    upsert s;
    PMS_LicenceController.saveLicenceKey(TOKEN_D_PM); // later the same day replaces the earlier one
    Assert.areEqual(
      Datetime.newInstanceGmt(2027, 1, 5, 15, 30, 0),
      PMS_License__c.getOrgDefaults().Token_Issued_At__c
    );
  }

  @isTest
  static void expiredKeyMessageNamesTheLastUsableDayNotTheValidUntil() {
    keyD(Date.newInstance(2027, 12, 1), null);
    PMS_Entitlements.tokenOverride = null;
    PMS_Entitlements.reset();
    PMS_LicenceController.manageOverride = true;
    try {
      PMS_LicenceController.saveLicenceKey(TOKEN_D_PM); // validUntil 06-30, extension to 09-30
      Assert.fail('Expired key must be rejected');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains(Date.newInstance(2027, 9, 30).format()),
        e.getMessage()
      );
      Assert.isFalse(
        e.getMessage().contains(Date.newInstance(2027, 6, 30).format()),
        e.getMessage()
      );
    }
  }

  @isTest
  static void beginInboundExemptsWritesOnlyInsideItsScope() {
    // beginInbound is the payment webhook scope, so it is exercised with payments (bookings also run a
    // separate licence cap check on insert that the scope does not cover).
    Account acc = new Account(Name = 'Inbound scope');
    insert acc;
    expired(null);
    PMS_Entitlements.beginInbound();
    PMS_Entitlements.beginInbound(); // nesting is counted
    PMS_Entitlements.endInbound();
    Database.SaveResult inScope = Database.insert(
      payment(acc.Id, 'in-scope'),
      false
    );
    Assert.isTrue(
      inScope.isSuccess(),
      'still inside the outer scope: ' + inScope.getErrors()
    );
    PMS_Entitlements.endInbound();
    PMS_Entitlements.endInbound(); // surplus end never goes negative
    Assert.isFalse(
      Database.insert(payment(acc.Id, 'after-1'), false).isSuccess(),
      'locked again after endInbound'
    );
    PMS_Entitlements.beginInbound();
    PMS_Entitlements.endInbound();
    Assert.isFalse(
      Database.insert(payment(acc.Id, 'after-2'), false).isSuccess()
    );
  }

  private static PMS_Payment__c payment(Id accountId, String ref) {
    return new PMS_Payment__c(
      Account__c = accountId,
      Amount__c = 10,
      Gateway_Reference__c = ref
    );
  }

  @isTest
  static void suspendedErrorIsAddedOncePerRecord() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    expired(null);
    Datetime start = Datetime.newInstance(2027, 3, 10, 15, 0, 0);
    List<Database.SaveResult> results = Database.insert(
      new List<PMS_Booking__c>{
        booking(h.rooms[0].Id, start),
        booking(h.rooms[0].Id, start.addDays(3))
      },
      false
    );
    for (Database.SaveResult sr : results) {
      Assert.isFalse(sr.isSuccess());
      Assert.areEqual(1, sr.getErrors().size(), 'no duplicate licence error');
    }
  }

  @isTest
  static void suspendedInvoiceInsertGetsExactlyOneLicenceError() {
    Account acc = new Account(Name = 'Invoice once');
    insert acc;
    expired(null);
    List<PMS_Invoice__c> rows = new List<PMS_Invoice__c>();
    for (Integer i = 0; i < 200; i++) {
      rows.add(new PMS_Invoice__c(Account__c = acc.Id));
    }
    List<Database.SaveResult> results = Database.insert(rows, false);
    Integer blocked = 0;
    for (Database.SaveResult sr : results) {
      if (!sr.isSuccess()) {
        blocked++;
        Assert.areEqual(1, sr.getErrors().size(), 'one licence error only');
      }
    }
    Assert.areEqual(200, blocked, 'every invoice is blocked while suspended');
  }

  @isTest
  static void suspendedBlocksUndeleteOfBookingsAndLockedObjects() {
    PMS_TestDataFactory.Hotel h = PMS_TestDataFactory.hotel(1);
    PMS_Booking__c existing = booking(
      h.rooms[0].Id,
      Datetime.newInstance(2027, 3, 10, 15, 0, 0)
    );
    insert existing;
    List<PMS_Rate__c> rates = [SELECT Id FROM PMS_Rate__c LIMIT 1]; // generic PMS_Lock_ trigger
    delete existing;
    if (!rates.isEmpty()) {
      delete rates;
    }
    expired(null);
    Database.UndeleteResult ur = Database.undelete(existing.Id, false);
    Assert.isFalse(ur.isSuccess(), 'booking undelete is locked');
    Assert.isTrue(
      ur.getErrors()[0].getMessage().contains('licence'),
      ur.getErrors()[0].getMessage()
    );
    if (!rates.isEmpty()) {
      Assert.isFalse(Database.undelete(rates, false)[0].isSuccess());
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM PMS_Booking__c WHERE Id = :existing.Id]
    );
    managed(TODAY, TODAY.addDays(-10), null); // pilot: undelete works again
    Assert.isTrue(Database.undelete(existing.Id, false).isSuccess());
  }

  private static void assertEmptyScope(Database.QueryLocator ql) {
    Assert.isTrue(
      ql.getQuery().toUpperCase().contains('ID = NULL'),
      'start() must return an empty scope while suspended: ' + ql.getQuery()
    );
  }

  @isTest
  static void suspendedBatchesReturnAnEmptyScopeAndDoNotChain() {
    expired(null);
    assertEmptyScope(new PMS_InvoiceBatch().start(null));
    Assert.isTrue(
      PMS_License__c.getOrgDefaults().Last_Error__c.contains('PMS_InvoiceBatch')
    );
    PMS_RecurringChargeBatch rent = new PMS_RecurringChargeBatch(
      Date.today(),
      true
    );
    assertEmptyScope(rent.start(null));
    Assert.isTrue(
      PMS_License__c.getOrgDefaults()
        .Last_Error__c.contains('PMS_RecurringChargeBatch')
    );
    PMS_AccessRecalcBatch recalc = new PMS_AccessRecalcBatch(
      new List<String>{ 'PMS_Site__c', 'PMS_Booking__c' },
      0
    );
    assertEmptyScope(recalc.start(null));
    Assert.isTrue(
      PMS_License__c.getOrgDefaults()
        .Last_Error__c.contains('PMS_AccessRecalcBatch')
    );
    // pilot again: the real queries are returned
    managed(TODAY, TODAY.addDays(-10), null);
    Assert.isFalse(
      new PMS_InvoiceBatch()
        .start(null)
        .getQuery()
        .toUpperCase()
        .contains('ID = NULL')
    );
    Assert.isTrue(
      new PMS_AccessRecalcBatch(new List<String>{ 'PMS_Site__c' }, 0)
        .start(null)
        .getQuery()
        .contains('PMS_Site__c')
    );
  }

  @isTest
  static void suspendedRolloutQueueableDoesNothing() {
    PMS_Access_Rollout__c row = new PMS_Access_Rollout__c(
      Name = 'PMS_Site__c',
      Target__c = 'Private',
      Step__c = PMS_AccessRollout.STEP_WAITING
    );
    insert row;
    expired(null);
    Test.startTest();
    new PMS_AccessRollout().execute(null); // would call the Metadata API (no mock set) if it ran
    Test.stopTest();
    Assert.isTrue(
      PMS_License__c.getOrgDefaults()
        .Last_Error__c.contains('PMS_AccessRollout')
    );
    Assert.areEqual(
      PMS_AccessRollout.STEP_WAITING,
      [SELECT Step__c FROM PMS_Access_Rollout__c WHERE Id = :row.Id].Step__c
    );
  }

  @isTest
  static void suspendedAccessSetupRefusesRecalculationSchedulingAndRollouts() {
    User me = new User(Id = UserInfo.getUserId());
    System.runAs(me) {
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'PMS_Access_Manager'
      ];
      if (
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE PermissionSetId = :ps.Id AND AssigneeId = :me.Id
        ] == 0
      ) {
        insert new PermissionSetAssignment(
          PermissionSetId = ps.Id,
          AssigneeId = me.Id
        );
      }
    }
    System.runAs(me) {
      expired(null);
      try {
        PMS_AccessConsoleController.recalculateNow();
        Assert.fail('recalculate must be refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('licence'), e.getMessage());
      }
      try {
        PMS_AccessConsoleController.scheduleNightly();
        Assert.fail('scheduling must be refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('licence'), e.getMessage());
      }
      try {
        PMS_AccessConsoleController.startRollout(
          new List<String>{ 'PMS_Site__c' },
          'apply',
          null
        );
        Assert.fail('sharing default changes must be refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('licence'), e.getMessage());
      }
      Assert.areEqual(0, [SELECT COUNT() FROM PMS_Access_Rollout__c]);
      // stopping a rollout is still allowed
      Assert.areEqual(0, PMS_AccessConsoleController.cancelRollout(null));
    }
  }
}
