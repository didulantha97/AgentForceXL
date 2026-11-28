#!/usr/bin/env node
/**
 * PMS access audit. Reads the SOURCE (no org needed) and reports, per persona, what each persona can
 * reach: objects (CRUD), fields (FLS), Apex entry points, tabs, apps, custom permissions, record types,
 * and which Apex controllers every app page needs through its LWCs.
 *
 *   node packages/pms/scripts/access-audit.js            Markdown report (gaps only for fields)
 *   node packages/pms/scripts/access-audit.js --full     also list every field and every OK row
 *   node packages/pms/scripts/access-audit.js --json     machine readable
 *   node packages/pms/scripts/access-audit.js --check    exit 1 if any policy violation (use in CI)
 *
 * Personas
 *   Admin   PMS_Core_Admin + PMS_App_Access + the Experience admin sets (see ADMIN_SETS)
 *   Staff   PMS_Standard_User permission set group, minus PMS_Standard_User_Muting
 *   Portal  PMS_Customer_Portal, PMS_Partner_Portal, PMS_Guest_Check_In, PMS_Public_Booking
 *
 * Policies (a violation is a "GAP" row; the script exits 1 under --check):
 *   Admin   must have every custom object CRUD, every settable field (edit unless formula/roll-up/auto
 *           number), every entry-point Apex class that is not portal-only, every app tab, every app,
 *           every record type and every custom permission except the "Hide" ones (those are negative
 *           switches the access engine hands out). Fields in EXCLUDED_FIELDS are intentionally kept
 *           out of every set.
 *   Staff   whatever Admin has, except: nothing on admin-only objects/classes/custom permissions,
 *           no View All / Modify All anywhere, no delete on financial objects, read-only on
 *           policy / configuration / log / access objects, and the Staff muting must not mute
 *           anything Admin needs for day-to-day work.
 *   Portal  class access only. Never object or field permissions, never a class that is not a
 *           portal controller, and every controller a site page needs must be granted.
 */
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const CORE = path.join(ROOT, "core/main/default");
const EXP = path.join(ROOT, "experience/main/default");
const ORG_SETUP = path.join(ROOT, "org-setup");

// ---------------------------------------------------------------------------------------------
// Policy configuration
// ---------------------------------------------------------------------------------------------
const ADMIN_SETS = [
  "PMS_Core_Admin",
  "PMS_App_Access",
  // Optional Core feature sets: an administrator needs every feature.
  "PMS_Access_Manager",
  "PMS_Channex",
  "PMS_Dynamic_Pricing",
  "PMS_Rent_Review",
  "PMS_Guest360_Viewer",
  "PMS_Guest360_Editor",
  // Experience
  "PMS_Experience_Access",
  "PMS_Payment_Integration",
  "PMS_Payment_Gateway",
  "PMS_Stripe_Access",
  "PMS_Dunning",
  "PMS_Guarantees",
  "PMS_Customer_Portal_Management",
  "PMS_Partner_Management"
];
/**
 * Sets assigned to a named role, never to the installer / Admin persona (e.g. the DPO holds Privacy Admin). What
 * Admin lacks because of that (classes, custom permissions, fields only these sets grant) is a design decision.
 */
const OPT_IN_SETS = ["PMS_Guest_Privacy_Admin"];
const STAFF_GROUP = "PMS_Standard_User";
const PORTAL_SETS = [
  "PMS_Customer_Portal",
  "PMS_Partner_Portal",
  "PMS_Guest_Check_In",
  "PMS_Public_Booking"
];
// Granted to the PMS Payments site guest user by profile / PMS_Payment_Link; not a persona but a portal class.
const OTHER_PORTAL_SETS = ["PMS_Payment_Link"];

/** Secret fields the repo keeps out of every permission set (only Apex in system context touches them). */
const EXCLUDED_FIELDS = new Set([
  "PMS_License__c.Token_1__c", // licence key chunks: written only through PMS_LicenceController
  "PMS_License__c.Token_2__c",
  "PMS_License__c.Token_3__c",
  "PMS_License__c.Token_4__c",
  "PMS_Invoice__c.Pay_Key__c", // secret in the reminder-letter pay link: "Never show it to staff or reuse it."
  "PMS_Booking__c.Web_Access_Key__c" // guest's key to fetch their own pay link: "Never shown in the UI."
]);
/** Code-maintained idempotency keys: readable by the people who run the feature, never hand-edited, so no edit FLS for anyone. */
const READONLY_BY_DESIGN = new Set([
  "PMS_Booking__c.Channex_Room_Key__c",
  "PMS_Rate__c.Dynamic_Key__c",
  // Guest 360 system-written Contact fields (field descriptions: "Written by PMS system code" / "Do not edit by hand")
  "Contact.PMS_Total_Stays__c",
  "Contact.PMS_Lifetime_Nights__c",
  "Contact.PMS_Room_Revenue__c",
  "Contact.PMS_Extras_Revenue__c",
  "Contact.PMS_First_Stay__c",
  "Contact.PMS_Last_Stay__c",
  "Contact.PMS_Next_Arrival__c",
  "Contact.PMS_Stats_Refreshed__c",
  "Contact.PMS_Retention_Due__c",
  "Contact.PMS_Duplicate_Reason__c",
  "Contact.PMS_OTA_Alias_Email__c",
  "Contact.PMS_Anonymised__c"
]);

/** Negative switches, handed out by the access engine from Access Team settings. Nobody gets them by hand. */
const NEGATIVE_CUSTOM_PERMS = new Set([
  "PMS_Hide_Amounts",
  "PMS_Hide_Customer_Details"
]);
/** Admin-only custom permissions, classes and objects: Staff must not hold them. */
const ADMIN_ONLY_CUSTOM_PERMS = new Set([
  "PMS_Manage_License",
  "PMS_Manage_Demo_Data",
  "PMS_Manage_Access"
]);
// PMS_LicenceController (licence banner on every home page) and PMS_DemoDataController (card hides itself)
// stay granted to Staff on purpose: both gate their actions on the custom permissions above.
const ADMIN_ONLY_CLASSES = new Set();
const ADMIN_ONLY_OBJECTS = new Set(["PMS_Demo_Record__c"]);

