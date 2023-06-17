import Foundation
import Combine
import MusicSearchKit
import Observation
import SwiftUI

@Observable
public final class SonosService {
    public var speakers: [SonosSpeaker] = []
    private var sonosDeviceDiscoveryService = SonosDeviceDiscoveryService()
    private var subscriptions = Set<AnyCancellable>()
    private var sonosAPI = SonosAPI()
    public var server = HTTPServer()

    public var sonosDevices: [SonosDevice] = []
    public var groups: [Group] = []

    private var musicSearch = MusicSearchService()

    public init () {
        let ip = NetworkInfoService().getIPAddress()
        print(ip)

        server.handler = { ip, xml in

            let volume = XMLParserSonos().parseRendererControl(xml: xml)
            let index = self.sonosDevices.firstIndex { device in
                device.ipAddress == ip
            }
            if let index {

                withAnimation {
                    self.sonosDevices[index].volume = volume
                }


            }
            //                }

        }
        //        let knownSpeaker = [
        //            SonosSpeaker(ip: "192.168.4.49", name: "Gym"),
        //            SonosSpeaker(ip: "192.168.4.153", name: "Kitchen"),
        //            SonosSpeaker(ip: "192.168.4.154", name: "Kitchen"),
        //            SonosSpeaker(ip: "192.168.4.51", name: "Patio"),
        //            SonosSpeaker(ip: "192.168.4.50", name: "Garage"),
        //            SonosSpeaker(ip: "192.168.4.48", name: "Living Room"),
        //            SonosSpeaker(ip: "192.168.4.144", name: "Theater")
        //        ]
        //        speakers = knownSpeaker
        //        getVolume()
        
        //        $volume
        //            .receive(on: DispatchQueue.main)
        //            .dropFirst()
        //            .sink { value in
        //                print(value)
        //                self.setVolume(value: Int(value))
        //            }.store(in: &subscriptions)
        //        sonosDeviceDiscoveryService.$devices.assign(to: &$sonosDevices)
//        sonosDeviceDiscoveryService.$discoveredDevice.assign(to: &$discoveredDevice)
//       
    }


    public func load() async {
        let mappedRooms = await getRooms()
        sonosDevices = mappedRooms.map({ room in
            SonosDevice(name: room.zoneName, ipAddress: room.ip)
        })
    }


    public func getDevices() async -> [SonosDevice] {
        await sonosDeviceDiscoveryService.getDevices()
    }
    
    public func setDeviceVolume(ip: String, volume: Int) async {
        await sonosAPI.setVolume(ipAddress: ip, volume: volume)
    }

    public func setRelativeVolume(ip: String, volume: Int) async {
        await sonosAPI.setRelativeVolume(ipAddress: ip, volume: volume)
    }
    
    public func getTrack(ip: String) async -> Track? {
        await sonosAPI.getCurrentTrack(ipAddress: ip)
    }

    public func getArtwork(song: String, artist: String, album: String) async -> URL? {
        let searchResults = await musicSearch.search(song: song, artist: artist)
        let found = searchResults.first { result in
            result.artistName == artist &&
            result.trackName == song &&
            result.album.contains(album)
        }
        guard let artworkString = found?.artworkURL, let url = URL(string: artworkString) else { return nil }
        return url
    }


    public func pause(ip: String) async{
        await sonosAPI.pause(ipAddress: ip)
    }

    public func play(ip: String) async{
        await sonosAPI.play(ipAddress: ip)
    }

    public func getVolume(ip: String) async -> Double {
        await sonosAPI.getVolume(ipAddress: ip)
    }

    public func getPlaybackInfo(ip: String) async -> String {
        await sonosAPI.playbackInfo(ipAddress: ip)
    }

    public func playDevice(ip: String) {
//        await sonosAPI.getVolume(
    }
    
    public func getZones() async -> [ZoneGroup] {
        let devices = await sonosDeviceDiscoveryService.getDevices()
        let zones = await sonosAPI.getZones(ipAddress: devices.first!.ipAddress)
        return zones
    }

    public func queue(song: String, on device: SonosDevice) async {
        await sonosAPI.removeAllTrackFromQueue(IP: device.ipAddress)
        await sonosAPI.queue(song: song, IP: device.ipAddress)
    }


    /// This will listen and update the sonos volume
    /// - Returns: <#description#>
    public func monitorVolume() async -> [ZoneGroup] {
        let devices = await sonosDeviceDiscoveryService.getDevices()
        let zones = await sonosAPI.getZones(ipAddress: devices.first!.ipAddress)
        return zones
    }


    public func getRooms() async -> [Room] {
        let zones = await getZones()

        let mappedRooms = zones.flatMap { zoneGroup in
            zoneGroup.zoneGroupMembers.compactMap {
                 if !$0.invisible {
                     return Room(UUID: $0.UUID, location: $0.location, zoneName: $0.zoneName)
                 } else {
                     return nil
                 }
             }
         }

        return mappedRooms
    }
}



