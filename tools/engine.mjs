// Bedtime or Bust: reference rules engine v2 (the week).
//
// This file is the executable specification. docs/RULES.md describes it in
// prose; Core/Sources/BedtimeCore/Engine.swift must behave identically, and
// tools/golden.mjs records traces the Swift tests replay.

export const METERS = ["energy", "rel", "mood", "sleepy", "debt", "home", "rep"];

export function mulberry32(seed) {
  let a = seed | 0;
  return function next() {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function weightedPick(items, weightOf, rng) {
  let total = 0;
  for (const it of items) total += weightOf(it);
  const r = rng() * total;
  let acc = 0;
  for (let i = 0; i < items.length; i++) {
    acc += weightOf(items[i]);
    if (r < acc) return i;
  }
  return items.length - 1;
}

const clamp = (v) => (v < 0 ? 0 : v > 100 ? 100 : v);

export function formatClock(minutes) {
  const m = ((minutes % 1440) + 1440) % 1440;
  const h24 = Math.floor(m / 60);
  const mm = m % 60;
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}:${String(mm).padStart(2, "0")} ${h24 < 12 ? "AM" : "PM"}`;
}

export class Game {
  constructor(content, seed) {
    this.content = content;
    this.cfg = content.config;
    this.rng = mulberry32(seed >>> 0);
    this.events = new Map(content.events.map((e) => [e.id, e]));
    this.taskDefs = new Map((content.tasks ?? []).map((t) => [t.id, t]));
    this.state = {
      seed: seed >>> 0,
      meters: { ...this.cfg.startMeters },
      day: 0,
      phase: "day",
      clock: 0,
      dayStart: 0,
      flags: new Set(),
      counters: {},
      ledger: { you: {}, partner: {} },
      nightYou: 0,
      nightPartner: 0,
      nightCardsLeft: 0,
      tasks: [],
      queue: [],
      seq: 0,
      seenToday: new Set(),
      seenWeek: new Set(),
      lastEventId: null,
      currentEventId: null,
      modifierId: null,
      step: 0,
      catastrophesToday: 0,
      lifelineUsed: false,
      lostDays: 0,
      endingId: null,
      report: null,
    };
    this.#startDay(0);
  }

  // ---- queries ----
  get now() {
    return this.state.day * 1440 + this.state.clock;
  }
  get currentEvent() {
    const id = this.state.currentEventId;
    return id == null ? null : this.events.get(id);
  }
  get modifier() {
    return this.content.modifiers.find((m) => m.id === this.state.modifierId) ?? null;
  }
  get ending() {
    const id = this.state.endingId;
    return id == null ? null : { id, ...this.content.endings[id] };
  }
  get isOver() {
    return this.state.endingId != null;
  }
  ledgerBalance() {
    const sum = (o) => Object.values(o).reduce((a, b) => a + b, 0);
    return sum(this.state.ledger.you) - sum(this.state.ledger.partner);
  }
  score() {
    let s = 0;
    for (const [k, w] of Object.entries(this.cfg.weekScore)) s += w * this.state.meters[k];
    return s;
  }
  band() {
    const d = this.state.meters.debt;
    return d <= 29 ? 0 : d <= 59 ? 1 : 2;
  }
  style() {
    let best = null;
    let bestN = 0;
    for (const st of this.content.styles) {
      const n = this.state.counters[`style.${st.id}`] ?? 0;
      if (n > bestN) [best, bestN] = [st, n];
    }
    return best ?? this.content.styles[0];
  }

  meets(cond) {
    if (!cond) return true;
    const s = this.state;
    for (const f of cond.flags ?? []) if (!s.flags.has(f)) return false;
    for (const f of cond.notFlags ?? []) if (s.flags.has(f)) return false;
    const val = (k) => (k === "day" ? s.day : k === "ledger" ? this.ledgerBalance() : s.meters[k]);
    for (const [k, v] of Object.entries(cond.min ?? {})) if (val(k) < v) return false;
    for (const [k, v] of Object.entries(cond.max ?? {})) if (val(k) > v) return false;
    return true;
  }

  visibleChoices(event = this.currentEvent) {
    if (!event) return [];
    return event.choices.filter((c) => this.meets(c.when));
  }
  isLocked(choice) {
    return (choice.minEnergy ?? 0) > this.state.meters.energy;
  }

  // ---- playing ----
  choose(index) {
    if (this.isOver) throw new Error("game is over");
    const s = this.state;
    const ev = this.currentEvent;
    const choices = this.visibleChoices(ev);
    if (!(index >= 0 && index < choices.length)) throw new Error(`bad choice ${index}`);
    const choice = choices[index];
    if (this.isLocked(choice)) throw new Error(`choice ${index} is locked`);
    const before = { ...s.meters };
    const dayBefore = s.day;
    const nowBefore = this.now;

    const cands = choice.outcomes.filter((o) => this.meets(o.when));
    if (cands.length === 0) throw new Error(`no outcome applies: ${ev.id}`);
    let outcomeIndex = 0;
    if (cands.length > 1) outcomeIndex = weightedPick(cands, (o) => o.weight ?? 1, this.rng);
    let out = cands[outcomeIndex];
    let snapped = false;
    const sn = this.cfg.snap;
    if (s.phase === "day" && choice.snapRisk && s.meters.energy < sn.belowEnergy) {
      if (this.rng() * 100 < sn.chancePct) {
        snapped = true;
        // The snap replaces the outcome, but the story keeps going: week-long
        // flags (escalation chains, callbacks) from the original still apply.
        const keep = (out.set ?? []).filter((f) => !f.startsWith("d:"));
        out = { text: sn.text, effects: sn.effects, set: [...(sn.set ?? []), ...keep] };
      }
    }
    this.#applyOutcome(out, nowBefore);
    for (const t of choice.tags ?? []) this.#count(`style.${t}`, 1);

    let minutes = 0;
    if (s.phase === "day") {
      minutes = choice.duration + this.cfg.eventGap;
      this.#advance(minutes);
    }
    s.seenToday.add(ev.id);
    s.seenWeek.add(ev.id);
    s.lastEventId = ev.id;
    s.step += 1;

    let dayEnded = null; // "night" | "lifeline"
    let endingId = this.#lossCheck();
    if (endingId === "lifeline") {
      endingId = null;
      // At night the lifeline just patches you up; by day it ends the day.
      if (s.phase === "day") dayEnded = "lifeline";
    }
    if (!endingId && !dayEnded) {
      for (const chk of ev.checks ?? []) {
        if (this.meets(chk.when)) {
          endingId = chk.ending;
          break;
        }
      }
    }
    if (!endingId && !dayEnded && ev.endsWeek) endingId = this.#grade();
    if (!endingId && !dayEnded && ev.endsDay) {
      const b = this.cfg.bedtime;
      if (s.meters.sleepy >= b.threshold) this.#applyOutcome({ effects: b.asleep }, this.now);
      else {
        this.#applyOutcome({ effects: b.awake }, this.now);
        s.flags.add(b.awakeFlag);
      }
      dayEnded = "night";
    }

    // Deltas describe this choice (including lifeline/bedtime effects), not the
    // overnight changes, which the morning report shows instead.
    const deltas = {};
    for (const m of METERS) if (s.meters[m] !== before[m]) deltas[m] = s.meters[m] - before[m];

    if (endingId) {
      s.endingId = endingId;
      s.currentEventId = null;
    } else if (dayEnded) {
      this.#goToNight();
    } else if (s.phase === "night") {
      s.nightCardsLeft -= 1;
      if (s.nightCardsLeft <= 0) this.#morning();
      else this.#pickNight();
    } else {
      this.#expireTasks();
      if (!ev.hazard && !ev.forced && !ev.noHazard) this.#rollHazard();
      s.currentEventId = this.#nextDayEvent().id;
    }

    return {
      eventId: ev.id,
      choiceIndex: index,
      outcomeIndex,
      snapped,
      text: out.text,
      // Presentation only (the UI's verdict badge, screen effect, reply bubbles).
      stamp: out.stamp ?? null,
      fx: out.fx ?? null,
      chat: out.chat ?? [],
      deltas,
      minutes,
      dayEnded: dayEnded ?? (s.day !== dayBefore ? "morning" : null),
      endingId: s.endingId,
    };
  }

  // ---- internals ----
  #count(k, n) {
    this.state.counters[k] = (this.state.counters[k] ?? 0) + n;
  }

  #applyOutcome(out, nowBefore) {
    const s = this.state;
    for (const [k, v] of Object.entries(out.effects ?? {})) s.meters[k] = clamp(s.meters[k] + v);
    for (const f of out.set ?? []) s.flags.add(f);
    for (const f of out.clear ?? []) s.flags.delete(f);
    for (const [k, v] of Object.entries(out.count ?? {})) this.#count(k, v);
    for (const [cat, who] of Object.entries(out.ledger ?? {})) {
      s.ledger[who][cat] = (s.ledger[who][cat] ?? 0) + 1;
      if (s.phase === "night" && cat === "night") {
        if (who === "you") s.nightYou += 1;
        else s.nightPartner += 1;
      }
    }
    for (const sc of out.schedule ?? []) s.queue.push({ event: sc.event, at: nowBefore + sc.in, seq: s.seq++ });
    if (out.cancel) s.queue = s.queue.filter((q) => !out.cancel.includes(q.event));
    if (out.completeTask) {
      const open = s.tasks.filter((t) => t.status === "open");
      const t = out.completeTask === "oldest" ? open[0] : open.find((x) => x.id === out.completeTask);
      if (t) {
        t.status = "done";
        s.ledger.you.errands = (s.ledger.you.errands ?? 0) + 1;
      }
    }
  }

  #advance(minutes) {
    const s = this.state;
    const t0 = s.clock - s.dayStart;
    const t1 = t0 + minutes;
    for (const rule of this.cfg.drift) {
      if (!this.meets(rule.when)) continue;
      const ticks = Math.floor(t1 / rule.every) - Math.floor(t0 / rule.every);
      s.meters[rule.meter] = clamp(s.meters[rule.meter] + rule.delta * ticks);
    }
    s.clock += minutes;
  }

  #lossCheck() {
    const s = this.state;
    for (const m of this.cfg.lossOrder) {
      if (s.meters[m] > 0) continue;
      if (this.cfg.lifelineMeters.includes(m) && !s.lifelineUsed && s.day < 4) {
        s.lifelineUsed = true;
        s.lostDays += 1;
        const l = this.content.lifeline;
        this.#applyOutcome({ effects: l.effects, set: l.set }, this.now);
        return "lifeline";
      }
      return this.cfg.losses[m];
    }
    return null;
  }

  #grade() {
    const sc = this.score();
    for (const g of this.cfg.grades) if (sc >= g.min) return g.id;
    return this.cfg.grades[this.cfg.grades.length - 1].id;
  }

  #expireTasks() {
    const s = this.state;
    for (const t of s.tasks) {
      if (t.status === "open" && t.due <= this.now) {
        t.status = "expired";
        const def = this.taskDefs.get(t.id);
        if (def?.expire) s.queue.push({ event: def.expire, at: this.now, seq: s.seq++ });
      }
    }
  }

  #rollHazard() {
    const s = this.state;
    const h = this.cfg.hazard;
    const band = this.band();
    const chance = h.base + h.bandBonus[band] + (s.clock >= h.lateDayClock ? h.lateDayBonus : 0);
    if (!(this.rng() * 100 < chance)) return;
    let severity = "sting";
    if (s.catastrophesToday < h.maxCatastrophesPerDay) {
      if (this.rng() * 100 < h.catastropheShare[band]) severity = "catastrophe";
    }
    const pool = this.content.events.filter(
      (e) => e.hazard === severity && !s.seenToday.has(e.id) && !(e.oncePerWeek && s.seenWeek.has(e.id))
        && this.meets(e.when) && !s.queue.some((q) => q.event === e.id),
    );
    if (pool.length === 0) return;
    const hz = pool.length === 1 ? pool[0] : pool[weightedPick(pool, (e) => e.weight ?? 1, this.rng)];
    if (hz.tell) s.queue.push({ event: hz.tell, at: this.now, seq: s.seq++ });
    s.queue.push({ event: hz.id, at: this.now, seq: s.seq++ });
    if (severity === "catastrophe") s.catastrophesToday += 1;
  }

  #nextDayEvent() {
    const s = this.state;
    const now = this.now;
    const due = s.queue.filter((q) => q.at <= now).sort((a, b) => a.at - b.at || a.seq - b.seq);
    let best = null; // { ev, prio, q }
    for (const q of due) {
      const ev = this.events.get(q.event);
      if (!ev || !this.meets(ev.when)) {
        s.queue = s.queue.filter((x) => x !== q);
        continue;
      }
      const prio = ev.priority ?? 80;
      if (!best || prio > best.prio) best = { ev, prio, q };
    }
    for (const ev of this.content.events) {
      if ((ev.priority ?? 0) <= 0 || (ev.phase ?? "day") !== "day" || ev.hazard || ev.forced) continue;
      if (!this.#windowEligible(ev)) continue;
      if (!best || ev.priority > best.prio) best = { ev, prio: ev.priority, q: null };
    }
    if (best) {
      if (best.q) s.queue = s.queue.filter((x) => x !== best.q);
      return best.ev;
    }
    const pool = this.content.events.filter(
      (ev) =>
        (ev.priority ?? 0) <= 0 &&
        (ev.phase ?? "day") === "day" &&
        !ev.hazard &&
        !ev.forced &&
        !ev.filler &&
        this.#windowEligible(ev),
    );
    if (pool.length === 0) return this.content.events.find((e) => e.filler);
    return pool[weightedPick(pool, (e) => this.#weight(e), this.rng)];
  }

  #windowEligible(ev) {
    const s = this.state;
    if (!ev.repeatable && s.seenToday.has(ev.id)) return false;
    if (ev.oncePerWeek && s.seenWeek.has(ev.id)) return false;
    if (ev.id === s.lastEventId) return false;
    if (!ev.window || s.clock < ev.window[0] || s.clock > ev.window[1]) return false;
    if (!this.meets(ev.when)) return false;
    if (ev.task && !s.tasks.some((t) => t.id === ev.task && t.status === "open")) return false;
    return this.visibleChoices(ev).length > 0;
  }

  #weight(ev) {
    const base = ev.weight ?? 1;
    if (!ev.weightBy) return base;
    return base + Math.floor((this.state.counters[ev.weightBy.counter] ?? 0) / ev.weightBy.every);
  }

  #goToNight() {
    const s = this.state;
    s.phase = "night";
    s.nightCardsLeft = this.cfg.night.cards + (s.flags.has(this.cfg.bedtime.awakeFlag) ? 1 : 0);
    s.nightYou = 0;
    s.nightPartner = 0;
    s.queue = [];
    this.#pickNight();
  }

  #pickNight() {
    const s = this.state;
    const pool = this.content.events.filter(
      (e) => e.phase === "night" && !s.seenToday.has(e.id) && !(e.oncePerWeek && s.seenWeek.has(e.id)) && this.meets(e.when),
    );
    if (pool.length === 0) {
      this.#morning();
      return;
    }
    s.currentEventId = pool[weightedPick(pool, (e) => this.#weight(e), this.rng)].id;
  }

  #morning() {
    const s = this.state;
    const n = this.cfg.night;
    const debtBefore = s.meters.debt;
    const refill = Math.max(n.minRefill, n.base - n.perWake * s.nightYou - (s.flags.has(n.lateCoffeeFlag) ? n.lateCoffeePenalty : 0));
    s.meters.energy = clamp(s.meters.energy + refill);
    s.meters.debt = clamp(s.meters.debt + n.debtPerWake * (s.nightYou + s.nightPartner) - n.recovery);
    s.meters.mood = clamp(n.moodBase - Math.floor(s.meters.debt / n.moodDebtDiv));
    s.meters.sleepy = n.sleepyStart;
    s.meters.home = clamp(s.meters.home + (s.meters.rel >= n.homeTidy.minRel ? n.homeTidy.high : n.homeTidy.low));
    for (const f of [...s.flags]) if (f.startsWith("d:")) s.flags.delete(f);
    let partnerDid = null;
    if (s.meters.rel >= n.partnerTaskMinRel) {
      const t = s.tasks.find((x) => x.status === "open");
      if (t) {
        t.status = "done";
        s.ledger.partner.errands = (s.ledger.partner.errands ?? 0) + 1;
        partnerDid = t.id;
      }
    }
    const report = {
      day: s.day + 1,
      nightYou: s.nightYou,
      nightPartner: s.nightPartner,
      refill,
      debtBefore,
      debtAfter: s.meters.debt,
      partnerDid,
    };
    this.#startDay(s.day + 1);
    s.report = { ...report, wakeClock: s.dayStart, tasksAdded: this.content.days[s.day].tasks ?? [], modifierId: s.modifierId };
  }

  #startDay(d) {
    const s = this.state;
    const dayDef = this.content.days[d];
    s.day = d;
    s.phase = "day";
    s.clock = s.dayStart = this.cfg.wake[this.band()];
    s.seenToday = new Set();
    s.queue = [];
    s.catastrophesToday = 0;
    s.lastEventId = null;
    let mod;
    if (dayDef.modifier === "random") {
      const pool = this.content.modifiers.filter((m) => m.pool);
      mod = pool[weightedPick(pool, (m) => m.weight ?? 1, this.rng)];
    } else {
      mod = this.content.modifiers.find((m) => m.id === dayDef.modifier);
    }
    s.modifierId = mod.id;
    this.#applyOutcome({ effects: mod.effects, set: mod.set }, this.now);
    for (const id of dayDef.tasks ?? []) {
      const def = this.taskDefs.get(id);
      s.tasks.push({ id, due: def.dueDay * 1440 + def.dueClock, status: "open" });
    }
    s.currentEventId = this.#nextDayEvent().id;
  }
}

export function snapshot(game) {
  const s = game.state;
  const sortObj = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : 1)));
  return {
    day: s.day,
    phase: s.phase,
    clock: s.clock,
    meters: { ...s.meters },
    flags: [...s.flags].sort(),
    counters: sortObj(s.counters),
    ledger: { you: sortObj(s.ledger.you), partner: sortObj(s.ledger.partner) },
    tasks: s.tasks.map((t) => `${t.id}:${t.status}`),
    step: s.step,
    lostDays: s.lostDays,
    endingId: s.endingId,
  };
}
