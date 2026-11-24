// Content linter for schema v2 (the week). Catches authoring mistakes before
// they reach the engines. Usage: node tools/validate.mjs [path/to/content.json]
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { METERS } from "./engine.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_CONTENT = resolve(here, "../Core/Sources/BedtimeCore/Resources/content.json");

const LIMITS = { title: 44, text: 300, label: 64, outcome: 300 };
const COND_VARS = new Set([...METERS, "day", "ledger"]);
const RANGES = { day: [0, 4], ledger: [-200, 200] };
const STRONG_PROFANITY = /\b(fuck\w*|shit\w*|cunt\w*|motherf\w*|bitch\w*)\b/i;
const GENDERED_PARTNER = /\b(husband|wife|boyfriend|girlfriend|hubby|wifey)\b/i;

export function validate(content) {
  const errors = [];
  const warnings = [];
  const err = (m) => errors.push(m);
  const warn = (m) => warnings.push(m);
  const isInt = Number.isInteger;
  const isPosInt = (n) => isInt(n) && n > 0;

  const cfg = content.config ?? {};
  const events = content.events ?? [];
  const eventIds = new Map(events.map((e) => [e.id, e]));
  const taskIds = new Set((content.tasks ?? []).map((t) => t.id));
  const counterIds = new Set((content.counters ?? []).map((c) => c.id));
  const styleIds = new Set((content.styles ?? []).map((s) => s.id));
  const tagIds = new Set([...styleIds, "present"]);
  const endingIds = new Set(Object.keys(content.endings ?? {}));
  const flagsSet = new Set();
  const flagsRead = [];
  const forcedRefs = new Set();

  const meterMap = (where, obj, allowCond = false) => {
    for (const [k, v] of Object.entries(obj ?? {})) {
      const ok = allowCond ? COND_VARS.has(k) : METERS.includes(k);
      if (!ok) err(`${where}: unknown ${allowCond ? "condition variable" : "meter"} "${k}"`);
      if (!isInt(v)) err(`${where}: value for "${k}" must be an integer`);
    }
  };
  const cond = (where, c) => {
    if (c == null) return;
    for (const k of Object.keys(c)) if (!["flags", "notFlags", "min", "max"].includes(k)) err(`${where}: unknown condition key "${k}"`);
    meterMap(`${where}.min`, c.min, true);
    meterMap(`${where}.max`, c.max, true);
    for (const f of [...(c.flags ?? []), ...(c.notFlags ?? [])]) flagsRead.push([where, f]);
  };
  const len = (where, kind, s) => {
    if (typeof s !== "string" || s.length === 0) return err(`${where}: missing ${kind}`);
    if (s.length > LIMITS[kind]) warn(`${where}: ${kind} is ${s.length} chars (limit ${LIMITS[kind]})`);
    if (STRONG_PROFANITY.test(s)) err(`${where}: strong profanity must be bleeped ("[BLEEP]")`);
    if (GENDERED_PARTNER.test(s)) warn(`${where}: the partner is never gendered ("your partner")`);
  };
  const eventRef = (where, id, mustBeForced = true) => {
    const ev = eventIds.get(id);
    if (!ev) return err(`${where}: unknown event "${id}"`);
    forcedRefs.add(id);
    if (mustBeForced && !ev.forced) warn(`${where}: "${id}" is referenced but not marked forced (it can also appear randomly)`);
  };

  // Outcome coverage: when every outcome has a `when`, they must cover every
  // value of a single variable, or the engine can find no outcome.
  const coverage = (where, outcomes) => {
    const conds = outcomes.map((o) => o.when);
    if (conds.some((c) => c == null)) return;
    const vars = new Set();
    for (const c of conds) {
      if ((c.flags?.length ?? 0) + (c.notFlags?.length ?? 0) > 0) return warn(`${where}: every outcome has a flag condition; add one without "when" as a fallback`);
      for (const k of [...Object.keys(c.min ?? {}), ...Object.keys(c.max ?? {})]) vars.add(k);
    }
    if (vars.size !== 1) return err(`${where}: when all outcomes have "when", they must test exactly one variable (found ${[...vars].join(", ") || "none"})`);
    const v = [...vars][0];
    const [lo, hi] = RANGES[v] ?? [0, 100];
    for (let x = lo; x <= hi; x++) {
      const hit = conds.some((c) => (c.min?.[v] ?? -Infinity) <= x && x <= (c.max?.[v] ?? Infinity));
      if (!hit) return err(`${where}: no outcome applies when ${v} = ${x}`);
    }
  };

  // ---- config ----
  for (const k of ["eventGap", "bedtimeClock"]) if (!isInt(cfg[k])) err(`config.${k} must be an integer`);
  if (!Array.isArray(cfg.wake) || cfg.wake.length !== 3) err("config.wake must list 3 wake clocks (one per debt band)");
  for (const m of METERS) if (!isInt(cfg.startMeters?.[m])) err(`config.startMeters.${m} missing`);
  for (const [i, r] of (cfg.drift ?? []).entries()) {
    if (!METERS.includes(r.meter)) err(`config.drift[${i}]: unknown meter`);
    if (!isPosInt(r.every) || !isInt(r.delta)) err(`config.drift[${i}]: every/delta must be integers`);
    cond(`config.drift[${i}].when`, r.when);
  }
  meterMap("config.bedtime.asleep", cfg.bedtime?.asleep);
  meterMap("config.bedtime.awake", cfg.bedtime?.awake);
  if (cfg.bedtime?.awakeFlag) flagsSet.add(cfg.bedtime.awakeFlag);
  if (cfg.night?.lateCoffeeFlag) flagsRead.push(["config.night.lateCoffeeFlag", cfg.night.lateCoffeeFlag]);
  for (const f of cfg.snap?.set ?? []) flagsSet.add(f);
  meterMap("config.snap.effects", cfg.snap?.effects);
  for (const m of cfg.lossOrder ?? []) if (!METERS.includes(m)) err(`config.lossOrder: unknown meter ${m}`);
  for (const e of Object.values(cfg.losses ?? {})) if (!endingIds.has(e)) err(`config.losses: unknown ending ${e}`);
  meterMap("config.weekScore", cfg.weekScore);
  const grades = cfg.grades ?? [];
  for (let i = 1; i < grades.length; i++) if (grades[i].min >= grades[i - 1].min) err("config.grades must be sorted by descending min");
  if (!grades.length || grades[grades.length - 1].min !== 0) err("config.grades: last grade must have min 0");
  for (const g of grades) if (!endingIds.has(g.id)) err(`config.grades: unknown ending ${g.id}`);

  // ---- tables ----
  for (const m of METERS) if (!content.meters?.[m]) err(`meters: missing display name for "${m}"`);
  if ((content.days ?? []).length !== 5) err("days: need exactly 5 (Monday to Friday)");
  const modIds = new Set((content.modifiers ?? []).map((m) => m.id));
  for (const [i, d] of (content.days ?? []).entries()) {
    if (d.modifier !== "random" && !modIds.has(d.modifier)) err(`days[${i}]: unknown modifier ${d.modifier}`);
    for (const t of d.tasks ?? []) if (!taskIds.has(t)) err(`days[${i}]: unknown task ${t}`);
  }
  if (!(content.modifiers ?? []).some((m) => m.pool)) err("modifiers: at least one needs pool: true (for random days)");
  for (const m of content.modifiers ?? []) {
    meterMap(`modifier "${m.id}".effects`, m.effects);
    for (const f of m.set ?? []) flagsSet.add(f);
    len(`modifier "${m.id}"`, "text", m.text);
  }
  for (const t of content.tasks ?? []) {
    if (!(t.dueDay >= 0 && t.dueDay <= 4) || !isInt(t.dueClock)) err(`task "${t.id}": dueDay 0-4 and integer dueClock required`);
    if (t.expire) eventRef(`task "${t.id}".expire`, t.expire);
    if (!events.some((e) => e.task === t.id)) warn(`task "${t.id}": no event lets the player do it (add an event with "task": "${t.id}")`);
  }
  meterMap("lifeline.effects", content.lifeline?.effects);
  for (const f of content.lifeline?.set ?? []) flagsSet.add(f);

  // ---- events ----
  const seen = new Set();
  let fillers = 0;
  for (const e of events) {
    const w = `event "${e.id}"`;
    if (seen.has(e.id)) err(`${w}: duplicate id`);
    seen.add(e.id);
    len(w, "title", e.title);
    len(w, "text", e.text);
    const phase = e.phase ?? "day";
    if (!["day", "night"].includes(phase)) err(`${w}: phase must be day or night`);
    if (e.hazard && !["sting", "catastrophe"].includes(e.hazard)) err(`${w}: hazard must be sting or catastrophe`);
    if (e.tell) eventRef(`${w}.tell`, e.tell);
    if (e.task && !taskIds.has(e.task)) err(`${w}: unknown task ${e.task}`);
    const randomDay = phase === "day" && !e.forced && !e.hazard;
    if (randomDay) {
      if (!Array.isArray(e.window) || e.window.length !== 2 || !(e.window[0] <= e.window[1])) err(`${w}: day events need window [from, to] (minutes since midnight)`);
    }
    if (e.weight !== undefined && !isPosInt(e.weight)) err(`${w}: weight must be a positive integer`);
    if (e.weightBy && (!e.weightBy.counter || !isPosInt(e.weightBy.every))) err(`${w}: weightBy needs counter and every`);
    if (e.filler) fillers++;
    cond(`${w}.when`, e.when);
    for (const [i, c] of (e.checks ?? []).entries()) {
      cond(`${w}.checks[${i}].when`, c.when);
      if (!endingIds.has(c.ending)) err(`${w}.checks[${i}]: unknown ending ${c.ending}`);
    }
    const choices = e.choices ?? [];
    if (choices.length < 1 || choices.length > 4) err(`${w}: needs 1-4 choices`);
    if (!choices.some((c) => !c.when && !c.minEnergy)) err(`${w}: needs at least one choice with no "when" and no "minEnergy" (so the player is never stuck)`);
    choices.forEach((c, ci) => {
      const cw = `${w} choice ${ci}`;
      len(cw, "label", c.label);
      if (!isPosInt(c.duration)) err(`${cw}: duration must be a positive integer (minutes)`);
      if (c.minEnergy !== undefined && !(isInt(c.minEnergy) && c.minEnergy >= 0 && c.minEnergy <= 100)) err(`${cw}: minEnergy must be 0-100`);
      for (const t of c.tags ?? []) if (!tagIds.has(t)) err(`${cw}: unknown tag "${t}" (styles or "present")`);
      cond(`${cw}.when`, c.when);
      if (!Array.isArray(c.outcomes) || c.outcomes.length < 1) err(`${cw}: needs at least one outcome`);
      coverage(cw, c.outcomes ?? []);
      (c.outcomes ?? []).forEach((o, oi) => {
        const ow = `${cw} outcome ${oi}`;
        len(ow, "outcome", o.text);
        if (o.weight !== undefined && !isPosInt(o.weight)) err(`${ow}: weight must be a positive integer`);
        cond(`${ow}.when`, o.when);
        meterMap(`${ow}.effects`, o.effects);
        for (const f of o.set ?? []) flagsSet.add(f);
        for (const [k, v] of Object.entries(o.count ?? {})) {
          if (!counterIds.has(k)) err(`${ow}: counter "${k}" is not declared in "counters"`);
          if (!isInt(v)) err(`${ow}: counter "${k}" must be an integer`);
        }
        for (const [cat, who] of Object.entries(o.ledger ?? {})) if (!["you", "partner"].includes(who)) err(`${ow}: ledger.${cat} must be "you" or "partner"`);
        for (const s of o.schedule ?? []) {
          eventRef(`${ow}.schedule`, s.event);
          if (!(isInt(s.in) && s.in >= 0)) err(`${ow}: schedule.in must be a non-negative integer`);
        }
        for (const id of o.cancel ?? []) if (!eventIds.has(id)) err(`${ow}: cancel refers to unknown event ${id}`);
        if (o.completeTask && o.completeTask !== "oldest" && !taskIds.has(o.completeTask)) err(`${ow}: unknown task ${o.completeTask}`);
      });
    });
  }
  if (fillers !== 1) err(`exactly one filler event required (found ${fillers})`);
  if (!events.some((e) => e.endsDay)) err("need an endsDay (bedtime) event");
  if (!events.some((e) => e.endsWeek)) err("need an endsWeek (date night) event");
  const nightFree = events.filter((e) => e.phase === "night" && !e.when).length;
  if (nightFree < (cfg.night?.cards ?? 2) + 1) err(`need at least ${(cfg.night?.cards ?? 2) + 1} night events without "when" (found ${nightFree})`);
  for (const e of events) if (e.forced && !forcedRefs.has(e.id)) warn(`event "${e.id}": forced but nothing schedules it (unreachable)`);
  for (const [where, f] of flagsRead) if (!flagsSet.has(f)) warn(`${where}: flag "${f}" is read but never set`);

  return { errors, warnings, stats: { events: events.length, night: events.filter((e) => e.phase === "night").length, hazards: events.filter((e) => e.hazard).length, modifiers: modIds.size } };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const path = process.argv[2] ?? DEFAULT_CONTENT;
  const content = JSON.parse(readFileSync(path, "utf8"));
  const { errors, warnings, stats } = validate(content);
  for (const w of warnings) console.log(`warning: ${w}`);
  for (const e of errors) console.log(`ERROR: ${e}`);
  console.log(`${stats.events} events (${stats.night} night, ${stats.hazards} hazards), ${stats.modifiers} modifiers, ${errors.length} errors, ${warnings.length} warnings`);
  process.exit(errors.length ? 1 : 0);
}
