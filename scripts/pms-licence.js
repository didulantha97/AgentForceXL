#!/usr/bin/env node
/**
 * Owner-side licence tool for PMS Core (see packages/pms/docs/Licensing.md).
 *
 *   node scripts/pms-licence.js keygen --out <dir outside the repo>
 *   node scripts/pms-licence.js issue  --org <orgId> --edition <name> --modules Hotel,Property,...
 *                                      --valid-until YYYY-MM-DD [--grace N] [--caps rooms=N,units=N,portal=N]
 *   node scripts/pms-licence.js extend --org <orgId> --until YYYY-MM-DD --reason "..." [--from-token <token>
 *                                      [--verify-key <public key file of the key that signed the token>]]
 *
 * The private key is read from the file named by env PMS_LICENCE_PRIVATE_KEY (PEM). It must live outside this
 * repository; the tool refuses otherwise. The key id is read from PMS_LICENCE_KEY_ID or from key-id.txt next to
 * the private key (keygen writes it). Every issued token is appended to issuance-log.jsonl in the key's directory.
 *
 * Token format (identical to PMS_Entitlements): base64url(payloadJson) + "." + base64url(RSA-SHA256 signature
 * over the ASCII bytes of the first part). Each token gets a fresh issuedAt (ISO 8601 UTC datetime) so replay
 * protection accepts it, even for a second key issued the same day. --issued-at (YYYY-MM-DD or an ISO 8601
 * datetime) exists only to build deterministic test fixtures.
 * After a key rotation, extend --from-token for a token signed by the OLD key needs --verify-key with the old
 * public key (PEM, or the base64 DER written by keygen as pms-licence-public.b64); the new token is signed with
 * the current private key.
 */
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..");
const MODULES = ["Hotel", "Property", "Finance", "Staff", "AI"];
const CAP_NAMES = {
  rooms: "maxRooms",
  units: "maxUnits",
  portal: "maxPortalUsers"
};

function fail(message) {
  console.error("error: " + message);
  process.exit(1);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) fail("unexpected argument " + a);
    const key = a.slice(2);
    const val = argv[i + 1];
    if (val === undefined || val.startsWith("--"))
      fail("--" + key + " needs a value");
    out[key] = val;
    i++;
  }
  return out;
}

function realOrSelf(p) {
  let cur = path.resolve(p);
  const tail = [];
  while (!fs.existsSync(cur)) {
    tail.unshift(path.basename(cur));
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return path.join(fs.realpathSync(cur), ...tail);
}

function insideRepo(p) {
  const rel = path.relative(fs.realpathSync(REPO_ROOT), realOrSelf(p));
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

function validDate(s, name) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s || "")) fail(name + " must be YYYY-MM-DD");
  const d = new Date(s + "T00:00:00Z");
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s)
    fail(name + " is not a real date");
  return s;
}

function validOrg(s) {
  if (!/^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(s || ""))
    fail("--org must be a 15 or 18 character Salesforce org id");
  return s;
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function nowIso() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function validIssuedAt(s, name) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(s || "")) return validDate(s, name);
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(s || "") ||
    Number.isNaN(new Date(s).getTime())
  )
    fail(
      name +
        " must be YYYY-MM-DD or an ISO 8601 UTC datetime (2027-01-05T09:30:00Z)"
    );
  return s;
}

function loadPublicKey(file) {
  if (!fs.existsSync(file)) fail("--verify-key file not found: " + file);
  const raw = fs.readFileSync(file, "utf8").trim();
  if (raw.includes("BEGIN")) return crypto.createPublicKey(raw);
  return crypto.createPublicKey({
    key: Buffer.from(raw.replace(/\s+/g, ""), "base64"),
    format: "der",
    type: "spki"
  });
}

function privateKeyPath() {
  const p = process.env.PMS_LICENCE_PRIVATE_KEY;
  if (!p)
    fail(
      "set PMS_LICENCE_PRIVATE_KEY to the path of the private key (outside the repo)"
    );
  if (!fs.existsSync(p)) fail("private key file not found: " + p);
  if (insideRepo(p))
    fail(
      "the private key is inside the repository. Move it out and never commit it."
    );
  if (fs.statSync(p).mode & 0o077)
    console.error(
      "warning: " + p + " is readable by group or others. Run: chmod 600 " + p
    );
  return path.resolve(p);
}

