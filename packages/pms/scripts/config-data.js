#!/usr/bin/env node
// Export / import PMS configuration records (see packages/pms/config-data/README.md).
// Called by scripts/pms-package.sh (config-export, config-import, bootstrap).
//
//   node config-data.js export <org> <data-dir> <ns|""> <work-dir>
//   node config-data.js import <org> <data-dir> <ns|""> <work-dir>   exit 10 = nothing imported
//   node config-data.js prefix <file> <ns|"">                        print file with PMS names namespaced
//
// Files are stored without a namespace; the namespace of the target org is added on import
// and removed on export.

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

// Configuration objects, in dependency order (parents first). Only the listed fields are
// exported: no secrets, no Last_Run/Channex sync state, no user or account lookups, no
// RecordTypeId. Name is left out for auto-number objects. Transactional data (bookings, invoices,
// payments, dunning events, logs) is deliberately not here.
const OBJECTS = [
  {
    sobject: "PMS_Dunning_Policy__c",
    fields:
      "Name, Active__c, Business_Late_Fee__c, Charge_Interest__c, Collections_Agency_Email__c, Collections_Days__c, Consumer_Reminder_Fee__c, Fee_In_Terms__c, Interest_Margin__c, Is_Default__c, Min_Days_Between__c, Minimum_Balance__c, Payment_Instructions__c, Plan_Grace_Days__c, Plan_Instalments__c, Plan_Offer_Days__c, Reference_Rate__c, Reminder_1_Days__c, Reminder_2_Days__c, Sender_Name__c"
  },
  {
    sobject: "PMS_Payment_Policy__c",
    fields:
      "Name, Active__c, Auto_Charge_Fees__c, Auto_Send_Card_Link__c, Deposit_Basis__c, Deposit_Due_Days__c, Deposit_Value__c, Fee_Tax_Rate__c, Free_Cancellation_Hours__c, Guarantee_Method__c, Guest_Terms__c, Late_Cancel_Basis__c, Late_Cancel_Value__c, No_Show_Basis__c, No_Show_Value__c, Preauth_Hours_Before__c, Release_Hold_On_Checkout__c"
  },
  {
    sobject: "PMS_Site__c",
    fields:
      "Name, Channex_Prices_Include_VAT__c, Check_In_Time__c, Check_Out_Time__c, City__c, Country__c, Currency_Code__c, Dunning_Policy__c, Management_Fee_Percent__c, Module__c, Payment_Policy__c, Phone__c, Postal_Code__c, Site_Type__c, Status__c, Street__c, Time_Zone__c"
  },
  {
    sobject: "PMS_Space_Type__c",
    fields:
      "Name, Channex_Room_Type_Id__c, Default_Occupancy__c, Default_Rate__c, Description__c, Site__c"
  },
  {
    sobject: "PMS_Rate_Plan__c",
    fields:
      "Name, Active__c, Cancellation_Policy__c, Currency_Code__c, Module__c, Payment_Policy__c, Pricing_Basis__c, Site__c, Tax_Rate__c, Valid_From__c, Valid_To__c"
  },
  {
    sobject: "PMS_Pricing_Strategy__c",
    fields:
      "Name, Active__c, Horizon_Days__c, Max_Change_Percent__c, Max_Percent__c, Max_Rate__c, Min_Percent__c, Min_Rate__c, Rate_Plan__c, Round_To__c"
  },
  {
    sobject: "PMS_Pricing_Factor__c",
    fields:
      "Name, Active__c, Adjust_Amount__c, Adjust_Percent__c, Date_From__c, Date_To__c, Days_Of_Week__c, Max_Value__c, Min_Value__c, Room_Type__c, Strategy__c, Type__c"
  },
  {
    sobject: "PMS_Channel_Mapping__c",
    fields:
      "Name, Active__c, Channex_Rate_Plan_Id__c, Rate_Plan__c, Room_Type__c, Site__c"
  },
  {
    sobject: "PMS_Index_Value__c",
    fields: "Month__c, Series__c, Source__c, Value__c, Year__c" // Name is auto-number
  },
  {
    sobject: "PMS_Access_Team__c",
    fields:
      "Name, Active__c, All_Internal_Users__c, Description__c, Hide_Amounts__c, Hide_Customer_Details__c"
  },
  {
    sobject: "PMS_Access_Rule__c",
    fields:
      "Access_Level__c, Active__c, Description__c, Module__c, Objects__c, Site__c, Team__c" // Name is auto-number
  },
  {
    // Hierarchy custom setting, org-wide row only. Webhook_Secret__c and the org-specific URLs
    // (Checkout_Return_URL__c, Public_Pay_URL__c) are never exported: fill them in per org.
    sobject: "PMS_Settings__c",
    fields: "Channex_Enabled__c, Channex_Horizon_Days__c",
    where: "SetupOwnerId = '{ORG_ID}'" // Id fields don't support LIKE; {ORG_ID} is filled in at run time
  }
];

