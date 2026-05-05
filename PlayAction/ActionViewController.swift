import SonosKit
import SwiftUI
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
import OSLog

private let log = Logger(subsystem: "com.nick.Clic.QueueAction", category: "share")

final class ActionViewController: UIViewController {
    private var viewModel = QueueListView.ViewModel()
    private var queueListView: QueueListView?
    private weak var hostingView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()

        #if targetEnvironment(macCatalyst)
        preferredContentSize = CGSize(width: 620, height: 820)
        view.backgroundColor = .clear
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blurView.frame = view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blurView)
        #endif

        queueListView = QueueListView(
            viewModel: viewModel,
            context: extensionContext,
            openURL: openURL
        )
        let hostingController = UIHostingController(rootView: queueListView)
        addChild(hostingController)
        hostingController.view.frame = self.view.bounds
        hostingController.view.backgroundColor = .clear
        #if targetEnvironment(macCatalyst)
        hostingController.view.alpha = 0
        #endif
        hostingView = hostingController.view
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        resolveSharedURL()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        #if targetEnvironment(macCatalyst)
        makeWindowTransparent()

        guard let hostingView, hostingView.alpha < 1 else { return }
        UIView.animate(withDuration: 0.25, delay: 0.05, options: [.curveEaseOut]) {
            hostingView.alpha = 1
        }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private func makeWindowTransparent() {
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor
        hostingView?.backgroundColor = .clear
        hostingView?.layer.backgroundColor = UIColor.clear.cgColor

        guard let window = view.window else { return }
        window.backgroundColor = .clear
        window.isOpaque = false

        // Walk up the view hierarchy in case a parent host paints opaque.
        var v: UIView? = view
        while let current = v {
            current.backgroundColor = .clear
            v = current.superview
        }
    }
    #endif

    private func resolveSharedURL() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            viewModel.isLoading = false
            return
        }

        for (index, item) in items.enumerated() {
            log.notice("item[\(index)] attributedTitle=\(item.attributedTitle?.string ?? "nil", privacy: .public) attributedContentText=\(item.attributedContentText?.string ?? "nil", privacy: .public) userInfo=\(String(describing: item.userInfo), privacy: .public)")

            if let text = item.attributedContentText?.string,
               let url = Self.firstURL(in: text) {
                log.notice("Found URL in attributedContentText: \(url.absoluteString, privacy: .public)")
                viewModel.url = url
                return
            }

            for (i, provider) in (item.attachments ?? []).enumerated() {
                log.notice("provider[\(index).\(i)] types=\(provider.registeredTypeIdentifiers, privacy: .public) suggestedName=\(provider.suggestedName ?? "nil", privacy: .public)")
                tryLoad(from: provider)
            }
        }
    }

    private func tryLoad(from provider: NSItemProvider) {
        // Try every registered type, ordered by usefulness.
        let preferredOrder: [String] = [
            UTType.url.identifier,
            "public.url",
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            UTType.text.identifier,
            "public.utf8-plain-text",
            "public.plain-text"
        ]

        let allTypes = preferredOrder + provider.registeredTypeIdentifiers
        var seen = Set<String>()
        let ordered = allTypes.filter { seen.insert($0).inserted }

        for type in ordered where provider.hasItemConformingToTypeIdentifier(type) {
            log.notice("loadItem type=\(type, privacy: .public)")
            provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, error in
                let itemDesc = String(describing: item)
                log.notice("loadItem returned type=\(type, privacy: .public) item=\(itemDesc, privacy: .public) error=\(error?.localizedDescription ?? "nil", privacy: .public)")
                let url = Self.coerceURL(from: item)
                    ?? Self.firstURL(in: Self.coerceString(from: item))
                OperationQueue.main.addOperation {
                    guard let self else { return }
                    if let url, self.viewModel.url == nil {
                        log.notice("Resolved URL: \(url.absoluteString, privacy: .public)")
                        self.viewModel.url = url
                    } else if self.viewModel.url == nil {
                        self.viewModel.isLoading = false
                    }
                }
            }
            return
        }

        viewModel.isLoading = false
    }

    private static func coerceURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let str = item as? String { return URL(string: str) }
        if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return URL(string: str)
        }
        return nil
    }

    private static func coerceString(from item: NSSecureCoding?) -> String? {
        if let str = item as? String { return str }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private static func firstURL(in text: String?) -> URL? {
        guard let text else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }
    
    func openURL(url: URL?) {
        guard let url else { return }
        log.notice("openURL request: \(url.absoluteString, privacy: .public)")

        // Preferred: NSExtensionContext.open works reliably in share extensions on iOS and Catalyst.
        if let extensionContext = self.extensionContext {
            extensionContext.open(url) { [weak self] success in
                log.notice("extensionContext.open success=\(success)")
                if success { return }
                // Fall back to responder-chain trick.
                _ = self?.openViaResponderChain(url)
            }
            return
        }
        _ = openViaResponderChain(url)
    }

    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                if #available(iOS 18.0, *) {
                    application.open(url, options: [:], completionHandler: nil)
                } else {
                    application.perform(NSSelectorFromString("openURL:"), with: url)
                }
                log.notice("openViaResponderChain dispatched via UIApplication")
                return true
            }
            responder = responder?.next
        }
        log.notice("openViaResponderChain: no UIApplication found in responder chain")
        return false
    }
}