/** Financial records: Staff never deletes these. */
const FINANCIAL_OBJECTS = new Set([
  "PMS_Booking__c",
  "PMS_Charge__c",
  "PMS_Invoice__c",
  "PMS_Payment__c",
  "PMS_Payment_Plan__c",
  "PMS_Payment_Plan_Instalment__c",
  "PMS_Vendor_Bill__c",
  "PMS_Vendor_Quote__c",
  "PMS_Owner_Statement__c",
  "PMS_Dunning_Event__c",
  "PMS_Rent_Adjustment__c",
  "PMS_Budget_Line__c",
  "PMS_Lease_Charge_Schedule__c"
]);
/** Policies, configuration, logs and access rules: Staff reads, never writes (create/edit/delete). */
const STAFF_READONLY_OBJECTS = new Set([
  "PMS_Payment_Policy__c",
  "PMS_Dunning_Policy__c",
  "PMS_Pricing_Strategy__c",
  "PMS_Pricing_Factor__c",
  "PMS_Channel_Mapping__c",
  "PMS_Channel_Log__c",
  "PMS_Dunning_Event__c",
  "PMS_Index_Value__c",
  "PMS_Access_Rule__c",
  "PMS_Access_Team__c",
  "PMS_Access_Team_Member__c",
  "PMS_Access_Rollout__c"
]);

const PERSONAS = ["Admin", "Staff", "Portal"];
const FLAGS = ["create", "read", "edit", "delete", "viewAll", "modifyAll"];
const FLAG_LETTER = {
  create: "C",
  read: "R",
  edit: "U",
  delete: "D",
  viewAll: "v",
  modifyAll: "m"
};

// ---------------------------------------------------------------------------------------------
// Tiny XML helpers (the metadata files are regular; no dependency needed)
// ---------------------------------------------------------------------------------------------
const decode = (s) =>
  s
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
const blocks = (xml, tag) =>
  [...xml.matchAll(new RegExp(`<${tag}\\s*>([\\s\\S]*?)</${tag}>`, "g"))].map(
    (m) => m[1]
  );
const val = (xml, tag) => {
  const m = xml.match(new RegExp(`<${tag}\\s*>([\\s\\S]*?)</${tag}>`));
  return m ? decode(m[1].trim()) : undefined;
};
const bool = (xml, tag) => val(xml, tag) === "true";
const read = (f) => fs.readFileSync(f, "utf8");
const exists = (f) => fs.existsSync(f);
const list = (d) => (exists(d) ? fs.readdirSync(d) : []);

// ---------------------------------------------------------------------------------------------
// Permission sets, muting sets, groups
// ---------------------------------------------------------------------------------------------
function emptyPerms() {
  return {
    objects: {},
    fields: {},
    classes: new Set(),
    tabs: {},
    apps: new Set(),
    customPerms: new Set(),
    recordTypes: new Set()
  };
}

const TAB_RANK = {
  None: 0,
  Hidden: 0,
  Available: 1,
  DefaultOff: 1,
  Visible: 2,
  DefaultOn: 2
};
const betterTab = (a, b) => ((TAB_RANK[a] || 0) >= (TAB_RANK[b] || 0) ? a : b);

function parseSet(file) {
  const xml = read(file);
  const p = emptyPerms();
  for (const b of blocks(xml, "objectPermissions")) {
    p.objects[val(b, "object")] = {
      create: bool(b, "allowCreate"),
      read: bool(b, "allowRead"),
      edit: bool(b, "allowEdit"),
      delete: bool(b, "allowDelete"),
      viewAll: bool(b, "viewAllRecords"),
      modifyAll: bool(b, "modifyAllRecords")
    };
  }
  for (const b of blocks(xml, "fieldPermissions")) {
    p.fields[val(b, "field")] = {
      read: bool(b, "readable"),
      edit: bool(b, "editable")
    };
  }
  for (const b of blocks(xml, "classAccesses")) {
    if (bool(b, "enabled")) p.classes.add(val(b, "apexClass"));
  }
  for (const b of blocks(xml, "tabSettings"))
    p.tabs[val(b, "tab")] = val(b, "visibility");
  for (const b of blocks(xml, "applicationVisibilities")) {
    if (bool(b, "visible")) p.apps.add(val(b, "application"));
  }
  for (const b of blocks(xml, "customPermissions")) {
    if (bool(b, "enabled")) p.customPerms.add(val(b, "name"));
  }
  for (const b of blocks(xml, "recordTypeVisibilities")) {
    if (bool(b, "visible")) p.recordTypes.add(val(b, "recordType"));
  }
  return p;
}

function union(list) {
  const out = emptyPerms();
  for (const p of list) {
    for (const [o, f] of Object.entries(p.objects)) {
      const cur = (out.objects[o] = out.objects[o] || {});
      for (const k of FLAGS) cur[k] = !!(cur[k] || f[k]);
    }
    for (const [fld, f] of Object.entries(p.fields)) {
      const cur = (out.fields[fld] = out.fields[fld] || {
        read: false,
        edit: false
      });
      cur.read = cur.read || f.read;
      cur.edit = cur.edit || f.edit;
    }
    p.classes.forEach((c) => out.classes.add(c));
    for (const [t, v] of Object.entries(p.tabs))
      out.tabs[t] = betterTab(out.tabs[t], v) || v;
    p.apps.forEach((a) => out.apps.add(a));
    p.customPerms.forEach((c) => out.customPerms.add(c));
    p.recordTypes.forEach((r) => out.recordTypes.add(r));
  }
  return out;
}

/** Muting: a permission set to true in the muting set is removed from the group's union. */
function mute(perms, muting) {
  for (const [o, m] of Object.entries(muting.objects)) {
    const cur = perms.objects[o];
    if (!cur) continue;
    for (const k of FLAGS) if (m[k]) cur[k] = false;
  }
  for (const [fld, m] of Object.entries(muting.fields)) {
    const cur = perms.fields[fld];
    if (!cur) continue;
    if (m.read) cur.read = false;
    if (m.edit) cur.edit = false;
  }
  muting.classes.forEach((c) => perms.classes.delete(c));
  for (const [t, v] of Object.entries(muting.tabs))
    if (TAB_RANK[v]) perms.tabs[t] = "None";
  muting.apps.forEach((a) => perms.apps.delete(a));
  muting.customPerms.forEach((c) => perms.customPerms.delete(c));
  muting.recordTypes.forEach((r) => perms.recordTypes.delete(r));
  return perms;
}

