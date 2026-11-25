import SwiftUI

/// "Who's in your house?": the names the game uses, plus settings.
struct HouseholdSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Before the first week: the confirm button starts Monday.
    var startsWeek = false

    @State private var draft = Household()

    private var kidName: String { draft.kid.trimmed.isEmpty ? "your toddler" : draft.kid.trimmed }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bean", text: $draft.kid)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your toddler's name")
                }
                Section {
                    TextField("Sam", text: $draft.partner)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your partner's name")
                } footer: {
                    Text("The game calls them both \u{201C}they.\u{201D}")
                }
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(Household.callYouSuggestions, id: \.self) { option in
                            Button(option) { draft.me = option }
                                .buttonStyle(.bordered)
                                .tint(draft.me == option ? Color.accentColor : Color.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Something else", text: $draft.me)
                        .autocorrectionDisabled()
                } header: {
                    Text("What does \(kidName) call you?")
                } footer: {
                    Text("Usually yelled. Usually at 5:58 AM.")
                }
                Section {
                    Toggle("Panic timers", isOn: Binding(get: { store.timersEnabled }, set: { store.setTimersEnabled($0) }))
                    Toggle("\u{1F602} / \u{1F634} playtest buttons", isOn: Binding(get: { store.reactionsEnabled }, set: { store.setReactionsEnabled($0) }))
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Panic cards give you a few seconds to decide, or your toddler decides for you. They're always off with VoiceOver.")
                }
            }
            .navigationTitle("Who's in your house?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(startsWeek ? "Start Monday" : "Save") {
                        store.setHousehold(draft)
                        dismiss()
                        if startsWeek { store.newWeek() }
                    }
                    .disabled(!draft.cleaned().isComplete)
                }
            }
            .onAppear { draft = store.household }
        }
    }
}
