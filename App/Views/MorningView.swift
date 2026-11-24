import BedtimeCore
import SwiftUI

/// The start of each day: last night's damage, today's twist, new list items.
struct MorningView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let engine = store.engine {
            let content = engine.content
            ScrollView {
                VStack(spacing: 16) {
                    Text(engine.dayDefinition.name)
                        .font(.largeTitle.bold())
                        .padding(.top, 24)
                    Text(Clock.format(engine.state.clock))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let report = engine.state.report {
                        Card {
                            Text("Last night").font(.headline)
                            ReportRow(label: "You got up", value: "\(report.nightYou)×")
                            ReportRow(label: "Your partner got up", value: "\(report.nightPartner)×")
                            ReportRow(label: "Energy refill", value: "+\(report.refill)")
                            ReportRow(label: "Sleep debt", value: "\(report.debtBefore) → \(report.debtAfter)")
                            if let did = report.partnerDid, let task = content.task(withID: did) {
                                Text("Your partner handled \"\(task.label)\" before work.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let modifier = engine.modifier {
                        Card {
                            Text("Today").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                            Text(modifier.title).font(.title2.bold())
                            Text(modifier.text)
                            if !modifier.effects.isEmpty {
                                DeltaRow(deltas: modifier.effects, content: content)
                            }
                        }
                    }

                    let added = engine.dayDefinition.tasks.compactMap { content.task(withID: $0) }
                    if !added.isEmpty {
                        Card {
                            Text("Added to your list").font(.headline)
                            ForEach(added) { task in
                                HStack {
                                    Text(task.label)
                                    Spacer()
                                    Text("by \(content.days[task.dueDay].name)")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    Button {
                        store.startDay()
                    } label: {
                        Text("Start \(engine.dayDefinition.name)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ReportRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.semibold)
        }
    }
}

/// Shown when the once-a-week lifeline rescues a lost day.
struct LifelineView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let engine = store.engine {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "figure.and.child.holdinghands")
                    .font(.system(size: 56))
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)
                Text(engine.content.lifeline.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Card {
                    Text(engine.content.lifeline.text)
                    DeltaRow(deltas: engine.content.lifeline.effects, content: engine.content)
                    Text("That was your one rescue this week. The next loss ends it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.continueAfterLifeline()
                } label: {
                    Text("Go to bed").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }
}
