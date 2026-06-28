import SwiftUI

/// Typed command bar + voice button. The typed path works in every mode and is
/// the reliable demo fallback. The voice button currently offers a quick-pick
/// of the supported example commands (a stage-safe stand-in for live speech);
/// real Deepgram / on-device Speech wires into `runStaged` / `runCommand`
/// later without changing anything downstream.
struct CommandBarView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var focused: Bool

    /// The supported demo commands, exactly as in the Person D brief, plus the
    /// identity lane ("find info on him").
    private let examples = [
        "Find info on him.",
        "Show me AI founders.",
        "Who should I talk to about infra?",
        "Only growth people.",
        "Draft an opener for Ava.",
        "Reset."
    ]

    var body: some View {
        @Bindable var model = appModel

        HStack(spacing: 10) {
            // Voice button (quick-pick stand-in for live speech).
            Menu {
                Section("Try saying") {
                    ForEach(examples, id: \.self) { example in
                        Button {
                            runStaged(example)
                        } label: {
                            Label(example, systemImage: "quote.bubble")
                        }
                    }
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.accent))
                    .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 3)
            }

            // Typed command field.
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(Theme.textTertiary)
                TextField("Type a command…", text: $model.commandDraft)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .autocorrectionDisabled()
                if !model.commandDraft.isEmpty {
                    Button {
                        submit()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(corner: 14)
        }
    }

    private func submit() {
        focused = false
        appModel.submitTypedCommand()
    }

    /// Simulate a voice command: show it in the bar momentarily, then run it
    /// through the shared command pipeline.
    private func runStaged(_ text: String) {
        focused = false
        Task { await appModel.runCommand(text) }
    }
}
