import Foundation

public enum SMAPIAction {
    case rateItem(id: String, rating: Int)
    case getExtendedMetadata(id: String)

    public var soapAction: String {
        switch self {
        case .rateItem: "rateItem"
        case .getExtendedMetadata: "getExtendedMetadata"
        }
    }

    var bodyXML: String {
        let ns = "http://www.sonos.com/Services/1.1"
        switch self {
        case let .rateItem(id, rating):
            return "<rateItem xmlns=\"\(ns)\"><id>\(id)</id><rating>\(rating)</rating></rateItem>"
        case let .getExtendedMetadata(id):
            return "<getExtendedMetadata xmlns=\"\(ns)\"><id>\(id)</id></getExtendedMetadata>"
        }
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
        let header = """
        <Header>\
        <credentials xmlns="http://www.sonos.com/Services/1.1">\
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