const SETS = {}; // name -> perms (permission sets)
const MUTING = {}; // name -> perms
const GROUPS = {}; // name -> {sets:[], muting:[]}
for (const dir of [CORE, EXP]) {
  for (const f of list(path.join(dir, "permissionsets"))) {
    SETS[f.replace(".permissionset-meta.xml", "")] = parseSet(
      path.join(dir, "permissionsets", f)
    );
  }
  for (const f of list(path.join(dir, "mutingpermissionsets"))) {
    MUTING[f.replace(".mutingpermissionset-meta.xml", "")] = parseSet(
      path.join(dir, "mutingpermissionsets", f)
    );
  }
  for (const f of list(path.join(dir, "permissionsetgroups"))) {
    const xml = read(path.join(dir, "permissionsetgroups", f));
    GROUPS[f.replace(".permissionsetgroup-meta.xml", "")] = {
      sets: blocks(xml, "permissionSets").map((s) => s.trim()),
      muting: blocks(xml, "mutingPermissionSets").map((s) => s.trim())
    };
  }
}

function personaPerms(name) {
  if (name === "Admin") return union(ADMIN_SETS.map((s) => must(SETS, s)));
  if (name === "Staff") {
    const g = must(GROUPS, STAFF_GROUP);
    const u = union(g.sets.map((s) => must(SETS, s)));
    return g.muting.reduce((acc, m) => mute(acc, must(MUTING, m)), u);
  }
  return union(
    [...PORTAL_SETS, ...OTHER_PORTAL_SETS].map((s) => must(SETS, s))
  );
}
function must(map, key) {
  if (!map[key]) throw new Error(`Not found in source: ${key}`);
  return map[key];
}

// ---------------------------------------------------------------------------------------------
// Metadata inventory
// ---------------------------------------------------------------------------------------------
const objects = []; // {name, kind: custom|setting|mdt|standard, fields:[...]}
{
  const dir = path.join(CORE, "objects");
  for (const name of list(dir)) {
    const odir = path.join(dir, name);
    const metaFile = path.join(odir, `${name}.object-meta.xml`);
    const meta = exists(metaFile) ? read(metaFile) : "";
    let kind = "standard";
    if (name.endsWith("__mdt")) kind = "mdt";
    else if (name.endsWith("__c"))
      kind = meta.includes("<customSettingsType>") ? "setting" : "custom";
    const fields = [];
    for (const f of list(path.join(odir, "fields"))) {
      const x = read(path.join(odir, "fields", f));
      const type = val(x, "type") || "";
      const isFormula = /<formula\s*>/.test(x);
      const readOnly = isFormula || type === "Summary" || type === "AutoNumber";
      const settable = !(bool(x, "required") || type === "MasterDetail");
      if (type === "MasterDetail" || bool(x, "required")) {
        fields.push({
          full: `${name}.${val(x, "fullName")}`,
          type,
          readOnly,
          settable: false
        });
        continue;
      }
      // Custom metadata fields (__mdt) and custom setting fields are gated by the object, FLS still applies
      fields.push({
        full: `${name}.${val(x, "fullName")}`,
        type,
        readOnly,
        settable
      });
    }
    const rts = list(path.join(odir, "recordTypes")).map(
      (f) => `${name}.${f.replace(".recordType-meta.xml", "")}`
    );
    objects.push({ name, kind, fields, recordTypes: rts });
  }
}

// Apex entry points
const AURA_METHOD_RE =
  /@AuraEnabled(?:\([^)]*\))?\s*(?:(?:public|global|static|private|webservice)\s+)*[\w.<>,\[\]\s]+?\s+\w+\s*\(/;
const classes = {}; // name -> {file, pkg, entry: bool, kinds:Set, usedBy:Set}
for (const [pkg, dir] of [
  ["core", CORE],
  ["experience", EXP]
]) {
  for (const f of list(path.join(dir, "classes"))) {
    if (!f.endsWith(".cls")) continue;
    const name = f.replace(".cls", "");
    const src = read(path.join(dir, "classes", f));
    if (/@isTest/i.test(src)) continue;
    const kinds = new Set();
    // @AuraEnabled also decorates wrapper properties; only a method (name followed by '(') is an entry point.
    if (AURA_METHOD_RE.test(src)) kinds.add("AuraEnabled");
    for (const k of ["RemoteAction", "InvocableMethod", "RestResource"]) {
      if (new RegExp("@" + k, "i").test(src)) kinds.add(k);
    }
    if (/@Http(Get|Post|Put|Patch|Delete)/i.test(src))
      kinds.add("RestResource");
    classes[name] = {
      name,
      pkg,
      entry: kinds.size > 0,
      kinds,
      usedBy: new Set(),
      src
    };
  }
}

// LWC -> Apex
const lwcs = {}; // name -> {pkg, apex:Set(class), children:Set(c-xxx)}
for (const [pkg, dir] of [
  ["core", CORE],
  ["experience", EXP]
]) {
  for (const n of list(path.join(dir, "lwc"))) {
    const ldir = path.join(dir, "lwc", n);
    if (
      !fs.statSync(ldir).isDirectory() ||
      n.startsWith(".") ||
      n === "jsconfig.json"
    )
      continue;
    const apex = new Set();
    const children = new Set();
    for (const f of list(ldir)) {
      if (!/\.(js|html)$/.test(f) || f.includes(".test.")) continue;
      const src = read(path.join(ldir, f));
      for (const m of src.matchAll(
        /@salesforce\/apex\/(?:[A-Za-z0-9]+\.)?([A-Za-z0-9_]+)\.[A-Za-z0-9_]+/g
      )) {
        apex.add(m[1]);
      }
      for (const m of src.matchAll(/<c-([a-z0-9-]+)/g)) {
        children.add(m[1].replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase()));
      }
    }
    // Components exposed only to Experience Builder (no Lightning App/Record/Home target) are portal components.
    const metaFile = path.join(ldir, `${n}.js-meta.xml`);
    const meta = exists(metaFile) ? read(metaFile) : "";
    const targets = blocks(meta, "target").map((t) => t.trim());
    const communityOnly =
      targets.length > 0 &&
      targets.every((t) => t.startsWith("lightningCommunity"));
    lwcs[n] = { name: n, pkg, apex, children, communityOnly };
  }
}
/** Apex needed by an LWC including child components (recursive, cycle-safe). */
function lwcApex(name, seen = new Set()) {
  if (seen.has(name) || !lwcs[name]) return new Set();
  seen.add(name);
  const out = new Set(lwcs[name].apex);
  for (const c of lwcs[name].children)
    lwcApex(c, seen).forEach((a) => out.add(a));
  return out;
}

