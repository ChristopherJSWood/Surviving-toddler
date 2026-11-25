// Scripted players shared by the week simulator (balance targets) and the
// golden-trace recorder (conformance coverage). Every policy is deterministic
// given the game state and, for `random`, the lcg stream it's handed.

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

export function makePolicies(content) {
  const cfg = content.config;

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

  // Each policy gets the game, the unlocked visible choices as [{c, i}] and a
  // random stream, and returns one entry of `avail`.
  const policies = {
    random: (g, avail, rand) => avail[Math.floor(rand() * avail.length)],
    careful: (g, avail) => avail.reduce((b, c) => (utility(g, c.c) > utility(g, b.c) ? c : b)),
    shortcut: (g, avail) => avail.reduce((b, c) => (energyNow(g, c.c) > energyNow(g, b.c) ? c : b)),
    right: (g, avail) => avail.reduce((b, c) => (effort(c.c) > effort(b.c) ? c : b)),
    worst: (g, avail) => avail.reduce((b, c) => (utility(g, c.c) < utility(g, b.c) ? c : b)),
  };
  // A decent human: plays carefully most of the time, but can't see the hidden
  // odds, so 30% of the time picks blind. "careful" reads the hidden outcome
  // weights, so it's an upper bound, not a typical player.
  policies.human = (g, avail, rand) => (rand() < 0.3 ? policies.random : policies.careful)(g, avail, rand);
  return policies;
}

export function lcg(seed) {
  let s = seed >>> 0;
  return () => (s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296;
}
