import Foundation

/// A mental-load task on the player's list.
public struct TaskState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case open, done, expired }
    public var id: String
    /// Absolute week minute (`day * 1440 + clock`) when it expires.
    public var due: Int
    public var status: Status
}

/// A forced event waiting to happen (a payback, a tell, an expired task).
public struct QueueEntry: Codable, Equatable, Sendable {
    public var event: String
    public var at: Int
    public var seq: Int
}

/// What happened overnight, for the morning report screen.
public struct DayReport: Codable, Equatable, Sendable {
    public var day: Int
    public var nightYou: Int
    public var nightPartner: Int
    public var refill: Int
    public var debtBefore: Int
    public var debtAfter: Int
    public var partnerDid: String?
    public var wakeClock: Int
    public var tasksAdded: [String]
    public var modifierID: String
}

/// Everything needed to resume a week exactly where it left off, including
/// the RNG state, so a restored game continues identically.
public struct GameState: Codable, Equatable, Sendable {
    public internal(set) var seed: UInt32
    public internal(set) var rng: SeededRandom
    public internal(set) var meters: Meters
    public internal(set) var day: Int
    public internal(set) var phase: Phase
    public internal(set) var clock: Int
    public internal(set) var dayStart: Int
    public internal(set) var flags: Set<String>
    public internal(set) var counters: [String: Int]
    public internal(set) var ledgerYou: [String: Int]
    public internal(set) var ledgerPartner: [String: Int]
    public internal(set) var nightYou: Int
    public internal(set) var nightPartner: Int
    public internal(set) var nightCardsLeft: Int
    public internal(set) var tasks: [TaskState]
    public internal(set) var queue: [QueueEntry]
    public internal(set) var seq: Int
    public internal(set) var seenToday: Set<String>
    public internal(set) var seenWeek: Set<String>
    public internal(set) var lastEventID: String?
    public internal(set) var currentEventID: String?
    public internal(set) var modifierID: String
    public internal(set) var step: Int
    public internal(set) var catastrophesToday: Int
    public internal(set) var lifelineUsed: Bool
    public internal(set) var lostDays: Int
    public internal(set) var endingID: String?
    public internal(set) var report: DayReport?

    /// Absolute week minute.
    public var now: Int { day * 1440 + clock }
}

public enum DayTransition: String, Equatable, Sendable {
    /// Bedtime: the night chapter begins.
    case night
    /// A loss was rescued by the once-a-week lifeline; the day is over.
    case lifeline
    /// The night ended and a new day began.
    case morning
}

/// What happened after a choice, for the outcome screen.
public struct StepResult: Equatable, Sendable {
    public let eventID: String
    public let choiceIndex: Int
    public let outcomeIndex: Int
    public let snapped: Bool
    public let text: String
    /// Net change per meter from this choice (overnight changes are in `GameState.report`).
    public let deltas: [Meter: Int]
    public let minutes: Int
    public let transition: DayTransition?
    public let endingID: String?
    /// Presentation only, from the applied outcome (none when you snapped).
    public let stamp: String?
    public let fx: OutcomeFX?
    public let chat: [ChatMessage]
}

public enum GameError: Error, Equatable {
    case gameOver
    case invalidChoice(Int)
    case lockedChoice(Int)
    case noOutcome(String)
}

/// The rules, a line-for-line port of `Game` in tools/engine.mjs (the
/// executable spec; prose in docs/RULES.md). ConformanceTests replays golden
/// traces from it. Change a rule there first, then here, then regenerate.
public struct GameEngine: Sendable {
    public let content: GameContent
    public private(set) var state: GameState
    private let eventIndex: [String: Int]

    public init(content: GameContent, seed: UInt32) {
        self.content = content
        eventIndex = Self.makeIndex(content.events)
        state = GameState(
            seed: seed, rng: SeededRandom(seed: seed), meters: content.config.startMeters,
            day: 0, phase: .day, clock: 0, dayStart: 0, flags: [], counters: [:],
            ledgerYou: [:], ledgerPartner: [:], nightYou: 0, nightPartner: 0, nightCardsLeft: 0,
            tasks: [], queue: [], seq: 0, seenToday: [], seenWeek: [], lastEventID: nil,
            currentEventID: nil, modifierID: "", step: 0, catastrophesToday: 0,
            lifelineUsed: false, lostDays: 0, endingID: nil, report: nil
        )
        startDay(0)
    }

