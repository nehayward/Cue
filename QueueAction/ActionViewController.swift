//
import SonosKit
import SwiftUI
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

struct ActionExtensionView: View {
    var test: Test
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()
    @Environment(\.dismiss) private var dismiss
    var context: NSExtensionContext?
    @State var sonosService: SonosService

    var body: some View {
        NavigationStack {
            Text(test.url)
            Text(test.id)
            List(sonosService.sorted) { group in
                Button(group.nameWithCount) {
                    impactFeedbackGenerator.impactOccurred()
                    Task {
                        await sonosService.queueSpotifyPlaylist(id: test.id, title: "", owner: "", on: group.ip, group: group)
                        await sonosService.play(ip: group.ip)
                        self.context?.completeRequest(returningItems: [])
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        self.context?.completeRequest(returningItems: [])
                    }
                }
            }
        }
        .task {
            try? await sonosService.updateGroups()
            impactFeedbackGenerator.prepare()
        }
    }
}

@Observable
class Test {
    var url: String
    var id: String {
        let url = URL(string: url)
        return url?.lastPathComponent ?? ""
    }

    init(url: String) {
        self.url = url
    }
}

class ActionViewController: UIViewController {
//    private var weak = ActionExtensionView:
    private var vm: Test = Test(url: "Test")
    var actionView: ActionExtensionView?

    

    override func viewDidLoad() {
        super.viewDidLoad()

        actionView = ActionExtensionView(test: vm, context: extensionContext, sonosService: SonosService.shared)
        let hostingController = UIHostingController(rootView: actionView)
        addChild(hostingController)
        hostingController.view.frame = self.view.bounds
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        vm.url = "Testing"

        // Get the item[s] we're handling from the extension context.
        
        // For example, look for an image and place it into an image view.
        // Replace this with something appropriate for the type[s] your extension supports.
        var imageFound = false
        for item in self.extensionContext!.inputItems as! [NSExtensionItem] {
            for provider in item.attachments! {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    // This is an image. We'll load it, then place it in our image view.
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil, completionHandler: { (imageURL, error) in
                        OperationQueue.main.addOperation {

//                            if let strongImageView = weakImageView {
                                if let imageURL = imageURL as? URL {
                                    self.vm.url = imageURL.absoluteString
//                                    strongImageView.image = UIImage(data: try! Data(contentsOf: imageURL))
                                }
//                            }
                        }
                    })
                    
                    imageFound = true
                    break
                }
            }
            
            if (imageFound) {
                // We only handle one image, so stop looking for more.
                break
            }
        }
    }
}