function loadSigner() {
  const keyPath = privateKeyPath();
  const privateKey = crypto.createPrivateKey(fs.readFileSync(keyPath));
  const publicKey = crypto.createPublicKey(privateKey);
  const dir = path.dirname(keyPath);
  let keyId = process.env.PMS_LICENCE_KEY_ID;
  const keyIdFile = path.join(dir, "key-id.txt");
  if (!keyId && fs.existsSync(keyIdFile))
    keyId = fs.readFileSync(keyIdFile, "utf8").trim();
  if (!keyId)
    fail(
      "no key id: set PMS_LICENCE_KEY_ID or create key-id.txt next to the private key"
    );
  return { privateKey, publicKey, keyId, dir };
}

function b64url(buf) {
  return Buffer.from(buf).toString("base64url");
}

function sign(payload, privateKey) {
  const first = b64url(Buffer.from(JSON.stringify(payload), "utf8"));
  const sig = crypto.sign("sha256", Buffer.from(first, "ascii"), privateKey); // RSA PKCS#1 v1.5
  return first + "." + b64url(sig);
}

function decode(token, publicKey) {
  const clean = String(token).replace(/\s+/g, "");
  const parts = clean.split(".");
  if (parts.length !== 2) fail("token is not in the expected format");
  const ok = crypto.verify(
    "sha256",
    Buffer.from(parts[0], "ascii"),
    publicKey,
    Buffer.from(parts[1], "base64url")
  );
  if (!ok)
    fail(
      "token was not signed by the expected key (after a key rotation pass --verify-key <old public key file>)"
    );
  return JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
}

function summary(p) {
  const mods = MODULES.filter((m) => p.modules && p.modules[m]);
  const caps = Object.keys(CAP_NAMES)
    .map(
      (k) =>
        k +
        "=" +
        (p.caps && p.caps[CAP_NAMES[k]] != null
          ? p.caps[CAP_NAMES[k]]
          : "unlimited")
    )
    .join(", ");
  return [
    "Org:        " + p.orgId,
    "Edition:    " + p.edition,
    "Modules:    " + (mods.join(", ") || "none"),
    "Caps:       " + caps,
    "Valid to:   " +
      p.validUntil +
      (p.graceDays != null
        ? " (+" + p.graceDays + " grace days)"
        : " (default grace)"),
    "Issued at:  " + p.issuedAt,
    p.extensionUntil
      ? "Extension:  temporary access until " +
        p.extensionUntil +
        " (" +
        (p.extensionReason || "no reason given") +
        ")"
      : "Extension:  none",
    "Key id:     " + p.keyId
  ].join("\n");
}

function emit(signer, payload, command) {
  const token = sign(payload, signer.privateKey);
  const logLine =
    JSON.stringify({ at: new Date().toISOString(), command, payload }) + "\n";
  const logFile = path.join(signer.dir, "issuance-log.jsonl");
  fs.appendFileSync(logFile, logLine, { mode: 0o600 });
  fs.chmodSync(logFile, 0o600); // the mode above only applies when the file is created
  console.log(summary(payload));
  console.log("\nToken (paste into the PMS licence card):\n");
  console.log(token);
  console.log("\nLogged to " + path.join(signer.dir, "issuance-log.jsonl"));
}

function parseCaps(spec) {
  const caps = { maxRooms: null, maxUnits: null, maxPortalUsers: null };
  if (!spec) return caps;
  for (const part of spec.split(",")) {
    const [k, v] = part.split("=");
    if (!CAP_NAMES[k])
      fail("unknown cap '" + k + "' (use rooms, units, portal)");
    if (!/^\d+$/.test(v || "")) fail("cap " + k + " must be a whole number");
    caps[CAP_NAMES[k]] = parseInt(v, 10);
  }
  return caps;
}

function cmdKeygen(a) {
  if (!a.out) fail("keygen needs --out <dir outside the repo>");
  if (insideRepo(a.out))
    fail("--out is inside the repository; choose a directory outside it");
  fs.mkdirSync(a.out, { recursive: true, mode: 0o700 });
  const privFile = path.join(a.out, "pms-licence-private.pem");
  if (fs.existsSync(privFile))
    fail(privFile + " already exists; refusing to overwrite a key");
  const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048
  });
  const der = publicKey.export({ type: "spki", format: "der" });
  const keyId =
    "pms-" +
    today().replace(/-/g, "") +
    "-" +
    crypto.createHash("sha256").update(der).digest("hex").slice(0, 6);
  fs.writeFileSync(
    privFile,
    privateKey.export({ type: "pkcs8", format: "pem" }),
    { mode: 0o600 }
  );
  fs.writeFileSync(path.join(a.out, "key-id.txt"), keyId + "\n", {
    mode: 0o600
  });
  fs.writeFileSync(
    path.join(a.out, "pms-licence-public.b64"),
    der.toString("base64") + "\n"
  );
  console.log("Private key (keep secret, back it up): " + privFile);
  console.log("export PMS_LICENCE_PRIVATE_KEY=" + privFile);
  console.log(
    "\nPaste into packages/pms/core/main/default/customMetadata/PMS_Licensing.Default.md-meta.xml:"
  );
  console.log("  Key_Id__c     = " + keyId);
  console.log("  Public_Key__c = " + der.toString("base64"));
}

