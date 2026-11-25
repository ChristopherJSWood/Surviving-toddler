import BedtimeCore
import SwiftUI

struct PlayView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingList = false
    @State private var fx = ScreenFX()

    /// Cards are dealt in from below; Reduce Motion gets a plain fade.
    private var entrance: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.asymmetric(
            insertion: AnyTransition.move(edge: .bottom).combined(with: .scale(scale: 0.92)).combined(with: .opacity),
            removal: AnyTransition.move(edge: .top).combined(with: .opacity))
    }

    var body: some View {
        if let engine = store.engine {
            VStack(spacing: 0) {
                HUDView(engine: engine, showingList: $showingList)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                ScrollView {
                    Group {
                        switch store.screen {
                        case .outcome(let result):
                            OutcomeCard(result: result, engine: engine)
                        default:
                            if let event = engine.currentEvent {
                                EventCard(event: event, engine: engine)
                            }
                        }
                    }
                    .padding()
                    .transition(entrance)
                }
            }
            .screenFX(fx)
            .sensoryFeedback(.selection, trigger: engine.state.step)
            .sheet(isPresented: $showingList) { ListSheet(engine: engine) }
            .onChange(of: store.screen) { _, screen in
                guard case .outcome(let result) = screen else { return }
                if result.snapped {
                    fx.shakes += 1
                    fx.flashes += 1
                    return
                }
                switch result.fx {
                case .shake: fx.shakes += 1
                case .flash: fx.flashes += 1
                case .confetti: fx.confetti += 1
                case nil: break
                }
            }
        }
    }
}

/// Clock, day, meters in three groups, ticking paybacks and the list button.
struct HUDView: View {
    @Environment(GameStore.self) private var store
    let engine: GameEngine
    @Binding var showingList: Bool

    private var openTasks: Int { engine.state.tasks.filter { $0.status == .open }.count }

    var body: some View {
        let content = engine.content
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(engine.state.phase == .night ? "2:47 AM" : Clock.format(engine.state.clock))
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text(engine.dayDefinition.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingList = true
                } label: {
                    Label("\(openTasks)", systemImage: "list.bullet.clipboard")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Your list, \(openTasks) open")
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    MeterBar(meter: .energy, value: engine.state.meters.energy, name: content.name(of: .energy))
                    MeterBar(meter: .rel, value: engine.state.meters.rel, name: content.name(of: .rel))
                }
                GridRow {
                    MeterBar(meter: .mood, value: engine.state.meters.mood, name: content.name(of: .mood))
                    SleepWidget(engine: engine)
                }
                GridRow {
                    MeterBar(meter: .home, value: engine.state.meters.home, name: content.name(of: .home))
                    MeterBar(meter: .rep, value: engine.state.meters.rep, name: content.name(of: .rep))
                }
            }
            let upcoming = Array(engine.upcoming.prefix(2))
            if !upcoming.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, item in
                        Label("\(store.say(item.event.title)) at \(Clock.format(item.at % 1440))", systemImage: "hourglass")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct MeterBar: View {
    let meter: Meter
    let value: Int
    let name: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var change: Int?
    @State private var changeID = 0

    private var isDanger: Bool { meter.dangerAt.map { value <= $0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: meter.symbol)
                    .foregroundStyle(isDanger ? Color.red : meter.tint)
                    .frame(width: 18)
                    .symbolEffect(.pulse, options: .repeating, isActive: isDanger && !reduceMotion)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                ZStack(alignment: .trailing) {
                    Text("\(value)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isDanger ? Color.red : Color.secondary)
                        .contentTransition(.numericText())
                    if let change {
                        Text(change > 0 ? "+\(change)" : "−\(abs(change))")
                            .font(.caption.weight(.black).monospacedDigit())
                            .foregroundStyle(changeColor(change))
                            .offset(y: -18)
                            .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity),
                                                    removal: .move(edge: .top).combined(with: .opacity)))
                            .id(changeID)
                    }
                }
            }
            ProgressView(value: Double(value), total: 100)
                .tint(isDanger ? Color.red : meter.tint)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: value)
        }
        .onChange(of: value) { old, new in
            let delta = new - old
            guard delta != 0 else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                change = delta
                changeID += 1
            }
        }
        .task(id: changeID) { @MainActor in
            guard change != nil else { return }
            try? await Task.sleep(for: .seconds(1.4))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.4)) { change = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(value) out of 100\(isDanger ? ", critical" : "")")
    }

    private func changeColor(_ delta: Int) -> Color {
        guard let better = meter.higherIsBetter else { return .indigo }
        return (delta > 0) == better ? .green : .red
    }
}