// Flows -> Apex actions
const flowApex = {}; // flow -> Set(class)
for (const [, dir] of [
  ["core", CORE],
  ["experience", EXP]
]) {
  for (const f of list(path.join(dir, "flows"))) {
    const x = read(path.join(dir, "flows", f));
    const set = new Set();
    for (const b of blocks(x, "actionCalls")) {
      if (val(b, "actionType") === "apex") set.add(val(b, "actionName"));
    }
    flowApex[f.replace(".flow-meta.xml", "")] = set;
  }
}
// Agent actions (apex:// targets in the Concierge agent) and the flows they run
const agentApex = new Set();
const agentFlows = new Set();
{
  const walk = (d) => {
    for (const f of list(d)) {
      const p = path.join(d, f);
      if (fs.statSync(p).isDirectory()) walk(p);
      else if (/\.agent$/.test(f)) {
        for (const m of read(p).matchAll(
          /target:\s*"(apex|flow):\/\/([A-Za-z0-9_]+)"/g
        )) {
          (m[1] === "apex" ? agentApex : agentFlows).add(m[2]);
        }
      }
    }
  };
  walk(path.join(ORG_SETUP, "agent"));
}
// Quick actions / REST etc. are not scanned: REST resources are marked via @RestResource.

// Site pages (portal LWCs) -> which portal controllers they need
const siteLwcs = {}; // site -> Set(lwc)
{
  const dir = path.join(ORG_SETUP, "main/default/digitalExperiences/site");
  for (const site of list(dir)) {
    const set = new Set();
    const walk = (d) => {
      for (const f of list(d)) {
        const p = path.join(d, f);
        if (fs.statSync(p).isDirectory()) walk(p);
        else if (f.endsWith(".json")) {
          for (const m of read(p).matchAll(
            /"definition"\s*:\s*"c:([A-Za-z0-9_]+)"/g
          ))
            set.add(m[1]);
        }
      }
    };
    walk(path.join(dir, site));
    siteLwcs[site] = set;
  }
}

// Usage annotation for classes
for (const [n, l] of Object.entries(lwcs))
  l.apex.forEach((a) => classes[a] && classes[a].usedBy.add(`lwc:${n}`));
for (const [n, s] of Object.entries(flowApex))
  s.forEach((a) => classes[a] && classes[a].usedBy.add(`flow:${n}`));
agentApex.forEach((a) => classes[a] && classes[a].usedBy.add("agent"));

// Tabs, apps, flexipages
const tabs = {}; // name -> {flexiPage, lwc, sobject}
for (const f of list(path.join(CORE, "tabs"))) {
  const x = read(path.join(CORE, "tabs", f));
  tabs[f.replace(".tab-meta.xml", "")] = {
    flexiPage: val(x, "flexiPage"),
    lwc: val(x, "lwcComponent")
  };
}
const flexipages = {}; // name -> {pkg, components:[{name}], type}
for (const [pkg, dir] of [
  ["core", CORE],
  ["experience", EXP]
]) {
  for (const f of list(path.join(dir, "flexipages"))) {
    const x = read(path.join(dir, "flexipages", f));
    const comps = new Set();
    const gates = {}; // component -> custom permissions its visibility rule requires
    for (const b of blocks(x, "componentInstance")) {
      const m = b.match(
        /<componentName>\s*(?:c:)?(pms[A-Za-z0-9_]+)\s*<\/componentName>/
      );
      if (!m) continue;
      comps.add(m[1]);
      for (const g of b.matchAll(
        /\$Permission\.CustomPermission\.([A-Za-z0-9_]+)\}[\s\S]*?<operator>\s*EQUAL\s*<\/operator>\s*<rightValue>\s*true/g
      )) {
        (gates[m[1]] = gates[m[1]] || new Set()).add(g[1]);
      }
    }
    // Record-page layouts may also embed child flexipage fields; ignored.
    flexipages[f.replace(".flexipage-meta.xml", "")] = {
      pkg,
      components: [...comps],
      gates,
      type: val(x, "type"),
      sobject: val(x, "sobjectType")
    };
  }
}
const apps = {}; // name -> {tabs, pages:Set(flexipage)}
for (const f of list(path.join(CORE, "applications"))) {
  const x = read(path.join(CORE, "applications", f));
  const name = f.replace(".app-meta.xml", "");
  const appTabs = blocks(x, "tabs").map((t) => t.trim());
  const pages = new Set();
  for (const b of blocks(x, "actionOverrides")) {
    if (val(b, "type") === "Flexipage") pages.add(val(b, "content"));
  }
  for (const t of appTabs)
    if (tabs[t] && tabs[t].flexiPage) pages.add(tabs[t].flexiPage);
  apps[name] = { name, tabs: appTabs, pages };
}
// Experience *_Plus record pages replace the Core record pages when the Experience package is installed
// (org assigns them as the org default for the object); show them under every app that overrides the base page.
for (const [pn, fp] of Object.entries(flexipages)) {
  if (!/_Plus$/.test(pn)) continue;
  const base = pn.replace(/_Plus$/, "");
  for (const a of Object.values(apps)) if (a.pages.has(base)) a.pages.add(pn);
}

// Custom permissions referenced in Apex
const customPermRefs = {}; // perm -> Set(class)
for (const c of Object.values(classes)) {
  for (const m of c.src.matchAll(
    /FeatureManagement\.checkPermission\(\s*'([A-Za-z0-9_]+)'\s*\)/g
  )) {
    (customPermRefs[m[1]] = customPermRefs[m[1]] || new Set()).add(c.name);
  }
}
const allCustomPerms = list(path.join(CORE, "customPermissions")).map((f) =>
  f.replace(".customPermission-meta.xml", "")
);
// Tab -> object mapping for standard "object tabs": tab name equals the object API name.

// ---------------------------------------------------------------------------------------------
// Evaluate
// ---------------------------------------------------------------------------------------------
const P = Object.fromEntries(PERSONAS.map((p) => [p, personaPerms(p)]));
const rows = {
  objects: [],
  fields: [],
  classes: [],
  tabs: [],
  apps: [],
  customPerms: [],
  recordTypes: [],
  pages: []
};
const gaps = []; // {persona, kind, item, issue, fix}
const gap = (persona, kind, item, issue) =>
  gaps.push({ persona, kind, item, issue });
// Role add-on sets are deliberately outside the Standard User group (revenue manager, channel manager, access
// manager, rent review). What Staff lack because of that is a design decision, not a failure.
const ADDON_SETS = [
  "PMS_Access_Manager",
  "PMS_Channex",
  "PMS_Dynamic_Pricing",
  "PMS_Rent_Review"
];
const notes = [];
const optInClass = (c) =>
  OPT_IN_SETS.some((s) => SETS[s] && SETS[s].classes.has(c));