    public init(content: GameContent, restoring state: GameState) {
        self.content = content
        eventIndex = Self.makeIndex(content.events)
        self.state = state
    }

    // MARK: - Queries

    public var currentEvent: GameEvent? { state.currentEventID.flatMap(event(withID:)) }
    public var modifier: DayModifier? { content.modifiers.first { $0.id == state.modifierID } }
    public var ending: Ending? { state.endingID.flatMap { content.endings[$0] } }
    public var isOver: Bool { state.endingID != nil }
    public var dayDefinition: DayDefinition { content.days[Swift.min(state.day, content.days.count - 1)] }

    public func event(withID id: String) -> GameEvent? {
        eventIndex[id].map { content.events[$0] }
    }

    /// Your chores minus your partner's. Positive means you've done more.
    public var ledgerBalance: Int {
        state.ledgerYou.values.reduce(0, +) - state.ledgerPartner.values.reduce(0, +)
    }

    /// Week score for grading (`Σ weekScore[m] × meter`).
    public var score: Int {
        content.config.weekScore.reduce(0) { $0 + $1.value * state.meters[$1.key] }
    }

    /// 0 rested, 1 tired, 2 wrecked (from toddler sleep debt).
    public var debtBand: Int {
        let debt = state.meters.debt
        return debt <= 29 ? 0 : (debt <= 59 ? 1 : 2)
    }

    /// The parenting style with the highest tally (ties: content order).
    public var style: StyleInfo? {
        var best: StyleInfo?
        var bestCount = 0
        for style in content.styles {
            let count = state.counters["style.\(style.id)"] ?? 0
            if count > bestCount {
                best = style
                bestCount = count
            }
        }
        return best ?? content.styles.first
    }

    /// Queued events that are still in the future, soonest first (for HUD chips).
    public var upcoming: [(event: GameEvent, at: Int)] {
        state.queue
            .filter { $0.at > state.now }
            .sorted { ($0.at, $0.seq) < ($1.at, $1.seq) }
            .compactMap { entry in event(withID: entry.event).map { ($0, entry.at) } }
    }

    public func meets(_ condition: Condition?) -> Bool {
        guard let condition else { return true }
        for flag in condition.flags where !state.flags.contains(flag) { return false }
        for flag in condition.notFlags where state.flags.contains(flag) { return false }
        for (key, value) in condition.minimum where self.value(of: key) < value { return false }
        for (key, value) in condition.maximum where self.value(of: key) > value { return false }
        return true
    }

    private func value(of variable: String) -> Int {
        switch variable {
        case "day": return state.day
        case "ledger": return ledgerBalance
        default: return Meter(rawValue: variable).map { state.meters[$0] } ?? 0
        }
    }

    /// Choices the player can see for `event` (default: the current event).
    public func visibleChoices(for event: GameEvent? = nil) -> [Choice] {
        guard let event = event ?? currentEvent else { return [] }
        return event.choices.filter { meets($0.condition) }
    }

    /// Visible but unaffordable: shown greyed out as "Too tired".
    public func isLocked(_ choice: Choice) -> Bool {
        choice.minEnergy > state.meters.energy
    }

    // MARK: - Playing

