import SwiftUI
import WatchKit
import DropKit
import SonosKitMini

struct CodeEntryScreen: View {
    @Environment(SonosMiniService.self) var sonosService
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if success {
                    successView
                } else {
                    entryView
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Pair with Code")
    }

    private var entryView: some View {
        VStack(spacing: 8) {
            // Code display
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    Text(digit(at: index))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .frame(width: 22, height: 28)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Number pad
            NumberPadView(code: $code, maxDigits: 6)

            Button {
                Task {
                    await connect()
                }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 6 || isLoading)
        }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let i = code.index(code.startIndex, offsetBy: index)
        return String(code[i])
    }

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("Connected!")
                .font(.headline)

            Text("Your Watch is now connected to your Sonos system.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    private func connect() async {
        guard code.count == 6 else { return }

        isLoading = true
        error = nil

        do {
            let ip = try await DropService.pickup(code: code)

            // Save IP to storage (same as HouseholdScreen)
            NSUbiquitousKeyValueStore.default.set(ip, forKey: "sonos_ip")
            UserDefaults.standard.set(ip, forKey: "sonos_ip")

            // Refresh the Sonos service
            try? await sonosService.loadWatch(useCache: false)

            success = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Number Pad

struct NumberPadView: View {
    @Binding var code: String
    let maxDigits: Int

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...9, id: \.self) { digit in
                NumberButton(digit: "\(digit)") {
                    appendDigit("\(digit)")
                }
            }

            // Empty space
            Color.clear
                .frame(height: 32)

            // Zero
            NumberButton(digit: "0") {
                appendDigit("0")
            }

            // Delete
            Button {
                WKInterfaceDevice.current().play(.click)
                deleteDigit()
            } label: {
                Image(systemName: "delete.left")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    private func appendDigit(_ digit: String) {
        guard code.count < maxDigits else { return }
        code.append(digit)
    }

    private func deleteDigit() {
        guard !code.isEmpty else { return }
        code.removeLast()
    }
}

struct NumberButton: View {
    let digit: String
    let action: () -> Void

    var body: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            Text(digit)
                .font(.title3)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(6)
    }
}

#Preview {
    NavigationStack {
        CodeEntryScreen()
            .environment(SonosMiniService.shared)
    }
}
