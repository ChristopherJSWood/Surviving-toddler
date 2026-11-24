# Writing Content (v2: the week)

All words and numbers live in `content/`:

- `content/base.json`: config, tables (days, modifiers, tasks, styles, endings, lifeline) and the anchor cards (wake, breakfast, nap, handoff, dinner, bedtime, Friday, date night).
- `content/events/*.json`: each file is a JSON **array** of events. Files merge in filename order.

Build and check:

```sh
node tools/build-content.mjs --validate   # merge in memory + lint, writes nothing
node tools/build-content.mjs              # write Core/Sources/BedtimeCore/Resources/content.json
```

The rules themselves are in `docs/RULES.md`.

## Meters

| Key | Name | Notes |
|---|---|---|
| `energy` | Energy | The parent's capacity. 0 = collapse. Engaged parenting costs it; shortcuts give it back now and bill you later. |
| `rel` | Relationship | With your partner. Drains on its own when Energy is low. 0 ends the week ("We need to talk"). |
| `mood` | Toddler Mood | 0 triggers the meltdown card. |
| `sleepy` | Sleepiness | Today's sleep pressure. Rises all day; naps lower it. Must be 50+ at bedtime (67+ at 7:00 PM on Friday, when you also need 35+ Energy). |
| `debt` | Sleep Debt | Toddler sleep debt across the week. High debt = earlier wake-up, more hazards, faster mood loss. |
| `home` | House | 0 = condemned. |
| `rep` | Reputation | What other parents think. 0 = removed from the group chat. |

Typical effect sizes: small ±2–5, medium ±6–12, big ±15–25. Catastrophes go up to −35 total across meters.

## An event

```json
{
  "id": "candy_bribe",
  "title": "The Checkout Lane",
  "text": "Candy, at eye level, with a cartoon on it. The toddler has spotted it. The toddler is drawing a breath.",
  "window": [540, 1020],
  "weight": 2,
  "when": { "notFlags": ["d:home"] },
  "choices": [
    { "label": "Buy the candy", "duration": 3, "tags": ["bribe"], "outcomes": [
      { "text": "...", "effects": { "mood": 12, "energy": 4 }, "count": { "snacks": 1 },
        "schedule": [ { "event": "sugar_crash", "in": 45 } ] } ] },
    { "label": "\"Not today.\"", "duration": 10, "tags": ["boundary"], "snapRisk": true, "outcomes": [
      { "weight": 1, "text": "...", "effects": { "mood": -4 } },
      { "weight": 2, "text": "...", "effects": { "mood": -14, "rep": -5 } } ] },
    { "label": "Turn it into a game: find something red", "duration": 5, "minEnergy": 30, "tags": ["present"], "outcomes": [
      { "text": "...", "effects": { "mood": 6, "energy": -6 } } ] }
  ]
}
```

### Event fields

| Field | Use |
|---|---|
| `window` | `[from, to]` in minutes since midnight (360 = 6:00 AM, 720 = noon, 1020 = 5 PM, 1170 = 7:30 PM). Required for normal day events. |
| `weight` | Relative odds among eligible random events (default 1). |
| `weightBy` | `{ "counter": "style.present", "every": 3 }` adds 1 to the weight per 3 counts. Use on small moments. |
| `when` | Condition (below). |
| `repeatable`, `oncePerWeek` | By default an event appears at most once a day. |
| `priority` | > 0 forces the event as soon as it's eligible. Anchors only. |
| `phase: "night"` | A 2 AM night card. No window. |
| `forced: true` | Only appears when something queues it (a `schedule`, a `tell`, or a task `expire`). No window. |
| `hazard: "sting"` / `"catastrophe"` | Only appears through the random hazard roll. No window. |
| `tell: "event_id"` | For a hazard: the warning card shown first. The tell must be `forced`, and its attentive choice should `cancel` the hazard. |
| `task: "task_id"` | Only eligible while that mental-load task is open. Its "do it now" outcome uses `completeTask`. |
| `moment: true` | Marks a small good moment (styling only). |

### Choice fields