    @discardableResult
    public mutating func choose(_ index: Int) throws -> StepResult {
        guard !isOver, let event = currentEvent else { throw GameError.gameOver }
        let choices = visibleChoices(for: event)
        guard choices.indices.contains(index) else { throw GameError.invalidChoice(index) }
        let choice = choices[index]
        guard !isLocked(choice) else { throw GameError.lockedChoice(index) }
        let before = state.meters
        let dayBefore = state.day
        let nowBefore = state.now

        let candidates = choice.outcomes.filter { meets($0.condition) }
        guard !candidates.isEmpty else { throw GameError.noOutcome(event.id) }
        var outcomeIndex = 0
        if candidates.count > 1 {
            outcomeIndex = Self.weightedPick(candidates, weight: { $0.weight }, rng: &state.rng)
        }
        var outcome = candidates[outcomeIndex]
        var snapped = false
        let snap = content.config.snap
        if state.phase == .day, choice.snapRisk, state.meters.energy < snap.belowEnergy {
            if state.rng.next() * 100 < Double(snap.chancePct) {
                snapped = true
                // The story keeps going: the original's week-long flags still apply.
                let keep = outcome.setFlags.filter { !$0.hasPrefix("d:") }
                outcome = Outcome(text: snap.text, effects: snap.effects, setFlags: snap.setFlags + keep)
            }
        }
        apply(outcome, nowBefore: nowBefore)
        for tag in choice.tags { state.counters["style.\(tag)", default: 0] += 1 }

        var minutes = 0
        if state.phase == .day {
            minutes = choice.duration + content.config.eventGap
            advance(minutes: minutes)
        }
        state.seenToday.insert(event.id)
        state.seenWeek.insert(event.id)
        state.lastEventID = event.id
        state.step += 1

        var transition: DayTransition?
        var endingID: String?
        switch lossCheck() {
        case .none: break
        case .lifeline: if state.phase == .day { transition = .lifeline }
        case .ending(let id): endingID = id
        }
        if endingID == nil, transition == nil {
            for check in event.checks where meets(check.condition) {
                endingID = check.ending
                break
            }
        }
        if endingID == nil, transition == nil, event.endsWeek { endingID = grade() }
        if endingID == nil, transition == nil, event.endsDay {
            let bedtime = content.config.bedtime
            if state.meters.sleepy >= bedtime.threshold {
                applyEffects(bedtime.asleep)
            } else {
                applyEffects(bedtime.awake)
                state.flags.insert(bedtime.awakeFlag)
            }
            transition = .night
        }

        var deltas: [Meter: Int] = [:]
        for meter in Meter.allCases where state.meters[meter] != before[meter] {
            deltas[meter] = state.meters[meter] - before[meter]
        }

        if let endingID {
            state.endingID = endingID
            state.currentEventID = nil
        } else if transition != nil {
            goToNight()
        } else if state.phase == .night {
            state.nightCardsLeft -= 1
            if state.nightCardsLeft <= 0 { morning() } else { pickNight() }
        } else {
            expireTasks()
            if event.hazard == nil, !event.forced, !event.noHazard { rollHazard() }
            state.currentEventID = nextDayEvent().id
        }

        if transition == nil, state.day != dayBefore { transition = .morning }
        return StepResult(
            eventID: event.id, choiceIndex: index, outcomeIndex: outcomeIndex, snapped: snapped,
            text: outcome.text, deltas: deltas, minutes: minutes, transition: transition,
            endingID: state.endingID, stamp: outcome.stamp, fx: outcome.fx, chat: outcome.chat
        )
    }

    // MARK: - Rules

    private mutating func applyEffects(_ effects: [Meter: Int]) {
        for (meter, delta) in effects { state.meters[meter] += delta }
    }

    private mutating func apply(_ outcome: Outcome, nowBefore: Int) {
        applyEffects(outcome.effects)
        for flag in outcome.setFlags { state.flags.insert(flag) }
        for flag in outcome.clearFlags { state.flags.remove(flag) }
        for (counter, delta) in outcome.counters { state.counters[counter, default: 0] += delta }
        for (category, who) in outcome.ledger {
            switch who {
            case .you: state.ledgerYou[category, default: 0] += 1
            case .partner: state.ledgerPartner[category, default: 0] += 1
            }
            if state.phase == .night, category == "night" {
                if who == .you { state.nightYou += 1 } else { state.nightPartner += 1 }
            }
        }
        for item in outcome.schedule {
            state.queue.append(QueueEntry(event: item.event, at: nowBefore + item.delay, seq: state.seq))
            state.seq += 1
        }
        if !outcome.cancel.isEmpty {
            state.queue.removeAll { outcome.cancel.contains($0.event) }
        }
        if let target = outcome.completeTask {
            let index: Int?
            if target == "oldest" {
                index = state.tasks.firstIndex { $0.status == .open }
            } else {
                index = state.tasks.firstIndex { $0.status == .open && $0.id == target }
            }
            if let index {
                state.tasks[index].status = .done
                state.ledgerYou["errands", default: 0] += 1
            }
        }
    }

    /// Passive drift while time passes. Ticks count from today's wake-up.
    private mutating func advance(minutes: Int) {
        let t0 = state.clock - state.dayStart
        let t1 = t0 + minutes
        for rule in content.config.drift where meets(rule.condition) {
            let ticks = t1 / rule.every - t0 / rule.every
            state.meters[rule.meter] += rule.delta * ticks
        }
        state.clock += minutes
    }

    private enum LossResult { case none, lifeline, ending(String) }

    private mutating func lossCheck() -> LossResult {
        let config = content.config
        for meter in config.lossOrder where state.meters[meter] <= 0 {
            if config.lifelineMeters.contains(meter), !state.lifelineUsed, state.day < 4 {
                state.lifelineUsed = true
                state.lostDays += 1
                applyEffects(content.lifeline.effects)
                for flag in content.lifeline.setFlags { state.flags.insert(flag) }
                return .lifeline
            }
            return .ending(config.losses[meter] ?? "collapse")
        }
        return .none
    }

