import SwiftUI

struct TitleView: View {
    @Environment(GameStore.self) private var store
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            Text("Bedtime or Bust")
                .font(.largeTitle.bold())
            Text("Five days. One toddler. One partner.\nMake it to date night.")
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

                    Button {
                        store.newWeek()
                    } label: {
                        Text("Start a new week").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        store.newWeek()
                    } label: {
                        Text("Start Monday").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("How to play") { showingHelp = true }
                    .padding(.top, 4)
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
