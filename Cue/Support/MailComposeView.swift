import Foundation
#if canImport(MessageUI)
import MessageUI
import SwiftUI
#endif

/// An email ready to send, for `MailComposeView`. Identifiable so a sheet
/// can be presented with it as its item.
struct MailDraft: Identifiable {
    struct Attachment {
        let data: Data
        let mimeType: String
        let fileName: String
    }

    let id = UUID()
    var recipients: [String]
    var subject: String
    var body: String
    var attachments: [Attachment] = []
}

#if canImport(MessageUI)

/// The system's mail sheet, with a draft filled in. Only offer it when
/// `canSendMail` is true: without a Mail account the sheet can't be shown.
struct MailComposeView: UIViewControllerRepresentable {
    let draft: MailDraft
    /// Called once the person sends, saves or cancels. Clear the sheet's
    /// item here to take it down.
    var onFinish: (MFMailComposeResult) -> Void

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(draft.recipients)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for attachment in draft.attachments {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}

extension MFMailComposeResult {
    /// What became of the email, for the log.
    var logDescription: String {
        switch self {
        case .cancelled: "cancelled"
        case .saved: "saved as a draft"
        case .sent: "sent"
        case .failed: "failed"
        @unknown default: "finished (\(rawValue))"
        }
    }
}
#endif
