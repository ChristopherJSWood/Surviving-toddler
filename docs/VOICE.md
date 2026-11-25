# Voice and Comedy Guide (v3)

The first human playtest said the game was "almost boring." Measured across 300 simulated weeks:

- **Repetition.** About half the cards in a week were repeats; the coffee card showed up 6–8 times, word for word.
- **Length.** A week ran 150–190 cards, roughly 10,000 words.
- **Predictability.** 75% of the choices players made had a single fixed outcome.
- **Small stakes.** 43% of outcomes moved the meters by 8 points or less.

This guide fixes the writing half of that. The schema is in [CONTENT_GUIDE.md](CONTENT_GUIDE.md).

## The voice: sharper deadpan × tiny tyrant

Switch between two registers depending on the situation.

| When the card is about... | Use | Sounds like |
|---|---|---|
| The toddler wanting, refusing, ruling, negotiating | **Tiny tyrant**: the toddler is a head of state, a CEO, a judge or a union boss, and you are the staff | "{kid} has vetoed the green cup. The decision is final. There is no appeals process." |
| You, your exhaustion, your partner, the adult world (group chat, work, advice culture, products) | **Sharper deadpan**: flat, specific, understated, with the punch on the last word | "You have spent $1,100 on wet gardens this year." |

The tyrant framing is a lens, not a costume. Don't put "Your Majesty" in every line. Use the institutional verbs (vetoes, overturns, files, audits, decrees, ratifies, unionizes, recalls the ambassador) and let the situation do the work.

## Names

The UI fills these in from the title screen.

| Placeholder | Means | Example |
|---|---|---|
| `{kid}` | the toddler's name | "{kid} has found the seam in their sock." |
| `{KID}` | the same, uppercase (for when you yell it) | "{KID}. NO. NOT THE—" |
| `{partner}` | your partner's name | "{partner} texts from the office." |
| `{me}` | what the toddler calls you (Mama, Dada, Mom, Papa...) | "\"{me}, I need you,\" they whisper, at 2:04 AM." |
| `{ME}` | the same, uppercase | "\"{ME}. {ME}. {ME}. {ME}.\"" |

- **Pronouns:** the toddler and your partner are always **they/them**. Never he/she, son/daughter or husband/wife. Narration says "you"; only the toddler says {me}.
- **Side characters** can have names and personalities, but keep their pronouns out of it where you can.

## Rules for funny

1. **Put a joke in the buttons.** Every choice label is a personality, not an action. Read the labels of one card together; they should sound like three different parents (the coward, the lawyer, the briber).
   - Bad: "Hand over the crackers."
   - Good: "Pay the crackers tax." / "Cite precedent: \"You SAID triangles.\"" / "Recut into squares like a coward."
2. **Be specific.** Use exact times (4:52 PM), counts (34 whys), prices ($3.49) and parody products ("Organic Harvest Medley"). Never say "some" or "a lot."
3. **Surprise.** At least **half the choices on a card need 2+ outcomes** that land differently, and one of them should flip the label's expectation. Keep it fair: a careful choice should still be the better bet.
4. **Bigger swings.** There are fewer cards now, so each must matter. Typical effects:

   | Size | Range |
   |---|---|
   | Small | ±4–8 |
   | Medium | ±10–18 |
   | Big | ±20–35 |

   No outcome should move nothing unless that's the joke.
5. **Escalate recurring situations.** Tantrums, food refusals, bad naps and coffee happen many times a week, and **every repeat is a different card** that knows it's a repeat. "Tantrum #3. You've started naming them like hurricanes." Chain the variants with week-long flags: `"set": ["tantrum:1"]`, and the next one requires `"flags": ["tantrum:1"], "notFlags": ["tantrum:2"]`.
6. **Call back.** Plant something early in the week and pay it off later (the Monday banana turns up in your shoe on Friday). Use flags without the `d:` prefix, which last all week.
7. **The toddler talks.** Their dialogue is the funniest thing in the game.
   - Short, ALL CAPS when yelling, with airtight toddler logic: "I WANT THE BLUE CUP," holding the blue cup.
   - They call you `{ME}` when they mean it.
8. **End on the punch.** The funniest word goes last. Cut everything after it.
9. **Length:**

   | Element | Aim | Hard limit |
   |---|---|---|
   | Card text | ≤ 220 characters | 300 |
   | Outcome | ≤ 200 characters | 300 |
   | Label | ≤ 50 characters | 64 |
   | Title | ≤ 32 characters | 44 |

   Titles are jokes too: "Toast Tribunal", "Nap: Attempt 2 of ∞", "Tantrum #4: Hurricane Gwendolyn".
