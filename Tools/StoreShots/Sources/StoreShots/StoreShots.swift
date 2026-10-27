import Foundation

/// App Store screenshots and previews from simulator captures: each device
/// drawn round its screenshot, a caption in SF Pro Rounded over a gradient
/// that runs across the set, at the exact sizes App Store Connect takes.
/// Everything app-specific is in the project file, so any app can use it.
@main
struct StoreShots {
    static let usage = """
    usage: storeshots <command> <project.json> [options]

      render <project> [--device <key>]... [--shot <name>]...
          Frame and caption every raw screenshot → <output>/<device>/NN-<shot>.png
      shoot <project> <device> <shot> [--launch]
          Save the device's simulator screen as <raw>/<device>/<shot>.png
          (status bar at 9:41). --launch relaunches the app with the shot's
          launch arguments first.
      record <project> <device> <clip> [--seconds 20]
          Record the simulator's screen → <clips>/<device>/<clip>.mov
      preview <project> [--name <preview>]
          Render the App Preview movies → <output>/previews/<name>.mov
      sheet <project>
          One image per device with every finished shot, to review the set
      devices
          The device models, their App Store sizes and slots
    """

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { exit(usage) }
        arguments.removeFirst()
        do {
            if command == "devices" { return Commands.listDevices() }
            guard let path = arguments.first else { exit(usage) }
            arguments.removeFirst()
            let workspace = try Workspace(path: path)
            switch command {
            case "render":
                try Commands.render(workspace, devices: values(of: "--device", in: &arguments),
                                    shots: values(of: "--shot", in: &arguments))
            case "shoot":
                let launch = flag("--launch", in: &arguments)
                guard arguments.count == 2 else { exit(usage) }
                try Commands.shoot(workspace, device: arguments[0], shot: arguments[1], launch: launch)
            case "record":
                let seconds = values(of: "--seconds", in: &arguments).last.flatMap(Double.init) ?? 20
                guard arguments.count == 2 else { exit(usage) }
                try Commands.record(workspace, device: arguments[0], clip: arguments[1], seconds: seconds)
            case "preview":
                try PreviewRenderer.renderAll(workspace, names: values(of: "--name", in: &arguments))
            case "sheet":
                try Commands.sheet(workspace)
            default:
                exit(usage)
            }
        } catch {
            FileHandle.standardError.write(Data("storeshots: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func exit(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        Foundation.exit(64)
    }

    private static func values(of option: String, in arguments: inout [String]) -> [String] {
        var values: [String] = []
        while let index = arguments.firstIndex(of: option), index + 1 < arguments.count {
            values.append(arguments[index + 1])
            arguments.removeSubrange(index...index + 1)
        }
        return values
    }

    private static func flag(_ option: String, in arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: option) else { return false }
        arguments.remove(at: index)
        return true
    }
}
