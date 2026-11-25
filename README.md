# Bedtime or Bust

A satirical iOS game about getting through a week with a toddler. You're a partnered parent. Make it from Monday's 5:58 AM monitor crackle to Friday's date night without collapsing or losing your partner.

- **Platform:** iOS 17+ (iPhone and iPad), SwiftUI
- **Play it in a browser:** open `prototype/index.html`. It runs the same rules and content as the iOS app.

## How the week works

Each card is a moment of your day with two to four choices. Every choice costs time and moves your meters.

Four meters:

| Group | Meter | What it does |
|---|---|---|
| You | **Bandwidth** | How much parent you have left, mental load included. Engaged choices cost it and lock ("Too tired") below their minimum. Shortcuts give it back now and bill you later. At 0 you collapse; Grandma rescues one day a week. |
| | **Relationship** | Slowly drifts unless you tend it, and drains fast when your Bandwidth is low. Decides how much your partner helps. 0 = "We need to talk": the week ends. |
| Toddler | **Mood** | 0 = meltdown. |
| | **Sleep** | How rested the toddler is this week. Bad nights and skipped naps cost it: earlier mornings, more hazards, faster meltdowns. |

Plus a **bedtime word**: *Wired, Drowsy, Ready for bed* or *Overtired*. It's today's sleepiness against tonight's bar, so time the nap.

Also in play:

- **Shortcuts with paybacks.** TV during a tantrum gives +Energy now and queues the Screen-Off Meltdown. A ticking chip shows when it's due.
- **Random hazards.** Most come with a warning you can act on; some are pure ambushes; rare catastrophes can follow you into tomorrow.
- **The mental-load list.** Tasks arrive each morning; forget one and it bites.
- **The ledger.** It records who did the night wakings, baths and dishes, and it decides how blame plays out.
- **Nights.** Two or three 2 AM cards set tomorrow's Energy and sleep debt.
- **Friday's date night.** At 7:00 the toddler must be Ready for bed (Friday's bar is higher) and you need 35+ Bandwidth.
- **Endings.** The week closes with your parenting style and a weekly performance review.

The week is about 100 cards long. Recurring situations (tantrums, food fights, bad naps, coffee) keep coming back, and each time it's a new card that knows it's a repeat. Other cards appear at most once a week.

- **Your household.** Before the first week, you name your toddler and your partner and pick what the toddler calls you. The game uses those names throughout.
- **Texts and the group chat.** Some cards play out as text threads with your partner or the daycare parents' group chat.
- **Running storylines.** Some gags build across the week and pay off later.
- **Panic cards.** You get a few seconds to decide, or the toddler decides for you. You can turn timers off; they're always off with VoiceOver.
- **Drama.** Verdict stamps slam onto outcomes, the screen shakes, flashes red or throws confetti, and meters float their changes. Every effect respects Reduce Motion.
- **Playtest log.** Tap 😂 or 😴 on any outcome; the title screen exports the taps as a CSV, so you can see which cards land and which drag. "Send to <partner>" shares a card.

How the game should sound, and how to be funny, is in [docs/VOICE.md](docs/VOICE.md).

## Run it on a Mac (Xcode 15 or later)

One command checks your tools, runs the engine tests, builds the app and launches it in the iOS Simulator:

```sh
tools/mac-build.sh         # or: --no-launch, or --playtest (plays a whole week, saves screenshots)
```

Each step stops with the command that fixes it. The full output is in `build/mac-build.log`. If XcodeGen isn't installed, the script downloads the official release into `build/tools` and checks its checksum. Homebrew can't install XcodeGen on macOS 14 with Xcode older than 15.3.

Tested: Xcode 15.2 (Swift 5.9.2) on macOS 14.8, iPhone 15 Pro simulator, iOS 17.2. Submitting to the App Store requires a current Xcode, which needs a newer macOS than 14.

| If it stops at | Run |
|---|---|
| xcode-select points to CommandLineTools | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| License not accepted | `sudo xcodebuild -license accept` |
| First launch / missing components | `xcodebuild -runFirstLaunch` |
| No iOS Simulator runtime | `xcodebuild -downloadPlatform iOS` (several GB) |
| App build | the error lines it prints are Swift compile errors: fix them, or paste them to whoever is helping |

To work in Xcode instead: `xcodegen generate`, `open BedtimeOrBust.xcodeproj`, pick an iPhone simulator, press ⌘R. `BedtimeOrBust.xcodeproj` is generated and git-ignored: change `project.yml`, not the project.

**On your own iPhone (optional, free Apple ID):**
1. In Xcode, open target BedtimeOrBust, then Signing & Capabilities.
2. Pick your Personal Team and change the bundle identifier from `com.example.bedtimeorbust` to something unique.
3. On the phone, turn on Settings > Privacy & Security > Developer Mode.
4. Connect the phone, select it as the destination, and press ⌘R.

Two catches: `xcodegen generate` resets the team, so set it again after regenerating; and free-team installs stop launching after a few days until you run them from Xcode again.

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
  policies.mjs        scripted players shared by simulate.mjs and golden.mjs
  golden.mjs          records traces the Swift tests replay
  build-prototype.mjs builds the browser playtest page
  mac-build.sh        Mac: check tools, test, build, launch in the Simulator
prototype/            single-file browser build
docs/RULES.md         the rules, including the order of random draws
docs/CONTENT_GUIDE.md how to write cards (fields)
docs/VOICE.md         how the game sounds and how to be funny
UITests/              automated full-week playthrough on the simulator
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

CI runs all of these, then the Swift tests on Linux. An iOS Simulator build on a GitHub macOS runner is configured but non-blocking: those runners haven't started for this account.

**Two engines, one set of rules.** The rules exist in Swift (for the app) and JavaScript (for the simulator and browser build). Both use the same random number generator (mulberry32) and the same draw order (docs/RULES.md). `golden.mjs` records full seeded weeks from the JavaScript engine: 30 with a fixed index policy, plus weeks from the simulator's scripted players, picked until every card and every ending appears and the snap path is exercised. `ConformanceTests.swift` replays every step: the card, which choices are visible and unlocked, the outcome, any snap, the clock and all seven meters. It fails on the first difference, and it checks the coverage itself. The app can't use `@testable`, so CI also type-checks `App/GameStore.swift` against the engine's public API on Linux.
