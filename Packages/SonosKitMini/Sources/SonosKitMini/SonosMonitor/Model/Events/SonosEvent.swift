import Foundation

enum SonosServiceEvent: Sendable {
    case groupRenderingControl(SonosGroupRenderingEvent)
    case avTransport(SonosAVTransportEvent)
    case renderingContrl(SonosRenderingControlEvent)
    case position(SonosPosition)
    case progress(Date)
    case isPlaying(Bool)
    case deviceProperties(SonosDevicePropertiesEvent)
//    case zoneUpdates([ZoneGroup])
//    case zoneChange(String, String)
//    case removeFromGroups(String)
    
    var serviceId: String {
        switch self {
        case .groupRenderingControl:
            return "GroupRenderingControl"
        case .avTransport:
            return "AVTransport"
        case .renderingContrl:
            return "RenderingControl"
        case .position:
            return "Position"
        case .progress:
            return "Progress"
        default:
            return "\(self)"
        }
    }
}