const addonClass = (c) => ADDON_SETS.some((s) => SETS[s].classes.has(c));
const note = (persona, kind, item, issue) =>
  notes.push({ persona, kind, item, issue });
/**
 * "Visible but not usable" for Staff: a component whose Apex controller Staff lack. It is fine only when the
 * component is gated by a custom permission that Staff do not hold (the add-on set grants it), and Admin does.
 */
function staffHidden(page, lwc) {
  const gate = page && page.gates && page.gates[lwc];
  if (!gate) return false;
  return [...gate].some(
    (cp) => !P.Staff.customPerms.has(cp) && P.Admin.customPerms.has(cp)
  );
}
/**
 * A component hidden by a custom permission that an opt-in role set grants together with the component's
 * controller (e.g. the guest privacy panel): only holders of that role set ever see it, so it is a design
 * decision for every persona, not a gap. Returns the role set name, or null.
 */
function optInGated(page, lwc, cls) {
  const gate = page && page.gates && page.gates[lwc];
  if (!gate) return null;
  return (
    OPT_IN_SETS.find(
      (s) =>
        SETS[s] &&
        SETS[s].classes.has(cls) &&
        [...gate].some((cp) => SETS[s].customPerms.has(cp))
    ) || null
  );
}
const crud = (persona, obj) => {
  const o = P[persona].objects[obj] || {};
  return FLAGS.map((k) => (o[k] ? FLAG_LETTER[k] : "-")).join("");
};

// Objects
for (const o of objects.filter((x) => x.kind !== "standard")) {
  const row = { object: o.name, kind: o.kind };
  for (const p of PERSONAS) row[p] = crud(p, o.name);
  rows.objects.push(row);
  const a = P.Admin.objects[o.name] || {};
  const s = P.Staff.objects[o.name] || {};
  const po = P.Portal.objects[o.name];
  if (o.kind === "mdt" || o.kind === "setting") {
    // System-managed by design: Apex reads them in system context (getAll / getOrgDefaults), admins edit them
    // in Setup, and the access / licence / webhook secrets they hold stay out of every permission set.
    // Policy: no persona other than a deliberate Admin grant holds object access to them.
    for (const p of ["Staff", "Portal"]) {
      const g = P[p].objects[o.name] || {};
      for (const k of FLAGS)
        if (g[k])
          gap(
            p,
            "object",
            o.name,
            `system-managed ${o.kind} but ${p} has ${k}`
          );
    }
    continue;
  }
  const need = ["create", "read", "edit", "delete"];
  for (const k of need)
    if (!a[k]) gap("Admin", "object", o.name, `missing ${k}`);
  if (ADMIN_ONLY_OBJECTS.has(o.name)) {
    for (const k of FLAGS)
      if (s[k])
        gap("Staff", "object", o.name, `admin-only object but Staff has ${k}`);
  } else {
    if (o.kind !== "setting" && !s.read)
      gap("Staff", "object", o.name, "no Read");
    for (const k of ["viewAll", "modifyAll"])
      if (s[k]) gap("Staff", "object", o.name, `has ${k}`);
    if (FINANCIAL_OBJECTS.has(o.name) && s.delete)
      gap("Staff", "object", o.name, "can delete a financial record");
    if (STAFF_READONLY_OBJECTS.has(o.name)) {
      for (const k of ["create", "edit", "delete"])
        if (s[k])
          gap("Staff", "object", o.name, `read-only object but Staff has ${k}`);
    }
    if (
      o.kind === "custom" &&
      !FINANCIAL_OBJECTS.has(o.name) &&
      !STAFF_READONLY_OBJECTS.has(o.name)
    ) {
      for (const k of ["create", "edit"]) {
        if (a[k] && !s[k])
          gap(
            "Staff",
            "object",
            o.name,
            `cannot ${k} (Admin can; no muting reason)`
          );
      }
    }
  }
  if (po)
    for (const k of FLAGS)
      if (po[k]) gap("Portal", "object", o.name, `portal widening: has ${k}`);
}

// Fields
const fieldFlsStaff = (full) =>
  P.Staff.fields[full] || { read: false, edit: false };
for (const o of objects) {
  for (const f of o.fields) {
    if (!f.settable) continue;
    if (o.kind === "mdt" || o.kind === "setting") {
      for (const p of ["Staff", "Portal"]) {
        const fp = P[p].fields[f.full];
        if (fp && (fp.read || fp.edit))
          gap(p, "field", f.full, `system-managed ${o.kind} field granted`);
      }
      continue;
    }
    const row = { field: f.full, type: f.type, readOnly: f.readOnly };
    for (const p of PERSONAS) {
      const fp = P[p].fields[f.full];
      row[p] = fp ? (fp.edit ? "RE" : fp.read ? "R-" : "--") : "--";
    }
    rows.fields.push(row);
    if (EXCLUDED_FIELDS.has(f.full)) {
      for (const p of PERSONAS) {
        const fp = P[p].fields[f.full];
        if (fp && (fp.read || fp.edit))
          gap(
            p,
            "field",
            f.full,
            "secret field must stay excluded but is granted"
          );
      }
      continue;
    }
    const a = P.Admin.fields[f.full];
    const optIn = OPT_IN_SETS.some((x) => SETS[x] && SETS[x].fields[f.full]);
    if (!a || !a.read) {
      if (optIn)
        note(
          "Admin",
          "field",
          f.full,
          `only role set ${OPT_IN_SETS.join("/")} grants it`
        );
      else gap("Admin", "field", f.full, "not readable");
    } else if (!f.readOnly && !READONLY_BY_DESIGN.has(f.full) && !a.edit) {
      if (optIn)
        note(
          "Admin",
          "field",
          f.full,
          `edit only via role set ${OPT_IN_SETS.join("/")}`
        );
      else gap("Admin", "field", f.full, "not editable");
    }
    const s = fieldFlsStaff(f.full);
    if (a && a.read && !s.read && !ADMIN_ONLY_OBJECTS.has(o.name))
      gap("Staff", "field", f.full, "not readable");
    else if (
      !f.readOnly &&
      a &&
      a.edit &&
      !s.edit &&
      !ADMIN_ONLY_OBJECTS.has(o.name) &&
      (P.Staff.objects[o.name] || {}).edit
    ) {
      // Staff can edit records of this object but not this field.
      gap("Staff", "field", f.full, "not editable");
    }
    if (ADMIN_ONLY_OBJECTS.has(o.name) && (s.read || s.edit))
      gap("Staff", "field", f.full, "admin-only object field granted to Staff");
    const pf = P.Portal.fields[f.full];
    if (pf && (pf.read || pf.edit))
      gap("Portal", "field", f.full, "portal widening: field granted");
  }
}
// Fields granted but not in source (typos / deleted fields) - these would also break a deploy
{
  const known = new Set(objects.flatMap((o) => o.fields.map((f) => f.full)));
  for (const p of ["Admin", "Staff"]) {
    for (const k of Object.keys(P[p].fields)) {
      const [obj] = k.split(".");
      if (
        !known.has(k) &&
        objects.some((o) => o.name === obj && o.kind !== "standard")
      ) {
        gap(
          p,
          "field",
          k,
          "permission set references a field that is not in source"
        );
      }
    }
  }
}

