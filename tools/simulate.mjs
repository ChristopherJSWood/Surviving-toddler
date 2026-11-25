// Week simulator: plays thousands of seeded weeks with scripted players and
// checks the balance targets from docs/DESIGN.md. `--check` makes it a CI gate.
//
// Usage: node tools/simulate.mjs [--weeks 1500] [--check] [--json] [--src]
//   --src  simulate the content sources (content/) instead of the built file
import { readFileSync } from "node:fs";
import { Game, METERS, mulberry32 } from "./engine.mjs";
import { DEFAULT_CONTENT } from "./validate.mjs";
import { buildContent } from "./build-content.mjs";
import { lcg, makePolicies } from "./policies.mjs";

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 ? Number(args[i + 1]) : dflt;
};
const WEEKS = opt("--weeks", 1500);
const CHECK = args.includes("--check");
const content = args.includes("--src") ? buildContent() : JSON.parse(readFileSync(DEFAULT_CONTENT, "utf8"));

const POLICIES = makePolicies(content);

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
  let repeats = 0;
  let timeouts = 0;
  const family = {};
  const badMon = { n: 0, wins: 0 };
  for (let w = 0; w < WEEKS; w++) {
    const seed = (w * 2654435761) >>> 0;
    const g = new Game(content, seed);
    const rand = lcg(seed ^ 0x9e3779b9);
    let guard = 0;
    let badMonday = null;
    let shocked = false;
    const thisWeek = new Set();
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
      if (thisWeek.has(ev.id) && !ev.repeatable && !ev.filler) repeats++;
      thisWeek.add(ev.id);
      if (ev.family) family[ev.family] = (family[ev.family] ?? 0) + 1;
      if (ev.filler) fillers++;
      if (ev.id === "date_check") dateReached++;
      const vis = g.visibleChoices();
      // The timeout choice isn't a button: it only happens when a panic timer
      // runs out. The random player freezes on 15% of panic cards.
      const avail = vis.map((c, i) => ({ c, i })).filter(({ c }) => !g.isLocked(c) && !c.timeout);
      const timeoutAt = vis.findIndex((c) => c.timeout);
      const freeze = ev.timer !== undefined && timeoutAt >= 0 && name === "random" && rand() < 0.15;
      if (freeze) timeouts++;
      const pick = freeze ? { c: vis[timeoutAt], i: timeoutAt } : policy(g, avail, rand);
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
    cardsPerWeek: +(steps / WEEKS).toFixed(1),
    repeatShare: +(repeats / steps).toFixed(4),
    familyPerWeek: Object.fromEntries(Object.entries(family).sort().map(([k, v]) => [k, +(v / WEEKS).toFixed(2)])),
    timeoutsPerWeek: +(timeouts / WEEKS).toFixed(2),
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
  const GOOD = ["energy", "rel", "mood"];
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

// Static shape of the writing (docs/VOICE.md): outcome variety and stamps.
const allChoices = content.events.flatMap((e) => e.choices.filter((c) => !c.timeout));
const allOutcomes = content.events.flatMap((e) => e.choices.flatMap((c) => c.outcomes));
const style = {
  multiOutcomeShare: allChoices.filter((c) => c.outcomes.length > 1).length / allChoices.length,
  stampShare: allOutcomes.filter((o) => o.stamp).length / allOutcomes.length,
  shakeShare: allOutcomes.filter((o) => o.fx === "shake").length / allOutcomes.length,
};

const TARGETS = {
  // "careful" reads the hidden outcome odds: an upper bound. "human" plays
  // carefully but picks blind 30% of the time: the main difficulty target.
  "a decent human finishes the week 65-85%": () => by.human.winRate >= 0.65 && by.human.winRate <= 0.85,
  "careful (sees hidden odds) finishes 85-97%": () => by.careful.winRate >= 0.85 && by.careful.winRate <= 0.97,
  "random finishes the week 10-25%": () => by.random.winRate >= 0.1 && by.random.winRate <= 0.25,
  "the top grade stays rare: legend in at most 30% of human weeks": () => (by.human.endings.legend ?? 0) <= 0.3,
  "always-shortcut finishes <= 15%": () => by.shortcut.winRate <= 0.15,
  // The plan's thesis: perfect parenting at any cost can't be a winning strategy.
  // (Originally "fails date night >= 40%", but this player burns out before Friday.)
  "always-right-thing finishes <= 40%": () => by.right.winRate <= 0.4,
  "after a forced terrible Monday night, careful still wins >= half its usual rate": () => shocked.winRate >= 0.5 * by.careful.winRate,
  // Four ways to lose since House and Reputation were cut (collapse, the talk,
  // and two date-night failures), so an even split is 25%. Blind play
  // neglects the relationship most; cap any one cause at 60%.
  "no loss cause above 60% of losses (random)": () => by.random.maxLossShare <= 0.6,
  "a small moment in >= 90% of careful weeks": () => by.careful.momentWeeks >= 0.9,
  "filler under 3% of cards (random)": () => by.random.fillerShare < 0.03,
  // Pacing and freshness: the first playtest found ~170 cards a week, half of
  // them repeats, "almost boring".
  "16-22 cards per day (random)": () => by.random.stepsPerDay >= 16 && by.random.stepsPerDay <= 22,
  "85-115 cards per week (careful)": () => by.careful.cardsPerWeek >= 85 && by.careful.cardsPerWeek <= 115,
  "under 5% of cards are repeats within a week (careful)": () => by.careful.repeatShare < 0.05,
  "tantrums and food fights recur: each 2+ times a week (careful)": () => (by.careful.familyPerWeek.tantrum ?? 0) >= 2 && (by.careful.familyPerWeek.food ?? 0) >= 2,
  "at least half of choices have 2+ possible outcomes": () => style.multiOutcomeShare >= 0.5,
  "stamps on 15-40% of outcomes": () => style.stampShare >= 0.15 && style.stampShare <= 0.4,
  "no strictly dominated choices": () => dom.length === 0,
};
const checks = Object.entries(TARGETS).map(([name, f]) => ({ name, pass: f() }));

if (args.includes("--json")) {
  console.log(JSON.stringify({ weeks: WEEKS, results: results.map(({ seen, picks, ...r }) => r), style, dominated: dom, never: randomNever, checks }, null, 2));
} else {
  console.log(`Simulated ${WEEKS} weeks per player\n`);
  for (const r of results) {
    console.log(`${r.policy.padEnd(8)} win ${(100 * r.winRate).toFixed(1)}%  cards/day ${r.stepsPerDay}  filler ${(100 * r.fillerShare).toFixed(1)}%  lifelines ${r.lifelinesPerWeek}  date-fail ${(100 * r.dateFailRate).toFixed(0)}%  moments ${(100 * r.momentWeeks).toFixed(0)}%  bad-Monday win ${r.badMondayWinRate == null ? "-" : (100 * r.badMondayWinRate).toFixed(0) + "% (" + r.badMondayWeeks + ")"}`);
    console.log(`         ${JSON.stringify(r.endings)}`);
    console.log(`         ${r.cardsPerWeek} cards/week, repeats ${(100 * r.repeatShare).toFixed(1)}%, families/week ${JSON.stringify(r.familyPerWeek)}${r.timeoutsPerWeek ? `, panic timeouts ${r.timeoutsPerWeek}/week` : ""}`);
  }
  console.log(`\ncareful with a forced terrible Monday night: win ${(100 * shocked.winRate).toFixed(1)}%  ${JSON.stringify(shocked.endings)}`);
  console.log(`\nNever seen (random + careful): ${randomNever.length ? randomNever.join(", ") : "none"}`);
  console.log(`Writing shape: ${(100 * style.multiOutcomeShare).toFixed(0)}% of choices have 2+ outcomes, stamps on ${(100 * style.stampShare).toFixed(0)}% of outcomes, shake on ${(100 * style.shakeShare).toFixed(0)}%`);
  console.log(`Dominated choices: ${dom.length ? "\n  " + dom.join("\n  ") : "none"}`);
  console.log("\nBalance targets:");
  for (const c of checks) console.log(`  ${c.pass ? "PASS" : "FAIL"}  ${c.name}`);
}
if (CHECK && checks.some((c) => !c.pass)) process.exit(1);
