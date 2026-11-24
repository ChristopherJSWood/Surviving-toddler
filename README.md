# Bedtime or Bust

A satirical iOS game about getting through a week with a toddler. You're a partnered parent. Make it from Monday's 5:58 AM monitor crackle to Friday's date night without collapsing, losing your partner, or getting removed from the group chat.

- **Platform:** iOS 17+ (iPhone and iPad), SwiftUI
- **Play it in a browser:** open `prototype/index.html`. It runs the same rules and content as the iOS app.

## How the week works

Each card is a moment of your day with two to four choices. Every choice costs time and moves your meters.

| Group | Meter | What it does |
|---|---|---|
| You | **Energy** | How much parent you have left. Engaged choices cost it and lock ("Too tired") below their minimum. Shortcuts give it back now and bill you later. 0 = you collapse. |
| | **Relationship** | Drains when your Energy is low. Decides how much your partner helps. 0 = "We need to talk": the week ends. |
| Toddler | **Mood** | 0 = meltdown. |
| | **Sleep** | Today's sleepiness (must reach the line at bedtime) and the week's **sleep debt**. High debt means earlier mornings, more hazards and faster meltdowns. |
| Household | **House**, **Reputation** | 0 loses the day. Grandma rescues one day per week. |

Also in play:

- **Shortcuts with paybacks.** TV during a tantrum gives +Energy now and queues the Screen-Off Meltdown. A ticking chip shows when it's due.
- **Random hazards.** Most come with a warning you can act on; some are pure ambushes; rare catastrophes can follow you into tomorrow.
- **The mental-load list.** Tasks arrive each morning; forget one and it bites.
- **The ledger.** It records who did the night wakings, baths and dishes, and it decides how blame plays out.
- **Nights.** Two or three 2 AM cards set tomorrow's Energy and sleep debt.
- **Friday's date night.** At 7:00 the toddler must be asleep (Sleepiness 67+) and you need 35+ Energy.
- **Endings.** The week closes with your parenting style and a weekly performance review.

## Run it on a Mac (Xcode 26)

```sh
brew install xcodegen          # one time
xcodegen generate              # creates BedtimeOrBust.xcodeproj from project.yml
open BedtimeOrBust.xcodeproj   # pick an iPhone simulator, press ⌘R
swift test --package-path Core # engine + conformance tests, no simulator needed
```

## Project layout

```
App/                  SwiftUI app: GameStore (flow, save/resume) and screens
Core/                 Swift package BedtimeCore: the rules engine (Foundation only)
  Sources/BedtimeCore/Resources/content.json   GENERATED: built from content/
  Tests/              unit tests + golden-trace conformance tests
content/              THE GAME'S WORDS AND NUMBERS
  base.json           config, days, tasks, styles, endings, anchor cards
  events/*.json       card packs, merged in filename order
tools/                Node scripts (Node 18+, no npm install)
  engine.mjs          reference rules engine: the executable spec
  build-content.mjs   merges content/ into content.json (--validate, --check)
  validate.mjs        content linter
  simulate.mjs        week simulator with balance targets (--check)
  golden.mjs          records traces the Swift tests replay
  build-prototype.mjs builds the browser playtest page
prototype/            single-file browser build
docs/RULES.md         the rules, including the order of random draws
docs/CONTENT_GUIDE.md how to write cards
docs/DESIGN.md        design rationale, research, balance data, risks
```

## Changing the game

```sh
node tools/build-content.mjs --validate   # lint your edits
node tools/build-content.mjs              # write content.json
node tools/simulate.mjs                   # still balanced?
node tools/golden.mjs                     # refresh the Swift conformance fixture
node tools/build-prototype.mjs            # refresh the browser build
```

CI runs all of these, then the Swift tests and an iOS Simulator build on a GitHub macOS runner.

**Two engines, one set of rules.** The rules exist in Swift (for the app) and JavaScript (for the simulator and browser build). Both use the same random number generator (mulberry32) and the same draw order (docs/RULES.md). `golden.mjs` records 30 full seeded weeks from the JavaScript engine, and `ConformanceTests.swift` replays them, failing on the first difference.
