/**
 * Licence and entitlement layer for PMS Core.
 *
 * States
 *  - DEV        unmanaged/dev context (no namespace) or Enforcement_Enabled__c off: everything on, no caps.
 *  - PILOT      within Pilot_Days of the install date: everything on, no caps.
 *  - ACTIVE     a valid signed licence key and today <= validUntil.
 *  - GRACE      valid key, validUntil < today <= validUntil + graceDays. Still fully usable; nag only.
 *  - SUSPENDED  no valid key and the pilot is over, or the key (plus grace) has expired. PMS is fully locked:
 *               every PMS trigger (guardWrites) rejects insert, update, delete and undelete, scheduled and batch
 *               jobs skip their run (jobsBlocked), outbound callouts and new online payments are refused, module
 *               features report disabled and caps are 0. Reads and exports stay open.
 *               Exemptions (they protect guests and money already in motion):
 *                - inbound OTA bookings (allowInbound, owner switch Allow_Inbound_When_Suspended__c), so every
 *                  Channex revision is saved and acknowledged and the channel never double sells;
 *                - confirmed payments and refunds reported by the payment provider (beginInbound/endInbound,
 *                  used only after webhook signature verification);
 *                - PMS Channel Log rows (diagnostics);
 *                - pasting a new licence key (owner switch Allow_Key_Entry_When_Suspended__c).
 *               On entering suspension the Channex ARI push sends one stop-sell per mapped room type, then pauses.
 *               Not locked: standard objects (Case, Account, Contact), PMS_Settings__c and PMS_License__c
 *               settings, and __Share rows. See docs/Licensing.md.
 * A valid, unexpired key wins over the pilot so a customer who pays early gets their caps and a clean banner.
 *
 * SANDBOX (reported as DEV, banner text only): Organization.IsSandbox. Unlimited, but flagged as not licensed for production.
 *
 * Token format: base64url(payloadJson) + '.' + base64url(signature)
 * Signature: RSA-SHA256 (PKCS#1 v1.5, 2048-bit) over the ASCII bytes of the first part (JWT style, so no
 * JSON re-serialisation issues). Public key: base64 DER X.509 SubjectPublicKeyInfo in PMS_Licensing__mdt.
 * Payload: orgId, edition, modules{Hotel,Property,Finance,Staff,AI}, caps{maxRooms,maxUnits,maxPortalUsers
 * (null = unlimited)}, validUntil (yyyy-MM-dd), graceDays, issuedAt (ISO 8601 datetime, e.g. 2027-01-05T09:30:00Z; a plain date is
 * accepted as the start of that day UTC), keyId.
 *
 * The evaluation is cached per transaction. Never queries in loops: one COUNT per capped object type per call.
 */
