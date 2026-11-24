// Builds the shipped content.json from its sources:
//   content/base.json        config, tables (days, tasks, endings...) and anchor events
//   content/events/*.json    arrays of extra events, merged in filename order
// Usage: node tools/build-content.mjs             (write Core/.../Resources/content.json)
//        node tools/build-content.mjs --validate  (merge in memory and lint; writes nothing)
//        node tools/build-content.mjs --check     (fail if the shipped file is stale)
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { validate, DEFAULT_CONTENT } from "./validate.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SRC = resolve(here, "../content");

export function buildContent() {
  const base = JSON.parse(readFileSync(join(SRC, "base.json"), "utf8"));
  const dir = join(SRC, "events");
  const files = readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith(".")).sort();
  const events = [...base.events];
  for (const f of files) {
    let arr;
    try {
      arr = JSON.parse(readFileSync(join(dir, f), "utf8"));
    } catch (e) {
      throw new Error(`content/events/${f}: invalid JSON (${e.message})`);
    }
    if (!Array.isArray(arr)) throw new Error(`content/events/${f}: must be a JSON array of events`);
    events.push(...arr);
  }
  return { ...base, events };
}

export function serialize(content) {
  return JSON.stringify(content, null, 1) + "\n";
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  let content;
  try {
    content = buildContent();
  } catch (e) {
    console.log(`ERROR: ${e.message}`);
    process.exit(1);
  }
  const { errors, warnings, stats } = validate(content);
  if (args.includes("--validate")) {
    for (const w of warnings) console.log(`warning: ${w}`);
    for (const e of errors) console.log(`ERROR: ${e}`);
    console.log(`${stats.events} events (${stats.night} night, ${stats.hazards} hazards), ${errors.length} errors, ${warnings.length} warnings`);
    process.exit(errors.length ? 1 : 0);
  }
  const out = serialize(content);
  if (args.includes("--check")) {
    const cur = existsSync(DEFAULT_CONTENT) ? readFileSync(DEFAULT_CONTENT, "utf8") : "";
    if (cur !== out) {
      console.log("content.json is stale: run `node tools/build-content.mjs` and commit it.");
      process.exit(1);
    }
    console.log("content.json is up to date.");
  } else {
    if (errors.length) {
      for (const e of errors) console.log(`ERROR: ${e}`);
      console.log("Not written: fix the errors above.");
      process.exit(1);
    }
    writeFileSync(DEFAULT_CONTENT, out);
    console.log(`wrote ${DEFAULT_CONTENT} (${stats.events} events, ${warnings.length} warnings)`);
  }
}