/// Today's sleepiness (with the bedtime line) and the week's sleep debt.
struct SleepWidget: View {
    let engine: GameEngine

    var body: some View {
        let sleepy = engine.state.meters.sleepy
        let debt = engine.state.meters.debt
        let threshold = engine.content.config.bedtime.threshold
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: Meter.sleepy.symbol).foregroundStyle(Meter.sleepy.tint).frame(width: 18)
                Text("Sleep").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(sleepy) · debt \(debt)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Meter.sleepy.tint).frame(width: proxy.size.width * CGFloat(sleepy) / 100)
                    Rectangle().fill(Color.primary.opacity(0.7))
                        .frame(width: 2)
                        .offset(x: proxy.size.width * CGFloat(threshold) / 100)
                }
            }
            .frame(height: 4)
            ProgressView(value: Double(debt), total: 100).tint(Meter.debt.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toddler sleep")
        .accessibilityValue("Sleepiness \(sleepy), needs \(threshold) at bedtime. Sleep debt \(debt).")
    }
}

@MainActor
struct EventCard: View {
    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let event: GameEvent
    let engine: GameEngine

    @State private var chatDone = false
    @State private var choicesShown = false
    @State private var remaining: Double = 1
    @State private var secondsLeft = 0

    /// Visible choices with their engine index; the timeout choice is never a button.
    private var buttons: [(index: Int, choice: Choice)] {
        engine.visibleChoices(for: event).enumerated()
            .filter { !$0.element.timeout }
            .map { (index: $0.offset, choice: $0.element) }
    }

    private var timeoutIndex: Int? {
        engine.visibleChoices(for: event).firstIndex(where: \.timeout)
    }

    private var timerActive: Bool {
        event.timer != nil && timeoutIndex != nil && store.timersEnabled && !voiceOver
    }

