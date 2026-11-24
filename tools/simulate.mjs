// Week simulator: plays thousands of seeded weeks with scripted players and
// checks the balance targets from docs/DESIGN.md. `--check` makes it a CI gate.
//
// Usage: node tools/simulate.mjs [--weeks 1500] [--check] [--json] [--src]
//   --src  simulate the content sources (content/) instead of the built file
import { readFileSync } from "node:fs";
import { Game, METERS, mulberry32 } from "./engine.mjs";
import { DEFAULT_CONTENT } from "./validate.mjs";
import { buildContent } from "./build-content.mjs";

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 ? Number(args[i + 1]) : dflt;
};
const WEEKS = opt("--weeks", 1500);
const CHECK = args.includes("--check");
const content = args.includes("--src") ? buildContent() : JSON.parse(readFileSync(DEFAULT_CONTENT, "utf8"));
const cfg = content.config;

// Concave utility: the last 10 points of a meter matter far more than the first.
const u = (v) => 100 * (1 - Math.exp(-Math.max(v, 0) / 22));
const WEIGHTS = { energy: 1.3, rel: 1.2, mood: 0.7, home: 0.9, rep: 0.8 };

function expectedAfter(g, choice) {
  const m = g.state.meters;
  const outs = choice.outcomes.filter((o) => g.meets(o.when));
  const total = outs.reduce((a, o) => a + (o.weight ?? 1), 0);
  return outs.map((o) => {
    const after = { ...m };
    for (const [k, v] of Object.entries(o.effects ?? {})) after[k] = Math.min(100, Math.max(0, after[k] + v));
    return { p: (o.weight ?? 1) / total, after, o };
  });
}

function utility(g, choice) {
  const ev = g.currentEvent;
  let util = 0;
  for (const { p, after, o } of expectedAfter(g, choice)) {
    let x = 0;
    for (const [k, w] of Object.entries(WEIGHTS)) x += w * u(after[k]);
    for (const k of ["energy", "rel", "home", "rep"]) if (after[k] <= 0) x -= 2000;
    x -= Math.max(0, after.debt - 35) * 0.8;
    x -= (o.schedule?.length ?? 0) * 25; // careful players know the bill comes
    if (ev.endsDay) x += after.sleepy >= cfg.bedtime.threshold ? 120 : -120;
    if (ev.id === "date_check" || ev.id?.includes("friday")) x += after.energy >= 30 ? 150 : -150;
    if (g.state.day === 4 && g.state.clock >= 1000) x += Math.min(after.sleepy, 70) * 2;
    util += p * x;
  }
  util -= (choice.duration / 20) * 1.3; // time costs Energy
  if (choice.snapRisk && g.state.meters.energy < cfg.snap.belowEnergy) util -= 0.3 * 120;
  return util;
}

const effort = (c) => (c.minEnergy ?? 0) + ((c.tags ?? []).some((t) => t === "present" || t === "martyr") ? 25 : 0);
const energyNow = (g, c) => expectedAfter(g, c).reduce((a, { p, after }) => a + p * after.energy, 0);

const POLICIES = {
  random: (g, avail, rand) => avail[Math.floor(rand() * avail.length)],
  careful: (g, avail) => avail.reduce((b, c) => (utility(g, c.c) > utility(g, b.c) ? c : b)),
  shortcut: (g, avail) => avail.reduce((b, c) => (energyNow(g, c.c) > energyNow(g, b.c) ? c : b)),
  right: (g, avail) => avail.reduce((b, c) => (effort(c.c) > effort(b.c) ? c : b)),
  worst: (g, avail) => avail.reduce((b, c) => (utility(g, c.c) < utility(g, b.c) ? c : b)),
};