10. **No reruns.** Normal cards get `"oncePerWeek": true`. Only use `repeatable` if you can defend it in writing.

### Banned (worn out, or already overused in this game)

- **Phrases:** "small mob boss", "hostage" (and "hostage negotiator"), "war hero", "crime scene", "boneless", "the forums", "a single tear", "peak living", "briefly human", "adulting", "mommy juice" or "wine o'clock", "we've all been there", "it's giving", "no thoughts".
- **Similes:** never use the same simile twice anywhere in the game. Search the other files before you use one.

## Stamps, effects, chats and timers

Field details are in [CONTENT_GUIDE.md](CONTENT_GUIDE.md).

- **`stamp`:** a verdict slammed onto the outcome. ALL CAPS, ≤ 24 characters, institutional or sports deadpan: `BOUNDARY: HELD`, `APPEAL DENIED`, `NAP: DENIED`, `PRECEDENT OVERTURNED`, `DIPLOMATIC INCIDENT`, `CASE CLOSED`, `TECHNICALLY A WIN`, `NOTED.`
  - Use it on about **1 outcome in 4**, mostly the big swings.
  - Don't reuse one stamp more than 3 times in the whole game.
- **`fx`:** what the screen does.
  - `shake`: a tantrum peaking, things falling, catastrophes. About 1 outcome in 10.
  - `flash`: a red alert for bad news, a loss or danger. About 1 in 20.
  - `confetti`: a real win (the nap took, date night, a sincere victory). About 1 in 20.
- **`chat`:** a card told as a text thread with `{partner}` or the group chat. 2–6 messages; texting voice (lowercase, quick, the occasional emoji); `"from": "you"` for your own messages. Outcomes can add reply bubbles. Groups are named like real ones: "Little Sprouts Parents 🌱 (23)".
- **`timer`:** a 4–6 second panic card for comic emergencies. If you freeze, the `"timeout": true` choice happens, and it's always the toddler's version of events.
  - Never use a timer for real physical danger. Safety plays straight.

## Tone limits (unchanged)

- **The toddler is never hurt.** No joke at the child's expense. Neglect and unsafe shortcuts never win.
- **Your partner is never the villain.** Blame is mutual, petty, recognizable and repairable.
- **Swearing:** mild words only. Strong words are written `[BLEEP]`, and the bleep can be the joke.
- **Drinking jokes** are about exhaustion, never about being impaired while in charge of the child.
- **Snapping is never a win.**
- **Small moments are sincere.** No punchline undercuts them: no stamp, no fx except `confetti` on the rare big one.
- **No real brands, shows, products or people.** Use parody types.

## Worked examples

These aren't in the game; don't copy them. They show the target.

### A recurring family, first of the week

```json
{
  "id": "example_tantrum_1",
  "family": "tantrum",
  "title": "Tantrum #1: The Sock Seam",
  "text": "{kid} has located the seam in their sock. The seam has always been there. Today, it has become a human rights issue.",
  "window": [420, 600], "weight": 3, "oncePerWeek": true,
  "when": { "notFlags": ["tantrum:1"] },
  "choices": [
    { "label": "Turn the sock inside out like a magician", "duration": 5, "minEnergy": 20, "tags": ["present"],
      "outcomes": [
        { "weight": 2, "text": "The seam is now on the outside, where it can't hurt anyone. {kid} inspects it like a customs officer and waves you through.", "effects": { "mood": 14, "energy": -6 }, "set": ["tantrum:1"], "stamp": "CLEARED CUSTOMS" },
        { "weight": 1, "text": "\"NOT LIKE THAT.\" There was a correct way to turn a sock inside out. You weren't told it. You will never be told it.", "effects": { "mood": -14, "energy": -6 }, "set": ["tantrum:1"], "stamp": "APPEAL DENIED", "fx": "shake" } ] },
    { "label": "Socks are cancelled. Effective immediately.", "duration": 2, "tags": ["negotiate"],
      "outcomes": [
        { "text": "{kid} accepts this instantly, which is somehow worse. They spend the morning barefoot and smug. The floor is 40% Cheerio.", "effects": { "mood": 10, "home": -10, "rep": -4 }, "set": ["tantrum:1"] } ] },
    { "label": "\"Those are the socks.\" Hold the line.", "duration": 12, "tags": ["boundary"], "snapRisk": true,
      "outcomes": [
        { "text": "Twelve minutes of grievance. Then they put the socks on themselves, sobbing, and leave with the dignity of someone carrying their desk out in a box.", "effects": { "mood": -10, "energy": -12 }, "set": ["tantrum:1"], "stamp": "BOUNDARY: HELD" } ] }
  ]
}
```

