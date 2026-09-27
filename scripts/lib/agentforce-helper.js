#!/usr/bin/env node
// Helper for scripts/sf-agentforce.sh. Reads `sf ... --json` output and edits
// package.xml manifests in place (keeps existing formatting and comments).
//
//   node agentforce-helper.js report <retrieve|deploy|delete> <json-file>
//   node agentforce-helper.js components <json-file>
//   node agentforce-helper.js names <json-file>
//   node agentforce-helper.js manifest-add <manifest> <Type> <Name>
//   node agentforce-helper.js manifest-remove <manifest> <Type> <Name>
//   node agentforce-helper.js manifest-remove-everywhere <Type> <Name>

"use strict";

const fs = require("fs");
const path = require("path");

// Child types are covered by their parent in a manifest (Bot covers BotVersion).
const SKIP_IN_MANIFEST = new Set(["BotVersion"]);

const toArray = (value) =>
  value === undefined || value === null ? [] : [].concat(value);

function readJson(file) {
  const text = fs.readFileSync(file, "utf8").trim();
  if (!text) {
    return { status: 1, message: "The sf command produced no output." };
  }
  try {
    return JSON.parse(text);
  } catch {
    return { status: 1, message: text.slice(0, 2000) };
  }
}

function packageDirectories() {
  const project = JSON.parse(fs.readFileSync("sfdx-project.json", "utf8"));
  return (project.packageDirectories || []).map((dir) =>
    dir.path.replace(/\/+$/, "")
  );
}

function packageDirFor(filePath) {
  const relative = path
    .relative(process.cwd(), filePath)
    .split(path.sep)
    .join("/");
  return packageDirectories()
    .filter((dir) => relative === dir || relative.startsWith(`${dir}/`))
    .sort((a, b) => b.length - a.length)[0];
}

function relative(filePath) {
  return filePath ? path.relative(process.cwd(), filePath) : "";
}

// ---------------------------------------------------------------------------
// report: print a readable summary; exit 1 when the operation failed
// ---------------------------------------------------------------------------
function report(mode, file) {
  const json = readJson(file);
  const result = json.result || {};
  const details = result.details || {};
  const files = toArray(result.files);

  const failures = [
    ...toArray(details.componentFailures).map(
      (f) => `${f.componentType || ""} ${f.fullName || ""}: ${f.problem}`
    ),
    ...files
      .filter((f) => f.state === "Failed")
      .map((f) => `${f.type} ${f.fullName}: ${f.error || "failed"}`),
    ...toArray(result.messages).map(
      (m) => `${m.fileName || ""}: ${m.problem || JSON.stringify(m)}`
    ),
    ...toArray(details.runTestResult && details.runTestResult.failures).map(
      (t) => `Test ${t.name}.${t.methodName}: ${t.message}`
    )
  ];
  // The same problem is often reported per file and for package.xml; show it once.
  const seenProblems = new Set();
  const unique = failures.filter((f) => {
    const problem = f.slice(f.indexOf(": ") + 2);
    if (seenProblems.has(problem)) return false;
    seenProblems.add(problem);
    return true;
  });

  const ok = files.filter((f) => f.state !== "Failed");
  if (ok.length) {
    console.log("");
    const rows = ok.map((f) => [
      f.state || "",
      f.type || "",
      f.fullName || "",
      relative(f.filePath)
    ]);
    const widths = [0, 1, 2].map((i) =>
      Math.max(...rows.map((r) => r[i].length))
    );
    for (const row of rows) {
      console.log(
        `  ${row
          .slice(0, 3)
          .map((c, i) => c.padEnd(widths[i]))
          .join("  ")}  ${row[3]}`
      );
    }
  }

  if (mode === "delete") {
    const deleted = toArray(details.componentSuccesses).filter(
      (c) => c.fullName && c.fullName !== "package.xml"
    );
    for (const c of deleted) {
      console.log(`  Deleted  ${c.componentType}  ${c.fullName}`);
    }
  }

  const warnings = toArray(json.warnings);
  for (const w of warnings) {
    console.log(`  Warning: ${w}`);
  }

  const status = result.status;
  const failed =
    json.status !== 0 ||
    unique.length > 0 ||
    (status && !/^Succeeded$/.test(status)) ||
    (mode === "retrieve" && ok.length === 0);

  if (failed) {
    console.log("");
    console.log(
      `✖ ${mode} failed${status && status !== "Succeeded" ? ` (${status})` : ""}.`
    );
    if (json.message && json.status !== 0) {
      console.log(`  ${json.message}`);
    }
    for (const f of unique) {
      console.log(`  - ${f}`);
    }
    if (
      mode === "retrieve" &&
      ok.length === 0 &&
      !unique.length &&
      !json.message
    ) {
      console.log(
        '  Nothing was retrieved. Check the type and API name (run the "list" command).'
      );
    }
    process.exit(1);
  }
  console.log("");
  console.log(`✔ ${mode} succeeded.`);
}

// ---------------------------------------------------------------------------
// components: "Type<TAB>Name<TAB>packageDir" for every retrieved/deployed item
// ---------------------------------------------------------------------------
function components(file) {
  const json = readJson(file);
  const seen = new Set();
  for (const f of toArray(json.result && json.result.files)) {
    if (
      f.state === "Failed" ||
      !f.type ||
      !f.fullName ||
      SKIP_IN_MANIFEST.has(f.type)
    ) {
      continue;
    }
    const key = `${f.type}\t${f.fullName}`;
    if (seen.has(key)) continue;
    seen.add(key);
    console.log(`${key}\t${f.filePath ? packageDirFor(f.filePath) || "" : ""}`);
  }
}

