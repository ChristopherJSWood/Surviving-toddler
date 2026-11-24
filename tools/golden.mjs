// Golden traces: records full seeded weeks from the reference engine. The
// Swift test suite replays every trace and must match step for step.
//
// Usage: node tools/golden.mjs          (rewrite the fixture)
//        node tools/golden.mjs --check  (fail if the fixture is stale)
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { Game, METERS, formatClock, mulberry32, snapshot } from "./engine.mjs";
import { DEFAULT_CONTENT } from "./validate.mjs";
import { lcg, makePolicies } from "./policies.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const FIXTURE = resolve(here, "../Core/Tests/BedtimeCoreTests/Fixtures/golden.json");

// The original 30 traces use an RNG-free policy: the k-th unlocked visible choice.
export function policyPick(seed, step, unlockedIndices) {
  return unlockedIndices[(seed + step * 31) % unlockedIndices.length];
}

// Coverage traces come from the simulator's scripted players, chosen greedily
// until every card and every ending appears and snaps are well exercised.
// Each step records the pick, so the Swift replay doesn't need the policies.
const COVERAGE_POLICIES = ["careful", "right", "worst", "shortcut", "random"];
const CANDIDATES_PER_POLICY = 400;
const MIN_SNAPS = 50;
const MAX_SNAP_TRACES = 16;

function record(content, seed, choose) {
  const g = new Game(content, seed);
  const steps = [];
  let guard = 0;
  while (!g.isOver) {
    if (++guard > 900) throw new Error(`runaway week: seed ${seed}`);
    const vis = g.visibleChoices();
    const unlocked = vis.map((c, i) => (g.isLocked(c) ? -1 : i)).filter((i) => i >= 0);
    const c = choose(g, vis, unlocked);
    const res = g.choose(c);
    steps.push({
      e: res.eventId,
      n: vis.length,
      u: unlocked.reduce((mask, i) => mask | (1 << i), 0),
      c,
      o: res.outcomeIndex,
      s: res.snapped ? 1 : 0,
      d: g.state.day,
      p: g.state.phase === "night" ? 1 : 0,
      t: g.state.clock,
      m: METERS.map((k) => g.state.meters[k]),
    });
  }
  return { seed, steps, final: snapshot(g) };
}

const featuresOf = (trace) => new Set([...trace.steps.map((s) => "event:" + s.e), "ending:" + trace.final.endingId]);
const snapsOf = (trace) => trace.steps.reduce((a, s) => a + s.s, 0);

export function coverage(content, traces) {
  const want = [...content.events.map((e) => "event:" + e.id), ...Object.keys(content.endings).map((id) => "ending:" + id)];
  const have = new Set(traces.flatMap((t) => [...featuresOf(t)]));
  return {
    events: content.events.filter((e) => have.has("event:" + e.id)).length,
    eventTotal: content.events.length,
    endings: Object.keys(content.endings).filter((id) => have.has("ending:" + id)).length,
    endingTotal: Object.keys(content.endings).length,
    snaps: traces.reduce((a, t) => a + snapsOf(t), 0),
    missing: want.filter((f) => !have.has(f)),
  };
}

export function buildGolden(content) {
  const seeds = [0, 1, 2, 7, 42, 1234, 99999, 2147483647, 2147483648, 4294967295];
  const r = mulberry32(20261124);
  while (seeds.length < 30) seeds.push(Math.floor(r() * 4294967296));

  const rng0 = mulberry32(0);
  const rngMax = mulberry32(4294967295);

  const traces = seeds.map((seed) => ({
    policy: "index",
    ...record(content, seed, (g, vis, unlocked) => policyPick(seed, g.state.step, unlocked)),
  }));

  const policies = makePolicies(content);
  const seedStream = mulberry32(20261125);
  const candidates = [];
  for (const name of COVERAGE_POLICIES) {
    for (let k = 0; k < CANDIDATES_PER_POLICY; k++) {
      const seed = Math.floor(seedStream() * 4294967296);
      const rand = lcg(seed ^ 0x9e3779b9);
      const trace = record(content, seed, (g, vis, unlocked) =>
        policies[name](g, unlocked.map((i) => ({ c: vis[i], i })), rand).i);
      candidates.push({ trace: { policy: name, ...trace }, features: featuresOf(trace), snaps: snapsOf(trace) });
    }
  }

  // Greedy set cover over cards and endings (ties: more snaps, then earlier).
  const have = new Set(traces.flatMap((t) => [...featuresOf(t)]));
  const used = new Set();
  for (;;) {
    let best = -1;
    let bestGain = 0;
    candidates.forEach((cand, i) => {
      if (used.has(i)) return;
      let gain = 0;
      for (const f of cand.features) if (!have.has(f)) gain++;
      if (gain > bestGain || (gain === bestGain && gain > 0 && cand.snaps > candidates[best].snaps)) {
        best = i;
        bestGain = gain;
      }
    });
    if (best < 0) break;
    used.add(best);
    for (const f of candidates[best].features) have.add(f);
    traces.push(candidates[best].trace);
  }

  // Then the snap path: add the snappiest remaining weeks until it's well covered.
  const bySnaps = candidates.map((c, i) => i).filter((i) => !used.has(i)).sort((x, y) => candidates[y].snaps - candidates[x].snaps || x - y);
  let added = 0;
  while (coverage(content, traces).snaps < MIN_SNAPS && added < MAX_SNAP_TRACES && bySnaps.length) {
    traces.push(candidates[bySnaps.shift()].trace);
    added++;
  }

  return {
    note: "GENERATED by tools/golden.mjs from tools/engine.mjs + content.json. Do not edit by hand.",
    meters: METERS,
    rng: { seed0: Array.from({ length: 8 }, () => rng0()), seedMax: Array.from({ length: 8 }, () => rngMax()) },
    clockFormat: [0, 304, 331, 358, 719, 720, 1170, 1439, 1440].map((m) => [m, formatClock(m)]),
    minSnaps: MIN_SNAPS,
    traces,
  };
}

function report(content, golden) {
  const cov = coverage(content, golden.traces);
  const steps = golden.traces.reduce((a, x) => a + x.steps.length, 0);
  console.log(`${golden.traces.length} traces, ${steps} steps: cards ${cov.events}/${cov.eventTotal}, endings ${cov.endings}/${cov.endingTotal}, snaps ${cov.snaps}`);
  if (cov.missing.length || cov.snaps < MIN_SNAPS) {
    console.log(`Coverage incomplete. Missing: ${cov.missing.join(", ") || "none"}; snaps ${cov.snaps} (need ${MIN_SNAPS}). Raise CANDIDATES_PER_POLICY in tools/golden.mjs.`);
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const content = JSON.parse(readFileSync(DEFAULT_CONTENT, "utf8"));
  const golden = buildGolden(content);
  report(content, golden);
  const next = JSON.stringify(golden) + "\n";
  if (process.argv.includes("--check")) {
    const cur = existsSync(FIXTURE) ? readFileSync(FIXTURE, "utf8") : "";
    if (cur !== next) {
      console.log("golden.json is stale: run `node tools/golden.mjs` and commit the result.");
      process.exit(1);
    }
    console.log("golden.json is up to date.");
  } else {
    writeFileSync(FIXTURE, next);
    console.log(`wrote ${(next.length / 1024).toFixed(0)} KB to ${FIXTURE}`);
  }
}
