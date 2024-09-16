import WidgetKit

struct SceneEntry: TimelineEntry {
    var date: Date
    let configuration: SceneWidgetConfigurationIntent
    let info: Info?

    struct Info {
        let room: SonosDeviceEntity
        let data: Data?
        let track: String
        let artist: String
    }
}
