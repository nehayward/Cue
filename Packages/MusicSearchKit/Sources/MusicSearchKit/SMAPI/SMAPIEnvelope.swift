import Foundation

public enum SMAPIAction {
    case rateItem(id: String, rating: Int)
    case getExtendedMetadata(id: String)
    /// Search within a search category. `id` is the search-category id returned
    /// by browsing the service's "search" container; `term` is the user query.
    case search(id: String, term: String, index: Int, count: Int)
    /// Exchanges an expired loginToken for a fresh authToken/privateKey pair.
    case refreshAuthToken

    public var soapAction: String {
        switch self {
        case .rateItem: "rateItem"
        case .getExtendedMetadata: "getExtendedMetadata"
        case .search: "search"
        case .refreshAuthToken: "refreshAuthToken"
        }
    }

    var bodyXML: String {
        let ns = "http://www.sonos.com/Services/1.1"
        switch self {
        case let .rateItem(id, rating):
            return "<rateItem xmlns=\"\(ns)\"><id>\(id)</id><rating>\(rating)</rating></rateItem>"
        case let .getExtendedMetadata(id):
            return "<getExtendedMetadata xmlns=\"\(ns)\"><id>\(id)</id></getExtendedMetadata>"
        case let .search(id, term, index, count):
            return "<search xmlns=\"\(ns)\"><id>\(id.xmlEscaped)</id><term>\(term.xmlEscaped)</term><index>\(index)</index><count>\(count)</count></search>"
        case .refreshAuthToken:
            return "<refreshAuthToken xmlns=\"\(ns)\"></refreshAuthToken>"
        }
    }
}

private extension String {
    /// Minimal XML entity escaping for SMAPI request bodies.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public struct SMAPIEnvelope {
    public let credentials: SMAPICredentials
    public let action: SMAPIAction

    public init(credentials: SMAPICredentials, action: SMAPIAction) {
        self.credentials = credentials
        self.action = action
    }

    public var xml: String {
        let ns = "http://www.sonos.com/Services/1.1"
        // Sonos-operated services (Sonos Radio) require the controller deviceId
        // + deviceProvider ahead of the loginToken, matching the official
        // controller. Services that don't supply a deviceId (e.g. Deezer) send
        // just the loginToken, exactly as before.
        let deviceTag = credentials.deviceId.map {
            "<deviceId>\($0)</deviceId><deviceProvider>Sonos</deviceProvider>"
        } ?? ""
        let header = """
        <Header>\
        <credentials xmlns="\(ns)">\
        \(deviceTag)\
        <loginToken>\
        <token>\(credentials.token)</token>\
        <key>\(credentials.key)</key>\
        <householdId>\(credentials.householdId)</householdId>\
        </loginToken>\
        </credentials>\
        </Header>
        """
        return """
        <Envelope \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
        xmlns:xsd="http://www.w3.org/2001/XMLSchema" \
        xmlns="http://schemas.xmlsoap.org/soap/envelope/">\
        \(header)\
        <Body>\(action.bodyXML)</Body>\
        </Envelope>
        """
    }
}