// names: fullNames from `sf org list metadata --json`, sorted
function names(file) {
  const json = readJson(file);
  toArray(json.result)
    .map((r) => r.fullName)
    .filter(Boolean)
    .sort((a, b) => a.localeCompare(b))
    .forEach((n) => console.log(n));
}

// ---------------------------------------------------------------------------
// Manifest editing
// ---------------------------------------------------------------------------
const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function typeBlocks(text, type) {
  const blocks = [];
  const re = /<types>[\s\S]*?<\/types>/g;
  let match;
  while ((match = re.exec(text))) {
    const nameMatch = match[0].match(/<name>\s*([^<]+?)\s*<\/name>/);
    if (nameMatch && nameMatch[1] === type) {
      const members = [
        ...match[0].matchAll(/<members>\s*([^<]+?)\s*<\/members>/g)
      ].map((m) => m[1]);
      blocks.push({
        start: match.index,
        end: match.index + match[0].length,
        text: match[0],
        members
      });
    }
  }
  return blocks;
}

function newManifest() {
  let version = "67.0";
  try {
    version =
      JSON.parse(fs.readFileSync("sfdx-project.json", "utf8"))
        .sourceApiVersion || version;
  } catch {
    // keep default
  }
  return [
    '<?xml version="1.0" encoding="UTF-8" ?>',
    '<Package xmlns="http://soap.sforce.com/2006/04/metadata">',
    `    <version>${version}</version>`,
    "</Package>",
    ""
  ].join("\n");
}

function manifestAdd(manifest, type, name) {
  let text = fs.existsSync(manifest)
    ? fs.readFileSync(manifest, "utf8")
    : newManifest();
  const blocks = typeBlocks(text, type);

  if (blocks.some((b) => b.members.includes(name) || b.members.includes("*"))) {
    console.log(`  = ${manifest}: ${type}:${name} already included`);
    return;
  }

  if (blocks.length) {
    // Insert a <members> line just above <name> in the first matching block.
    const block = blocks[0];
    const nameLine = block.text.match(/([ \t]*)<name>/);
    const memberIndent =
      (block.text.match(/\n([ \t]*)<members>/) || [])[1] ?? nameLine[1];
    const updated = block.text.replace(
      /([ \t]*)<name>/,
      `${memberIndent}<members>${name}</members>\n$1<name>`
    );
    text = text.slice(0, block.start) + updated + text.slice(block.end);
  } else {
    // Add a new <types> block just above <version>.
    const versionMatch = text.match(/\n([ \t]*)<version>/);
    if (!versionMatch) {
      throw new Error(
        `${manifest} has no <version> element; fix it by hand first.`
      );
    }
    const indent = versionMatch[1] || "    ";
    const inner = indent.includes("\t") ? `${indent}\t` : `${indent}    `;
    const block = `\n${indent}<types>\n${inner}<members>${name}</members>\n${inner}<name>${type}</name>\n${indent}</types>`;
    text =
      text.slice(0, versionMatch.index) +
      block +
      text.slice(versionMatch.index);
  }

  fs.mkdirSync(path.dirname(manifest), { recursive: true });
  fs.writeFileSync(manifest, text);
  console.log(`  + ${manifest}: added ${type}:${name}`);
}

function manifestRemove(manifest, type, name, quietIfMissing = false) {
  if (!fs.existsSync(manifest)) {
    if (!quietIfMissing) console.log(`  = ${manifest} does not exist`);
    return false;
  }
  let text = fs.readFileSync(manifest, "utf8");
  const blocks = typeBlocks(text, type);
  let changed = false;

  // Walk backwards so earlier offsets stay valid.
  for (const block of blocks.reverse()) {
    if (!block.members.includes(name)) {
      if (block.members.includes("*") && !quietIfMissing) {
        console.log(
          `  = ${manifest}: ${type} uses "*", nothing to remove for ${name}`
        );
      }
      continue;
    }
    const memberLine = new RegExp(
      `[ \\t]*<members>\\s*${escapeRegex(name)}\\s*</members>[ \\t]*\\r?\\n?`,
      "g"
    );
    let updated = block.text.replace(memberLine, "");
    let start = block.start;
    let end = block.end;
    if (!/<members>/.test(updated)) {
      // Drop the now-empty block together with its indentation and line break.
      updated = "";
      while (start > 0 && /[ \t]/.test(text[start - 1])) start--;
      if (text[end] === "\r") end++;
      if (text[end] === "\n") end++;
    }
    text = text.slice(0, start) + updated + text.slice(end);
    changed = true;
  }

  if (changed) {
    fs.writeFileSync(manifest, text);
    console.log(`  - ${manifest}: removed ${type}:${name}`);
  } else if (!quietIfMissing) {
    console.log(`  = ${manifest}: ${type}:${name} was not listed`);
  }
  return changed;
}

function manifestRemoveEverywhere(type, name) {
  let any = false;
  for (const dir of packageDirectories()) {
    any =
      manifestRemove(
        path.join(dir, "manifest", "package.xml"),
        type,
        name,
        true
      ) || any;
  }
  if (!any)
    console.log(`  = ${type}:${name} was not listed in any package manifest`);
}

// ---------------------------------------------------------------------------
const [command, ...args] = process.argv.slice(2);
try {
  switch (command) {
    case "report":
      report(args[0], args[1]);
      break;
    case "components":
      components(args[0]);
      break;
    case "names":
      names(args[0]);
      break;
    case "manifest-add":
      manifestAdd(args[0], args[1], args[2]);
      break;
    case "manifest-remove":
      manifestRemove(args[0], args[1], args[2]);
      break;
    case "manifest-remove-everywhere":
      manifestRemoveEverywhere(args[0], args[1]);
      break;
    default:
      console.error(`Unknown helper command: ${command}`);
      process.exit(2);
  }
} catch (error) {
  console.error(`Error: ${error.message}`);
  process.exit(1);
}