// Never written to disk, whatever the query returns.
const SECRET_FIELD =
  /(^|_)(key|keys|token|tokens|secret|secrets|password|passwd|credential|credentials|apikey|signature)(_|$)/i;
const RAW_ID = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;
// Lookups between exported objects; a raw Id here means the parent was not exported.
const LOOKUPS =
  /^(Site|Team|Rate_Plan|Room_Type|Strategy|Payment_Policy|Dunning_Policy)__c$/;
const ALWAYS_DROP = new Set([
  "Id",
  "RecordTypeId",
  "OwnerId",
  "SetupOwnerId",
  "CreatedById",
  "LastModifiedById"
]);

const customToken =
  /(?<![A-Za-z0-9_])(?![A-Za-z0-9]+__[A-Za-z0-9_]+__(?:c|r|mdt)\b)([A-Za-z][A-Za-z0-9_]*?__(?:c|r|mdt))\b/g;
const addNs = (text, ns) =>
  ns ? text.replace(customToken, `${ns}__$1`) : text;
const stripNs = (text, ns) => (ns ? text.split(`${ns}__`).join("") : text);

function sf(args) {
  return execFileSync("sf", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, SF_DISABLE_AUTOUPDATE: "true" },
    maxBuffer: 64 * 1024 * 1024
  });
}

const orgIdCache = {};
function orgId(org) {
  if (!orgIdCache[org]) {
    const res = JSON.parse(
      sf([
        "data",
        "query",
        "-q",
        "SELECT Id FROM Organization",
        "-o",
        org,
        "--json"
      ])
    );
    orgIdCache[org] = res.result.records[0].Id;
  }
  return orgIdCache[org];
}

function withOrgId(where, org) {
  return where && where.includes("{ORG_ID}")
    ? where.split("{ORG_ID}").join(orgId(org))
    : where;
}

function countRecords(org, sobject, where) {
  where = withOrgId(where, org);
  const q = `SELECT COUNT() FROM ${sobject}${where ? ` WHERE ${where}` : ""}`;
  return JSON.parse(sf(["data", "query", "-q", q, "-o", org, "--json"])).result
    .totalSize;
}

function cmdExport(org, dataDir, ns, workDir) {
  fs.rmSync(workDir, { recursive: true, force: true });
  fs.mkdirSync(workDir, { recursive: true });
  const queries = OBJECTS.map((o) =>
    addNs(
      `SELECT Id, ${o.fields} FROM ${o.sobject}${o.where ? ` WHERE ${withOrgId(o.where, org)}` : ""}`,
      ns
    )
  );
  const args = ["data", "export", "tree", "--plan", "-o", org, "-d", workDir];
  queries.forEach((q) => args.push("-q", q));
  console.log(
    `Exporting ${OBJECTS.length} configuration objects from ${org}...`
  );
  try {
    sf(args);
  } catch (e) {
    console.error((e.stderr || e.message).toString());
    process.exit(1);
  }

  const planFile = fs
    .readdirSync(workDir)
    .find((f) => f === "plan.json" || f.endsWith("-plan.json"));
  if (!planFile) {
    console.log("No records found; nothing exported.");
    process.exit(0);
  }
  const plan = JSON.parse(
    stripNs(fs.readFileSync(path.join(workDir, planFile), "utf8"), ns)
  );
  const stripped = new Set();
  const outPlan = [];
  const keep = [];
  fs.mkdirSync(dataDir, { recursive: true });

  // Rebuild in OBJECTS order so file names and the plan are stable between exports.
  for (const entry of plan) {
    const sobject = entry.sobject;
    const records = [];
    for (const f of entry.files) {
      const data = JSON.parse(
        stripNs(fs.readFileSync(path.join(workDir, f), "utf8"), ns)
      );
      records.push(...(data.records || []));
    }
    if (!records.length) continue;
    for (const r of records) {
      for (const key of Object.keys(r)) {
        if (key === "attributes") continue;
        const bare = key.replace(/__[cr]$/, "");
        if (ALWAYS_DROP.has(key)) delete r[key];
        else if (SECRET_FIELD.test(bare)) {
          stripped.add(`${sobject}.${key}`);
          delete r[key];
        } else if (
          LOOKUPS.test(key) &&
          typeof r[key] === "string" &&
          !r[key].startsWith("@") &&
          RAW_ID.test(r[key])
        ) {
          // A lookup value that did not resolve to another exported record: drop it.
          delete r[key];
        }
      }
    }
    const idx = String(
      OBJECTS.findIndex((o) => o.sobject === sobject) + 1
    ).padStart(2, "0");
    const file = `${idx}-${sobject}.json`;
    fs.writeFileSync(
      path.join(dataDir, file),
      JSON.stringify({ records }, null, 2) + "\n"
    );
    keep.push(file);
    outPlan.push({
      sobject,
      saveRefs: true,
      resolveRefs: true,
      files: [file]
    });
  }
  outPlan.sort((a, b) => a.files[0].localeCompare(b.files[0]));
  fs.writeFileSync(
    path.join(dataDir, "plan.json"),
    JSON.stringify(outPlan, null, 2) + "\n"
  );
  // Remove stale per-object files from earlier exports.
  for (const f of fs.readdirSync(dataDir)) {
    if (/^\d\d-PMS_.*\.json$/.test(f) && !keep.includes(f))
      fs.unlinkSync(path.join(dataDir, f));
  }
  console.log(`Wrote ${keep.length} files and plan.json to ${dataDir}:`);
  outPlan.forEach((e) => console.log(`  ${e.sobject}`));
  if (stripped.size)
    console.log(`Stripped secret-looking fields: ${[...stripped].join(", ")}`);
}

