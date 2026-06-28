import SwiftUI

/// "What are we looking for?" — the Lazy GTM voice panel. Glass card over the
/// blurred camera. Press the mic (Deepgram, when available) or type; quick chips
/// seed common requests. Submitting runs the Scout search with a premium,
/// phased loading state.
struct LazyGTMVoicePanelView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    private let chips = [
        "Hire a Swift engineer",
        "Find investors",
        "Find customers",
        "Find sponsors",
    ]

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { if !appModel.isRunningGTM { dismiss() } }

            card.padding(.horizontal, 22)
        }
        .onChange(of: appModel.partialTranscript) { _, new in
            if appModel.isListening, !new.isEmpty { draft = new }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if appModel.isRunningGTM {
                loadingState
            } else {
                chipsRow
                composer
                if let err = appModel.gtmError {
                    Text(err).font(.caption).foregroundStyle(Color.red.opacity(0.85))
                } else if let mic = micHint {
                    Text(mic).font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .frame(maxWidth: 460)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38).background(Theme.accentSoft, in: Circle())
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text("What are we looking for?").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("I'll scout and rank prospects for you.").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30).background(Theme.surface, in: Circle())
            }
            .disabled(appModel.isRunningGTM)
            .accessibilityLabel("Close")
        }
    }

    private var chipsRow: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Button { draft = chip; focused = false } label: {
                    Text(chip)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(draft == chip ? .black : Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(draft == chip ? Theme.accent : Theme.surface))
                        .overlay(Capsule().strokeBorder(draft == chip ? .clear : Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            if appModel.isVoiceAvailable {
                Button { toggleMic() } label: {
                    Image(systemName: appModel.isListening ? "waveform" : "mic.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appModel.isListening ? .black : Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(appModel.isListening ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceStrong), in: Circle())
                }
                .accessibilityLabel(appModel.isListening ? "Stop listening" : "Start listening")
            }

            TextField("Type your request…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.subheadline).foregroundStyle(Theme.textPrimary)
                .lineLimit(1...3).focused($focused).submitLabel(.go).onSubmit(submit)

            Button(action: submit) {
                ZStack {
                    Circle().fill(canSubmit ? Theme.accent : Theme.surfaceStrong).frame(width: 38, height: 38)
                    Image(systemName: "arrow.up").font(.subheadline.weight(.bold))
                        .foregroundStyle(canSubmit ? .black : Theme.textTertiary)
                }
            }
            .disabled(!canSubmit)
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(appModel.gtmStatusMessage ?? "Searching…")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("Finding the right people").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var micHint: String? {
        appModel.isVoiceAvailable ? "Tap the mic or type — then search." : "Voice needs a backend — type your request."
    }

    private var canSubmit: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func toggleMic() {
        if appModel.isListening {
            appModel.stopListening(run: false)
        } else {
            draft = ""
            appModel.startListening()
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if appModel.isListening { appModel.stopListening(run: false) }
        focused = false
        Task {
            await appModel.runGTMScout(transcript: text)
            if appModel.showScout { isPresented = false }
        }
    }

    private func dismiss() {
        if appModel.isListening { appModel.stopListening(run: false) }
        isPresented = false
    }
}
