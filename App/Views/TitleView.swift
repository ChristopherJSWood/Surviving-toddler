import SwiftUI

@MainActor
struct TitleView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingHelp = false
    @State private var household: HouseholdPrompt?

    /// Why the names sheet is open: to start a week, or just to edit.
    private enum HouseholdPrompt: Identifiable {
        case startWeek, edit
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
                .phaseAnimator([false, true]) { moon, up in
                    moon
                        .offset(y: up && !reduceMotion ? -8 : 0)
                        .rotationEffect(.degrees(up && !reduceMotion ? -6 : 4))
                } animation: { _ in
                    .easeInOut(duration: 1.6)
                }
                .accessibilityHidden(true)
            Text("Bedtime or Bust")
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()

            VStack(spacing: 12) {
                if store.hasSavedGame {
                    Button {
                        store.resume()
                    } label: {
                        Text("Continue this week").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("resume")

                    Button {
                        start()
                    } label: {
                        Text("Start a new week").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        start()
                    } label: {
                        Text("Start Monday").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("start")
                }
                HStack(spacing: 20) {
                    Button("How to play") { showingHelp = true }
                    Button("Names & settings") { household = .edit }
                }
                .padding(.top, 4)
                if !store.reactions.isEmpty {
                    ShareLink(item: store.reactionsCSV(), preview: SharePreview("Bedtime or Bust playtest log")) {
                        Label("Export playtest log (\(store.reactions.count))", systemImage: "square.and.arrow.up")
                            .font(.footnote)
                    }
                }
            }
            .controlSize(.large)

            if store.stats.weeksPlayed > 0 {
                Text("Weeks survived: \(store.stats.weeksWon) of \(store.stats.weeksPlayed) · Best score: \(store.stats.bestScore)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .sheet(isPresented: $showingHelp) { HowToPlayView() }
        .sheet(item: $household) { prompt in
            HouseholdSheet(startsWeek: prompt == .startWeek)
        }
    }

    private var subtitle: String {
        guard store.household.isComplete else { return "Five days. One toddler. One partner.\nMake it to date night." }
        return store.say("Five days. {kid}. {partner}.\nMake it to date night.")
    }

    /// The first week asks who's in the house; after that, straight to Monday.
    private func start() {
        if store.household.isComplete {
            store.newWeek()
        } else {
            household = .startWeek
        }
    }
}

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("The goal") {
                    Text("Get from Monday morning to Friday's date night. At 7:00 PM on Friday the toddler must be asleep (Sleepiness 67+) and you need at least 35 Energy, or the date is off.")
                }
                Section("You") {
                    Label("Energy is how much parent you have left. Good parenting costs it. Below a choice's minimum it's greyed out: too tired. At zero you collapse.", systemImage: "bolt.fill")
                    Label("Relationship drains when you're running on empty. A healthy one means your partner helps more. At zero the week ends.", systemImage: "heart.fill")
                }
                Section("Shortcuts") {
                    Label("TV, candy and late coffee give Energy now and send a bill later. A ticking chip shows when it's due.", systemImage: "hourglass")
                }
                Section("Your toddler") {
                    Label("Sleepiness must be 50+ at bedtime. Naps lower it.", systemImage: "moon.zzz.fill")
                    Label("Sleep Debt carries across the week. High debt means earlier mornings, more chaos, faster meltdowns.", systemImage: "bed.double.fill")
                }
                Section("The household") {
                    Label("House and Reputation at zero end the day. Once a week, Grandma rescues you.", systemImage: "house.fill")
                    Label("Your list holds the invisible jobs. Forget one and it bites later.", systemImage: "list.bullet.clipboard")
                }
            }
            .navigationTitle("How to play")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