@NamespaceAccessible
public with sharing class PMS_Entitlements {
  @NamespaceAccessible
  public static final String DEV = 'DEV';
  @NamespaceAccessible
  public static final String PILOT = 'PILOT';
  @NamespaceAccessible
  public static final String ACTIVE = 'ACTIVE';
  @NamespaceAccessible
  public static final String GRACE = 'GRACE';
  @NamespaceAccessible
  public static final String SUSPENDED = 'SUSPENDED';

  @NamespaceAccessible
  public static final String MODULE_HOTEL = 'Hotel';
  @NamespaceAccessible
  public static final String MODULE_PROPERTY = 'Property';
  @NamespaceAccessible
  public static final String MODULE_FINANCE = 'Finance';
  @NamespaceAccessible
  public static final String MODULE_STAFF = 'Staff';
  @NamespaceAccessible
  public static final String MODULE_AI = 'AI';

  /** Thrown by assertCanCreate. The message is safe to show to users. */
  @NamespaceAccessible
  public class LicenceException extends Exception {
  }

  /** Parsed and verified licence token. */
  public class TokenInfo {
    public Boolean valid = false;
    public String error;
    public String orgId;
    public String edition;
    public String keyId;
    public Date validUntil;
    public Datetime issuedAt;
    public Date extensionUntil;
    public String extensionReason;
    public Integer graceDays;
    public Map<String, Boolean> modules = new Map<String, Boolean>();
    public Map<String, Integer> caps = new Map<String, Integer>();
  }

  private class Config {
    Boolean enforce = true;
    Integer pilotDays = 90;
    Integer graceDays = 30;
    String publicKey;
    String keyId;
    String previousPublicKey;
    String previousKeyId;
    Boolean allowInbound = true;
    Boolean allowKeyEntry = true;
  }

  private class Snapshot {
    String state;
    Integer daysRemaining;
    String edition;
    Date endDate;
    TokenInfo token;
    Boolean sandbox = false;
    Boolean extension = false;
  }

  private static final String ALGORITHM = 'RSA-SHA256';
  private static final Map<String, String> CAP_KEYS = new Map<String, String>{
    'Room' => 'maxRooms',
    'Unit' => 'maxUnits',
    'PortalUser' => 'maxPortalUsers'
  };
  private static final Map<String, String> CAP_LABELS = new Map<String, String>{
    'Room' => 'rooms',
    'Unit' => 'units',
    'PortalUser' => 'portal users'
  };

  private static Snapshot cached;
  private static Config cachedConfig;
  private static Boolean cachedSandbox;
  private static Boolean installDateChecked = false;
  private static Date cachedDurableDate;
  private static String forcedState; // set only through forceStateForTest

  /**
   * Core-only (deliberately not @NamespaceAccessible): set by the Channex inbound path so OTA bookings that
   * already exist on the channel are always accepted, even when the licence is suspended. Otherwise the
   * revision would never be acknowledged and the OTA would keep the room sold elsewhere (double booking).
   */
  public static Boolean allowInbound = false;

  private static Integer inboundDepth = 0;

  // Test hooks. Package-private to Core tests; they cannot leak into Experience.
  @TestVisible
  private static Boolean forceManaged = false;
  @TestVisible
  private static Boolean enforcementOverride;
  @TestVisible
  private static Integer pilotDaysOverride;
  @TestVisible
  private static Integer defaultGraceOverride;
  @TestVisible
  private static Date todayOverride;
  @TestVisible
  private static Date installDateOverride;
  @TestVisible
  private static String orgIdOverride;
  @TestVisible
  private static String publicKeyOverride;
  @TestVisible
  private static String keyIdOverride;
  @TestVisible
  private static String tokenOverride;
  @TestVisible
  private static String previousPublicKeyOverride;
  @TestVisible
  private static String previousKeyIdOverride;
  @TestVisible
  private static Boolean sandboxOverride;
  @TestVisible
  private static Boolean allowInboundConfigOverride;
  @TestVisible
  private static Boolean allowKeyEntryOverride;
  @TestVisible
  private static Date fallbackInstallOverride;

  // ------------------------------------------------------------------ public API

  @NamespaceAccessible
  public static String state() {
    return snapshot().state;
  }

  @NamespaceAccessible
  public static Boolean isModuleEnabled(String module) {
    Snapshot s = snapshot();
    if (s.state == DEV || s.state == PILOT) {
      return true;
    }
    if (s.state == SUSPENDED || s.token == null) {
      return false;
    }
    return s.token.modules.get(module) == true;
  }

  /** Cap for 'Room', 'Unit' or 'PortalUser' (or the raw key such as maxRooms). Null = unlimited. 0 when suspended. */
  @NamespaceAccessible
  public static Integer capFor(String what) {
    Snapshot s = snapshot();
    String key = capKey(what);
    if (s.state == SUSPENDED && key != null) {
      return 0;
    }
    if (s.state != ACTIVE && s.state != GRACE) {
      return null;
    }
    return key == null ? null : s.token.caps.get(key);
  }

  /** Days left in the current period (pilot, licence, or grace). Null in DEV, 0 when suspended. */
  @NamespaceAccessible
  public static Integer daysRemaining() {
    return snapshot().daysRemaining;
  }

  @NamespaceAccessible
  public static String edition() {
    return snapshot().edition;
  }

  /** How many more records of this kind may be created. Null = unlimited. */
  @NamespaceAccessible
  public static Integer remaining(String what) {
    Integer cap = capFor(what);
    if (cap == null) {
      return null;
    }
    return Math.max(0, cap - existingCount(what));
  }

  @NamespaceAccessible
  public static void assertCanCreate(String what, Integer adding) {
    assertCanCreate(what, adding, null);
  }

  /** existing may be passed when the caller already knows the current count (for example portal users). */
  @NamespaceAccessible
  public static void assertCanCreate(
    String what,
    Integer adding,
    Integer existing
  ) {
    Snapshot s = snapshot();
    if (s.state == SUSPENDED) {
      throw new LicenceException(suspendedMessage(s));
    }
    Integer cap = capFor(what);
    if (cap == null || adding == null || adding <= 0) {
      return;
    }
    Integer used = existing == null ? existingCount(what) : existing;
    if (used + adding > cap) {
      String label = CAP_LABELS.containsKey(what) ? CAP_LABELS.get(what) : what;
      throw new LicenceException(
        'Your PMS licence allows ' +
          cap +
          ' ' +
          label +
          ' and ' +
          used +
          ' are in use, so ' +
          adding +
          ' more cannot be added. Contact your PMS provider to upgrade.'
      );
    }
  }

  // ------------------------------------------------------------------ Core-internal API

  /** Customer-facing banner text, or null when nothing needs saying. */
  public static String bannerText() {
    Snapshot s = snapshot();
    if (s.sandbox) {
      return 'Sandbox - not licensed for production use';
    }
    if (s.extension) {
      return 'Temporary access until ' + s.endDate.format();
    }
    if (s.state == PILOT && s.daysRemaining != null && s.daysRemaining <= 14) {
      return 'Pilot access: ' +
        s.daysRemaining +
        (s.daysRemaining == 1 ? ' day' : ' days') +
        ' left. Enter a licence key before ' +
        s.endDate.format() +
        ' to keep creating bookings.';
    }
    if (s.state == GRACE) {
      return 'Your PMS licence has expired. Grace period: ' +
        s.daysRemaining +
        (s.daysRemaining == 1 ? ' day' : ' days') +
        ' left. Renew your licence key to avoid interruption.';
    }
    if (s.state == SUSPENDED) {
      return suspendedMessage(s);
    }
    return null;
  }

  /** Text for a record rejected because the cap (or the licence) is exhausted. */
  public static String limitMessage(String what) {
    Snapshot s = snapshot();
    if (s.state == SUSPENDED) {
      return suspendedMessage(s);
    }
    String label = CAP_LABELS.containsKey(what) ? CAP_LABELS.get(what) : what;
    return 'Your PMS licence allows ' +
      capFor(what) +
      ' ' +
      label +
      ' and the limit has been reached. Contact your PMS provider to upgrade.';
  }

  public static String endDateLabel() {
    Snapshot s = snapshot();
    return s.endDate == null ? null : s.endDate.format();
  }

  public static Map<String, Boolean> modules() {
    Map<String, Boolean> result = new Map<String, Boolean>();
    for (
      String m : new List<String>{
        MODULE_HOTEL,
        MODULE_PROPERTY,
        MODULE_FINANCE,
        MODULE_STAFF,
        MODULE_AI
      }
    ) {
      result.put(m, isModuleEnabled(m));
    }
    return result;
  }

  public static String lastError() {
    Snapshot s = snapshot();
    return s.token == null ? null : s.token.error;
  }

  /** Verifies a token against the configured key, org and key id. Never throws. */
  public static TokenInfo inspect(String token) {
    TokenInfo info = new TokenInfo();
    try {
      String clean = token == null ? '' : token.replaceAll('\\s+', '');
      if (String.isEmpty(clean)) {
        info.error = 'No licence key installed.';
        return info;
      }
      List<String> parts = clean.split('\\.');
      if (
        parts.size() != 2 ||
        String.isEmpty(parts[0]) ||
        String.isEmpty(parts[1])
      ) {
        info.error = 'The licence key is not in the expected format.';
        return info;
      }
      Config c = config();
      // Current key first, then the optional previous key so key rotation does not invalidate issued keys.
      List<String> keys = new List<String>();
      List<String> keyIds = new List<String>();
      String current = cleanKey(
        publicKeyOverride != null ? publicKeyOverride : c.publicKey
      );
      if (usableKey(current)) {
        keys.add(current);
        keyIds.add(keyIdOverride != null ? keyIdOverride : c.keyId);
      }
      String previous = cleanKey(
        previousPublicKeyOverride != null
          ? previousPublicKeyOverride
          : c.previousPublicKey
      );
      if (usableKey(previous)) {
        keys.add(previous);
        keyIds.add(
          previousKeyIdOverride != null
            ? previousKeyIdOverride
            : c.previousKeyId
        );
      }
      if (keys.isEmpty()) {
        info.error = 'The licence public key is not configured in this package.';
        return info;
      }
      Integer matched = -1;
      for (Integer i = 0; i < keys.size() && matched < 0; i++) {
        try {
          if (
            Crypto.verify(
              ALGORITHM,
              Blob.valueOf(parts[0]),
              fromBase64Url(parts[1]),
              EncodingUtil.base64Decode(keys[i])
            )
          ) {
            matched = i;
          }
        } catch (Exception e) {
          // not verifiable with this key: try the next one
        }
      }
      if (matched < 0) {
        info.error = 'The licence key signature is not valid.';
        return info;
      }
      Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(
        fromBase64Url(parts[0]).toString()
      );
      info.orgId = (String) p.get('orgId');
      info.edition = (String) p.get('edition');
      info.keyId = (String) p.get('keyId');
      String until = (String) p.get('validUntil');
      if (String.isBlank(until)) {
        info.error = 'The licence key has no expiry date.';
        return info;
      }
      info.validUntil = Date.valueOf(until);
      String issued = (String) p.get('issuedAt');
      if (String.isBlank(issued)) {
        info.error = 'The licence key has no issue date.';
        return info;
      }
      info.issuedAt = parseIssuedAt(issued);
      info.graceDays = intOrNull(p.get('graceDays'));
      String ext = (String) p.get('extensionUntil');
      info.extensionUntil = String.isBlank(ext) ? null : Date.valueOf(ext);
      info.extensionReason = (String) p.get('extensionReason');
      Object mods = p.get('modules');
      if (mods instanceof Map<String, Object>) {
        for (String m : ((Map<String, Object>) mods).keySet()) {
          info.modules.put(m, ((Map<String, Object>) mods).get(m) == true);
        }
      }
      Object caps = p.get('caps');
      if (caps instanceof Map<String, Object>) {
        for (String k : ((Map<String, Object>) caps).keySet()) {
          info.caps.put(k, intOrNull(((Map<String, Object>) caps).get(k)));
        }
      }
      String expectedKeyId = keyIds[matched];
      if (String.isBlank(info.keyId) || info.keyId != expectedKeyId) {
        info.error = 'The licence key was signed with an unrecognised key.';
        return info;
      }
      if (
        !sameOrg(
          info.orgId,
          orgIdOverride != null ? orgIdOverride : UserInfo.getOrganizationId()
        )
      ) {
        info.error = 'The licence key was issued for a different Salesforce org.';
        return info;
      }
      info.valid = true;
    } catch (Exception e) {
      info.valid = false;
      info.error = 'The licence key could not be read.';
    }
    return info;
  }

  /** Last day (inclusive) of the grace period for a verified token. */
  public static Date graceEnd(TokenInfo info) {
    Integer g = info.graceDays == null ? config().graceDays : info.graceDays;
    return info.validUntil.addDays(Math.max(0, g));
  }

  /** Last day the key lets the customer in: the later of grace end and any extension. */
  public static Date lastUsableDay(TokenInfo info) {
    Date d = graceEnd(info);
    return info.extensionUntil != null &&
      info.extensionUntil > d
      ? info.extensionUntil
      : d;
  }

  /** True while suspended: all PMS writes, jobs and outbound callouts are locked. Reads and exports stay open. */
  @NamespaceAccessible
  public static Boolean isLocked() {
    return state() == SUSPENDED;
  }

  /** Inbound OTA bookings are accepted while suspended (flag set by the Channex path, and the owner switch is on). */
  public static Boolean inboundAccepted() {
    return allowInbound && config().allowInbound;
  }

  /**
   * Scoped exemption for confirmed money already moved (payment provider webhooks). Call ONLY after the
   * webhook signature has been verified and always pair with endInbound() in a finally block. While active,
   * guardWrites() lets the writes through. Nesting is counted.
   */
  @NamespaceAccessible
  public static void beginInbound() {
    inboundDepth++;
  }

  /** Ends one beginInbound(). Safe to call more often than begin: never goes below zero. */
  @NamespaceAccessible
  public static void endInbound() {
    inboundDepth = Math.max(0, inboundDepth - 1);
  }

  /** The user-facing suspended message (Core use: Access Setup and other screens that refuse to act while locked). */
  public static String lockedMessage() {
    return suspendedMessage(snapshot());
  }

  /** Owner switch only: may inbound OTA bookings be saved while suspended? (Without the per-transaction flag.) */
  public static Boolean inboundEnabled() {
    return !isLocked() || config().allowInbound;
  }

  /** May a suspended customer still paste a licence key? Owner switch; always true when not suspended. */
  public static Boolean keyEntryAllowed() {
    return !isLocked() || config().allowKeyEntry;
  }

  /**
   * Call first from every PMS trigger. When suspended it puts an error on every record of the DML
   * (insert, update and delete) and returns true. No-op in DEV, sandbox, pilot, grace and active states.
   * Exempt: inbound OTA bookings while the owner switch allows them, writes inside beginInbound()/endInbound()
   * (verified payment webhooks) and channel logs. PMS_License__c is a custom setting and has no triggers.
   * A record already flagged by another PMS trigger in the same DML is not flagged again (hasErrors).
   */
  @NamespaceAccessible
  public static Boolean guardWrites() {
    if (!Trigger.isExecuting || !isLocked()) {
      return false;
    }
    List<SObject> records = Trigger.isDelete ? Trigger.old : Trigger.new;
    if (records == null || records.isEmpty()) {
      return false;
    }
    String api = records[0].getSObjectType().getDescribe().getName();
    if (
      inboundAccepted() ||
      inboundDepth > 0 ||
      api.endsWith('PMS_Channel_Log__c')
    ) {
      return false;
    }
    String message = suspendedMessage(snapshot());
    for (SObject r : records) {
      if (!r.hasErrors()) {
        r.addError(message);
      }
    }
    return true;
  }

  /** Scheduled entry points call this first. When suspended it records why and returns true (skip the run). */
  @NamespaceAccessible
  public static Boolean jobsBlocked(String jobName) {
    if (!isLocked()) {
      return false;
    }
    System.debug(
      LoggingLevel.WARN,
      'PMS job ' + jobName + ' skipped: licence suspended.'
    );
    try {
      PMS_License__c s = PMS_License__c.getOrgDefaults();
      s.Last_Error__c = ('Job ' +
        jobName +
        ' skipped ' +
        Datetime.now().format() +
        ': licence suspended.')
        .left(255);
      upsert s;
    } catch (Exception e) {
      // logging must never fail the job
    }
    return true;
  }

  public static Date today() {
    return todayOverride != null ? todayOverride : Date.today();
  }

  /**
   * Replay protection for a newly pasted key: null when acceptable, otherwise the reason. A key issued
   * before the stored one is rejected; the same issue date (re-paste) is fine.
   */
  public static String replayError(TokenInfo info) {
    Datetime stored = PMS_License__c.getOrgDefaults().Token_Issued_At__c;
    if (
      stored != null &&
      info != null &&
      info.issuedAt != null &&
      info.issuedAt < stored
    ) {
      return 'This licence key is older than the one already installed (issued ' +
        info.issuedAt.format() +
        ' versus ' +
        stored.format() +
        '). Use the latest key from your PMS provider.';
    }
    return null;
  }

  /** ISO 8601 datetime, or a plain yyyy-MM-dd date (start of that day, UTC) for keys issued before datetimes. */
  @TestVisible
  private static Datetime parseIssuedAt(String s) {
    String t = s.trim();
    if (t.length() <= 10) {
      return Datetime.newInstanceGmt(
        Date.valueOf(t),
        Time.newInstance(0, 0, 0, 0)
      );
    }
    return (Datetime) JSON.deserialize('"' + t + '"', Datetime.class);
  }

  /** Stores a token that has already been validated with inspect(). Splits it across Token_1..4__c. */
  public static void storeToken(String token) {
    String clean = token.replaceAll('\\s+', '');
    TokenInfo info = inspect(clean);
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    for (Integer i = 0; i < 4; i++) {
      Integer offset = i * 255;
      s.put(
        'Token_' + (i + 1) + '__c',
        offset < clean.length()
          ? clean.substring(offset, Math.min(offset + 255, clean.length()))
          : null
      );
    }
    s.Last_Checked__c = Datetime.now();
    s.Last_Error__c = null;
    if (info.valid && info.issuedAt != null) {
      s.Token_Issued_At__c = info.issuedAt;
    }
    if (s.Install_Date__c == null) {
      s.Install_Date__c = durableInstallDate();
    }
    upsert s;
    reset();
  }

  /** Sets the install date once. Never overwrites, so upgrades do not restart the pilot. */
  public static void ensureInstallDate() {
    if (installDateChecked) {
      return; // once per transaction: triggers call this on every insert
    }
    if (snapshot().state == DEV) {
      return; // unmanaged, enforcement off or sandbox: no pilot clock, so no queries and no DML
    }
    installDateChecked = true;
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    if (s.Install_Date__c == null) {
      s.Install_Date__c = durableInstallDate();
      upsert s;
      reset();
    }
    installDateChecked = true; // reset() clears the flag; the date is now recorded, so stay a no-op
  }

  /**
   * Best available "first used" date when none was recorded: the oldest Site or Space (system mode, one
   * query per object, only called when the install date is blank). Falls back to today on an empty org.
   */
  private static Date durableInstallDate() {
    if (fallbackInstallOverride != null) {
      return fallbackInstallOverride;
    }
    if (cachedDurableDate != null) {
      return cachedDurableDate; // snapshot() and ensureInstallDate() both ask: query once per transaction
    }
    Date result = today();
    try {
      for (PMS_Site__c r : [
        SELECT CreatedDate
        FROM PMS_Site__c
        WITH SYSTEM_MODE
        ORDER BY CreatedDate ASC
        LIMIT 1
      ]) {
        result = r.CreatedDate.date() < result ? r.CreatedDate.date() : result;
      }
      for (PMS_Space__c r : [
        SELECT CreatedDate
        FROM PMS_Space__c
        WITH SYSTEM_MODE
        ORDER BY CreatedDate ASC
        LIMIT 1
      ]) {
        result = r.CreatedDate.date() < result ? r.CreatedDate.date() : result;
      }
    } catch (Exception e) {
      // keep today
    }
    cachedDurableDate = result;
    return result;
  }

  /**
   * Test hook for Experience (and other packages') tests: pins the licence state without a signed token.
   * Throws outside tests. Pass null to clear.
   */
  @NamespaceAccessible
  public static void forceStateForTest(String state) {
    if (!Test.isRunningTest()) {
      throw new LicenceException(
        'forceStateForTest is only available in tests.'
      );
    }
    if (state != null && state != DEV && state != PILOT && state != SUSPENDED) {
      throw new LicenceException(
        'Only DEV, PILOT and SUSPENDED can be forced (ACTIVE and GRACE need a token).'
      );
    }
    forcedState = state;
    cached = null;
  }

  /** Clears the per-transaction cache. */
  public static void reset() {
    cached = null;
    cachedConfig = null;
    cachedDurableDate = null;
    // cachedSandbox is kept: Organization.IsSandbox cannot change inside a transaction (saves a query per reset).
    installDateChecked = false;
  }

  /** Test hook: clears the scoped payment exemption. */
  @TestVisible
  private static void resetInbound() {
    inboundDepth = 0;
  }

  // ------------------------------------------------------------------ internals

  private static Snapshot snapshot() {
    if (cached == null) {
      cached = compute();
    }
    return cached;
  }

  private static Snapshot compute() {
    Snapshot s = new Snapshot();
    if (forcedState != null && Test.isRunningTest()) {
      s.state = forcedState;
      s.edition = forcedState == DEV ? 'Development' : forcedState;
      s.daysRemaining = forcedState == SUSPENDED ? 0 : null;
      return s;
    }
    Config c = config();
    if (!detectManaged() || !c.enforce) {
      s.state = DEV;
      s.edition = 'Development';
      return s;
    }
    if (isSandbox()) {
      s.state = DEV;
      s.edition = 'Sandbox';
      s.sandbox = true;
      return s;
    }
    Date today = today();
    s.token = inspect(storedToken());
    if (s.token.valid) {
      s.edition = s.token.edition;
      if (s.token.extensionUntil != null && today <= s.token.extensionUntil) {
        // Owner-issued temporary unlock: wins over expiry and grace.
        s.state = ACTIVE;
        s.extension = true;
        s.endDate = s.token.extensionUntil;
        s.daysRemaining = today.daysBetween(s.token.extensionUntil);
        return s;
      }
      if (today <= s.token.validUntil) {
        s.state = ACTIVE;
        s.endDate = s.token.validUntil;
        s.daysRemaining = today.daysBetween(s.token.validUntil);
        return s;
      }
    }
    Date installDate = installDateOverride;
    if (installDate == null) {
      installDate = PMS_License__c.getOrgDefaults().Install_Date__c;
    }
    if (installDate == null) {
      // Blank (evaluation must not DML): use the oldest Site/Space so the pilot cannot restart forever.
      // The install handler, daily job and insert triggers record the date.
      installDate = durableInstallDate();
    }
    Date pilotEnd = installDate.addDays(c.pilotDays);
    if (today < pilotEnd) {
      s.state = PILOT;
      s.edition = 'Pilot';
      s.endDate = pilotEnd;
      s.daysRemaining = today.daysBetween(pilotEnd);
      return s;
    }
    if (s.token.valid) {
      Date graceEnd = graceEnd(s.token);
      if (today <= graceEnd) {
        s.state = GRACE;
        s.endDate = graceEnd;
        s.daysRemaining = today.daysBetween(graceEnd);
        return s;
      }
    }
    s.state = SUSPENDED;
    s.daysRemaining = 0;
    return s;
  }

  private static Config config() {
    if (cachedConfig != null) {
      return cachedConfig;
    }
    Config c = new Config();
    PMS_Licensing__mdt m = PMS_Licensing__mdt.getInstance('Default');
    if (m != null) {
      c.enforce = m.Enforcement_Enabled__c == true;
      c.pilotDays = m.Pilot_Days__c == null ? 90 : m.Pilot_Days__c.intValue();
      c.graceDays = m.Default_Grace_Days__c == null
        ? 30
        : m.Default_Grace_Days__c.intValue();
      c.publicKey = m.Public_Key__c;
      c.keyId = m.Key_Id__c;
      c.previousPublicKey = m.Previous_Public_Key__c;
      c.previousKeyId = m.Previous_Key_Id__c;
      c.allowInbound = m.Allow_Inbound_When_Suspended__c != false;
      c.allowKeyEntry = m.Allow_Key_Entry_When_Suspended__c != false;
    }
    if (enforcementOverride != null) {
      c.enforce = enforcementOverride;
    }
    if (allowInboundConfigOverride != null) {
      c.allowInbound = allowInboundConfigOverride;
    }
    if (allowKeyEntryOverride != null) {
      c.allowKeyEntry = allowKeyEntryOverride;
    }
    if (pilotDaysOverride != null) {
      c.pilotDays = pilotDaysOverride;
    }
    if (defaultGraceOverride != null) {
      c.graceDays = defaultGraceOverride;
    }
    cachedConfig = c;
    return c;
  }

  /** True when running from an installed (namespaced) package. Namespace prefix on the object API name is the reliable signal. */
  @TestVisible
  private static Boolean detectManaged() {
    if (forceManaged) {
      return true;
    }
    String name = PMS_License__c.SObjectType.getDescribe().getName();
    return name.indexOf('PMS_License__c') > 0 ||
      PMS_Entitlements.class.getName().contains('.');
  }

  private static Boolean isSandbox() {
    if (sandboxOverride != null) {
      return sandboxOverride;
    }
    if (cachedSandbox == null) {
      cachedSandbox = [
        SELECT IsSandbox
        FROM Organization
        WITH SYSTEM_MODE
        LIMIT 1
      ]
      .IsSandbox;
    }
    return cachedSandbox;
  }

  private static Boolean usableKey(String k) {
    return !String.isBlank(k) && !k.startsWith('REPLACE');
  }

  private static String storedToken() {
    if (tokenOverride != null) {
      return tokenOverride;
    }
    PMS_License__c s = PMS_License__c.getOrgDefaults();
    String t = '';
    for (Integer i = 1; i <= 4; i++) {
      String part = (String) s.get('Token_' + i + '__c');
      t += part == null ? '' : part;
    }
    return t;
  }

  private static String suspendedMessage(Snapshot s) {
    String reason = s.token != null &&
      s.token.error != null &&
      !s.token.valid
      ? ' (' + s.token.error + ')'
      : '';
    return 'Your PMS licence is not active' +
      reason +
      '. Account suspended: PMS is read-only until a valid licence key is entered. ' +
      'You can still view and export your data.';
  }

  private static String capKey(String what) {
    if (what == null) {
      return null;
    }
    if (CAP_KEYS.containsKey(what)) {
      return CAP_KEYS.get(what);
    }
    return CAP_KEYS.values().contains(what) ? what : null;
  }

  /** One COUNT, only called when a cap exists. Not cached: earlier DML in the transaction changes it. System mode on purpose: the cap is org-wide. */
  private static Integer existingCount(String what) {
    if (what != 'Room' && what != 'Unit') {
      return 0;
    }
    Id rt = PMS_ModuleConfig.recordTypeId(PMS_Space__c.SObjectType, what);
    return rt == null
      ? 0
      : [
          SELECT COUNT()
          FROM PMS_Space__c
          WHERE RecordTypeId = :rt
          WITH SYSTEM_MODE
        ];
  }

  private static Boolean sameOrg(String a, String b) {
    if (
      String.isBlank(a) ||
      String.isBlank(b) ||
      a.length() < 15 ||
      b.length() < 15
    ) {
      return false;
    }
    // 15-char ids are case sensitive; the 18-char form only appends a checksum.
    return a.substring(0, 15).equals(b.substring(0, 15));
  }

  private static Integer intOrNull(Object v) {
    return v == null ? null : Decimal.valueOf(String.valueOf(v)).intValue();
  }

  private static String cleanKey(String k) {
    if (k == null) {
      return null;
    }
    return k.replaceAll('-----[A-Z ]+-----', '').replaceAll('\\s+', '');
  }

  private static Blob fromBase64Url(String s) {
    String b = s.replace('-', '+').replace('_', '/');
    while (Math.mod(b.length(), 4) != 0) {
      b += '=';
    }
    return EncodingUtil.base64Decode(b);
  }
}