function lcg(seed) {
  let s = seed >>> 0;
  return () => (s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296;
}

function run(name, { shock = false } = {}) {
  const policy = POLICIES[name];
  const endings = {};
  const seen = {};
  const picks = {};
  let steps = 0;
  let fillers = 0;
  let wins = 0;
  let momentsWeeks = 0;
  let lifelines = 0;
  let dateReached = 0;
  let dateFailed = 0;
  let dayCount = 0;
  const badMon = { n: 0, wins: 0 };
  for (let w = 0; w < WEEKS; w++) {
    const seed = (w * 2654435761) >>> 0;
    const g = new Game(content, seed);
    const rand = lcg(seed ^ 0x9e3779b9);
    let guard = 0;
    let badMonday = null;
    let shocked = false;
    while (!g.isOver) {
      // Stress test: a terrible first night (as if the toddler was up for hours).
      if (shock && !shocked && g.state.day === 1) {
        shocked = true;
        g.state.meters.debt = Math.min(100, g.state.meters.debt + 30);
        g.state.meters.energy = Math.max(0, g.state.meters.energy - 20);
      }
      if (++guard > 900) throw new Error(`runaway week: seed ${seed}`);
      const ev = g.currentEvent;
      seen[ev.id] = (seen[ev.id] ?? 0) + 1;
      if (ev.filler) fillers++;
      if (ev.id === "date_check") dateReached++;
      const vis = g.visibleChoices();
      const avail = vis.map((c, i) => ({ c, i })).filter(({ c }) => !g.isLocked(c));
      const pick = policy(g, avail, rand);
      const key = `${ev.id}#${ev.choices.indexOf(pick.c)}`;
      picks[key] = (picks[key] ?? 0) + 1;
      g.choose(pick.i);
      steps++;
      if (badMonday === null && g.state.day === 1 && g.state.report) badMonday = g.state.report.nightYou >= 2 || g.state.meters.debt >= 40;
    }
    const e = g.state.endingId;
    endings[e] = (endings[e] ?? 0) + 1;
    const won = content.endings[e].kind === "win";
    if (won) wins++;
    if (e === "couch" || e === "sitter_quits") dateFailed++;
    if ((g.state.counters.moments ?? 0) > 0) momentsWeeks++;
    lifelines += g.state.lostDays;
    dayCount += g.state.day + 1;
    if (badMonday) {
      badMon.n++;
      if (won) badMon.wins++;
    }
  }
  const losses = Object.entries(endings).filter(([e]) => content.endings[e].kind === "loss");
  const lossTotal = losses.reduce((a, [, n]) => a + n, 0);
  return {
    policy: name,
    winRate: wins / WEEKS,
    endings: Object.fromEntries(Object.entries(endings).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, +(v / WEEKS).toFixed(3)])),
    maxLossShare: lossTotal ? Math.max(...losses.map(([, n]) => n / lossTotal)) : 0,
    stepsPerDay: +(steps / dayCount).toFixed(1),
    fillerShare: +(fillers / steps).toFixed(4),
    lifelinesPerWeek: +(lifelines / WEEKS).toFixed(2),
    momentWeeks: momentsWeeks / WEEKS,
    dateFailRate: dateReached ? dateFailed / dateReached : 0,
    badMondayWinRate: badMon.n ? badMon.wins / badMon.n : null,
    badMondayWeeks: badMon.n,
    seen,
    picks,
  };
}

// Static check: a choice no better on any meter, worse on one, and no faster
// (ignoring choices with conditions, locks or scheduled paybacks).
function dominated() {
  const out = [];
  const exp = (c) => {
    const total = c.outcomes.reduce((a, o) => a + (o.weight ?? 1), 0);
    const e = Object.fromEntries(METERS.map((k) => [k, 0]));
    for (const o of c.outcomes) for (const k of METERS) e[k] += ((o.weight ?? 1) / total) * (o.effects?.[k] ?? 0);
    return e;
  };
  const plain = (c) => !c.when && !c.minEnergy && !c.outcomes.some((o) => o.when || o.schedule || o.completeTask || o.cancel || o.ledger || o.set);
  const GOOD = ["energy", "rel", "mood", "home", "rep"];
  for (const ev of content.events) {
    const cs = ev.choices;
    cs.forEach((c, i) => {
      cs.forEach((d, j) => {
        if (i === j || !plain(c) || !plain(d)) return;
        const a = exp(c);
        const b = exp(d);
        const geq = GOOD.every((k) => b[k] >= a[k]) && b.sleepy === a.sleepy && b.debt <= a.debt && d.duration <= c.duration;
        const strict = GOOD.some((k) => b[k] > a[k]) || d.duration < c.duration || b.debt < a.debt;
        if (geq && strict) out.push(`${ev.id}: "${c.label}" is dominated by "${d.label}"`);
      });
    });
  }
  return out;
}

