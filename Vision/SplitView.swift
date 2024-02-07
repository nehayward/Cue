import Foundation
import SwiftUI
import UIKit

#if targetEnvironment(macCatalyst) || os(visionOS)
//import AppKit

struct MacSplitViewRepresentable<Master, Detail>: UIViewControllerRepresentable where Master: View, Detail: View {
    // View builders for the master and detail views
    let masterBuilder: () -> Master
    let detailBuilder: () -> Detail

    // Custom initializer accepting view builders
    init(@ViewBuilder masterBuilder: @escaping () -> Master,
         @ViewBuilder detailBuilder: @escaping () -> Detail) {
        self.masterBuilder = masterBuilder
        self.detailBuilder = detailBuilder
    }

    func makeUIViewController(context: Context) -> UISplitViewController {
        let splitViewController = UISplitViewController()
        splitViewController.primaryBackgroundStyle = .sidebar
        splitViewController.minimumPrimaryColumnWidth = 500
        splitViewController.maximumPrimaryColumnWidth = 800

        // Create hosting controllers for the master and detail views
        let masterVC = UIHostingController(rootView: masterBuilder())
        let detailVC = UIHostingController(rootView: detailBuilder())

        splitViewController.viewControllers = [masterVC, detailVC]

        return splitViewController
    }

    func updateUIViewController(_ uiViewController: UISplitViewController, context: Context) {
       #if targetEnvironment(macCatalyst)
       if let windowScene = uiViewController.view.window?.windowScene {
           windowScene.titlebar?.titleVisibility = .hidden
           windowScene.titlebar?.toolbar = nil
       }
       #endif
    }
}

//class AppDelegate: NSObject, UIApplicationDelegate, NSToolbarDelegate {
//    // Your UIKit app delegate methods
//    static var appKitController: NSObject?
//
//    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
//        AppDelegate.loadAppKitIntegrationFramework()
//        return false
//    }
//
//    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
//            if options.userActivities.first?.activityType == "NewTaskWindow" {
//                return UISceneConfiguration(name: "New Task Configuration", sessionRole: connectingSceneSession.role)
//            } else {
//                return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
//            }
//        }
//
//    class func loadAppKitIntegrationFramework() {
//        if let frameworksPath = Bundle.main.privateFrameworksPath {
//            let bundlePath = "\(frameworksPath)/AppKitIntegration.framework"
//            do {
//                try Bundle(path: bundlePath)?.loadAndReturnError()
//
//                let bundle = Bundle(path: bundlePath)!
//                NSLog("[APPKIT BUNDLE] Loaded Successfully")
//
//                if let appKitControllerClass = bundle.classNamed("AppKitIntegration.AppKitController") as? NSObject.Type {
//                    appKitController = appKitControllerClass.init()
//                }
//            }
//            catch {
//                NSLog("[APPKIT BUNDLE] Error loading: \(error)")
//            }
//        }
//    }
//}

//final class MSWMainViewController<Main: View>: UIHostingController<Main> {
//    let mainBuilder: () -> Main
//
//    // Custom initializer accepting view builders
//    init(@ViewBuilder mainBuilder: @escaping () -> Main) {
//        self.mainBuilder = mainBuilder
//        super.init(rootView: mainBuilder())
//        title = "CatalystMenuBarStatusWindow"
//
//        NotificationCenter.default.addObserver(forName:  NSNotification.Name("com.example.statuswindow.show"), object: nil, queue: nil) { _ in
//            DispatchQueue.main.async {
//                self.showStatusWindow()
//            }
//        }
//    }
//
//    required init?(coder aDecoder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
//    // MARK: -
//
//    func showStatusWindow() {
//
//        /*
//
//         When the source view for a UIKit popover is not a subview of a window,
//         it triggers behavior we take advantage of in our NSPopover extension.
//
//         */
//
//        let vc = MSWStatusViewController()
//        vc.modalPresentationStyle = .popover
//
//        vc.popoverPresentationController?.sourceView = self.view
//        vc.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 1337, height: 1337)
//        vc.popoverPresentationController?.permittedArrowDirections = [.any]
//        vc.popoverPresentationController?.canOverlapSourceViewRect = true
//
//        present(vc, animated: true, completion: nil)
//    }
//}
#endif

