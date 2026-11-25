# Writing Content (v3)

**Read [VOICE.md](VOICE.md) first.** It covers how the game should sound and how to be funny. This file covers the fields.

All words and numbers live in `content/`:

- `content/base.json`: config and tables (days, modifiers, tasks, styles, endings, lifeline). Its `events` is empty.
- `content/events/*.json`: each file is a JSON **array** of events. Files merge in filename order, which also breaks ties between same-priority anchors.

| File | Holds |
|---|---|
| `00-anchors.json` | the day's skeleton: wake, breakfast, nap, handoff, dinner, bedtime, Friday, date night, meltdown, filler |
| `10-recurring.json` | recurring situations with escalating variants: tantrums, food refusal, coffee, snacks, diapers |
| `20-classics.json`, `30-days.json` | one-off day cards; day- and modifier-specific cards |
| `30-hazards.json`, `30-paybacks.json` | hazards with their warning cards, and shortcut paybacks |
| `30-partner.json`, `40-chats.json`, `40-storylines.json` | partner and blame cards, text threads, week-long running gags |
| `30-moments.json`, `30-nights.json`, `30-tasks.json` | small good moments, 2 AM cards, mental-load tasks |

Build and check:

```sh
node tools/build-content.mjs --validate   # merge in memory + lint, writes nothing
node tools/build-content.mjs              # write Core/Sources/BedtimeCore/Resources/content.json
```

The rules themselves are in `docs/RULES.md`.

## Meters

| Key | Shown as | Notes |
|---|---|---|
| `energy` | **Bandwidth** | The parent's capacity, mental load included. 0 = collapse. Engaged parenting costs it; shortcuts give it back now and bill you later. Social judgment costs it too. |
| `rel` | **Relationship** | With your partner. Drifts down slowly, and faster when Bandwidth is low. 0 ends the week ("We need to talk"). Shared mess and blame cost it. |
| `mood` | **Mood** | The toddler's. 0 triggers the meltdown card. |
| `debt` | **Sleep** (shown as 100 − debt) | Toddler sleep debt across the week. Raising `debt` lowers Sleep. High debt = earlier wake-up, more hazards, faster mood loss. |
| `sleepy` | the **bedtime word** | Today's sleep pressure. Rises all day; naps lower it. Must be 50+ at bedtime (higher at 7:00 PM on Friday, when you also need 35+ Bandwidth). |

There is no House or Reputation meter (removed in v3). Mess and the group chat's judgment are paid in Bandwidth or Relationship.

Typical effect sizes (v3): small ±4–8, medium ±10–18, big ±20–35. A week is about 100 cards, so each one has to matter.

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
| `family` | Recurring situation (`tantrum`, `food`, `nap`, `coffee`...). Variants of one family chain with week-long flags so each repeat is a new card. |
| `chat` | `{ "with": "{partner}", "messages": [ { "from": "{partner}", "text": "..." }, { "from": "you", "text": "..." } ] }`: the card plays out as a text thread (1–8 messages, each ≤ 160 characters). `text` is still required, as a one-line caption. |
| `timer` | 3–10 seconds to choose (panic cards). Needs exactly one choice with `"timeout": true`, which isn't shown as a button and happens if time runs out. Players can turn timers off, and they're off with VoiceOver. |

### Choice fields

| Field | Use |
|---|---|
| `label`, `duration` | Button text and minutes (≥ 1). 15 extra minutes always pass between cards. |
| `minEnergy` | Engaged choices: shown but **locked** ("Too tired") below this Energy. |
| `when` | Hides the choice unless met. |
| `tags` | Style tallies: `tagteam`, `negotiate`, `screen`, `martyr`, `bribe`, `boundary`, plus `present` (engaged; makes small moments likelier). |
| `snapRisk` | Calm or boundary-holding choices. Below 20 Energy there's a 30% chance you snap instead. |
| `timeout` | On a timed card only: what happens if you freeze. No `when` or `minEnergy`. |

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
| `stamp` | A verdict badge slammed onto the outcome, ALL CAPS, ≤ 24 characters (`BOUNDARY: HELD`). |
| `fx` | `shake`, `flash` (red alert) or `confetti` (a real win). |
| `chat` | Reply bubbles shown with the outcome, `[ { "from": "{partner}", "text": "lol" } ]` (≤ 4). |

### Names

Any text may use `{kid}`, `{KID}`, `{partner}`, `{me}` and `{ME}` (what the toddler calls you). The UI fills them in from the title screen, and the linter rejects any other `{...}`. The toddler and your partner are always they/them.

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
