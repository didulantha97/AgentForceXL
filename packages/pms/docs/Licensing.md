# Licensing

PMS Core enforces a licence with our own signed key. There is no LMA/FMA because we are not in the
Salesforce Partner Program. All logic lives in `PMS_Entitlements` (Core); the UI is `pmsLicenceBanner`.

## How access works

| State       | When                                                                  | Effect                                                                           |
| ----------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `DEV`       | Unmanaged code (no namespace), or `Enforcement_Enabled__c` is off     | Everything on, no caps                                                           |
| `PILOT`     | Less than `Pilot_Days__c` (90) after the install date                 | Everything on, no caps, banner from 14 days before the end                       |
| `ACTIVE`    | Valid key and today <= `validUntil`                                   | Modules and caps from the key                                                    |
| `GRACE`     | Valid key, `validUntil` < today <= `validUntil + graceDays`           | Same as ACTIVE, with a banner                                                    |
| `SUSPENDED` | No valid key and the pilot is over, or the key plus grace has expired | Full lock: PMS is read-only (see below)                                          |
| Sandbox     | `Organization.IsSandbox` (managed, enforcement on)                    | Reported as `DEV`: unlimited, banner "Sandbox - not licensed for production use" |

A valid, unexpired key wins over the pilot, so a customer who pays early gets their caps straight away.
An owner-issued **extension** (below) makes the state `ACTIVE` with the banner "Temporary access until <date>".
Managed detection uses the namespace prefix of the `PMS_License__c` API name (class name is a fallback), so
an unmanaged scratch org is always `DEV`.

### Full lock when suspended

Owner policy: when suspended **everything is locked, except what protects guests and money already in motion**.

- Insert, update, delete **and undelete** are blocked on every PMS object that supports triggers. `PMS_Entitlements.guardWrites()`
  is the first call of every Core trigger (`PMS_AccessShare_*`, Booking, Space, Charge, Payment, access teams, work
  orders, vendor bills/quotes, and `PMS_Lock_*` triggers for the rest) and of the Experience triggers. When several
  triggers fire for one DML, a record already flagged is not flagged again (`SObject.hasErrors()`).
- Scheduled jobs, batches and queueables (`PMS_DailyJob`, nightly access, `PMS_AccessRecalcBatch`,
  `PMS_AccessRollout`, `PMS_RecurringChargeBatch`, `PMS_InvoiceBatch`, pricing, owner statements, rent adjustment,
  dunning, `PMS_GuaranteeJob`, `PMS_GuaranteeActionJob`, check-in invitations, web booking cleanup) skip their run
  (batches return an empty scope and do not chain) and write the reason to `PMS_License__c.Last_Error__c`.
- Access Setup refuses recalculation, nightly scheduling and sharing default changes (rollouts); stopping a
  rollout stays possible.
