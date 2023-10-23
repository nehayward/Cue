#if DEBUG
import SwiftUI

private let screenshotDirectory = "/Users/nickhayward/Desktop/"

struct PreviewScreenshot: ViewModifier {
    struct LocatorView: UIViewRepresentable {
        let tag: Int

        func makeUIView(context: Context) -> UIView {
            return UIView()
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            uiView.tag = tag
        }
    }

    @Environment(\.colorScheme) var colorScheme

    private let tag = Int.random(in: 0..<Int.max)
    let screenshotName: String

    private var screenshotPath: String {
        let colorSchemeName = colorScheme == .dark ? "dark" : "light"
        let deviceName = UIDevice.current.name

        let actualName = "\(screenshotName)-\(colorSchemeName).png"

        return "\(screenshotDirectory)/\(deviceName)/\(actualName)"
    }

    private func createDirectory() {
        let deviceName = UIDevice.current.name
        let screenshotDir = "\(screenshotDirectory)/\(deviceName)/"

        var isDir: ObjCBool = false

        if !FileManager.default.fileExists(atPath: screenshotDir, isDirectory: &isDir) {
            try! FileManager.default.createDirectory(
                atPath: screenshotDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } else if !isDir.boolValue {
            fatalError()
        }
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            LocatorView(tag: tag).frame(width: 0, height: 0)
            content
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                UIApplication.shared.windows.forEach { window in
                    guard window.viewWithTag(self.tag) != nil else { return }

                    UIGraphicsBeginImageContextWithOptions(window.bounds.size, window.isOpaque, 0.0)
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    let image = UIGraphicsGetImageFromCurrentImageContext()!
                    UIGraphicsEndImageContext()

                    self.createDirectory()

                    try? image.pngData()?.write(to: URL(fileURLWithPath: self.screenshotPath))
                }
            }
        }
    }
}

extension View {
    func screenshot(name: String) -> some View {
        self.modifier(PreviewScreenshot(screenshotName: name))
    }
}

struct PreviewScreenshot_Previews: PreviewProvider {
    static var previews: some View {
        // Usage:
        // 1. Use .screenshot(name:) on your view
        // 2. Turn on Live Preview (the play icon in the Canvas)
        // => Screenshot will appear in a few seconds
        Text("Screenshot!")
            .screenshot(name: "Test")
            .colorScheme(.dark) // colorScheme should come after .screenshot(name:) to affect the screenshot name
    }
}
#endif
