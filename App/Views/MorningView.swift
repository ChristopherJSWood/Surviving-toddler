import BedtimeCore
import SwiftUI

/// The start of each day: last night's damage, today's twist, new list items.
struct MorningView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    var body: some View {
        if let engine = store.engine {
            let content = engine.content
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.orange, .yellow)
                        .rotationEffect(.degrees(risen || reduceMotion ? 0 : -90))
                        .offset(y: risen || reduceMotion ? 0 : 70)
                        .opacity(risen ? 1 : 0)
                        .padding(.top, 20)
                        .accessibilityHidden(true)
                    Text(engine.dayDefinition.name)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .scaleEffect(risen || reduceMotion ? 1 : 1.6)
                        .opacity(risen ? 1 : 0)
                    Text(Clock.format(engine.state.clock))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let report = engine.state.report {
                        Card {
                            Text("Last night").font(.headline)
                            ReportRow(label: "You got up", value: "\(report.nightYou)×")
                            ReportRow(label: store.say("{partner} got up"), value: "\(report.nightPartner)×")
                            ReportRow(label: "Bandwidth refill", value: "+\(report.refill)")
                            ReportRow(label: store.say("{kid}'s sleep"), value: "\(100 - report.debtBefore) → \(100 - report.debtAfter)")
                            if let did = report.partnerDid, let task = content.task(withID: did) {
                                Text(store.say("{partner} handled \"\(task.label)\" before work."))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let modifier = engine.modifier {
                        Card {
                            Text("Today").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                            Text(store.say(modifier.title)).font(.title2.bold())
                            Text(store.say(modifier.text))
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
                                    Text(store.say(task.label))
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
                    .accessibilityIdentifier("startDay")
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
            }
            .onAppear {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { risen = true }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: risen)
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
                Text(store.say(engine.content.lifeline.title)).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Card {
                    Text(store.say(engine.content.lifeline.text))
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
                .accessibilityIdentifier("goToBed")
                .controlSize(.large)
            }
            .padding(24)
        }
    }
}