    var body: some View {
        let eyebrow: (text: String, color: Color)? = timerActive ? (text: "Panic", color: Color.red) : engine.content.eyebrow(for: event)
        VStack(spacing: 14) {
            Card(border: eyebrow?.color.opacity(0.6)) {
                if let eyebrow {
                    Text(eyebrow.text)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(eyebrow.color)
                }
                Text(store.say(event.title)).font(.title2.bold())
                if let chat = event.chat {
                    Text(store.say(event.text)).font(.footnote).foregroundStyle(.secondary)
                    ChatThread(title: store.say(chat.with), lines: chat.messages.map { line($0) }) {
                        withAnimation(.snappy) { chatDone = true }
                    }
                } else {
                    Text(store.say(event.text)).font(.body)
                }
            }
            if timerActive, chatDone, let seconds = event.timer {
                CountdownBar(fraction: remaining, secondsLeft: secondsLeft)
                    .transition(.scale.combined(with: .opacity))
                    .task(id: "\(event.id)-\(engine.state.step)") { @MainActor in
                        await runTimer(seconds: seconds)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: secondsLeft)
            }
            ForEach(Array(buttons.enumerated()), id: \.offset) { order, item in
                choiceButton(item.index, item.choice)
                    .accessibilityIdentifier("choice-\(order)")
                    .opacity(choicesShown ? 1 : 0)
                    .offset(y: choicesShown || reduceMotion ? 0 : 18)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(order) * 0.07), value: choicesShown)
            }
        }
        .id(event.id + "-\(engine.state.step)")
        .onAppear {
            chatDone = event.chat == nil
            if chatDone { choicesShown = true }
        }
        .onChange(of: chatDone) { _, done in if done { choicesShown = true } }
    }

    private func line(_ m: ChatMessage) -> ChatThread.Line {
        ChatThread.Line(from: store.say(m.from), text: store.say(m.text), mine: m.isMine)
    }

    @ViewBuilder
    private func choiceButton(_ index: Int, _ choice: Choice) -> some View {
        let locked = engine.isLocked(choice)
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { store.choose(index) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(store.say(choice.label))
                Spacer(minLength: 8)
                Text(locked ? "Too tired · needs \(choice.minEnergy)" : "\(choice.duration) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(ChoiceButtonStyle(locked: locked))
        .disabled(locked || !choicesShown)
        .accessibilityHint(locked ? "Too tired. Needs \(choice.minEnergy) Energy." : "Takes about \(choice.duration) minutes")
    }

    @MainActor
    private func runTimer(seconds: Int) async {
        let total = Double(seconds)
        let start = Date()
        while true {
            let left = max(0, total - Date().timeIntervalSince(start))
            remaining = left / total
            secondsLeft = Int(left.rounded(.up))
            if left <= 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
        }
        guard let timeoutIndex, store.screen == .event else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { store.choose(timeoutIndex) }
    }
}

struct OutcomeCard: View {
    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let result: StepResult
    let engine: GameEngine

    @State private var lightsOut = false

    var body: some View {
        let title = engine.event(withID: result.eventID).map { store.say($0.title) } ?? ""
        VStack(spacing: 16) {
            if result.transition == .night {
                LightsOut().transition(.opacity)
            }
            Card(border: result.snapped ? Color.red.opacity(0.6) : nil) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.say(result.text)).font(.title3)
                if !result.chat.isEmpty {
                    ChatThread(title: nil, lines: result.chat.map {
                        ChatThread.Line(from: store.say($0.from), text: store.say($0.text), mine: $0.isMine)
                    })
                }
                if let stamp = result.snapped ? "YOU SNAPPED" : result.stamp {
                    HStack {
                        Spacer()
                        StampView(text: store.say(stamp), color: stampColor)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                if !result.deltas.isEmpty {
                    DeltaRow(deltas: result.deltas, content: engine.content)
                }
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ReactionRow(result: result, title: title)
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { store.continueAfterOutcome() }
            } label: {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("continue")
        }
        .id("outcome-\(engine.state.step)")
    }

    /// Red for bad news, green for good, indigo when it's mixed.
    private var stampColor: Color {
        if result.snapped { return .red }
        let score = result.deltas.reduce(0) { sum, entry in
            guard let better = entry.key.higherIsBetter else { return sum }
            return sum + (better ? entry.value : -entry.value)
        }
        return score > 4 ? .green : (score < -4 ? .red : .indigo)
    }

    private var footer: String {
        switch result.transition {
        case .night: return "Lights out. The night has plans."
        case .lifeline: return "This day is over."
        case .morning: return "The night is over."
        case .none: return result.minutes > 0 ? "\(result.minutes) minutes pass. It's \(Clock.format(engine.state.clock))." : ""
        }
    }

    private var buttonTitle: String {
        if engine.isOver { return "How did the week end?" }
        switch result.transition {
        case .lifeline: return "Call for help"
        case .morning: return "Good morning"
        case .night: return "Lights out"
        default: return "Continue"
        }
    }
}

/// The bedtime flourish: the moon drops in and the stars come out.
struct LightsOut: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow, .white)
                .symbolEffect(.pulse, options: .repeating, isActive: shown && !reduceMotion)
                .offset(y: shown || reduceMotion ? 0 : -80)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -30))
            Text("LIGHTS OUT")
                .font(.system(.title, design: .rounded).weight(.black))
                .tracking(4)
        }
        .opacity(shown ? 1 : 0)
        .padding(.vertical, 8)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lights out")
    }
}