- Outbound callouts stop. New online payments are refused (`PMS_StripeCheckout.createSession`, the single funnel for
  staff pay links, the portal, public booking and the Core pay link service: "Online payments are temporarily
  unavailable."). Channex ARI follows the stop-sell rule below.
- Reads and data export stay available. `pmsLicenceBanner` shows the read-only "Account suspended" banner.

### Stop-sell on suspension (Channex)

Leaving the last known availability on the OTAs would keep selling rooms that PMS can no longer manage. So the first
`PMS_ChannexSync` PUSH after the lock sends **one** stop-sell per connected site: availability `0` and
`stop_sell: true` for every mapped room type / rate plan over the push horizon (two callouts per site, built with two
queries). Success is recorded as a `PMS_Channel_Log__c` row with Kind `Stop Sell` and Status `Success`. That log is the
marker: while it is the newest Availability/Rates/Stop Sell log of the site, nothing more is pushed and no log is
written, so it is not repeated every 15 minutes. A failed or partly rejected stop-sell is logged as Error/Warning and
retried on the next run. Site timestamps (`Channex_Last_Push__c`) are not touched while locked. When the licence is
active again the normal push runs, writes newer Availability/Rates logs (which ends the marker) and resyncs the full
horizon, so rooms reopen without any manual step. Inbound OTA bookings keep being accepted throughout.

### What is NOT locked

- Standard objects (`Case`, `Account`, `Contact`, `User`): they are not PMS data and have no licence guard.
  (`PMS_CaseTrigger` and `PMS_UserTrigger` are Experience helpers on standard objects.)
- Custom settings `PMS_Settings__c`, `PMS_License__c` and `PMS_Access_Rollout__c`: settings cannot have triggers,
  and the licence key itself must stay writable.
- `__Share` rows: managed by the platform and by the access engine; they grant nothing a locked user could use to write.
- `PMS_Channel_Log__c` (diagnostics, needed for the stop-sell marker and the inbound audit trail).

Two safety exceptions, both switchable by the owner in `PMS_Licensing__mdt` (default on):

| Switch                              | Effect while suspended                                                                                                                                                                                                 |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Allow_Inbound_When_Suspended__c`   | Inbound Channex/OTA bookings (new, modified, cancelled) are still accepted and acknowledged, so the OTA never double sells. Outbound ARI pushes always stop, so no new sales are made. Turn off to refuse inbound too. |
| `Allow_Key_Entry_When_Suspended__c` | A customer can still paste a licence key (`PMS_LicenceController.saveLicenceKey`, `PMS_License__c`) to unlock.                                                                                                         |

Channex inbound sets the Core-only flag `PMS_Entitlements.allowInbound` (not `@NamespaceAccessible`). `PMS_ChannexBookings`
sets it around each revision, and `PMS_ChannexSync.Runner` sets it (try/finally) around the whole PULL and ACK stages
so the bookkeeping DML (`Channex_Last_Pull__c`, logs) is not blocked and the queueable does not roll back unacknowledged
revisions. If the owner switch is off the PULL stage is skipped and the chain goes straight to the stop-sell.

A third exception is not switchable: **confirmed payments and refunds** reported by the payment provider are still
recorded, because the money has already moved. `PMS_StripeWebhook` and `PMS_PaymentWebhook` wrap only their
post-signature-verification path in `PMS_Entitlements.beginInbound()` / `endInbound()` (`@NamespaceAccessible`,
counted, always reset in `finally`). `allowInbound` itself stays Core-only. Unsigned calls are rejected before the scope opens.

### Sandboxes

In a sandbox the state is `DEV` (no caps, nothing locked) and the banner reads "Sandbox - not licensed for production
use". One cached `Organization` query, only when enforcement is on in a managed install.

### Replay protection and key rotation

- `issuedAt` is required and is an ISO 8601 UTC datetime (`2027-01-05T09:30:00Z`). A plain `yyyy-MM-dd` from older keys
  is still accepted and counts as the start of that day (UTC). The accepted key's `issuedAt` is stored in
  `PMS_License__c.Token_Issued_At__c` (DateTime); a pasted key with an older `issuedAt` is rejected, the same instant
  (re-paste) is accepted. Two keys issued on the same day (for example an extension) are therefore ordered correctly.
- `Previous_Public_Key__c` / `Previous_Key_Id__c` in `PMS_Licensing__mdt` keep the previous key valid next to the
  current one, so a rotation does not invalidate issued keys. Clear them when the old keys have expired.
- Org id comparison is case sensitive on the first 15 characters.

### Install date

When `Install_Date__c` is blank, the pilot is measured from the oldest `PMS_Site__c`/`PMS_Space__c` (system mode, only
when blank), else today. `ensureInstallDate()` also runs from the Space and Booking insert triggers (guarded).

The install date is stored in `PMS_License__c.Install_Date__c` by `PMS_InstallHandler` (post-install script,
registered in `sfdx-project.json`). It is only written when blank, so upgrades never restart the pilot.
`PMS_DailyJob` repeats this as a safety net.

## Algorithm and token format

Signature: **RSA-SHA256** (PKCS#1 v1.5, 2048-bit key). Apex `Crypto.verify` supports it with a plain
X.509 public key; ECDSA signature encoding in Apex is less well documented, so RSA is the safe choice.

```
token = base64url(payloadJson) + "." + base64url(signature)
signature = RSA-SHA256 over the ASCII bytes of the first part (the base64url payload string)
```

Payload (keep it compact: the whole token must be at most 1020 characters, it is stored in four 255-character fields):

```json
{
  "orgId": "00D...",
  "edition": "Standard",
  "modules": {
    "Hotel": true,
    "Property": true,
    "Finance": false,
    "Staff": false,
    "AI": false
  },
  "caps": { "maxRooms": 40, "maxUnits": null, "maxPortalUsers": 100 },
  "validUntil": "2027-06-30",
  "graceDays": 14,
  "issuedAt": "2027-01-05T09:30:00Z",
  "keyId": "prod-2027-1"
}
```

- `orgId` must match the subscriber org (15 or 18 characters).
- `caps`: `null` or a missing entry means unlimited.
- `graceDays` is optional; the default is `Default_Grace_Days__c` (30).
- `keyId` must equal `Key_Id__c` in `PMS_Licensing__mdt`, which lets us rotate keys.
- A 2048-bit RSA token is about 700 characters with the payload above.

## Owner tool: `scripts/pms-licence.js`

Local Node CLI (built-in `crypto`, RSA-SHA256, same token format as `PMS_Entitlements`). The private key is read
from the file in env `PMS_LICENCE_PRIVATE_KEY`; the tool refuses a key (or `--out`) inside this repository. The key
id comes from `PMS_LICENCE_KEY_ID` or `key-id.txt` next to the key. Every token gets a fresh `issuedAt` (UTC
datetime) and is appended to `issuance-log.jsonl` in the key's directory (mode forced to 0600 on every write). The tool
warns when the private key file is readable by group or others (`chmod 600`).

```bash
# 1. once: production keypair (directory must be outside the repo; keep a backup)
node scripts/pms-licence.js keygen --out ~/pms-licence-keys
export PMS_LICENCE_PRIVATE_KEY=~/pms-licence-keys/pms-licence-private.pem

# 2. issue a licence
node scripts/pms-licence.js issue --org 00D... --edition Standard --modules Hotel,Property \
  --valid-until 2027-06-30 --grace 14 --caps rooms=40,portal=100

# 3. temporary unlock (client cannot pay yet / is excused); keeps the entitlements of the latest token for the org
node scripts/pms-licence.js extend --org 00D... --until 2027-03-31 --reason "Awaiting PO" [--from-token <token>]

# 3b. after a key rotation: extend a token that the OLD key signed (verify it with the old public key, sign with the new key)
node scripts/pms-licence.js extend --org 00D... --until 2027-03-31 --reason "Awaiting PO" \
  --from-token <old token> --verify-key ~/old-keys/pms-licence-public.b64
```

`extend --until` must be today or later (an error otherwise) and prints a warning when it is before the licence's
`validUntil`, because the extension would then change nothing. `--verify-key` takes a PEM public key or the base64 DER
file written by `keygen`.

`keygen` prints `Key_Id__c` and `Public_Key__c`: paste both into
`core/main/default/customMetadata/PMS_Licensing.Default.md-meta.xml` **before** `version`/`promote`. The shipped
file holds `REPLACE_` placeholders and `scripts/pms-package.sh version|promote` refuses to build while any remain.
When `PMS_LICENCE_PRIVATE_KEY` is set, that guard also signs a test payload with it and verifies the signature with the
packaged `Public_Key__c`, refusing on a mismatch (a wrong paste would make every issued key invalid). When it is not set
the guard warns that the match was not checked.
Never commit the private key or put it in a package, custom setting or script. To rotate: `keygen` into a new
directory, move the old public key/id into `Previous_*`, ship the new version, then issue with the new key.

### Extension (temporary unlock)

Signed payload fields `extensionUntil` (yyyy-MM-dd) and `extensionReason`. While today <= `extensionUntil` the state
is `ACTIVE` regardless of `validUntil` or grace, with banner "Temporary access until <date>". After that date the
normal rules apply again. Only the owner can issue it because the token is signed.

`bash scripts/pms-licence-check.sh` runs a local round trip: it generates a throw-away key in a temp directory,
issues and extends a token, and verifies both signatures with `openssl`. `--issued-at` (YYYY-MM-DD or an ISO 8601 UTC
datetime) on `issue`/`extend` exists only for building fixtures.

## Configuration reference

`PMS_Licensing__mdt` (protected, record `Default`): `Enforcement_Enabled__c`, `Pilot_Days__c`, `Public_Key__c`,
`Key_Id__c`, `Previous_Public_Key__c`, `Previous_Key_Id__c`, `Allow_Inbound_When_Suspended__c`,
`Allow_Key_Entry_When_Suspended__c`, `Licence_Endpoint__c` (unused in the pilot), `Default_Grace_Days__c`.
`PMS_License__c` (protected hierarchy setting): `Install_Date__c`, `Token_Issued_At__c`, `Token_1__c`..`Token_4__c`, `Last_Checked__c`, `Last_Error__c`.

## For Experience code

Call the `@NamespaceAccessible` methods of `PMS_Entitlements`: `state()`, `isModuleEnabled(String)`,
`capFor(String)`, `remaining(String)`, `daysRemaining()`, `edition()`, `assertCanCreate(String, Integer[, Integer])`
(throws `PMS_Entitlements.LicenceException`), `isLocked()`, `guardWrites()` (call first in every trigger, and also for `after undelete`),
`jobsBlocked(String)` (call first in scheduled jobs and at the start of batches/queueables), and
`beginInbound()` / `endInbound()` (only around payment-provider webhook handling after signature verification; always
pair them in `try/finally`). Public booking pages must not show licence text to guests:
`PMS_PublicBookingController` replaces it with "Online booking is temporarily unavailable". Cap names: `Room`, `Unit`, `PortalUser`. Core counts rooms and units;
for `PortalUser` pass the current count as the third argument.

## Tests

`PMS_EntitlementsTest` uses a throw-away test public key and pre-signed tokens with test hooks for org id, key,
key id and date. The test private key was deleted; to add a fixture, generate a new test pair, re-sign all
fixtures and replace the public key in the test. The extension fixtures (`TOKEN_C_*`) were made with
`scripts/pms-licence.js` and `--issued-at`; their key is also throw-away. `TOKEN_D_*` use datetime `issuedAt` (same day,
09:00 and 15:30) for the same-day replay test; `TOKEN_OK` and `TOKEN_C_*` keep a plain-date `issuedAt` on purpose, to cover
backward compatibility.

## Script guards

`scripts/pms-package.sh bootstrap` and `config-import` (and the sample data step) first query `Organization` and only
proceed for scratch orgs/trials (`TrialExpirationDate` set) and Developer Edition orgs. The alias `agentforce-org-nov`
and any non-sandbox org that is not a trial or Developer Edition are always refused. Other orgs (sandboxes) need
`--i-know-this-org`.
