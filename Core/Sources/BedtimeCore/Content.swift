import Foundation

// Data model for content.json (schema v2, the week). All game text and numbers
// live in content/ and are merged into Resources/content.json by
// tools/build-content.mjs. Field meanings: docs/CONTENT_GUIDE.md and docs/RULES.md.

public enum Phase: String, Codable, Sendable { case day, night }
public enum Who: String, Codable, Sendable { case you, partner }
public enum HazardSeverity: String, Codable, Sendable { case sting, catastrophe }

/// A requirement on game state. `minimum`/`maximum` keys are meter names,
/// `day` (0 = Monday) or `ledger` (your chores minus your partner's).
public struct Condition: Decodable, Equatable, Sendable {
    public var flags: [String]
    public var notFlags: [String]
    public var minimum: [String: Int]
    public var maximum: [String: Int]

    public static let variables: Set<String> = Set(Meter.allCases.map(\.rawValue)).union(["day", "ledger"])

    enum CodingKeys: String, CodingKey {
        case flags, notFlags
        case minimum = "min"
        case maximum = "max"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flags = try c.decodeIfPresent([String].self, forKey: .flags) ?? []
        notFlags = try c.decodeIfPresent([String].self, forKey: .notFlags) ?? []
        minimum = try c.decodeIfPresent([String: Int].self, forKey: .minimum) ?? [:]
        maximum = try c.decodeIfPresent([String: Int].self, forKey: .maximum) ?? [:]
        for key in minimum.keys where !Self.variables.contains(key) {
            throw DecodingError.dataCorruptedError(forKey: .minimum, in: c, debugDescription: "Unknown condition variable \"\(key)\"")
        }
        for key in maximum.keys where !Self.variables.contains(key) {
            throw DecodingError.dataCorruptedError(forKey: .maximum, in: c, debugDescription: "Unknown condition variable \"\(key)\"")
        }
    }
}

public struct ScheduledEvent: Decodable, Equatable, Sendable {
    public var event: String
    /// Minutes after the choice was made.
    public var delay: Int

    enum CodingKeys: String, CodingKey {
        case event
        case delay = "in"
    }
}

public struct Outcome: Decodable, Sendable {
    public var text: String
    public var weight: Int
    public var condition: Condition?
    public var effects: [Meter: Int]
    public var setFlags: [String]
    public var clearFlags: [String]
    public var counters: [String: Int]
    public var ledger: [String: Who]
    public var schedule: [ScheduledEvent]
    public var cancel: [String]
    public var completeTask: String?

    enum CodingKeys: String, CodingKey {
        case text, weight, effects, ledger, schedule, cancel, completeTask
        case condition = "when"
        case setFlags = "set"
        case clearFlags = "clear"
        case counters = "count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        condition = try c.decodeIfPresent(Condition.self, forKey: .condition)
        effects = try c.decodeMeterMap(forKey: .effects)
        setFlags = try c.decodeIfPresent([String].self, forKey: .setFlags) ?? []
        clearFlags = try c.decodeIfPresent([String].self, forKey: .clearFlags) ?? []
        counters = try c.decodeIfPresent([String: Int].self, forKey: .counters) ?? [:]
        ledger = try c.decodeIfPresent([String: Who].self, forKey: .ledger) ?? [:]
        schedule = try c.decodeIfPresent([ScheduledEvent].self, forKey: .schedule) ?? []
        cancel = try c.decodeIfPresent([String].self, forKey: .cancel) ?? []
        completeTask = try c.decodeIfPresent(String.self, forKey: .completeTask)
    }

    init(text: String, effects: [Meter: Int], setFlags: [String]) {
        self.text = text
        weight = 1
        condition = nil
        self.effects = effects
        self.setFlags = setFlags
        clearFlags = []
        counters = [:]
        ledger = [:]
        schedule = []
        cancel = []
        completeTask = nil
    }
}

