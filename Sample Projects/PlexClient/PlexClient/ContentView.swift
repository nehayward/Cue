import SwiftUI
import AVFoundation

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Button {
                Task {
                    try? await setupAudioSession()
                    await playAudio(from: URL(string: "http://192.168.4.252:32400/library/parts/4360/1714748324/file.mp3")!)
                }
            } label: {
                Text("Play")
            }
        }
        .padding()
    }

    func setupAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [])
        try audioSession.setActive(true)
    }

    func playAudio(from url: URL) async {
        let headers: [String: String] =
        ["X-Plex-Token": "3zy3EmAvq8dmHdhfCd9z"]

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])

        let item = AVPlayerItem(asset: asset)
        print(item.duration)
        let player = AVPlayer(playerItem: item)
        player.play()

        // Wait until playback finishes
        await withCheckedContinuation { continuation in
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                print("Playback finished")
                continuation.resume()
            }
        }
    }
}

#Preview {
    ContentView()
}