const results = Object.keys(POLICIES).map((p) => run(p));
const by = Object.fromEntries(results.map((r) => [r.policy, r]));
const shocked = run("careful", { shock: true });
const dom = dominated();
const randomNever = content.events.filter((e) => !(by.random.seen[e.id] > 0) && !(by.careful.seen[e.id] > 0)).map((e) => e.id);

const TARGETS = {
  "careful finishes the week 60-85%": () => by.careful.winRate >= 0.6 && by.careful.winRate <= 0.85,
  "random finishes the week 10-25%": () => by.random.winRate >= 0.1 && by.random.winRate <= 0.25,
  "always-shortcut finishes <= 15%": () => by.shortcut.winRate <= 0.15,
  // The plan's thesis: perfect parenting at any cost can't be a winning strategy.
  // (Originally "fails date night >= 40%", but this player burns out before Friday.)
  "always-right-thing finishes <= 40%": () => by.right.winRate <= 0.4,
  "after a forced terrible Monday night, careful still wins >= half its usual rate": () => shocked.winRate >= 0.5 * by.careful.winRate,
  "no loss cause above 40% of losses (random)": () => by.random.maxLossShare <= 0.4,
  "a small moment in >= 90% of careful weeks": () => by.careful.momentWeeks >= 0.9,
  "filler under 3% of cards (random)": () => by.random.fillerShare < 0.03,
  "20-35 cards per day (random)": () => by.random.stepsPerDay >= 20 && by.random.stepsPerDay <= 35,
  "no strictly dominated choices": () => dom.length === 0,
};
const checks = Object.entries(TARGETS).map(([name, f]) => ({ name, pass: f() }));

if (args.includes("--json")) {
  console.log(JSON.stringify({ weeks: WEEKS, results: results.map(({ seen, picks, ...r }) => r), dominated: dom, never: randomNever, checks }, null, 2));
} else {
  console.log(`Simulated ${WEEKS} weeks per player\n`);
  for (const r of results) {
    console.log(`${r.policy.padEnd(8)} win ${(100 * r.winRate).toFixed(1)}%  cards/day ${r.stepsPerDay}  filler ${(100 * r.fillerShare).toFixed(1)}%  lifelines ${r.lifelinesPerWeek}  date-fail ${(100 * r.dateFailRate).toFixed(0)}%  moments ${(100 * r.momentWeeks).toFixed(0)}%  bad-Monday win ${r.badMondayWinRate == null ? "-" : (100 * r.badMondayWinRate).toFixed(0) + "% (" + r.badMondayWeeks + ")"}`);
    console.log(`         ${JSON.stringify(r.endings)}`);
  }
  console.log(`\ncareful with a forced terrible Monday night: win ${(100 * shocked.winRate).toFixed(1)}%  ${JSON.stringify(shocked.endings)}`);
  console.log(`\nNever seen (random + careful): ${randomNever.length ? randomNever.join(", ") : "none"}`);
  console.log(`Dominated choices: ${dom.length ? "\n  " + dom.join("\n  ") : "none"}`);
  console.log("\nBalance targets:");
  for (const c of checks) console.log(`  ${c.pass ? "PASS" : "FAIL"}  ${c.name}`);
}
if (CHECK && checks.some((c) => !c.pass)) process.exit(1);