public struct Choice: Decodable, Sendable {
    public var label: String
    /// Minutes this choice takes (the engine adds `config.eventGap` on top).
    public var duration: Int
    /// Hidden unless met.
    public var condition: Condition?
    /// Shown but locked ("Too tired") while Energy is below this.
    public var minEnergy: Int
    public var snapRisk: Bool
    public var tags: [String]
    public var outcomes: [Outcome]

    enum CodingKeys: String, CodingKey {
        case label, duration, minEnergy, snapRisk, tags, outcomes
        case condition = "when"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        duration = try c.decode(Int.self, forKey: .duration)
        condition = try c.decodeIfPresent(Condition.self, forKey: .condition)
        minEnergy = try c.decodeIfPresent(Int.self, forKey: .minEnergy) ?? 0
        snapRisk = try c.decodeIfPresent(Bool.self, forKey: .snapRisk) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        outcomes = try c.decode([Outcome].self, forKey: .outcomes)
    }
}

public struct WeightBy: Decodable, Sendable {
    public var counter: String
    public var every: Int
}

public struct Check: Decodable, Sendable {
    public var condition: Condition?
    public var ending: String

    enum CodingKeys: String, CodingKey {
        case ending
        case condition = "when"
    }
}

public struct GameEvent: Decodable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var phase: Phase
    /// Clock minutes during which a day event can appear, inclusive.
    public var window: ClosedRange<Int>?
    public var weight: Int
    public var weightBy: WeightBy?
    /// As written in content (nil when absent): queued events default to 80.
    public var priority: Int?
    public var repeatable: Bool
    public var oncePerWeek: Bool
    public var isFiller: Bool
    public var forced: Bool
    public var noHazard: Bool
    public var hazard: HazardSeverity?
    public var tell: String?
    public var task: String?
    public var moment: Bool
    public var endsDay: Bool
    public var endsWeek: Bool
    public var condition: Condition?
    public var checks: [Check]
    public var choices: [Choice]

    enum CodingKeys: String, CodingKey {
        case id, title, text, phase, window, weight, weightBy, priority, repeatable, oncePerWeek
        case forced, noHazard, hazard, tell, task, moment, endsDay, endsWeek, checks, choices
        case isFiller = "filler"
        case condition = "when"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .day
        if let bounds = try c.decodeIfPresent([Int].self, forKey: .window) {
            guard bounds.count == 2, bounds[0] <= bounds[1] else {
                throw DecodingError.dataCorruptedError(forKey: .window, in: c, debugDescription: "window must be [from, to]")
            }
            window = bounds[0]...bounds[1]
        } else {
            window = nil
        }
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        weightBy = try c.decodeIfPresent(WeightBy.self, forKey: .weightBy)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        repeatable = try c.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
        oncePerWeek = try c.decodeIfPresent(Bool.self, forKey: .oncePerWeek) ?? false
        isFiller = try c.decodeIfPresent(Bool.self, forKey: .isFiller) ?? false
        forced = try c.decodeIfPresent(Bool.self, forKey: .forced) ?? false
        noHazard = try c.decodeIfPresent(Bool.self, forKey: .noHazard) ?? false
        hazard = try c.decodeIfPresent(HazardSeverity.self, forKey: .hazard)
        tell = try c.decodeIfPresent(String.self, forKey: .tell)
        task = try c.decodeIfPresent(String.self, forKey: .task)
        moment = try c.decodeIfPresent(Bool.self, forKey: .moment) ?? false
        endsDay = try c.decodeIfPresent(Bool.self, forKey: .endsDay) ?? false
        endsWeek = try c.decodeIfPresent(Bool.self, forKey: .endsWeek) ?? false
        condition = try c.decodeIfPresent(Condition.self, forKey: .condition)
        checks = try c.decodeIfPresent([Check].self, forKey: .checks) ?? []
        choices = try c.decode([Choice].self, forKey: .choices)
    }
}

