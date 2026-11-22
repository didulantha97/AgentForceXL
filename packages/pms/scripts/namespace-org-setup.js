#!/usr/bin/env node
// Copies packages/pms/org-setup/<part> to <out-dir> and rewrites references to
// packaged PMS components so they resolve after the managed packages are
// installed in a client org:
//
//   LWC in site pages      c:pmsPublicBooking         -> <ns>:pmsPublicBooking
//   objects / fields       PMS_Booking__c.Status__c   -> <ns>__PMS_Booking__c.<ns>__Status__c
//   Apex classes, flows    PMS_CreateBookingAction    -> <ns>__PMS_CreateBookingAction
//   Experience flexipages  PMS_Booking_Record_Page_Plus -> <ns>__PMS_Booking_Record_Page_Plus
//   file names             PMS_Booking__c.sharingRules-meta.xml -> <ns>__PMS_Booking__c...
//   object directories     objects/PMS_Booking__c/ -> objects/<ns>__PMS_Booking__c/
//
// Every custom field and object in org-setup belongs to PMS Core, so every
// un-namespaced X__c / X__r / X__mdt token gets the prefix. Apex classes and
// flows are prefixed only when they are actually in one of the packages.
//
// With no namespace (empty string) the files are copied unchanged, which is
// what you want for a scratch org deployed from source.
//
//   node namespace-org-setup.js <namespace|""> <part: main|agent> <out-dir>

"use strict";

const fs = require("fs");
const path = require("path");

const [ns, part, outDir] = process.argv.slice(2);
if (ns === undefined || !part || !outDir) {
  console.error(
    'Usage: node namespace-org-setup.js <namespace|""> <main|agent> <out-dir>'
  );
  process.exit(1);
}

const pmsRoot = path.resolve(__dirname, "..");
const srcDir = path.join(pmsRoot, "org-setup", part);
if (!fs.existsSync(srcDir)) {
  console.error(`No such org-setup part: ${srcDir}`);
  process.exit(1);
}

// Names of packaged Apex classes, flows and Visualforce pages (Core and Experience).
function namesIn(dir, suffix) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(suffix))
    .map((f) => f.slice(0, -suffix.length));
}
const packaged = new Set();
for (const pkg of ["core", "experience"]) {
  const base = path.join(pmsRoot, pkg, "main", "default");
  namesIn(path.join(base, "classes"), ".cls").forEach((n) => packaged.add(n));
  namesIn(path.join(base, "flows"), ".flow-meta.xml").forEach((n) =>
    packaged.add(n)
  );
  namesIn(path.join(base, "pages"), ".page").forEach((n) => packaged.add(n));
}
// Experience-owned record pages referenced by object-level View overrides.
namesIn(
  path.join(pmsRoot, "experience", "main", "default", "flexipages"),
  ".flexipage-meta.xml"
).forEach((n) => packaged.add(n));

const TEXT = /\.(xml|json|js|html|css|txt|agent|yaml|yml)$/i;
const customToken =
  /(?<![A-Za-z0-9_])(?![A-Za-z0-9]+__[A-Za-z0-9_]+__(?:c|r|mdt)\b)([A-Za-z][A-Za-z0-9_]*?__(?:c|r|mdt))\b/g;
const packagedToken = packaged.size
  ? new RegExp(
      `(?<![A-Za-z0-9_])(${[...packaged]
        .sort((a, b) => b.length - a.length)
        .join("|")})(?![A-Za-z0-9_])`,
      "g"
    )
  : null;

// Site admin / email sender of the target org (set by scripts/pms-package.sh).
const adminUsername = process.env.PMS_ADMIN_USERNAME || "";
const adminEmail = process.env.PMS_ADMIN_EMAIL || adminUsername;

function rewrite(text) {
  text = text
    .replace(/__PMS_ADMIN_USERNAME__/g, adminUsername)
    .replace(/__PMS_ADMIN_EMAIL__/g, adminEmail);
  if (!ns) return text;
  let out = text.replace(/(["'>\s])c:(pms[A-Za-z0-9]+)/g, `$1${ns}:$2`);
  out = out.replace(customToken, `${ns}__$1`);
  if (packagedToken) out = out.replace(packagedToken, `${ns}__$1`);
  return out;
}

function renameFile(name) {
  if (!ns) return name;
  return name.replace(
    /^([A-Za-z][A-Za-z0-9_]*?__(?:c|mdt))(?=\.)/,
    `${ns}__$1`
  );
}

// Object folders (objects/PMS_Booking__c/) are named after the object.
function renameDir(name) {
  if (!ns) return name;
  return name.replace(/^([A-Za-z][A-Za-z0-9_]*?__(?:c|mdt))$/, `${ns}__$1`);
}

// Objects whose org-setup definition carries sharing defaults (OWD). The admin may have changed
// them (Access Console), so they are never deployed with the source values: the caller passes the
// target org's current values in PMS_OWD_JSON ({"PMS_Booking__c":{"internal":"Private","external":"Private"}},
// keyed by un-namespaced API name). Without that variable the object files are left out entirely.
const OWD_OBJECTS = ["PMS_Booking__c", "PMS_Invoice__c"];
let owd = null;
try {
  owd = process.env.PMS_OWD_JSON ? JSON.parse(process.env.PMS_OWD_JSON) : null;
} catch (e) {
  owd = null;
}
const SHARING =
  /^(Private|Read|ReadWrite|ReadWriteTransfer|FullAccess|ControlledByParent)$/;
function applyOwd(text, objectName) {
  const cur = owd && owd[objectName];
  if (
    !cur ||
    !SHARING.test(cur.internal || "") ||
    !SHARING.test(cur.external || "")
  ) {
    return null;
  }
  return text
    .replace(
      /<sharingModel>[^<]*<\/sharingModel>/,
      `<sharingModel>${cur.internal}</sharingModel>`
    )
    .replace(
      /<externalSharingModel>[^<]*<\/externalSharingModel>/,
      `<externalSharingModel>${cur.external}</externalSharingModel>`
    );
}

let files = 0;
function to_(dest, name) {
  return path.join(dest, renameFile(name));
}
function copy(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, entry.name);
    if (entry.isDirectory()) {
      copy(from, path.join(dest, renameDir(entry.name)));
      continue;
    }
    const owdObject = entry.name.replace(/\.object-meta\.xml$/, "");
    if (
      entry.name.endsWith(".object-meta.xml") &&
      OWD_OBJECTS.includes(owdObject)
    ) {
      const patched = applyOwd(fs.readFileSync(from, "utf8"), owdObject);
      if (patched === null) {
        console.error(
          `warning: current sharing defaults of ${owdObject} unknown; NOT deploying its object definition (OWD left as it is)`
        );
        continue;
      }
      fs.writeFileSync(to_(dest, entry.name), rewrite(patched));
      files++;
      continue;
    }
    const to = path.join(dest, renameFile(entry.name));
    if (TEXT.test(entry.name)) {
      fs.writeFileSync(to, rewrite(fs.readFileSync(from, "utf8")));
    } else {
      fs.copyFileSync(from, to);
    }
    files++;
  }
}

if (part === "main" && !adminUsername) {
  console.error(
    "Set PMS_ADMIN_USERNAME (and PMS_ADMIN_EMAIL) to the target org's admin user."
  );
  process.exit(1);
}

fs.rmSync(outDir, { recursive: true, force: true });
copy(srcDir, outDir);
console.log(
  `org-setup/${part}: ${files} files -> ${outDir}` +
    (ns ? ` (namespace ${ns})` : " (no namespace)")
);
