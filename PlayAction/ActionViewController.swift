import SonosKit
import SwiftUI
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

final class ActionViewController: UIViewController {
    private var viewModel = QueueListView.ViewModel()
    private var queueListView: QueueListView?

    override func viewDidLoad() {
        super.viewDidLoad()

        queueListView = QueueListView(
            viewModel: viewModel,
            context: extensionContext,
            openURL: openURL
        )
        let hostingController = UIHostingController(rootView: queueListView)
        addChild(hostingController)
        hostingController.view.frame = self.view.bounds
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        for item in self.extensionContext!.inputItems as! [NSExtensionItem] {
            for provider in item.attachments! {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    // This is an image. We'll load it, then place it in our image view.
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil, completionHandler: { (URL, error) in
                        OperationQueue.main.addOperation { [weak self] in
                            guard let URL = URL as? URL else {
                                self?.viewModel.isLoading = false
                                return
                            }
                            self?.viewModel.url = URL
                        }
                    })
                }
            }
        }
    }
    
    // Redirect To App
    func openURL(url: URL?) {
        guard let url else {
            return
        }
        openURL(url)
    }

    /// Open URL Code
    @objc @discardableResult func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                if #available(iOS 18.0, *) {
                    application.open(url, options: [:], completionHandler: nil)
                    return true
                } else {
                    return application.perform(#selector(openURL(_:)), with: url) != nil
                }
            }
            responder = responder?.next
        }
        return false
    }
}
