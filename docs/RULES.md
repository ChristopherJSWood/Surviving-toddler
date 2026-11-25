# Rules v2: The Week

This is the contract both engines implement: `tools/engine.mjs` (the executable
spec) and `Core/Sources/BedtimeCore/Engine.swift`. Golden traces prove they agree,
so every rule below, including the **order of random draws**, is normative.

## State

| Field | Meaning |
|---|---|
| `meters` | `energy, rel, mood, sleepy, debt` (this order), integers clamped to 0–100. Players see Bandwidth (`energy`), Relationship, Mood and Sleep (`100 − debt`); `sleepy` appears as a bedtime word. |
| `day` | 0–4, Monday to Friday |
| `phase` | `day` or `night` |
| `clock` | minutes since midnight of the current day |
| `dayStart` | wake-up clock for today (drift ticks count from here) |
| `flags` | set of strings; flags starting `d:` are cleared every morning |
| `counters` | receipt counters and `style.<id>` tallies |
| `ledger` | `you` and `partner` maps of category → count |
| `nightYou`, `nightPartner` | wake-ups handled in the current night |
| `tasks` | mental-load list: `{id, due, status: open/done/expired}`; `due` is absolute week minutes (`day*1440 + clock`) |
| `queue` | forced events: `{event, at, seq}`; due when `at ≤ now` |
| `seenToday`, `seenWeek` | event ids shown |
| `lifelineUsed`, `lostDays`, `catastrophesToday` | as named |
| `endingId` | set when the week is over |

`now` always means `day*1440 + clock`. Debt band: 0 if `debt ≤ 29`, 1 if `≤ 59`, else 2.

## Random draws

mulberry32 over a `UInt32` state. One draw per weighted pick (`r*total`, first index whose running sum exceeds `r`). Draws happen **only** at these points, in this order:

1. **Start of a day** whose `modifier` is `random`: pick among modifiers with `pool: true`.
2. **Choosing:** if more than one outcome passes its `when`, pick one. Then, if a snap is possible (below), one snap draw.
3. **After a day-phase choice** (not after `hazard`, `forced` or `noHazard` events): one hazard draw. On a hit, one severity draw (only if a catastrophe is still allowed today), then one pick among eligible hazards (only if more than one).
4. **Next random event** (no forced event due): one pick among eligible events.
5. **Night cards:** one pick among eligible night events.

## A step: `choose(i)`

`i` indexes the **visible** choices (those whose `when` passes). A visible choice with `minEnergy > energy` is **locked**; choosing it is an error.

1. **Outcome:** keep outcomes whose `when` passes; pick by weight if there are several.
2. **Snap:** in the day phase, if the choice has `snapRisk` and `energy < snap.belowEnergy`, draw; if `r*100 < snap.chancePct`, the outcome is replaced by `config.snap` (its text, effects and flags). The original outcome's week-long flags (those not starting `d:`) are still set, after the snap's, so escalation chains and callbacks continue.
3. **Apply:** effects (each clamped), `set`, `clear`, `count`, `ledger` (each `cat: who` adds 1; in the night phase `night` also adds to `nightYou`/`nightPartner`), choice `tags` (`style.<tag>` += 1), `schedule` (queue `{event, at: now + in}`, using `now` before time advances), `cancel` (remove queued entries for those events), `completeTask` (an id or `oldest`: mark done, `ledger.you.errands` += 1).
4. **Time** (day phase only): `minutes = duration + eventGap`. For each drift rule in order, if its `when` passes now: `meter += delta × (⌊t1/every⌋ − ⌊t0/every⌋)`, where `t0 = clock − dayStart`, `t1 = t0 + minutes`. Then `clock += minutes`.
5. Record `seenToday`, `seenWeek`, `lastEventId`; `step += 1`.
6. **Losses:** for meters in `lossOrder`, the first at 0 triggers a loss. If the meter is in `lifelineMeters`, it's not Friday, and the lifeline is unused: use it (apply `lifeline` effects, `lostDays += 1`); by day this also ends the day (go to night), at night the night simply continues. Otherwise the week ends with `losses[meter]`.
7. **Checks:** the first `checks` entry whose `when` passes ends the week with its ending.
8. `endsWeek`: the week ends with the grade for `Σ weekScore[m] × meter`.
9. `endsDay`: apply `bedtime.asleep` if `sleepy ≥ bedtime.threshold`, else `bedtime.awake` and set `bedtime.awakeFlag`. Go to night.
10. **Night phase:** decrement cards left; when none remain, run the morning and start the next day.
11. **Day phase:** expire overdue tasks (list order; queue each `expire` event now), roll for a hazard, then pick the next event.

## Hazards

Chance in percent = `base + bandBonus[band] + (clock ≥ lateDayClock ? lateDayBonus : 0)`. On a hit, the severity is a catastrophe if `catastrophesToday < maxCatastrophesPerDay` and the severity draw is `< catastropheShare[band]` (percent), otherwise a sting. Eligible hazards: that severity, `when` passes, not seen today (nor this week if `oncePerWeek`), not already queued. If the hazard has a `tell`, queue the tell then the hazard (both now), otherwise just the hazard. A catastrophe adds 1 to `catastrophesToday` when queued.

## Picking the next day event

1. **Forced candidates:** due queue entries (events marked `forced` only ever appear this way) (by `at`, then `seq`; entries whose event `when` fails are dropped) and eligible `priority > 0` events (file order). A queued event's priority is its own, or 80 if it has none. Highest priority wins; ties go to queued entries first, then file order. A chosen queue entry is removed.
2. **Otherwise random:** events with no priority (`priority` absent or ≤ 0), `phase: day`, no `hazard`, not `forced`, not `filler`, `repeatable` or not seen today, not seen this week if `oncePerWeek`, not the last event, clock inside `window`, `when` passes, its `task` (if any) open, at least one visible choice. Weight = `weight + ⌊counters[weightBy.counter] / weightBy.every⌋`.
3. **Otherwise** the filler event.

Night cards: events with `phase: night`, `when` passes, not seen today (nor this week if `oncePerWeek`); weighted pick.

## Going to night and the morning

**Night:** `phase = night`, cards = `night.cards` (+1 if the awake flag is set), `nightYou = nightPartner = 0`, queue cleared.

**Morning:**

1. `energy += max(minRefill, base − perWake × nightYou − (lateCoffeeFlag ? lateCoffeePenalty : 0))`
2. `debt += debtPerWake × (nightYou + nightPartner) − recovery`
3. `mood = moodBase − ⌊debt / moodDebtDiv⌋`; `sleepy = sleepyStart`
4. Clear `d:` flags.
5. If `rel ≥ partnerTaskMinRel`, your partner completes the oldest open task (`ledger.partner.errands += 1`).
6. `day += 1`, then start the day:
   - `clock = dayStart =` the wake time for the debt band;
   - clear `seenToday`, the queue and `lastEventId`; `catastrophesToday = 0`;
   - apply the day's modifier (`random` draws from the pool);
   - add the day's tasks;
   - pick the first event.

The engine keeps a `report` of the last morning for the UI. Its `debtAfter` is captured before the new day's modifier applies.