### The same family, escalated

```json
{
  "id": "example_tantrum_3",
  "family": "tantrum",
  "title": "Tantrum #3: Hurricane Gwendolyn",
  "text": "Third one this week. You've started naming them. Hurricane Gwendolyn formed over the discovery that bathwater is wet, and it is gaining strength.",
  "window": [1050, 1160], "weight": 3, "oncePerWeek": true,
  "when": { "flags": ["tantrum:2"], "notFlags": ["tantrum:3"] }
}
```

### A chat card

```json
{
  "id": "example_chat_ceiling",
  "title": "Status Update",
  "text": "{partner} checks in from the office, where people sit down.",
  "chat": { "with": "{partner}", "messages": [
    { "from": "{partner}", "text": "how's it going?" },
    { "from": "you", "text": "[photo: yogurt on the ceiling]" },
    { "from": "{partner}", "text": "wait how is it on the CEILING" } ] },
  "window": [720, 960], "oncePerWeek": true,
  "choices": [
    { "label": "\"Physics has left the chat.\"", "duration": 2,
      "outcomes": [
        { "text": "A wheezing emoji. Then the important one.", "effects": { "rel": 8, "energy": 6 }, "chat": [ { "from": "{partner}", "text": "want me to grab dinner on the way home" } ], "stamp": "DINNER: SECURED" } ] },
    { "label": "Send a four-minute voice memo", "duration": 5,
      "outcomes": [
        { "text": "You describe the incident in full. You cry briefly around minute three. {partner} listens to all of it at 2x speed, in a meeting.", "effects": { "rel": 6, "energy": 10 }, "chat": [ { "from": "{partner}", "text": "i'm so sorry. also my boss heard \"ceiling\"" } ] } ] },
    { "label": "Leave them on read. Let them wonder.", "duration": 1,
      "outcomes": [
        { "weight": 1, "text": "They wonder. They come home forty minutes early carrying three kinds of snacks.", "effects": { "rel": 4, "energy": 12 }, "stamp": "LEVERAGE" },
        { "weight": 1, "text": "They don't wonder. They forget. You don't.", "effects": { "rel": -12 }, "stamp": "NOTED." } ] }
  ]
}
```

### A panic card

```json
{
  "id": "example_panic_question",
  "title": "The Question",
  "text": "Checkout line. {kid} points at the man ahead of you and inhales. You know. Whatever comes next will be loud, and it will be accurate.",
  "window": [600, 1020], "oncePerWeek": true, "timer": 5,
  "when": { "notFlags": ["d:home"] },
  "choices": [
    { "label": "\"LOOK! A DOG!\" (There is no dog.)", "duration": 2,
      "outcomes": [
        { "weight": 2, "text": "{kid} spins around searching for the dog. By the time they realize there was never a dog, the man is gone. So is a little of their trust in you.", "effects": { "mood": -6, "rep": 4 }, "stamp": "CRISIS AVERTED" },
        { "weight": 1, "text": "\"THERE'S NO DOG, {ME}.\" They turn back to the man, now with more questions.", "effects": { "rep": -12 }, "fx": "shake" } ] },
    { "label": "Sing. Loudly. Anything.", "duration": 2,
      "outcomes": [
        { "text": "You belt the first song that comes to mind. It's the one about the bus. Everyone looks at you instead. That was the plan.", "effects": { "rep": -6, "mood": 10 }, "stamp": "TOOK THE HIT" } ] },
    { "label": "Freeze", "duration": 2, "timeout": true,
      "outcomes": [
        { "text": "\"WHY DOES THAT MAN HAVE NO HAIR ON HIS HEAD BUT LOTS IN HIS EARS.\" He turns around. He's heard it before. Never this loud.", "effects": { "rep": -18 }, "stamp": "DIPLOMATIC INCIDENT", "fx": "shake" } ] }
  ]
}
```

### A small moment (sincere: no stamp, no joke after it)

```json
{
  "id": "example_moment_lap",
  "moment": true,
  "title": "Unprompted",
  "text": "Out of nowhere, {kid} climbs into your lap, puts both hands on your face and says, \"{ME}. You my best friend.\" They mean it with their whole body.",
  "window": [600, 1100], "oncePerWeek": true,
  "choices": [
    { "label": "Hold still. Remember this.", "duration": 5,
      "outcomes": [ { "text": "You do. Later, on a hard night, this is the one you'll play back.", "effects": { "energy": 15, "mood": 10 }, "count": { "moments": 1 } } ] }
  ]
}
```
