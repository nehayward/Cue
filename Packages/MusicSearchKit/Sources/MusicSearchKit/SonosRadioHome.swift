import Foundation

/// A curated section ("swimlane") on Sonos Radio's home browse page — e.g.
/// "Trending Now", "Summertime", "The Beautiful Game" — fetched from the
/// browse REST endpoint the official controller uses.
public struct SonosRadioHomeSection: Sendable {
    /// The section's browse object id (a path like "/stations/en-US/US/…"),
    /// browsable for the section's full station list.
    public let id: String
    public let title: String
    /// Layout hint from the service ("swimlane", "list", …).
    public let displayType: String?
    public let items: [SonosRadioHomeItem]
}

/// A station (or sub-container) inside a home section.
public struct SonosRadioHomeItem: Sendable {
    /// Playable object id, e.g. "sonos:2997".
    public let id: String
    public let title: String
    /// Tagline shown under the title, e.g. "Today's Hottest Hits".
    public let subtitle: String?
    public let imageURL: URL?
    public let canPlay: Bool
    public let canEnumerate: Bool
}

// MARK: - Wire format

/// Raw JSON envelope of `GET /browse/v1[…]`. The root response carries its
/// sections in `views`; a section browse may carry stations in `items` or a
/// nested `views` — both are handled.
struct SonosRadioBrowseResponse: Decodable {
    let total: Int?
    let views: [Node]?
    let items: [Node]?

    struct Node: Decodable {
        let id: ObjectID?
        let displayType: String?
        let content: Content?
        let browsePolicies: BrowsePolicies?
        let items: [Node]?
    }

    struct ObjectID: Decodable {
        let objectId: String?
    }

    struct Content: Decodable {
        let container: Container?
    }

    struct Container: Decodable {
        let name: String?
        let type: String?
        let id: ObjectID?
        let imageUrl: String?
        let summary: String?
        let artist: Artist?
    }

    struct Artist: Decodable {
        let name: String?
    }

    struct BrowsePolicies: Decodable {
        let canPlay: Bool?
        let canEnumerate: Bool?
    }
}

extension SonosRadioBrowseResponse {
    /// The root response's sections, in service order.
    var sections: [SonosRadioHomeSection] {
        (views ?? []).compactMap(\.asSection)
    }

    /// Every item in the response regardless of nesting, for section browses.
    var flattenedItems: [SonosRadioHomeItem] {
        var nodes = items ?? []
        for view in views ?? [] {
            nodes.append(contentsOf: view.items ?? [])
        }
        return nodes.compactMap(\.asItem)
    }
}

extension SonosRadioBrowseResponse.Node {
    var asSection: SonosRadioHomeSection? {
        guard let id = id?.objectId ?? content?.container?.id?.objectId,
              let title = content?.container?.name, !title.isEmpty else {
            return nil
        }
        return SonosRadioHomeSection(
            id: id,
            title: title,
            displayType: displayType,
            items: (items ?? []).compactMap(\.asItem)
        )
    }

    var asItem: SonosRadioHomeItem? {
        guard let id = id?.objectId ?? content?.container?.id?.objectId,
              let title = content?.container?.name, !title.isEmpty else {
            return nil
        }
        let container = content?.container
        let subtitle = [container?.artist?.name, container?.summary]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        return SonosRadioHomeItem(
            id: id,
            title: title,
            subtitle: subtitle,
            imageURL: container?.imageUrl.flatMap { URL(string: $0) },
            canPlay: browsePolicies?.canPlay ?? false,
            canEnumerate: browsePolicies?.canEnumerate ?? false
        )
    }
}