function cmdIssue(a) {
  const signer = loadSigner();
  validOrg(a.org);
  if (!a.edition) fail("--edition is required");
  const wanted = (a.modules || "")
    .split(",")
    .map((m) => m.trim())
    .filter(Boolean);
  if (!wanted.length) fail("--modules is required, for example Hotel,Property");
  for (const m of wanted)
    if (!MODULES.includes(m))
      fail("unknown module '" + m + "' (use " + MODULES.join(", ") + ")");
  const payload = {
    orgId: a.org,
    edition: a.edition,
    modules: Object.fromEntries(MODULES.map((m) => [m, wanted.includes(m)])),
    caps: parseCaps(a.caps),
    validUntil: validDate(a["valid-until"], "--valid-until")
  };
  if (a.grace !== undefined) {
    if (!/^\d+$/.test(a.grace)) fail("--grace must be a whole number of days");
    payload.graceDays = parseInt(a.grace, 10);
  }
  payload.issuedAt = a["issued-at"]
    ? validIssuedAt(a["issued-at"], "--issued-at")
    : nowIso();
  payload.keyId = signer.keyId;
  emit(signer, payload, "issue");
}

function latestFromLog(signer, org) {
  const file = path.join(signer.dir, "issuance-log.jsonl");
  if (!fs.existsSync(file)) return null;
  let found = null;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line.trim()) continue;
    try {
      const rec = JSON.parse(line);
      if (
        rec.payload &&
        String(rec.payload.orgId).slice(0, 15) === org.slice(0, 15)
      )
        found = rec.payload;
    } catch (e) {
      /* ignore damaged line */
    }
  }
  return found;
}

function cmdExtend(a) {
  const signer = loadSigner();
  validOrg(a.org);
  validDate(a.until, "--until");
  if (a.until < today())
    fail("--until " + a.until + " is in the past; it must be today or later");
  if (a["verify-key"] && !a["from-token"])
    fail("--verify-key only applies together with --from-token");
  if (!a.reason || !a.reason.trim())
    fail(
      "--reason is required (it is kept in the licence and the issuance log)"
    );
  const base = a["from-token"]
    ? decode(
        a["from-token"],
        a["verify-key"] ? loadPublicKey(a["verify-key"]) : signer.publicKey
      )
    : latestFromLog(signer, a.org);
  if (!base)
    fail(
      "no existing token for this org: pass --from-token or issue one first"
    );
  if (String(base.orgId).slice(0, 15) !== a.org.slice(0, 15))
    fail("--from-token belongs to a different org");
  if (a.until < base.validUntil)
    console.error(
      "warning: --until " +
        a.until +
        " is before the licence's validUntil " +
        base.validUntil +
        ", so the extension changes nothing"
    );
  const payload = { ...base };
  payload.extensionUntil = a.until;
  payload.extensionReason = a.reason.trim();
  payload.issuedAt = a["issued-at"]
    ? validIssuedAt(a["issued-at"], "--issued-at")
    : nowIso();
  payload.keyId = signer.keyId;
  // keep key order stable: keyId last
  delete payload.keyId;
  payload.keyId = signer.keyId;
  emit(signer, payload, "extend");
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  switch (cmd) {
    case "keygen":
      return cmdKeygen(args);
    case "issue":
      return cmdIssue(args);
    case "extend":
      return cmdExtend(args);
    default:
      console.error(
        fs
          .readFileSync(__filename, "utf8")
          .split("*/")[0]
          .replace(/^#!.*\n/, "")
          .replace(/^\/\*\*\n|^ \* ?/gm, "")
      );
      process.exit(cmd ? 1 : 0);
  }
}

if (require.main === module) main();
module.exports = { sign, decode, summary };