| Field | Use |
|---|---|
| `label`, `duration` | Button text and minutes (≥ 1). 15 extra minutes always pass between cards. |
| `minEnergy` | Engaged choices: shown but **locked** ("Too tired") below this Energy. |
| `when` | Hides the choice unless met. |
| `tags` | Style tallies: `tagteam`, `negotiate`, `screen`, `martyr`, `bribe`, `boundary`, plus `present` (engaged; makes small moments likelier). |
| `snapRisk` | Calm or boundary-holding choices. Below 20 Energy there's a 30% chance you snap instead. |

Every event needs at least one choice with no `when` and no `minEnergy`.

### Outcome fields

| Field | Use |
|---|---|
| `text` | What happened. |
| `weight` | Relative odds among outcomes that pass their `when`. |
| `when` | Outcome only possible if met. If every outcome has a `when`, they must test one variable and cover all of its values (e.g. `min rel 50` / `max rel 49`). |
| `effects` | `{ meter: delta }`. |
| `set`, `clear` | Flags. Flags starting `d:` reset every morning. |
| `count` | Receipt counters; must be declared in `base.json` `counters`. |
| `ledger` | `{ "night": "you" }`: who did a chore. Categories: `night`, `morning`, `bath`, `dishes`, `bedtime`, `dinner`, `errands`, `evening`, `laundry`. |
| `schedule` | `[{ "event": "id", "in": minutes }]`: queue a forced event (the payback for a shortcut). |
| `cancel` | `["id"]`: remove queued events (an attentive tell response cancels its hazard). |
| `completeTask` | A task id, or `"oldest"`. |

### Conditions

`{ "flags": [...], "notFlags": [...], "min": {...}, "max": {...} }`. `min` and `max` take any meter plus `day` (0 = Monday … 4 = Friday) and `ledger` (your chores minus your partner's; positive means you've done more).

Useful flags: `d:screen` (TV used today), `d:snapped`, `d:napSkipped`, `d:napDone`, `d:lateCoffee`, `d:handoff`, `d:secondWind` (the toddler wasn't sleepy at bedtime), `d:deadline` (Tue), `d:home` (Wed: daycare closed), `d:teething`, `d:grandma`, `d:potty` (Thu modifiers), `d:friday`.

## Tone

Adult, deadpan and specific. The jokes aim at the adult world: advice, influencers, the group chat, work, marketing, your own coping, and the two of you being too tired to be kind.

- **Swearing:** mild words in text ("damn", "crap", "hell", "ass"). The strongest words are bleeped, written `[BLEEP]`. The linter rejects unbleeped strong profanity.
- **The partner** is always "your partner", never gendered, never the villain. Blame is mutual, petty, recognizable and repairable. Nobody controls, threatens or humiliates anyone.
- **The toddler** is never hurt. No joke comes at the child's expense. Neglect and unsafe shortcuts are never the winning choice. Real safety practice plays it straight.
- **Drinking** jokes are about exhaustion, never about being impaired while in charge of the child.
- **Snapping** is never a win; it gets a regret card at night.
- **No real** brands, shows, products, influencers or people. Use parody types ("a man in an alarming amount of corduroy", "Sunshine Sing-Along").
- **Small moments** are sincere. No punchline undercuts them.
- **Length:** titles ≤ 44 characters, text ≤ 300, labels ≤ 64. One idea per card. Concrete numbers ("34 whys", "$3.49").
- **Facts** in "Experts Say" cards must be true:
  - 11–14 hours of sleep per 24 hours for ages 1–2 ([Paruthi et al., 2016](https://doi.org/10.5664/jcsm.5866); *to confirm:* the PubMed abstract doesn't list the ranges, so check the full text's table before shipping);
  - 8–10 or more tries before a new food is accepted ([Spill et al., 2019](https://doi.org/10.1093/ajcn/nqy308)).

## Design rules

1. **Every choice needs a real upside.** The simulator fails CI on choices that are worse on every meter.
2. **Engaged options cost Energy and carry `minEnergy`.** The lazy option is always available, and usually schedules or flags a later cost.
3. **Every hazard with a `tell` gives the player a fair chance:** the tell's attentive choice `cancel`s it.
