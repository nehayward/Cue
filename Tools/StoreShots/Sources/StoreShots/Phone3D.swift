import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SceneKit

/// The device in 3D, for previews that draw it round their recordings: an
/// extruded metal body with rounded edges and its buttons, the black glass
/// front, the recording on the screen (unlit, so its colours stay true), the
/// Dynamic Island and the glass's reflections over it all, lit by a soft
/// studio environment. Each frame is rendered by SceneKit on a clear
/// background and laid on its own shadow.
///
/// Sizes are in screen widths: the display is 1 wide, and the model's
/// bezel, rim, corner and depth are fractions of that, as in `DeviceFrame`.
final class Phone3D {
    /// Each render's size in pixels: the device, with room round it to turn.
    let canvas: CGSize
    private let renderer: SCNRenderer
    private let pivot = SCNNode()
    private let screen = SCNMaterial()

    init(model: DeviceModel, screenSize: CGSize, canvas: CGSize, finish: String?) {
        self.canvas = canvas
        let aspect = screenSize.height / screenSize.width
        let border = model.bezel + model.rim
        let width = 1 + 2 * border, height = aspect + 2 * border
        let corner = model.screenRadius + border
        let depth = model.depth

        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Self.studio()
        scene.lightingEnvironment.intensity = 2.2
        scene.rootNode.addChildNode(pivot)
        // A key light above and to the left, for a highlight along the
        // rounded edges as the device turns.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = NSColor.white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.5, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        let metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = Self.metalColor(finish)
        metal.metalness.contents = 1.0
        metal.roughness.contents = 0.26

        // The body: a rounded rectangle pushed out to the device's depth, its
        // edges rounded about as far in as the rim shows from the front.
        let outline = NSBezierPath(roundedRect: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                   xRadius: corner, yRadius: corner)
        outline.flatness = 0.0005
        let body = SCNShape(path: outline, extrusionDepth: depth)
        body.chamferMode = .both
        body.chamferRadius = model.rim * 1.15
        let round = NSBezierPath()
        round.move(to: NSPoint(x: 0, y: 1))
        round.curve(to: NSPoint(x: 1, y: 0), controlPoint1: NSPoint(x: 0.55, y: 1), controlPoint2: NSPoint(x: 1, y: 0.55))
        body.chamferProfile = round
        body.materials = [metal]
        pivot.addChildNode(SCNNode(geometry: body))

        // The front, in layers just proud of the body: black glass, the
        // screen, the island, then the glass's reflections added over them.
        let front = depth / 2
        let glassMaterial = SCNMaterial()
        glassMaterial.lightingModel = .physicallyBased
        glassMaterial.diffuse.contents = NSColor(white: 0.012, alpha: 1)
        glassMaterial.metalness.contents = 0.0
        glassMaterial.roughness.contents = 0.06
        pivot.addChildNode(Self.plane(width: width - 2 * model.rim, height: height - 2 * model.rim,
                                      corner: corner - model.rim, z: front + 0.0004, material: glassMaterial, order: 1))

        screen.lightingModel = .constant
        screen.diffuse.contents = NSColor.black
        screen.diffuse.mipFilter = .linear
        pivot.addChildNode(Self.plane(width: 1, height: aspect, corner: model.screenRadius,
                                      z: front + 0.0008, material: screen, order: 2))

        if model.kind == .phone {
            // 126 × 37 pt on a 402 pt display, 11 pt from its top.
            let island = SCNMaterial()
            island.lightingModel = .constant
            island.diffuse.contents = NSColor.black
            let long = 0.315, short = 0.093
            let node = Self.plane(width: long, height: short, corner: short / 2, z: front + 0.0012, material: island, order: 3)
            node.position.y = aspect / 2 - 0.0275 - short / 2
            pivot.addChildNode(node)
        }

        let glare = SCNMaterial()
        glare.lightingModel = .physicallyBased
        glare.diffuse.contents = NSColor.black
        glare.metalness.contents = 0.0
        glare.roughness.contents = 0.08
        glare.blendMode = .add
        glare.writesToDepthBuffer = false
        pivot.addChildNode(Self.plane(width: width - 2 * model.rim, height: height - 2 * model.rim,
                                      corner: corner - model.rim, z: front + 0.0016, material: glare, order: 4))

        if model.kind == .phone {
            // Left: Action button, volume up, volume down. Right: side button,
            // Camera Control. Fractions of the height from the top.
            for (left, from, to) in [(true, 0.18, 0.215), (true, 0.255, 0.315), (true, 0.335, 0.395),
                                     (false, 0.27, 0.37), (false, 0.53, 0.58)] as [(Bool, CGFloat, CGFloat)] {
                let length = height * (to - from)
                let proud = model.rim * 0.9
                let button = SCNBox(width: proud * 2, height: length, length: depth * 0.42, chamferRadius: proud * 0.9)
                button.materials = [metal]
                let node = SCNNode(geometry: button)
                node.position = SCNVector3((left ? -1 : 1) * (width / 2), height / 2 - height * (from + to) / 2, 0)
                pivot.addChildNode(node)
            }
        }

        // A long lens, so the device keeps its shape as it turns, far enough
        // back that it fills the canvas as the screen's pixels do.
        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.fieldOfView = 16
        camera.zNear = 0.1
        camera.zFar = 100
        let visible = canvas.height / screenSize.width
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, visible / (2 * tan(camera.fieldOfView / 2 * .pi / 180)))
        scene.rootNode.addChildNode(cameraNode)

        renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
    }

    /// The device turned by `yaw` and `pitch` (radians) with `frame` on its
    /// screen, on its shadow, `canvas` in size.
    func render(_ frame: CGImage, yaw: Double, pitch: Double) throws -> CIImage {
        screen.diffuse.contents = frame
        pivot.eulerAngles = SCNVector3(pitch, yaw, 0)
        let snapshot = renderer.snapshot(atTime: 0, with: canvas, antialiasingMode: .multisampling4X)
        guard let image = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure("SceneKit drew no device")
        }
        let device = CIImage(cgImage: image)
        let shade = device.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.42),
        ])
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = shade
        blur.radius = Float(canvas.width * 0.035)
        let shadow = blur.outputImage!.transformed(by: CGAffineTransform(translationX: 0, y: -canvas.width * 0.025))
        return device.composited(over: shadow).cropped(to: CGRect(origin: .zero, size: canvas))
    }

    private static func plane(width: CGFloat, height: CGFloat, corner: CGFloat, z: CGFloat,
                              material: SCNMaterial, order: Int) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        plane.cornerRadius = corner
        plane.cornerSegmentCount = 24
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0, z)
        node.renderingOrder = order
        return node
    }

    private static func metalColor(_ finish: String?) -> NSColor {
        switch finish {
        case "silver": NSColor(white: 0.78, alpha: 1)
        case "midnight": NSColor(srgbRed: 0.16, green: 0.19, blue: 0.26, alpha: 1)
        default: NSColor(white: 0.42, alpha: 1)
        }
    }

    /// A dark studio, as an equirectangular map: tall strip lights all round,
    /// a broad soft box overhead, and Cue's green rising from the floor.
    private static func studio() -> CGImage {
        let width = 2048, height = 1024
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.02, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Core Graphics' origin is the bottom left: y here is up from the floor.
        let floor = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.02, green: 0.59, blue: 0.41, alpha: 0.55), CGColor(srgbRed: 0.02, green: 0.59, blue: 0.41, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(floor, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(height) * 0.42), options: [])
        func soft(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ brightness: CGFloat, stretch: CGFloat = 1) {
            let glow = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: brightness, alpha: 1), CGColor(gray: brightness, alpha: 0.6), CGColor(gray: brightness, alpha: 0),
            ] as CFArray, locations: [0, 0.45, 1])!
            context.saveGState()
            context.translateBy(x: x * CGFloat(width), y: y * CGFloat(height))
            context.scaleBy(x: 1, y: stretch)
            context.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                       endRadius: radius * CGFloat(width), options: [])
            context.restoreGState()
        }
        // Tall strips at the four quarters, so every edge faces one, and a
        // broad box overhead.
        for x in [0.0, 0.25, 0.5, 0.75, 1.0] as [CGFloat] {
            soft(x, 0.56, 0.05, 0.95, stretch: 4)
        }
        soft(0.5, 0.92, 0.3, 0.8, stretch: 0.35)
        soft(0.0, 0.92, 0.3, 0.8, stretch: 0.35)
        soft(1.0, 0.92, 0.3, 0.8, stretch: 0.35)
        return context.makeImage()!
    }
}
