import DanceLogger
import SwiftUI

/// Settings ▸ Report a Problem: an email to support with Cue's log
/// attached, or the log file to share some other way, plus the log itself
/// and the switch that makes it record more.
///
/// The attachment is one plain-text file: a header with the state of the
/// app (`SupportReport.header()`), then the last few days of `DanceLogStore`.
struct ReportProblemScreen: View {
    @State private var mailDraft: MailDraft?
    @State private var isPreparingEmail = false
    @State private var detailedUntil: Date? = DanceLogStore.shared.detailedUntil
    @State private var logSize: Int?
    @State private var isConfirmingClear = false
    @State private var failure: String?

    private var canSendMail: Bool {
        #if canImport(MessageUI)
        MailComposeView.canSendMail
        #else
        false
        #endif
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Something not working?")
                        .font(.headline)
                    Text("Email support with Cue's log attached. The log shows what Cue was doing over the last few days — what played, where, and any errors along the way — so the problem can be found and fixed. Passwords and sign-in tokens are left out.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                if canSendMail {
                    Button {
                        Task { await composeEmail() }
                    } label: {
                        HStack {
                            Label("Email Support", systemImage: "envelope")
                            Spacer()
                            if isPreparingEmail {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isPreparingEmail)
                }
                ShareLink(
                    item: SupportReportFile(),
                    subject: Text(SupportReport.emailSubject),
                    preview: SharePreview("Cue Log", image: Image(systemName: "doc.text"))
                ) {
                    Label("Share Log File", systemImage: "square.and.arrow.up")
                }
            } footer: {
                if canSendMail {
                    Text("Or share the log file with another app, and send it to \(SupportReport.email).")
                } else {
                    Text("Mail isn't set up on this device. Share the log file with the email app you use, and send it to \(SupportReport.email).")
                }
            }

            Section {
                NavigationLink {
                    LogViewerScreen()
                } label: {
                    LabeledContent("View Log") {
                        if let logSize {
                            Text(Int64(logSize), format: .byteCount(style: .file))
                        }
                    }
                }
                Toggle(isOn: detailedLogging) {
                    Text("Detailed Logging")
                    Text(detailedLoggingStatus)
                }
                .tint(.accent)
                Button("Clear Log", role: .destructive) {
                    isConfirmingClear = true
                }
            } header: {
                Text("Log")
            } footer: {
                Text("Detailed Logging records much more of what Cue does, for 24 hours. Turn it on, make the problem happen again, then email support.")
            }
        }
        .navigationTitle("Report a Problem")
        #if canImport(MessageUI)
        .sheet(item: $mailDraft) { draft in
            MailComposeView(draft: draft) { result in
                DanceLog.app.notice("Report a Problem: email \(result.logDescription)")
                mailDraft = nil
            }
            .ignoresSafeArea()
        }
        #endif
        .confirmationDialog("Clear the Log?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) {
                clearLog()
            }
        } message: {
            Text("Everything Cue has logged on this device is deleted.")
        }
        .alert("Couldn't Attach the Log", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .task {
            await refreshLogSize()
        }
    }

    // MARK: - Detailed Logging

    private var isDetailed: Bool {
        detailedUntil.map { $0 > .now } ?? false
    }

    private var detailedLogging: Binding<Bool> {
        Binding {
            isDetailed
        } set: { isOn in
            DanceLogStore.shared.isDetailed = isOn
            detailedUntil = DanceLogStore.shared.detailedUntil
            DanceLog.app.notice("Detailed Logging \(isOn ? "on" : "off")")
        }
    }

    private var detailedLoggingStatus: String {
        if isDetailed, let detailedUntil {
            return "On until \(detailedUntil.formatted(date: .omitted, time: .shortened)) \(Calendar.current.isDateInToday(detailedUntil) ? "today" : "tomorrow")"
        }
        #if DEBUG
        return "Always on in Debug builds"
        #else
        return "Off"
        #endif
    }

    // MARK: - Actions

    private func composeEmail() async {
        isPreparingEmail = true
        defer { isPreparingEmail = false }
        DanceLog.app.notice("Report a Problem: preparing an email")
        do {
            let url = try await SupportReport.makeFile()
            let data = try Data(contentsOf: url)
            mailDraft = MailDraft(
                recipients: [SupportReport.email],
                subject: SupportReport.emailSubject,
                body: SupportReport.emailBody(),
                attachments: [.init(data: data, mimeType: "text/plain", fileName: url.lastPathComponent)]
            )
        } catch {
            DanceLog.app.error("Report a Problem: couldn't write the log file: \(error)")
            failure = error.localizedDescription
        }
    }

    private func clearLog() {
        DanceLogStore.shared.clear()
        DanceLog.app.notice("Log cleared")
        Task { await refreshLogSize() }
    }

    private func refreshLogSize() async {
        logSize = await Task.detached(priority: .utility) {
            DanceLogStore.shared.totalSize()
        }.value
    }
}