// Apex classes
const portalClasses = new Set();
for (const s of [...PORTAL_SETS, ...OTHER_PORTAL_SETS])
  SETS[s].classes.forEach((c) => portalClasses.add(c));
// LWCs reachable from a site page (portal / public booking) are portal components.
const siteClosure = new Set();
(function walk() {
  const visit = (n) => {
    if (siteClosure.has(n) || !lwcs[n]) return;
    siteClosure.add(n);
    lwcs[n].children.forEach(visit);
  };
  Object.values(siteLwcs).forEach((set) => set.forEach(visit));
  Object.values(lwcs)
    .filter((l) => l.communityOnly)
    .forEach((l) => visit(l.name));
})();
const internalUse = (c) =>
  [...c.usedBy].some((u) =>
    u.startsWith("lwc:") ? !siteClosure.has(u.slice(4)) : true
  );
for (const c of Object.values(classes).filter((x) => x.entry)) {
  const restOnly = c.kinds.size === 1 && c.kinds.has("RestResource");
  const unused = !restOnly && c.usedBy.size === 0;
  const portalOnly =
    (portalClasses.has(c.name) && !internalUse(c)) ||
    (c.usedBy.size > 0 && !internalUse(c));
  const row = {
    class: c.name,
    pkg: c.pkg,
    kinds: [...c.kinds].join("+"),
    usedBy: [...c.usedBy].join(", ") || "-",
    audience: restOnly
      ? "external"
      : unused
        ? "unused"
        : portalOnly
          ? "portal"
          : "internal"
  };
  for (const p of PERSONAS) row[p] = P[p].classes.has(c.name) ? "Y" : "-";
  rows.classes.push(row);
  if (restOnly || unused) {
    // External callers (webhooks) and entry points nothing calls: no persona requirement, but never Portal-wide.
    if (restOnly && P.Staff.classes.has(c.name))
      gap(
        "Staff",
        "class",
        c.name,
        "webhook / REST class reachable by Staff (belongs in an admin or integration set)"
      );
    if (P.Portal.classes.has(c.name) && !portalClasses.has(c.name))
      gap("Portal", "class", c.name, "granted to a portal persona");
    continue;
  }
  if (portalOnly) {
    if (P.Staff.classes.has(c.name))
      gap("Staff", "class", c.name, "portal-only class granted to Staff");
    continue;
  }
  if (!P.Admin.classes.has(c.name)) {
    if (optInClass(c.name))
      note(
        "Admin",
        "class",
        c.name,
        `role set ${OPT_IN_SETS.join("/")} grants it (assigned separately)`
      );
    else gap("Admin", "class", c.name, "entry-point class not granted");
  }
  if (ADMIN_ONLY_CLASSES.has(c.name)) {
    if (P.Staff.classes.has(c.name))
      gap("Staff", "class", c.name, "admin-only class granted to Staff");
  } else if (P.Admin.classes.has(c.name) && !P.Staff.classes.has(c.name)) {
    if (addonClass(c.name)) {
      /* role add-on: usability is checked per tab and per page component below */
    } else gap("Staff", "class", c.name, "entry-point class not granted");
  }
  if (P.Portal.classes.has(c.name))
    gap(
      "Portal",
      "class",
      c.name,
      "internal class granted to a portal persona"
    );
}
// Portal controllers: each portal persona owns its own set
const PORTAL_EXPECT = {
  PMS_Customer_Portal: [
    "PMS_PortalController",
    "PMS_PortalMoneyController",
    "PMS_PortalV2Controller"
  ],
  PMS_Partner_Portal: ["PMS_PartnerPortalController"],
  PMS_Guest_Check_In: ["PMS_GuestCheckInController"],
  PMS_Public_Booking: ["PMS_PublicBookingController"]
};
for (const [set, expect] of Object.entries(PORTAL_EXPECT)) {
  for (const c of expect) {
    if (!SETS[set].classes.has(c))
      gap(
        "Portal",
        "class",
        `${set}: ${c}`,
        "portal controller missing from its set"
      );
  }
  for (const c of SETS[set].classes) {
    if (!expect.includes(c))
      gap("Portal", "class", `${set}: ${c}`, "class outside the portal design");
  }
}
// Site LWCs -> controllers must be granted to the persona that uses the site
const SITE_SET = {
  PMS_Booking1: "PMS_Public_Booking",
  PMS_Customer_Portal1: "PMS_Customer_Portal",
  PMS_Partner_Portal1: "PMS_Partner_Portal"
};
const sitePages = [];
for (const [site, set] of Object.entries(siteLwcs)) {
  for (const l of set_(siteLwcs[site])) {
    const needs = [...lwcApex(l)].sort();
    sitePages.push({ site, lwc: l, apex: needs });
    for (const a of needs) {
      const personaSets = [SITE_SET[site]].concat(
        site === "PMS_Booking1" ? ["PMS_Guest_Check_In"] : []
      );
      if (!personaSets.some((s) => SETS[s] && SETS[s].classes.has(a))) {
        gap(
          "Portal",
          "class",
          `${site}/${l} -> ${a}`,
          "site component needs a controller its persona set does not grant"
        );
      }
    }
  }
}
function set_(s) {
  return [...s];
}

for (const l of Object.values(lwcs).filter(
  (x) =>
    x.communityOnly && !Object.values(siteLwcs).some((set) => set.has(x.name))
)) {
  sitePages.push({
    site: "(Experience Builder)",
    lwc: l.name,
    apex: [...lwcApex(l.name)].sort()
  });
}

