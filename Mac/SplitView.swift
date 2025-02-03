import Foundation
import SwiftUI
import SonosKit
import SubscriptionKit


struct SidebarSplitView: View, UIViewControllerRepresentable {
    typealias UIViewControllerType = UISplitViewController
    let splitViewController = UISplitViewController(style: .doubleColumn)

    var columnA = UIViewController()
    var columnB = UIViewController()
    var columnC = UIViewController()

    init<A:View, B:View, C: View>(@ViewBuilder content: @escaping () -> TupleView <(A,B,C)>) {
        let content = content()
        columnA = UIHostingController(rootView: content.value.0)
        columnB = UIHostingController(rootView: content.value.1)
        columnC = UIHostingController(rootView: content.value.2)

        columnA.view.backgroundColor = .clear
        columnB.view.backgroundColor = .clear
        splitViewController.viewControllers = [columnA, columnB]
        splitViewController.setViewController(columnC, for: .compact)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        splitViewController.primaryBackgroundStyle = .sidebar
        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.preferredSplitBehavior = .tile
        splitViewController.maximumPrimaryColumnWidth = 600
        splitViewController.minimumPrimaryColumnWidth = 320

        splitViewController.preferredPrimaryColumnWidthFraction = 0.3
        return splitViewController
    }

    func updateUIViewController(_ uiView: UIViewControllerType, context: Context) { }
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