public struct DayModifier: Decodable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var weight: Int
    public var pool: Bool
    public var effects: [Meter: Int]
    public var setFlags: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, text, weight, pool, effects
        case setFlags = "set"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        pool = try c.decodeIfPresent(Bool.self, forKey: .pool) ?? false
        effects = try c.decodeMeterMap(forKey: .effects)
        setFlags = try c.decodeIfPresent([String].self, forKey: .setFlags) ?? []
    }
}

public struct DayDefinition: Decodable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// A modifier id, or "random" to draw from modifiers with `pool: true`.
    public var modifier: String
    public var tasks: [String]

    enum CodingKeys: String, CodingKey { case id, name, modifier, tasks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        modifier = try c.decode(String.self, forKey: .modifier)
        tasks = try c.decodeIfPresent([String].self, forKey: .tasks) ?? []
    }
}

public struct TaskDefinition: Decodable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var dueDay: Int
    public var dueClock: Int
    public var expire: String?
}

public struct Lifeline: Decodable, Sendable {
    public var title: String
    public var text: String
    public var effects: [Meter: Int]
    public var setFlags: [String]

    enum CodingKeys: String, CodingKey {
        case title, text, effects
        case setFlags = "set"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        effects = try c.decodeMeterMap(forKey: .effects)
        setFlags = try c.decodeIfPresent([String].self, forKey: .setFlags) ?? []
    }
}

public struct Ending: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable { case win, loss, soft }
    public var kind: Kind
    public var title: String
    public var text: String
}

public struct CounterInfo: Decodable, Identifiable, Sendable {
    public var id: String
    public var label: String
}

public struct StyleInfo: Decodable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var text: String
}

public struct GameConfig: Decodable, Sendable {
    public struct DriftRule: Decodable, Sendable {
        public var meter: Meter
        public var every: Int
        public var delta: Int
        public var condition: Condition?

        enum CodingKeys: String, CodingKey {
            case meter, every, delta
            case condition = "when"
        }
    }

    public struct Bedtime: Decodable, Sendable {
        public var threshold: Int
        public var asleep: [Meter: Int]
        public var awake: [Meter: Int]
        public var awakeFlag: String

