import SwiftUI

/// First-launch "What are you here for today?" mission setup — and the same view
/// reused as an edit sheet from the Brain. Graphite glass, chat-style composer,
/// quick chips. Over the live (blurred) app on first run; no landing page, no
/// marketing copy.
struct MissionSetupView: View {
    @Environment(AppModel.self) private var appModel

    /// Edit mode (sheet) vs first-run (full-screen overlay).
    var isEditing: Bool = false
    /// Called after the mission is set, so a presenting sheet can dismiss.
    var onDone: (() -> Void)? = nil

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private let chips: [(label: String, text: String)] = [
        ("Investors", "Looking for investors"),
        ("Get hired", "Trying to get hired"),
        ("Hiring", "Hiring for my team"),
        ("Customers", "Looking for customers"),
        ("Sponsors", "Looking for sponsors"),
        ("Founders", "Finding startup founders"),
        ("Cofounder", "Looking for a cofounder"),
    ]

    var body: some View {
        ZStack {
            if !isEditing {
                // Blurred live app behind the panel (no blank onboarding page).
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.25).ignoresSafeArea()
            }
            card
                .padding(.horizontal, 22)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chipsRow
            composer
            footer
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .frame(maxWidth: 460)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accentSoft, in: Circle())
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(isEditing ? "Today's goal" : "What are you here for today?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("I'll prioritize who you meet and draft the follow-ups.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if isEditing {
                Button { onDone?() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Close")
            }
        }
    }

    private var chipsRow: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(chips, id: \.label) { chip in
                Button { draft = chip.text; focused = false } label: {
                    Text(chip.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(draft == chip.text ? .black : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(draft == chip.text ? Theme.accent : Theme.surface)
                        )
                        .overlay(Capsule().strokeBorder(draft == chip.text ? .clear : Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Type your goal…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(submit)
                .disabled(appModel.isParsingMission)

            Button(action: submit) {
                ZStack {
                    Circle().fill(canSubmit ? Theme.accent : Theme.surfaceStrong)
                        .frame(width: 38, height: 38)
                    if appModel.isParsingMission {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(canSubmit ? .black : Theme.textTertiary)
                    }
                }
            }
            .disabled(!canSubmit || appModel.isParsingMission)
            .accessibilityLabel(isEditing ? "Update mission" : "Continue")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder private var footer: some View {
        if appModel.isParsingMission {
            Label("Reading your goal…", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        } else if !isEditing {
            Button { skip() } label: {
                Text("Skip — just networking")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        focused = false
        Task {
            await appModel.parseMission(rawText: text)
            onDone?()
        }
    }

    private func skip() {
        appModel.skipMissionSetup()
        onDone?()
    }
}
