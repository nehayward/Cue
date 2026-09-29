import SwiftUI

/// Live Transcription in the player's trailing panel, in the queue's place:
/// what the station playing is saying, newest line at the bottom and the line
/// still being heard under it in grey, under a header laid out like Next
/// Up's, with the language menu where Next Up names the group. For a station
/// on this device or on a speaker alike.
///
/// Being on screen is what runs it — the service starts on appear and stops,
/// taps and all, on disappear.
struct LiveTranscriptionView: View {
    private var transcription: LiveTranscriptionService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Transcription")
                    .font(.title3.bold())
                LiveTranscriptionLanguageMenu()
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
                    ForEach(transcription.lines) { line in
                        Text(line.text)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !transcription.volatileText.isEmpty {
                        Text(transcription.volatileText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if transcription.lines.isEmpty {
                        Text("Listening…")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.bottom, 12)
                .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)
            .onChange(of: transcription.lines.count) {
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: transcription.volatileText) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private static let bottomID = "bottom"

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