        enum CodingKeys: String, CodingKey { case threshold, asleep, awake, awakeFlag }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            threshold = try c.decode(Int.self, forKey: .threshold)
            asleep = try c.decodeMeterMap(forKey: .asleep)
            awake = try c.decodeMeterMap(forKey: .awake)
            awakeFlag = try c.decode(String.self, forKey: .awakeFlag)
        }
    }

    public struct Night: Decodable, Sendable {
        public struct HomeTidy: Decodable, Sendable {
            public var minRel: Int
            public var high: Int
            public var low: Int
        }

        public var cards: Int
        public var base: Int
        public var perWake: Int
        public var minRefill: Int
        public var lateCoffeeFlag: String
        public var lateCoffeePenalty: Int
        public var debtPerWake: Int
        public var recovery: Int
        public var moodBase: Int
        public var moodDebtDiv: Int
        public var sleepyStart: Int
        public var homeTidy: HomeTidy
        public var partnerTaskMinRel: Int
    }

    public struct Hazard: Decodable, Sendable {
        public var base: Int
        public var bandBonus: [Int]
        public var lateDayClock: Int
        public var lateDayBonus: Int
        public var catastropheShare: [Int]
        public var maxCatastrophesPerDay: Int
    }

    public struct Snap: Decodable, Sendable {
        public var belowEnergy: Int
        public var chancePct: Int
        public var text: String
        public var effects: [Meter: Int]
        public var setFlags: [String]

        enum CodingKeys: String, CodingKey {
            case belowEnergy, chancePct, text, effects
            case setFlags = "set"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            belowEnergy = try c.decode(Int.self, forKey: .belowEnergy)
            chancePct = try c.decode(Int.self, forKey: .chancePct)
            text = try c.decode(String.self, forKey: .text)
            effects = try c.decodeMeterMap(forKey: .effects)
            setFlags = try c.decodeIfPresent([String].self, forKey: .setFlags) ?? []
        }
    }

    public struct Grade: Decodable, Sendable {
        public var minimum: Int
        public var id: String

        enum CodingKeys: String, CodingKey {
            case id
            case minimum = "min"
        }
    }

    public var eventGap: Int
    public var bedtimeClock: Int
    public var wake: [Int]
    public var startMeters: Meters
    public var drift: [DriftRule]
    public var bedtime: Bedtime
    public var night: Night
    public var hazard: Hazard
    public var snap: Snap
    public var lossOrder: [Meter]
    public var losses: [Meter: String]
    public var lifelineMeters: [Meter]
    public var weekScore: [Meter: Int]
    public var grades: [Grade]

    enum CodingKeys: String, CodingKey {
        case eventGap, bedtimeClock, wake, startMeters, drift, bedtime, night, hazard, snap
        case lossOrder, losses, lifelineMeters, weekScore, grades
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventGap = try c.decode(Int.self, forKey: .eventGap)
        bedtimeClock = try c.decode(Int.self, forKey: .bedtimeClock)
        wake = try c.decode([Int].self, forKey: .wake)
        startMeters = try c.decode(Meters.self, forKey: .startMeters)
        drift = try c.decode([DriftRule].self, forKey: .drift)
        bedtime = try c.decode(Bedtime.self, forKey: .bedtime)
        night = try c.decode(Night.self, forKey: .night)
        hazard = try c.decode(Hazard.self, forKey: .hazard)
        snap = try c.decode(Snap.self, forKey: .snap)
        lossOrder = try c.decode([Meter].self, forKey: .lossOrder)
        let rawLosses = try c.decode([String: String].self, forKey: .losses)
        var losses: [Meter: String] = [:]
        for (name, ending) in rawLosses {
            guard let meter = Meter(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: .losses, in: c, debugDescription: "Unknown meter \"\(name)\"")
            }
            losses[meter] = ending
        }
        self.losses = losses
        lifelineMeters = try c.decode([Meter].self, forKey: .lifelineMeters)
        weekScore = try c.decodeMeterMap(forKey: .weekScore)
        grades = try c.decode([Grade].self, forKey: .grades)
    }
}

public enum ContentError: Error, Equatable, CustomStringConvertible {
    case missingResource
    case invalid(String)

    public var description: String {
        switch self {
        case .missingResource: return "content.json is missing from the BedtimeCore bundle"
        case .invalid(let reason): return "content.json is invalid: \(reason)"
        }
    }
}

public struct GameContent: Decodable, Sendable {
    public var version: Int
    public var config: GameConfig
    public var meterNames: [Meter: String]
    public var counters: [CounterInfo]
    public var styles: [StyleInfo]
    public var days: [DayDefinition]
    public var modifiers: [DayModifier]
    public var tasks: [TaskDefinition]
    public var lifeline: Lifeline
    public var endings: [String: Ending]
    public var events: [GameEvent]

    enum CodingKeys: String, CodingKey {
        case version, config, counters, styles, days, modifiers, tasks, lifeline, endings, events
        case meterNames = "meters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        config = try c.decode(GameConfig.self, forKey: .config)
        let names = try c.decode([String: String].self, forKey: .meterNames)
        var meterNames: [Meter: String] = [:]
        for meter in Meter.allCases { meterNames[meter] = names[meter.rawValue] ?? meter.rawValue.capitalized }
        self.meterNames = meterNames
        counters = try c.decodeIfPresent([CounterInfo].self, forKey: .counters) ?? []
        styles = try c.decode([StyleInfo].self, forKey: .styles)
        days = try c.decode([DayDefinition].self, forKey: .days)
        modifiers = try c.decode([DayModifier].self, forKey: .modifiers)
        tasks = try c.decodeIfPresent([TaskDefinition].self, forKey: .tasks) ?? []
        lifeline = try c.decode(Lifeline.self, forKey: .lifeline)
        endings = try c.decode([String: Ending].self, forKey: .endings)
        events = try c.decode([GameEvent].self, forKey: .events)
        try validateEngineInvariants()
    }