// Tabs
const usedTabs = new Set();
Object.values(apps).forEach((a) => a.tabs.forEach((t) => usedTabs.add(t)));
for (const t of [...usedTabs].sort()) {
  const row = { tab: t };
  for (const p of PERSONAS) row[p] = P[p].tabs[t] || "-";
  rows.tabs.push(row);
  const std = t.startsWith("standard-");
  if (!std && !TAB_RANK[P.Admin.tabs[t]] && !TAB_RANK[P.Admin.tabs[t]])
    gap("Admin", "tab", t, "tab not visible");
  if (!std && TAB_RANK[P.Admin.tabs[t]] === 0)
    gap("Admin", "tab", t, "tab set to None");
  const adminOnlyTab = t === "PMS_Access_Setup";
  if (
    !std &&
    !adminOnlyTab &&
    TAB_RANK[P.Admin.tabs[t]] &&
    !TAB_RANK[P.Staff.tabs[t]]
  ) {
    // A tab only a role add-on set grants (Rent Review) is hidden from Staff on purpose.
    if (ADDON_SETS.some((x) => TAB_RANK[SETS[x].tabs[t]]))
      note(
        "Staff",
        "tab",
        t,
        "hidden for Staff; the role add-on set grants it"
      );
    else gap("Staff", "tab", t, "tab not visible");
  }
  if (
    tabs[t] &&
    (tabs[t].flexiPage || tabs[t].lwc) &&
    TAB_RANK[P.Staff.tabs[t]]
  ) {
    const comps = tabs[t].lwc
      ? [tabs[t].lwc.replace(/^c:/, "")]
      : (flexipages[tabs[t].flexiPage] || { components: [] }).components;
    const pg = tabs[t].flexiPage ? flexipages[tabs[t].flexiPage] : null;
    for (const l of comps) {
      if (staffHidden(pg, l)) continue;
      for (const c of lwcApex(l)) {
        if (!P.Staff.classes.has(c))
          gap(
            "Staff",
            "tab",
            t,
            `visible but not usable: controller ${c} not granted to Staff`
          );
      }
    }
  }
  if (adminOnlyTab && TAB_RANK[P.Staff.tabs[t]])
    gap("Staff", "tab", t, "admin-only tab visible to Staff");
  if (TAB_RANK[P.Portal.tabs[t]])
    gap("Portal", "tab", t, "portal widening: tab visible");
}
// Apps
for (const a of Object.keys(apps).sort()) {
  const row = { app: a };
  for (const p of PERSONAS) row[p] = P[p].apps.has(a) ? "Y" : "-";
  rows.apps.push(row);
  if (!P.Admin.apps.has(a)) gap("Admin", "app", a, "app not visible");
  if (a !== "PMS_Admin" && !P.Staff.apps.has(a))
    gap("Staff", "app", a, "app not visible");
  if (P.Portal.apps.has(a))
    gap("Portal", "app", a, "portal widening: app visible");
}
// Record types
for (const o of objects) {
  for (const rt of o.recordTypes) {
    const row = { recordType: rt };
    for (const p of PERSONAS) row[p] = P[p].recordTypes.has(rt) ? "Y" : "-";
    rows.recordTypes.push(row);
    if (!P.Admin.recordTypes.has(rt))
      gap("Admin", "recordType", rt, "not visible");
    if (!P.Staff.recordTypes.has(rt))
      gap("Staff", "recordType", rt, "not visible");
  }
}
// Custom permissions
for (const cp of allCustomPerms.sort()) {
  const holders = Object.keys(SETS).filter((s) => SETS[s].customPerms.has(cp));
  const row = {
    permission: cp,
    checkedIn: [...(customPermRefs[cp] || [])].join(", ") || "-",
    heldBySets: holders.join(", ") || "-"
  };
  for (const p of PERSONAS) row[p] = P[p].customPerms.has(cp) ? "Y" : "-";
  rows.customPerms.push(row);
  if (NEGATIVE_CUSTOM_PERMS.has(cp)) {
    for (const p of PERSONAS)
      if (P[p].customPerms.has(cp))
        gap(p, "customPermission", cp, "negative switch granted by hand");
    continue;
  }
  if (!P.Admin.customPerms.has(cp)) {
    if (OPT_IN_SETS.some((x) => SETS[x] && SETS[x].customPerms.has(cp)))
      note(
        "Admin",
        "customPermission",
        cp,
        `role set ${OPT_IN_SETS.join("/")} grants it (assigned separately)`
      );
    else gap("Admin", "customPermission", cp, "not granted");
  }
  if (ADMIN_ONLY_CUSTOM_PERMS.has(cp) && P.Staff.customPerms.has(cp))
    gap(
      "Staff",
      "customPermission",
      cp,
      "admin-only permission granted to Staff"
    );
  if (P.Portal.customPerms.has(cp))
    gap("Portal", "customPermission", cp, "portal widening");
}
// Referenced but undefined custom permissions
for (const cp of Object.keys(customPermRefs)) {
  if (!allCustomPerms.includes(cp))
    gap(
      "Admin",
      "customPermission",
      cp,
      "checked in Apex but not defined in source"
    );
}

// App -> flexipage -> LWC -> Apex controllers
for (const a of Object.values(apps).sort((x, y) =>
  x.name.localeCompare(y.name)
)) {
  for (const pn of [...a.pages].sort()) {
    const fp = flexipages[pn];
    if (!fp) {
      rows.pages.push({
        app: a.name,
        page: pn,
        lwc: "(page not in source)",
        apex: []
      });
      continue;
    }
    // A page reached only through a tab is unreachable when the tab is hidden from Staff.
    const viaTab = Object.entries(tabs)
      .filter(([, v]) => v.flexiPage === pn)
      .map(([k]) => k);
    const pageHiddenForStaff =
      viaTab.length > 0 && viaTab.every((k) => !TAB_RANK[P.Staff.tabs[k]]);
    for (const l of fp.components.length
      ? fp.components
      : ["(no custom components)"]) {
      const needs = lwcs[l] ? [...lwcApex(l)].sort() : [];
      rows.pages.push({
        app: a.name,
        page: pn,
        lwc: l,
        apex: needs.map((c) => ({
          class: c,
          Admin: P.Admin.classes.has(c),
          Staff: P.Staff.classes.has(c),
          Portal: P.Portal.classes.has(c)
        }))
      });
      for (const c of needs) {
        if (!classes[c]) {
          gap(
            "Admin",
            "page",
            `${a.name}/${pn}/${l}`,
            `calls ${c}, which is not in source`
          );
          continue;
        }
        const optInSet = optInGated(fp, l, c);
        if (optInSet) {
          for (const p of ["Admin", "Staff"])
            if (!P[p].classes.has(c))
              note(
                p,
                "page",
                `${a.name}/${pn}/${l}`,
                `hidden by custom permission ${[...fp.gates[l]].join(", ")}; role set ${optInSet} grants it and ${c} (assigned separately)`
              );
          continue;
        }
        if (!P.Admin.classes.has(c))
          gap(
            "Admin",
            "page",
            `${a.name}/${pn}/${l}`,
            `controller ${c} not granted`
          );
        if (
          !ADMIN_ONLY_CLASSES.has(c) &&
          !P.Staff.classes.has(c) &&
          !pageHiddenForStaff
        ) {
          if (staffHidden(fp, l))
            note(
              "Staff",
              "page",
              `${a.name}/${pn}/${l}`,
              `hidden for Staff by custom permission ${[...fp.gates[l]].join(", ")} (add-on set grants it)`
            );
          else
            gap(
              "Staff",
              "page",
              `${a.name}/${pn}/${l}`,
              `visible but not usable: controller ${c} not granted to Staff`
            );
        }
      }
    }
  }
}
// Flows used by the agent
for (const f of agentFlows) {
  for (const c of flowApex[f] || []) {
    if (!P.Admin.classes.has(c))
      gap(
        "Admin",
        "flow",
        `${f} -> ${c}`,
        "agent flow action class not granted"
      );
  }
}

