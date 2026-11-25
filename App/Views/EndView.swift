import BedtimeCore
import SwiftUI

/// The weekly performance review.
struct EndView: View {
    @Environment(GameStore.self) private var store
    @State private var fx = ScreenFX()

    var body: some View {
        if let engine = store.engine, let ending = engine.ending {
            let content = engine.content
            ScrollView {
                VStack(spacing: 16) {
                    StampView(text: ending.kind == .win ? "WEEK: SURVIVED" : "WEEK: OVER",
                              color: ending.kind == .win ? .green : .red, delay: 0.5)
                        .padding(.top, 28)
                    Text(store.say(ending.title))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Card {
                        Text(store.say(ending.text))
                        if ending.kind == .win {
                            Text("Score: \(engine.score)").font(.headline.monospacedDigit())
                        }
                        Text("Ended \(engine.dayDefinition.name) at \(Clock.format(engine.state.clock)) after \(engine.state.step) decisions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let style = engine.style {
                        Card {
                            Text("Your parenting style").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                            Text(store.say(style.title)).font(.title2.bold())
                            Text(store.say(style.text))
                        }
                    }
                    Card {
                        Text("Weekly performance review").font(.headline)
                        ForEach(content.counters) { counter in
                            ReviewRow(label: store.say(counter.label), value: "\(engine.state.counters[counter.id] ?? 0)")
                        }
                        Divider()
                        ReviewRow(label: store.say("Night wake-ups (you · {partner})"),
                                  value: "\(engine.state.ledgerYou["night"] ?? 0) · \(engine.state.ledgerPartner["night"] ?? 0)")
                        ReviewRow(label: store.say("Chores (you · {partner})"),
                                  value: "\(engine.state.ledgerYou.values.reduce(0, +)) · \(engine.state.ledgerPartner.values.reduce(0, +))")
                        ReviewRow(label: "Days Grandma saved", value: "\(engine.state.lostDays)")
                    }
                    Card {
                        Text("Final meters").font(.headline)
                        ForEach([Meter.energy, .rel, .mood], id: \.self) { meter in
                            MeterBar(meter: meter, value: engine.state.meters[meter], name: content.name(of: meter))
                        }
                        MeterBar(meter: .debt, value: engine.state.meters.rested, name: "Sleep", asRested: true)
                    }
                    VStack(spacing: 12) {
                        ShareLink(item: store.shareText()) {
                            Label("Share your week", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            store.newWeek()
                        } label: {
                            Text("Try another week").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("tryAgain")
                        Button("Back to title") { store.backToTitle() }
                    }
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
            }
            .screenFX(fx)
            .task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                if ending.kind == .win {
                    fx.confetti += 1
                } else {
                    fx.shakes += 1
                    fx.flashes += 1
                }
            }
        }
    }
}

private struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
