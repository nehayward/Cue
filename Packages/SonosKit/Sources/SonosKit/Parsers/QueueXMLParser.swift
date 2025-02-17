//import Foundation
//
//// Your imports remain the same
//final class QueueXMLParser: NSObject, XMLParserDelegate {
//    var tracks: [PlayableContent] = []
//    private var currentElement = ""
//    private var currentTrack: [String: String] = [:]
//    private var currentText = ""
//    private var ip: String
//    private var preferredIPForTrackAlbumArt: String?
//    
//    init(ip: String, preferredIPForTrackAlbumArt: String?) {
//        self.ip = ip
//        self.preferredIPForTrackAlbumArt = preferredIPForTrackAlbumArt
//        super.init()
//    }
//    
//    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
//        currentElement = elementName
//        
//        if elementName == "item" {
//            currentTrack = [:]
//            if let id = attributeDict["id"] {
//                currentTrack["id"] = id
//            }
//        } else if elementName == "res" {
//            if let duration = attributeDict["duration"] {
//                currentTrack["duration"] = duration
//            }
//            if let protocolInfo = attributeDict["protocolInfo"] {
//                currentTrack["protocolInfo"] = protocolInfo
//            }
//        }
//        currentText = ""
//    }
//    
//    func parser(_ parser: XMLParser, foundCharacters string: String) {
//        currentText += string
//    }
//    
//    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
//        switch elementName {
//        case "dc:title":
//            currentTrack["title"] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
//        case "dc:creator":
//            currentTrack["artist"] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
//        case "upnp:album":
//            currentTrack["album"] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
//        case "upnp:class":
//            currentTrack["class"] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
//        case "res":
//            currentTrack["uri"] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
//        case "upnp:albumArtURI":
//            let artURI = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
//            let ip = preferredIPForTrackAlbumArt ?? self.ip
//            let artURL = URL(string: "http://\(ip):1400\(artURI.unescaped)")
//            currentTrack["albumArtURL"] = artURL?.absoluteString
//        case "item":
//            if let track = createPlayableContent() {
//                tracks.append(track)
//            }
//            currentTrack = [:]
//        default:
//            break
//        }
//    }
//    
//    private func createPlayableContent() -> PlayableContent? {
//        guard let title = currentTrack["title"],
//              let uri = currentTrack["uri"],
//              let type = currentTrack["class"],
//              let contentType = ContentType(type) else {
//            return nil
//        }
//        
//        let artist = currentTrack["artist"] ?? ""
//        let album = currentTrack["album"] ?? ""
//        let subtitle = [artist, album].filter { !$0.isEmpty }.joined(separator: " • ")
//        
//        var trackDuration = Duration.zero
//        if let durationString = currentTrack["duration"] {
//            let components = durationString.components(separatedBy: ":")
//            if components.count == 3,
//               let hours = Int(components[0]),
//               let minutes = Int(components[1]),
//               let seconds = Int(components[2]) {
//                let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
//                trackDuration = .milliseconds(totalMilliseconds)
//            }
//        }
//        
////    
////        let (musicService, trackID) = MusicServiceParser().parse(xml: bodyContent.unescaped, trackURI: trackURI)
////
////        let thumbnailURL = currentTrack["albumArtURL"].flatMap { URL(string: $0) }
////        
////        
////        let metadata = PlayableContentMetadata(
////            duration: trackDuration,
////            artist: artist,
////            album: album
////        )
////        
////        let mediaContent = MediaContent(
////            service: musicService,
////            id: trackID,
////            type: trackID.contains(
////                "i."
////            ) ? .libraryTrack : .track,,
////            location: nil
////        )
////        
////        return PlayableContent(
////            title: title,
////            subtitle: subtitle,
////            thumbnail: thumbnailURL,
////            artwork: thumbnailURL,
////            content: mediaContent,
////            metadata: metadata
////        )
//        
//        return nil
//    }
//}
