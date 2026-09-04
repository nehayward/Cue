import UIKit
import UniformTypeIdentifiers

/// Presents the system folder picker from whatever is on top, and hands the
/// chosen folder back. UIKit rather than SwiftUI's `fileImporter`: on Mac
/// Catalyst the importer, used inside a sheet, trips an AppKit assertion
/// (the open panel wants a modal session the sheet already holds), where a
/// `UIDocumentPickerViewController` presented from the sheet's own
/// controller comes up as a proper window panel.
@MainActor
final class FolderPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = FolderPicker()

    private var completion: ((URL?) -> Void)?

    /// Shows the picker. The URL is security-scoped; the caller starts
    /// access (or bookmarks it) as it needs.
    func present(completion: @escaping (URL?) -> Void) {
        guard let presenter = Self.topViewController() else {
            completion(nil)
            return
        }
        self.completion = completion
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(with: urls.first)
    }

    /// A file rather than a folder — some providers hand one back — means
    /// the folder it sits in.
    private func finish(with url: URL?) {
        let completion = completion
        self.completion = nil
        guard var url else {
            completion?(nil)
            return
        }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        if !isDirectory {
            url = url.deletingLastPathComponent()
        }
        completion?(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let completion = completion
        self.completion = nil
        completion?(nil)
    }

    /// The controller at the top of the key window's presentation chain —
    /// the sheet the Files settings live in, when that's what's showing.
    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
