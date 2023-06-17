import Foundation
import Combine
import RegexBuilder
import SWXMLHash

public final class SonosSpeaker: ObservableObject, Identifiable, Equatable {
    public static func == (lhs: SonosSpeaker, rhs: SonosSpeaker) -> Bool {
        lhs.ip == rhs.ip
    }

    public var id: String { ip }

    @Published public var volume: Double = 0
    @Published public var name: String = ""

    private var sonosAPI = SonosAPI()
    private var subscriptions = Set<AnyCancellable>()
    public let ip: String

    init(ip: String, name: String = "", deviceIP: String) {
        self.name = name
        self.ip = ip
        getVolume()
        getInfo()

//        sonosAPI.subscribe(ip: ip, deviceIP: deviceIP)

//        $volume
//            .receive(on: DispatchQueue.main)
//            .dropFirst()
//            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
//            .sink { value in
//                print(value)
//                self.setVolume(value: Int(value))
//            }.store(in: &subscriptions)
    }

    
    func getVolume() {
        guard let URL = URL(string: "http://\(ip):1400/MediaRenderer/RenderingControl/Control") else {return}
        var request = URLRequest(url: URL)
        request.httpMethod = "POST"
        request.addValue("urn:schemas-upnp-org:service:RenderingControl:1#GetVolume", forHTTPHeaderField: "Soapaction")
        request.addValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")

        let bodyString = "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:GetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><InstanceID>0</InstanceID><Channel>Master</Channel></u:GetVolume></s:Body></s:Envelope>"
        request.httpBody = bodyString.data(using: .utf8, allowLossyConversion: true)

        URLSession.shared
            .dataTaskPublisher(for: request)
            .sink { completion in
                print(completion)
            } receiveValue: { (data, response) in
                guard let soapResponse = String(data: data, encoding: .utf8) else { return }
//                        let pattern = #"<CurrentVolume>(.*?)<\/CurrentVolume>"#
                let volume = Reference(Int.self)

                let currentVolumeSearch = Regex {
                    "<CurrentVolume>"
                    TryCapture(as: volume) {
                        OneOrMore(.digit)
                    } transform: { match in
                        Int(match)
                    }
                    "</CurrentVolume>"
                  }
                  .anchorsMatchLineEndings()

                if let result = soapResponse.firstMatch(of: currentVolumeSearch) {
                    print("Volume: \(result[volume])")
                    DispatchQueue.main.async {
                        self.volume = Double(result[volume])
                    }
                }
            }.store(in: &subscriptions)

//        Timer
//            .publish(every: 1, on: .main, in: .common)
//            .autoconnect()
//            .sink { value    in
//                URLSession.shared
//                    .dataTaskPublisher(for: request)
//                    .sink { completion in
//                        print(completion)
//                    } receiveValue: { (data, response) in
//                        print(String(data: data, encoding: .utf8))
//                        guard let soapResponse = String(data: data, encoding: .utf8) else { return }
////                        let pattern = #"<CurrentVolume>(.*?)<\/CurrentVolume>"#
//                        let volume = Reference(Int.self)
//
//                        let currentVolumeSearch = Regex {
//                            "<CurrentVolume>"
//                            TryCapture(as: volume) {
//                                OneOrMore(.digit)
//                            } transform: { match in
//                                Int(match)
//                            }
//                            "</CurrentVolume>"
//                          }
//                          .anchorsMatchLineEndings()
//
//                        if let result = soapResponse.firstMatch(of: currentVolumeSearch) {
//                            print("Volume: \(result[volume])")
//                        }
//
//                    }.store(in: &self.subscriptions)
//            }.store(in: &subscriptions)

    }

    func setVolume(value: Int) {
        guard let URL = URL(string: "http://\(ip):1400/MediaRenderer/RenderingControl/Control") else {return}
        var request = URLRequest(url: URL)
        request.httpMethod = "POST"
        request.addValue("\(ip):1400", forHTTPHeaderField: "Host")
        request.addValue("urn:schemas-upnp-org:service:RenderingControl:1#SetVolume", forHTTPHeaderField: "Soapaction")
        request.addValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")

        let bodyString = #"<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>\#(value)</DesiredVolume></u:SetVolume></s:Body></s:Envelope>"#
        request.httpBody = bodyString.data(using: .nonLossyASCII)

        URLSession.shared
            .dataTaskPublisher(for: request)
            .sink { completion in
                print(completion)
            } receiveValue: { (data, response) in
                print(String(data: data, encoding: .utf8))
            }.store(in: &subscriptions)
    }

    func getInfo() {
        guard let URL = URL(string: "http://\(ip):1400/xml/device_description.xml") else {return}
        var request = URLRequest(url: URL)
        request.httpMethod = "GET"

        URLSession.shared
            .dataTaskPublisher(for: request)
            .sink { completion in
                print(completion)
            } receiveValue: { (data, response) in
                guard let soapResponse = String(data: data, encoding: .utf8) else { return }
                print(soapResponse)

                let xml = XMLHash.parse(soapResponse)
                print(xml)

                //                        let pattern = #"<CurrentVolume>(.*?)<\/CurrentVolume>"#
//                let volume = Reference(Int.self)
//
//                let currentVolumeSearch = Regex {
//                    "<CurrentVolume>"
//                    TryCapture(as: volume) {
//                        OneOrMore(.digit)
//                    } transform: { match in
//                        Int(match)
//                    }
//                    "</CurrentVolume>"
//                }
//                    .anchorsMatchLineEndings()
//
//                if let result = soapResponse.firstMatch(of: currentVolumeSearch) {
//                    print("Volume: \(result[volume])")
//                    self.volume = Double(result[volume])
//                }
            }.store(in: &subscriptions)
    }
}



