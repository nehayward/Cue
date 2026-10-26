import Foundation
import SwiftUI

enum Commands {
    /// Every shot for each device, framed, captioned, at the slot's size.
    static func render(_ workspace: Workspace, devices only: [String], shots names: [String]) throws {
        let project = workspace.project
        let icon = try project.icon.map { try Renderer.load(workspace.resolve($0)) }
        let keys = only.isEmpty ? project.devices.keys.sorted() : only
        for key in keys {
            let setup = try workspace.setup(key)
            let model = try workspace.model(key)
            let shots = workspace.shots(for: key)
            guard !shots.isEmpty else {
                print("\(key): no raw screenshots in \(workspace.rawFolder.appendingPathComponent(key).path)")
                continue
            }
            let folder = workspace.outputFolder.appendingPathComponent(key)
            // A whole set replaces the last one, so renamed shots don't linger.
            if names.isEmpty { try? FileManager.default.removeItem(at: folder) }
            for (index, entry) in shots.enumerated() where names.isEmpty || names.contains(entry.shot.name) {
                let screen = try Renderer.load(entry.screen)
                let landscape = setup.landscape ?? (screen.width > screen.height)
                let canvas = model.canvas(landscape: landscape)
                let image: CGImage
                if setup.bare == true {
                    image = try Renderer.filled(screen, to: canvas)
                } else {
                    let companion = try entry.shot.companion.map { companion in
                        (model: try workspace.model(companion.device),
                         screen: try Renderer.load(workspace.raw(companion.device, companion.screen)))
                    }
                    let view = try ShotView(shot: entry.shot, model: model, canvas: canvas, index: index,
                                        theme: project.theme, screen: screen, companion: companion, icon: icon,
                                            deviceWidth: setup.deviceWidth.map { CGFloat($0) }, bleed: setup.bleed ?? false)
                    image = try Renderer.image(view, size: canvas)
                }
                let flat = try Renderer.opaque(image, background: project.theme.base.cgColor)
                guard flat.width == Int(canvas.width), flat.height == Int(canvas.height) else {
                    throw Failure("\(key)/\(entry.shot.name) came out \(flat.width)×\(flat.height), not \(Int(canvas.width))×\(Int(canvas.height))")
                }
                let url = folder.appendingPathComponent(String(format: "%02d-%@.png", index + 1, entry.shot.name))
                try Renderer.write(flat, to: url)
                print("\(key): \(url.lastPathComponent) \(flat.width)×\(flat.height)")
            }
        }
    }

    /// The simulator's screen now, saved as a device's raw screenshot. With
    /// `launch`, the app is relaunched first with the shot's arguments.
    static func shoot(_ workspace: Workspace, device key: String, shot name: String, launch: Bool) throws {
        let setup = try workspace.setup(key)
        guard let simulatorName = setup.simulator else { throw Failure("\(key) has no simulator in the project") }
        let simulator = try Simulator.named(simulatorName)
        if setup.statusBar ?? true { try simulator.overrideStatusBar() }
        if launch {
            guard let bundleID = workspace.project.bundleID else { throw Failure("the project has no bundleID to launch") }
            let shot = workspace.project.shots.first { $0.name == name }
            try simulator.relaunch(bundleID, arguments: (workspace.project.launch ?? []) + (shot?.launch ?? []))
            Thread.sleep(forTimeInterval: shot?.wait ?? 8)
        }
        let url = workspace.raw(key, name)
        try simulator.screenshot(to: url, display: setup.display)
        let image = try Renderer.load(url)
        print("\(key): \(name).png \(image.width)×\(image.height) from \(simulatorName)")
    }

    /// A screen recording for a preview, from the device's simulator.
    static func record(_ workspace: Workspace, device key: String, clip name: String, seconds: Double) throws {
        let setup = try workspace.setup(key)
        guard let simulatorName = setup.simulator else { throw Failure("\(key) has no simulator in the project") }
        let simulator = try Simulator.named(simulatorName)
        if setup.statusBar ?? true { try simulator.overrideStatusBar() }
        let url = workspace.clipsFolder.appendingPathComponent(key).appendingPathComponent(name + ".mov")
        try simulator.record(to: url, seconds: seconds, display: setup.display)
        print("\(key): \(url.path)")
    }

    /// Each device's finished images side by side, small, to look over at once.
    static func sheet(_ workspace: Workspace) throws {
        let fileManager = FileManager.default
        for key in workspace.project.devices.keys.sorted() {
            let folder = workspace.outputFolder.appendingPathComponent(key)
            let files = ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { continue }
            let images = try files.map(Renderer.load)
            let height: CGFloat = 900
            let gap: CGFloat = 24
            let widths = images.map { CGFloat($0.width) * height / CGFloat($0.height) }
            let size = CGSize(width: widths.reduce(0, +) + gap * CGFloat(images.count + 1), height: height + 2 * gap)
            let view = HStack(spacing: gap) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: widths[index], height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(gap)
            .background(Color(white: 0.93))
            let url = workspace.outputFolder.appendingPathComponent("sheet-\(key).png")
            try Renderer.write(try Renderer.opaque(try Renderer.image(view, size: size), background: .white), to: url)
            print("sheet: \(url.path)")
        }
    }

    static func listDevices() {
        for model in DeviceModel.catalog.values.sorted(by: { $0.id < $1.id }) {
            let preview = model.preview.map { " · preview \(Int($0.width))×\(Int($0.height))" } ?? ""
            print("\(model.id.padding(toLength: 18, withPad: " ", startingAt: 0)) \(Int(model.canvas.width))×\(Int(model.canvas.height))\(preview)  \(model.slot)")
        }
    }
}