    private func grade() -> String {
        let total = score
        for grade in content.config.grades where total >= grade.minimum { return grade.id }
        return content.config.grades[content.config.grades.count - 1].id
    }

    private mutating func expireTasks() {
        for index in state.tasks.indices where state.tasks[index].status == .open && state.tasks[index].due <= state.now {
            state.tasks[index].status = .expired
            if let expire = content.task(withID: state.tasks[index].id)?.expire {
                state.queue.append(QueueEntry(event: expire, at: state.now, seq: state.seq))
                state.seq += 1
            }
        }
    }

    private mutating func rollHazard() {
        let hazard = content.config.hazard
        let band = debtBand
        let chance = hazard.base + hazard.bandBonus[band] + (state.clock >= hazard.lateDayClock ? hazard.lateDayBonus : 0)
        guard state.rng.next() * 100 < Double(chance) else { return }
        var severity = HazardSeverity.sting
        if state.catastrophesToday < hazard.maxCatastrophesPerDay {
            if state.rng.next() * 100 < Double(hazard.catastropheShare[band]) { severity = .catastrophe }
        }
        let pool = content.events.filter { event in
            event.hazard == severity
                && !state.seenToday.contains(event.id)
                && !(event.oncePerWeek && state.seenWeek.contains(event.id))
                && meets(event.condition)
                && !state.queue.contains { $0.event == event.id }
        }
        guard !pool.isEmpty else { return }
        let chosen = pool.count == 1 ? pool[0] : pool[Self.weightedPick(pool, weight: { $0.weight }, rng: &state.rng)]
        if let tell = chosen.tell {
            state.queue.append(QueueEntry(event: tell, at: state.now, seq: state.seq))
            state.seq += 1
        }
        state.queue.append(QueueEntry(event: chosen.id, at: state.now, seq: state.seq))
        state.seq += 1
        if severity == .catastrophe { state.catastrophesToday += 1 }
    }

    private mutating func nextDayEvent() -> GameEvent {
        let now = state.now
        let due = state.queue.filter { $0.at <= now }.sorted { ($0.at, $0.seq) < ($1.at, $1.seq) }
        var best: (event: GameEvent, priority: Int, entry: QueueEntry?)?
        for entry in due {
            guard let event = self.event(withID: entry.event), meets(event.condition) else {
                state.queue.removeAll { $0 == entry }
                continue
            }
            let priority = event.priority ?? 80
            if best == nil || priority > best!.priority { best = (event, priority, entry) }
        }
        for event in content.events {
            let priority = event.priority ?? 0
            guard priority > 0, event.phase == .day, event.hazard == nil, !event.forced else { continue }
            guard windowEligible(event) else { continue }
            if best == nil || priority > best!.priority { best = (event, priority, nil) }
        }
        if let best {
            if let entry = best.entry { state.queue.removeAll { $0 == entry } }
            return best.event
        }
        let pool = content.events.filter { event in
            (event.priority ?? 0) <= 0 && event.phase == .day && event.hazard == nil
                && !event.forced && !event.isFiller && windowEligible(event)
        }
        if pool.isEmpty { return content.filler ?? content.events[0] }
        // Weights are computed first: a closure reading `state` while `state.rng`
        // is borrowed inout would be an overlapping access.
        let weights = pool.map { weight(of: $0) }
        return pool[Self.weightedIndex(weights, rng: &state.rng)]
    }

    private func windowEligible(_ event: GameEvent) -> Bool {
        if !event.repeatable && state.seenToday.contains(event.id) { return false }
        if event.oncePerWeek && state.seenWeek.contains(event.id) { return false }
        if event.id == state.lastEventID { return false }
        guard let window = event.window, window.contains(state.clock) else { return false }
        if !meets(event.condition) { return false }
        if let task = event.task, !state.tasks.contains(where: { $0.id == task && $0.status == .open }) { return false }
        return !visibleChoices(for: event).isEmpty
    }

    private func weight(of event: GameEvent) -> Int {
        guard let by = event.weightBy else { return event.weight }
        return event.weight + (state.counters[by.counter] ?? 0) / by.every
    }