    /// Location of the content.json bundled with this package.
    public static var bundledURL: URL? {
        Bundle.module.url(forResource: "content", withExtension: "json")
    }

    /// Loads the content.json bundled with this package.
    public static func bundled() throws -> GameContent {
        guard let url = bundledURL else { throw ContentError.missingResource }
        return try load(from: Data(contentsOf: url))
    }

    public static func load(from data: Data) throws -> GameContent {
        try JSONDecoder().decode(GameContent.self, from: data)
    }

    public var filler: GameEvent? { events.first { $0.isFiller } }
    public func name(of meter: Meter) -> String { meterNames[meter] ?? meter.rawValue }
    public func task(withID id: String) -> TaskDefinition? { tasks.first { $0.id == id } }

    /// Only the guarantees the engine relies on to never crash or dead-end.
    /// Authoring mistakes are caught by tools/validate.mjs.
    private func validateEngineInvariants() throws {
        if days.count != 5 { throw ContentError.invalid("needs exactly five days") }
        if config.wake.count != 3 { throw ContentError.invalid("config.wake needs three entries") }
        if config.hazard.bandBonus.count != 3 || config.hazard.catastropheShare.count != 3 {
            throw ContentError.invalid("hazard band tables need three entries")
        }
        if config.grades.isEmpty { throw ContentError.invalid("needs at least one grade") }
        if events.filter(\.isFiller).count != 1 { throw ContentError.invalid("needs exactly one filler event") }
        let modifierIDs = Set(modifiers.map(\.id))
        for day in days {
            if day.modifier == "random" {
                if !modifiers.contains(where: \.pool) { throw ContentError.invalid("a random day needs pool modifiers") }
            } else if !modifierIDs.contains(day.modifier) {
                throw ContentError.invalid("unknown modifier \(day.modifier)")
            }
            for task in day.tasks where self.task(withID: task) == nil {
                throw ContentError.invalid("unknown task \(task)")
            }
        }
        var ids = Set<String>()
        for event in events {
            if !ids.insert(event.id).inserted { throw ContentError.invalid("duplicate event id \(event.id)") }
            if !event.choices.contains(where: { $0.condition == nil && $0.minEnergy == 0 }) {
                throw ContentError.invalid("event \(event.id) needs a choice that is always available")
            }
            for choice in event.choices {
                if choice.outcomes.isEmpty { throw ContentError.invalid("a choice in \(event.id) has no outcomes") }
                if choice.duration < 1 { throw ContentError.invalid("a choice in \(event.id) takes no time") }
                if choice.outcomes.contains(where: { $0.weight < 1 }) { throw ContentError.invalid("non-positive weight in \(event.id)") }
            }
            for check in event.checks where endings[check.ending] == nil {
                throw ContentError.invalid("unknown ending \(check.ending)")
            }
        }
        var refs: [String] = tasks.compactMap(\.expire)
        for event in events {
            if let tell = event.tell { refs.append(tell) }
            for choice in event.choices {
                for outcome in choice.outcomes { refs += outcome.schedule.map(\.event) }
            }
        }
        for ref in refs where !ids.contains(ref) { throw ContentError.invalid("reference to unknown event \(ref)") }
        for ending in Array(config.losses.values) + config.grades.map(\.id) where endings[ending] == nil {
            throw ContentError.invalid("missing ending \(ending)")
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes `{ "mood": 5, "energy": -3 }`, rejecting unknown meter names.
    func decodeMeterMap(forKey key: Key) throws -> [Meter: Int] {
        guard let raw = try decodeIfPresent([String: Int].self, forKey: key) else { return [:] }
        var result: [Meter: Int] = [:]
        for (name, value) in raw {
            guard let meter = Meter(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Unknown meter \"\(name)\"")
            }
            result[meter] = value
        }
        return result
    }
}
