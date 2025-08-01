import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import SonosKit

enum TransferError: Error { case importFailed }

enum MultiTypeTransferable {
    case playable(PlayableContent)
    case url(URL)
}

extension MultiTypeTransferable: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        // String Representation
        DataRepresentation(contentType: .playableContent) { transferable in
            if case let .playable(playableContent) = transferable {
                return try JSONEncoder().encode(playableContent)
            }
            return Data()
        } importing: { data in
            guard let playableContent = try? JSONDecoder().decode(PlayableContent.self, from: data) else {
                throw TransferError.importFailed
            }
            return .playable(playableContent)
        }

        // UIImage Representation
        DataRepresentation(contentType: .url) { transferable in
            if case let .url(url) = transferable {
                return url.dataRepresentation
            }
            return Data()
        } importing: { data in
            guard let url = URL(string: String(decoding: data, as: UTF8.self)) else {
                throw TransferError.importFailed
            }
            return .url(url)
        }
    }
    
}
