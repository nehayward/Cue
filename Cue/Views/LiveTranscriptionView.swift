import SwiftUI

/// Live Transcription in the player's trailing panel, in the queue's place:
/// what the station playing is saying, newest at the bottom. The line being
/// said right now is bright, behind a moving waveform; lines already said
/// are dimmed and fade out at the top. The header, laid out like Next Up's,
/// carries the language menu where Next Up names the group and a Live badge
/// while it's listening. For a station on this device or on a speaker alike.
///
/// Being on screen is what runs it — the service starts on appear and stops,
/// taps and all, on disappear.
struct LiveTranscriptionView: View {
    private var transcription: LiveTranscriptionService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Transcription")
                        .font(.title3.bold())
                    LiveTranscriptionLanguageMenu()
                }
                Spacer(minLength: 8)
                LiveTranscriptionStatusBadge(state: transcription.state)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            content
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { transcription.activate() }
        .onDisappear { transcription.deactivate() }
    }

    @ViewBuilder
    private var content: some View {
        switch transcription.state {
        case .unsupported:
            message("Live Transcription needs iOS 26 or later on a device that supports on-device speech.", systemImage: "exclamationmark.bubble")
        case .unavailable(let reason):
            message(reason, systemImage: "speaker.slash")
        case .failed(let reason):
            message(reason, systemImage: "exclamationmark.triangle")
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 8) {
                Text("Downloading \(languageName)…")
                    .font(.headline)
                ProgressView(value: fraction)
                Text("Only the first time — it's kept on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .paused where transcription.lines.isEmpty:
            message("Paused — transcription picks up when the station plays again.", systemImage: "pause.circle")
        case .connecting where transcription.lines.isEmpty:
            VStack(spacing: 8) {
                ProgressView()
                Text("Tuning in…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .listening, .paused, .connecting:
            transcript
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Already said: dimmed, so the live line stands out.
                    ForEach(transcription.lines) { line in
                        Text(line.text)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    liveLine
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                // Room under the top fade for the first line to be read.
                .padding(.top, Self.fadeHeight / 2)
                .padding(.bottom, 12)
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeHeight)
                    Color.black
                }
            }
            .onChange(of: transcription.lines.count) {
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: transcription.volatileText) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private static let bottomID = "bottom"
    private static let fadeHeight: CGFloat = 32

    /// What's being said right now, behind a waveform that moves while the
    /// station is heard — or, before the first words, where they'll appear.
    @ViewBuilder
    private var liveLine: some View {
        let isListening = transcription.state == .listening
        if !transcription.volatileText.isEmpty || isListening {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isListening)
                    .accessibilityHidden(true)
                if transcription.volatileText.isEmpty {
                    Text("Listening…")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(transcription.volatileText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Now: \(transcription.volatileText)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var languageName: String {
        transcription.locale.map(LiveTranscriptionService.displayName(for:)) ?? "language"
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where the transcript stands, beside the title: Live while the station is
/// being heard, and a quieter word while it's tuning in or paused.
private struct LiveTranscriptionStatusBadge: View {
    let state: LiveTranscriptionService.State

    @State private var isPulsing = false

    var body: some View {
        switch state {
        case .listening:
            HStack(spacing: 5) {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }
                Text("LIVE")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.red, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Live")
        case .connecting:
            label("Tuning in")
        case .paused:
            label("Paused")
        default:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

/// Picks the transcription language — remembered for the station playing,
/// and the first guess for stations not heard before. A language not yet on
/// the device downloads once picked.
private struct LiveTranscriptionLanguageMenu: View {
    private var transcription: LiveTranscriptionService { .shared }

    var body: some View {
        Menu {
            Picker("Language", selection: selection) {
                ForEach(transcription.supportedLocales, id: \.identifier) { locale in
                    Text(LiveTranscriptionService.displayName(for: locale))
                        .tag(locale.identifier)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(transcription.locale.map(LiveTranscriptionService.displayName(for:)) ?? "Language")
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(transcription.supportedLocales.isEmpty)
    }

    private var selection: Binding<String> {
        Binding {
            transcription.locale?.identifier ?? ""
        } set: { identifier in
            transcription.setLocale(Locale(identifier: identifier))
        }
    }
}

/// The header's switch for Live Transcription, filled while it's on.
struct LiveTranscriptionButton: View {
    private var transcription: LiveTranscriptionService { .shared }

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            withAnimation(.smooth) {
                transcription.isEnabled.toggle()
            }
        } label: {
            Label("Live Transcription", systemImage: transcription.isEnabled ? "captions.bubble.fill" : "captions.bubble")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonBorderShape(.circle)
        .help("Live Transcription")
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
