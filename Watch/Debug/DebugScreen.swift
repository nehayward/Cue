import SwiftUI
import SonosKit
import WatchConnectivity

struct DebugScreen: View {
    @State var sonosSearch = SonosSearch()
    @State var receiver = Receiver()

    var body: some View {
        Text(sonosSearch.lastKnownIP)
            .onAppear {
                sonosSearch.startBrowsing()
            }
            .onAppear {
                print(WCSession.default.applicationContext)
                print(WCSession.default.receivedApplicationContext)
            }
    }
}

class Receiver: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print(session)
        print(activationState)
    }
}