function cmdImport(org, dataDir, ns, workDir) {
  const planPath = path.join(dataDir, "plan.json");
  if (!fs.existsSync(planPath)) {
    console.log(`No ${planPath}; run config-export in a configured org first.`);
    process.exit(10);
  }
  const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
  fs.rmSync(workDir, { recursive: true, force: true });
  fs.mkdirSync(workDir, { recursive: true });

  const skipped = [];
  const outPlan = [];
  const where = Object.fromEntries(OBJECTS.map((o) => [o.sobject, o.where]));
  for (const entry of plan) {
    const text = entry.files
      .map((f) => fs.readFileSync(path.join(dataDir, f), "utf8"))
      .join("\n");
    // A file that references a skipped object (@<Object>Ref1) cannot resolve it: skip it too.
    const blocked = skipped.find((s) => text.includes(`"@${s.sobject}Ref`));
    let existing = 0;
    try {
      existing = countRecords(
        org,
        addNs(entry.sobject, ns),
        where[entry.sobject] && addNs(where[entry.sobject], ns)
      );
    } catch (e) {
      console.error(
        `Cannot query ${entry.sobject} in ${org}: ${(e.stderr || e.message).toString().trim()}`
      );
      process.exit(1);
    }
    if (existing > 0) {
      console.warn(
        `warning: ${entry.sobject} already has ${existing} record(s) in ${org}; skipping.`
      );
      skipped.push({ sobject: entry.sobject, reason: "exists" });
      continue;
    }
    if (blocked) {
      console.warn(
        `warning: ${entry.sobject} references skipped ${blocked.sobject}; skipping.`
      );
      skipped.push({ sobject: entry.sobject, reason: "dependency" });
      continue;
    }
    const files = entry.files.map((f) => {
      fs.writeFileSync(
        path.join(workDir, f),
        addNs(fs.readFileSync(path.join(dataDir, f), "utf8"), ns)
      );
      return f;
    });
    outPlan.push({ ...entry, sobject: addNs(entry.sobject, ns), files });
  }
  if (!outPlan.length) {
    console.log("Nothing to import.");
    process.exit(10);
  }
  const workPlan = path.join(workDir, "plan.json");
  fs.writeFileSync(workPlan, JSON.stringify(outPlan, null, 2));
  console.log(`Importing: ${outPlan.map((e) => e.sobject).join(", ")}`);
  try {
    console.log(sf(["data", "import", "tree", "--plan", workPlan, "-o", org]));
  } catch (e) {
    console.error(
      (e.stdout || "").toString() + (e.stderr || e.message).toString()
    );
    process.exit(1);
  }
  console.log(
    "Not imported by design: Webhook_Secret__c, Stripe/Channex credentials, Checkout_Return_URL__c, Public_Pay_URL__c. Set them per org."
  );
}

const [cmd, ...rest] = process.argv.slice(2);
if (cmd === "export" && rest.length === 4) cmdExport(...rest);
else if (cmd === "import" && rest.length === 4) cmdImport(...rest);
else if (cmd === "prefix" && rest.length === 2) {
  process.stdout.write(addNs(fs.readFileSync(rest[0], "utf8"), rest[1]));
} else {
  console.error(
    'Usage: config-data.js export|import <org> <data-dir> <ns|""> <work-dir> | prefix <file> <ns|"">'
  );
  process.exit(1);
}
