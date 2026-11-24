import BedtimeCore
import SwiftUI

/// The weekly performance review.
struct EndView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let engine = store.engine, let ending = engine.ending {
            let content = engine.content
            ScrollView {
                VStack(spacing: 16) {
                    Text(ending.kind == .win ? "Week complete" : "Week over")
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(ending.kind == .win ? Color.green : Color.red)
                        .padding(.top, 24)
                    Text(ending.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Card {
                        Text(ending.text)
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
                            Text(style.title).font(.title2.bold())
                            Text(style.text)
                        }
                    }
                    Card {
                        Text("Weekly performance review").font(.headline)
                        ForEach(content.counters) { counter in
                            ReviewRow(label: counter.label, value: "\(engine.state.counters[counter.id] ?? 0)")
                        }
                        Divider()
                        ReviewRow(label: "Night wake-ups (you · partner)",
                                  value: "\(engine.state.ledgerYou["night"] ?? 0) · \(engine.state.ledgerPartner["night"] ?? 0)")
                        ReviewRow(label: "Chores (you · partner)",
                                  value: "\(engine.state.ledgerYou.values.reduce(0, +)) · \(engine.state.ledgerPartner.values.reduce(0, +))")
                        ReviewRow(label: "Days Grandma saved", value: "\(engine.state.lostDays)")
                    }
                    Card {
                        Text("Final meters").font(.headline)
                        ForEach([Meter.energy, .rel, .mood, .home, .rep], id: \.self) { meter in
                            MeterBar(meter: meter, value: engine.state.meters[meter], name: content.name(of: meter))
                        }
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
                        Button("Back to title") { store.backToTitle() }
                    }
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
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
