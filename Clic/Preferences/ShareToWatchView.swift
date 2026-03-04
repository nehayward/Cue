import SwiftUI
import DropKit
import SonosKit

struct ShareToWatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService

    @State private var code = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var expiresAt: Date?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                HeaderView()

                CodeView(
                    code: code,
                    isLoading: isLoading,
                    expiresAt: expiresAt
                )

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                FooterView(
                    code: code,
                    isLoading: isLoading,
                    sonosIP: sonosService.lastKnownIP,
                    onGenerate: generateCode
                )
            }
            .navigationTitle("Share to Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task {
            await generateCode()
        }
    }

    private func generateCode() async {
        let currentIP = sonosService.lastKnownIP
        guard !currentIP.isEmpty else {
            error = "No Sonos system connected. Please connect your iPhone to Sonos first."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await DropService.drop(value: currentIP, ttl: 120)
            code = response.code
            expiresAt = Date().addingTimeInterval(TimeInterval(response.ttl))

        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Subviews

private struct HeaderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "applewatch")
                .font(.system(size: 60))
                .foregroundStyle(.accent.gradient)

            Text("Share to Watch")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter this code on any Apple Watch to connect it to your Sonos system. Great for guests or troubleshooting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct CodeView: View {
    let code: String
    let isLoading: Bool
    let expiresAt: Date?

    private var isExpired: Bool {
        guard let expiresAt else { return true }
        return Date() >= expiresAt
    }

    var body: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(1.5)
                .frame(height: 80)
        } else if !code.isEmpty {
            VStack(spacing: 12) {
                Text(code)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .tracking(8)
                    .contentTransition(.numericText())

                expirationLabel
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var expirationLabel: some View {
        if let expiresAt, !isExpired {
            HStack(spacing: 4) {
                Text("Expires in")
                Text(expiresAt, style: .timer)
                    .monospacedDigit()
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        } else if expiresAt != nil {
            Text("Code expired")
                .font(.title3)
                .foregroundStyle(.red)
        }
    }
}

private struct FooterView: View {
    let code: String
    let isLoading: Bool
    let sonosIP: String
    let onGenerate: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await onGenerate()
                }
            } label: {
                Text(code.isEmpty ? "Generate Code" : "Generate New Code")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.gradient)
                    .foregroundStyle(.white)
                    .contentTransition(.identity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading)

            if !sonosIP.isEmpty {
                Text("Current Sonos IP: \(sonosIP)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}

#Preview {
    ShareToWatchView()
        .withEnvironments()
}
