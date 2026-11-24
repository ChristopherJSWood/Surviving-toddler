import BedtimeCore
import SwiftUI

struct PlayView: View {
    @Environment(GameStore.self) private var store
    @State private var showingList = false

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
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            .sensoryFeedback(.selection, trigger: engine.state.step)
            .sheet(isPresented: $showingList) { ListSheet(engine: engine) }
        }
    }
}

/// Clock, day, meters in three groups, ticking paybacks and the list button.
struct HUDView: View {
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
                        Label("\(item.event.title) at \(Clock.format(item.at % 1440))", systemImage: "hourglass")
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

    private var isDanger: Bool { meter.dangerAt.map { value <= $0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: meter.symbol)
                    .foregroundStyle(meter.tint)
                    .frame(width: 18)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(value)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isDanger ? Color.red : Color.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(value), total: 100)
                .tint(isDanger ? Color.red : meter.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(value) out of 100\(isDanger ? ", critical" : "")")
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

struct EventCard: View {
    @Environment(GameStore.self) private var store
    let event: GameEvent
    let engine: GameEngine

    var body: some View {
        let eyebrow = engine.content.eyebrow(for: event)
        VStack(spacing: 16) {
            Card(border: eyebrow?.color.opacity(0.6)) {
                if let eyebrow {
                    Text(eyebrow.text)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(eyebrow.color)
                }
                Text(event.title).font(.title2.bold())
                Text(event.text).font(.body)
            }
            ForEach(Array(engine.visibleChoices(for: event).enumerated()), id: \.offset) { index, choice in
                let locked = engine.isLocked(choice)
                Button {
                    withAnimation(.snappy) { store.choose(index) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(choice.label)
                        Spacer(minLength: 8)
                        Text(locked ? "Too tired · needs \(choice.minEnergy)" : "\(choice.duration) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(ChoiceButtonStyle(locked: locked))
                .disabled(locked)
                .accessibilityHint(locked ? "Too tired. Needs \(choice.minEnergy) Energy." : "Takes about \(choice.duration) minutes")
            }
        }
        .id(event.id + "-\(engine.state.step)")
    }
}

struct OutcomeCard: View {
    @Environment(GameStore.self) private var store
    let result: StepResult
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 16) {
            Card(border: result.snapped ? Color.red.opacity(0.6) : nil) {
                if let event = engine.event(withID: result.eventID) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if result.snapped {
                    Text("You snapped")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.red)
                }
                Text(result.text).font(.title3)
                if !result.deltas.isEmpty {
                    DeltaRow(deltas: result.deltas, content: engine.content)
                }
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                withAnimation(.snappy) { store.continueAfterOutcome() }
            } label: {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .id("outcome-\(engine.state.step)")
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
        default: return "Continue"
        }
    }
}

/// "+6 Toddler Mood  −3 Energy" chips.
struct DeltaRow: View {
    let deltas: [Meter: Int]
    let content: GameContent

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Meter.allCases.filter { deltas[$0] != nil }, id: \.self) { meter in
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
            }
        }
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
                            Text(content.task(withID: task.id)?.label ?? task.id)
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
                            Text("You \(engine.state.ledgerYou[category] ?? 0) · Partner \(engine.state.ledgerPartner[category] ?? 0)")
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