/// Playtest buttons (😂 / 😴) and "send this to your partner".
@MainActor
struct ReactionRow: View {
    @Environment(GameStore.self) private var store
    let result: StepResult
    let title: String

    var body: some View {
        let current = store.reaction(forStep: store.engine?.state.step ?? -1)
        HStack(spacing: 10) {
            if store.reactionsEnabled {
                reactionButton("😂", kind: .laugh, current: current, label: "This was funny")
                reactionButton("😴", kind: .bored, current: current, label: "This dragged")
            }
            Spacer()
            ShareLink(item: "\(title)\n\n\(store.say(result.text))\n\n(Bedtime or Bust)") {
                Label("Send to \(store.say("{partner}"))", systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func reactionButton(_ emoji: String, kind: Reaction.Kind, current: Reaction.Kind?, label: String) -> some View {
        Button {
            store.react(kind, to: result)
        } label: {
            Text(emoji)
                .font(.title2)
                .padding(.horizontal, 6)
                .scaleEffect(current == kind ? 1.25 : 1)
                .opacity(current == nil || current == kind ? 1 : 0.35)
                .animation(.spring(response: 0.25, dampingFraction: 0.45), value: current)
        }
        .buttonStyle(.bordered)
        .sensoryFeedback(.selection, trigger: current)
        .accessibilityLabel(label)
        .accessibilityAddTraits(current == kind ? .isSelected : [])
    }
}

/// "+6 Toddler Mood  −3 Energy" chips.
struct DeltaRow: View {
    let deltas: [Meter: Int]
    let content: GameContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(Meter.allCases.filter { deltas[$0] != nil }.enumerated()), id: \.element) { order, meter in
                let delta = deltas[meter] ?? 0
                let good: Bool? = meter.higherIsBetter.map { $0 == (delta > 0) }
                Label {
                    Text("\(delta > 0 ? "+" : "−")\(abs(delta)) \(content.name(of: meter))")
                } icon: {
                    Image(systemName: meter.symbol)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(chipColor(good).opacity(0.15)))
                .foregroundStyle(chipColor(good))
                .scaleEffect(shown || reduceMotion ? 1 : 0.5)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.5 + Double(order) * 0.08), value: shown)
            }
        }
        .onAppear { shown = true }
    }

    private func chipColor(_ good: Bool?) -> Color {
        switch good {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .indigo
        }
    }
}

/// Your mental-load list and the who-did-what ledger.
struct ListSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let engine: GameEngine

    var body: some View {
        let content = engine.content
        NavigationStack {
            List {
                Section("Your list") {
                    if engine.state.tasks.isEmpty {
                        Text("Nothing yet. Enjoy it.").foregroundStyle(.secondary)
                    }
                    ForEach(engine.state.tasks, id: \.id) { task in
                        HStack {
                            Image(systemName: task.status == .done ? "checkmark.circle.fill" : (task.status == .expired ? "xmark.circle.fill" : "circle"))
                                .foregroundStyle(task.status == .done ? Color.green : (task.status == .expired ? Color.red : Color.secondary))
                            Text(store.say(content.task(withID: task.id)?.label ?? task.id))
                                .strikethrough(task.status != .open)
                            Spacer()
                            Text("\(content.days[min(task.due / 1440, 4)].name) \(Clock.format(task.due % 1440))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("The ledger") {
                    let categories = Set(engine.state.ledgerYou.keys).union(engine.state.ledgerPartner.keys).sorted()
                    if categories.isEmpty {
                        Text("Nobody has done anything yet. Suspicious.").foregroundStyle(.secondary)
                    }
                    ForEach(categories, id: \.self) { category in
                        HStack {
                            Text(category.capitalized)
                            Spacer()
                            Text("You \(engine.state.ledgerYou[category] ?? 0) · \(store.say("{partner}")) \(engine.state.ledgerPartner[category] ?? 0)")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("The list")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