// ---------------------------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------------------------
const args = new Set(process.argv.slice(2));
if (args.has("--json")) {
  console.log(
    JSON.stringify(
      { personas: PERSONAS, rows, gaps, notes, sitePages },
      null,
      2
    )
  );
  process.exitCode = args.has("--check") && gaps.length ? 1 : 0;
  return;
}
const full = args.has("--full");
const table = (headers, data) => {
  const out = [
    `| ${headers.join(" | ")} |`,
    `| ${headers.map(() => "---").join(" | ")} |`
  ];
  for (const r of data)
    out.push(`| ${r.map((c) => String(c).replace(/\|/g, "/")).join(" | ")} |`);
  return out.join("\n");
};
const out = [];
out.push("# PMS access audit (from source)\n");
out.push(`Admin = ${ADMIN_SETS.join(" + ")}`);
out.push(
  `Staff = ${STAFF_GROUP} group (${GROUPS[STAFF_GROUP].sets.join(", ")}) minus ${GROUPS[STAFF_GROUP].muting.join(", ")}`
);
out.push(`Portal = ${[...PORTAL_SETS, ...OTHER_PORTAL_SETS].join(" + ")}\n`);
out.push(
  `Gaps: ${gaps.length} (Admin ${gaps.filter((g) => g.persona === "Admin").length}, Staff ${gaps.filter((g) => g.persona === "Staff").length}, Portal ${gaps.filter((g) => g.persona === "Portal").length})\n`
);

out.push(
  "## Objects (C=create R=read U=edit D=delete v=viewAll m=modifyAll)\n"
);
out.push(
  table(
    ["Object", "Kind", ...PERSONAS],
    rows.objects.map((r) => [r.object, r.kind, ...PERSONAS.map((p) => r[p])])
  )
);

out.push(
  "\n## Fields (RE=read+edit, R-=read only, --=none; applicable fields only)\n"
);
const fr = full ? rows.fields : [];
if (full)
  out.push(
    table(
      ["Field", "Type", ...PERSONAS],
      fr.map((r) => [
        r.field,
        r.type + (r.readOnly ? " (ro)" : ""),
        ...PERSONAS.map((p) => r[p])
      ])
    )
  );
else
  out.push(
    `${rows.fields.length} fields checked; ${gaps.filter((g) => g.kind === "field").length} field gaps (listed under Gaps). Use --full for the full matrix.`
  );

out.push("\n## Apex entry points (classAccess)\n");
out.push(
  table(
    ["Class", "Pkg", "Kind", "Audience", "Used by", ...PERSONAS],
    rows.classes.map((r) => [
      r.class,
      r.pkg,
      r.kinds,
      r.audience,
      r.usedBy,
      ...PERSONAS.map((p) => r[p])
    ])
  )
);

out.push("\n## Tabs used by apps\n");
out.push(
  table(
    ["Tab", ...PERSONAS],
    rows.tabs.map((r) => [r.tab, ...PERSONAS.map((p) => r[p])])
  )
);

out.push("\n## Apps\n");
out.push(
  table(
    ["App", ...PERSONAS],
    rows.apps.map((r) => [r.app, ...PERSONAS.map((p) => r[p])])
  )
);

out.push("\n## Record types\n");
out.push(
  table(
    ["Record type", ...PERSONAS],
    rows.recordTypes.map((r) => [r.recordType, ...PERSONAS.map((p) => r[p])])
  )
);

out.push("\n## Custom permissions\n");
out.push(
  table(
    ["Permission", "Checked in Apex", "Held by sets", ...PERSONAS],
    rows.customPerms.map((r) => [
      r.permission,
      r.checkedIn,
      r.heldBySets,
      ...PERSONAS.map((p) => r[p])
    ])
  )
);

out.push(
  "\n## App pages -> LWC -> Apex controller (A=Admin S=Staff P=Portal has classAccess)\n"
);
out.push(
  table(
    ["App", "Page", "LWC", "Apex controllers"],
    rows.pages.map((r) => [
      r.app,
      r.page,
      r.lwc,
      r.apex
        .map(
          (c) =>
            `${c.class} [${c.Admin ? "A" : "-"}${c.Staff ? "S" : "-"}${c.Portal ? "P" : "-"}]`
        )
        .join(", ") || "-"
    ])
  )
);

out.push("\n## Site pages -> LWC -> Apex controller (portal)\n");
out.push(
  table(
    ["Site", "LWC", "Apex"],
    sitePages.map((r) => [r.site, r.lwc, r.apex.join(", ") || "-"])
  )
);

out.push("\n## Gaps\n");
out.push(
  gaps.length
    ? table(
        ["Persona", "Kind", "Item", "Issue"],
        gaps.map((g) => [g.persona, g.kind, g.item, g.issue])
      )
    : "None."
);
out.push("\n## Design decisions (not failures)\n");
out.push(
  notes.length
    ? table(
        ["Persona", "Kind", "Item", "Note"],
        notes.map((g) => [g.persona, g.kind, g.item, g.issue])
      )
    : "None."
);
console.log(out.join("\n"));
if (args.has("--check") && gaps.length) process.exitCode = 1;