    private mutating func goToNight() {
        state.phase = .night
        state.nightCardsLeft = content.config.night.cards + (state.flags.contains(content.config.bedtime.awakeFlag) ? 1 : 0)
        state.nightYou = 0
        state.nightPartner = 0
        state.queue = []
        pickNight()
    }

    private mutating func pickNight() {
        let pool = content.events.filter {
            $0.phase == .night && !state.seenToday.contains($0.id)
                && !($0.oncePerWeek && state.seenWeek.contains($0.id)) && meets($0.condition)
        }
        if pool.isEmpty {
            morning()
            return
        }
        let weights = pool.map { weight(of: $0) }
        state.currentEventID = pool[Self.weightedIndex(weights, rng: &state.rng)].id
    }

    private mutating func morning() {
        let night = content.config.night
        let debtBefore = state.meters.debt
        let coffee = state.flags.contains(night.lateCoffeeFlag) ? night.lateCoffeePenalty : 0
        let refill = Swift.max(night.minRefill, night.base - night.perWake * state.nightYou - coffee)
        state.meters[.energy] += refill
        state.meters[.debt] += night.debtPerWake * (state.nightYou + state.nightPartner) - night.recovery
        state.meters[.mood] = night.moodBase - state.meters.debt / night.moodDebtDiv
        state.meters[.sleepy] = night.sleepyStart
        state.flags = state.flags.filter { !$0.hasPrefix("d:") }
        var partnerDid: String?
        if state.meters.rel >= night.partnerTaskMinRel, let index = state.tasks.firstIndex(where: { $0.status == .open }) {
            state.tasks[index].status = .done
            state.ledgerPartner["errands", default: 0] += 1
            partnerDid = state.tasks[index].id
        }
        // Captured before startDay applies the next day's modifier (as in engine.mjs).
        let debtAfter = state.meters.debt
        let nightYou = state.nightYou
        let nightPartner = state.nightPartner
        let nextDay = state.day + 1
        startDay(nextDay)
        state.report = DayReport(
            day: nextDay, nightYou: nightYou, nightPartner: nightPartner, refill: refill,
            debtBefore: debtBefore, debtAfter: debtAfter, partnerDid: partnerDid,
            wakeClock: state.dayStart, tasksAdded: content.days[state.day].tasks, modifierID: state.modifierID
        )
    }

    private mutating func startDay(_ day: Int) {
        let definition = content.days[day]
        state.day = day
        state.phase = .day
        state.dayStart = content.config.wake[debtBand]
        state.clock = state.dayStart
        state.seenToday = []
        state.queue = []
        state.catastrophesToday = 0
        state.lastEventID = nil
        let modifier: DayModifier
        if definition.modifier == "random" {
            let pool = content.modifiers.filter(\.pool)
            modifier = pool[Self.weightedPick(pool, weight: { $0.weight }, rng: &state.rng)]
        } else {
            modifier = content.modifiers.first { $0.id == definition.modifier } ?? content.modifiers[0]
        }
        state.modifierID = modifier.id
        applyEffects(modifier.effects)
        for flag in modifier.setFlags { state.flags.insert(flag) }
        for id in definition.tasks {
            if let task = content.task(withID: id) {
                state.tasks.append(TaskState(id: id, due: task.dueDay * 1440 + task.dueClock, status: .open))
            }
        }
        state.currentEventID = nextDayEvent().id
    }

    /// One RNG draw; returns an index chosen in proportion to `weight`.
    static func weightedPick<T>(_ items: [T], weight: (T) -> Int, rng: inout SeededRandom) -> Int {
        weightedIndex(items.map(weight), rng: &rng)
    }

    /// One RNG draw over precomputed integer weights (same algorithm as weightedPick in engine.mjs).
    static func weightedIndex(_ weights: [Int], rng: inout SeededRandom) -> Int {
        var total = 0.0
        for w in weights { total += Double(w) }
        let r = rng.next() * total
        var accumulated = 0.0
        for (index, w) in weights.enumerated() {
            accumulated += Double(w)
            if r < accumulated { return index }
        }
        return weights.count - 1
    }

    private static func makeIndex(_ events: [GameEvent]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (i, event) in events.enumerated() { index[event.id] = i }
        return index
    }
}

/// "6:05 AM"-style formatting, identical to formatClock in tools/engine.mjs.
public enum Clock {
    public static func format(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let hour24 = m / 60
        let minute = m % 60
        let suffix = hour24 < 12 ? "AM" : "PM"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return "\(hour12):\(minute < 10 ? "0" : "")\(minute) \(suffix)"
    }
}
