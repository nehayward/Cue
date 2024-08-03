import SwiftUI
import MessageUI
import AppleArchive

struct MailViewRepresentable: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var subject: String
    var recipients: [String]?
    var messageBody: String?
    var logFilesDirectory: URL  // Directory containing log files

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<MailViewRepresentable>) -> MFMailComposeViewController {
        let mailComposer = MFMailComposeViewController()
        mailComposer.mailComposeDelegate = context.coordinator
        configureMailComposer(mailComposer)
        return mailComposer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: UIViewControllerRepresentableContext<MailViewRepresentable>) {
        // No update action needed
    }

    private func configureMailComposer(_ mailComposer: MFMailComposeViewController) {
        if MFMailComposeViewController.canSendMail() {
            mailComposer.setSubject(subject)
            mailComposer.setToRecipients(recipients)
            if let body = messageBody {
                mailComposer.setMessageBody(body, isHTML: false)
            }
            // Attach zipped log files
            mailComposer.addAttachmentData(try! Data(contentsOf: zip()!), mimeType: "application/zip", fileName: logFilesDirectory.lastPathComponent)
        } else {
            print("Cannot send email")
        }
    }

    private func zip() -> URL? {
        let fm = FileManager.default
        let baseDirectoryUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "Logs")

        // this will hold the URL of the zip file
        var archiveUrl: URL?
        // if we encounter an error, store it here
        var error: NSError?

        let coordinator = NSFileCoordinator()
        // zip up the documents directory
        // this method is synchronous and the block will be executed before it returns
        // if the method fails, the block will not be executed though
        // if you expect the archiving process to take long, execute it on another queue
        coordinator.coordinate(readingItemAt: baseDirectoryUrl, options: [.forUploading], error: &error) { (zipUrl) in
            // zipUrl points to the zip file created by the coordinator
            // zipUrl is valid only until the end of this block, so we move the file to a temporary folder
            let tmpUrl = try! fm.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: zipUrl,
                create: true
            ).appendingPathComponent("archive.zip")

            
            try! fm.moveItem(at: zipUrl, to: tmpUrl)

            // store the URL so we can use it outside the block
            archiveUrl = tmpUrl
        }

        return archiveUrl

//        if let archiveUrl = archiveUrl {
//            // bring up the share sheet so we can send the archive with AirDrop for example
//            let avc = UIActivityViewController(activityItems: [archiveUrl], applicationActivities: nil)
//            present(avc, animated: true)
//        } else {
//            print(error)
//        }
    }

}
