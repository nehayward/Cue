import SwiftUI
import SonosKit

struct AudioInfoView: View {
    @Environment(SonosService.self) var sonosService
    @State private var showDetails: Bool = false

    var body: some View {
        let quality = sonosService.songAudioInfo
        let supportsDetails = (quality?.lossless ?? false) || (quality?.immersive ?? false)

        // Create a string like "24-bit • 48kHz" or just "48kHz"
        let qualityString = [quality?.bitDepth.map { "\($0)-bit" }, quality?.sampleRateFormatted]
            .compactMap { $0 }
            .joined(separator: " • ")

        ZStack {
            if supportsDetails {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    showDetails.toggle()
                } label: {
                    ZStack {
                        HStack(spacing: 2) {
                            if quality?.lossless ?? false {
                                Image("lossless", bundle: .musicSearchKitBundle)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                    .opacity(showDetails ? 1 : 0)
                            } else if quality?.immersive ?? false {
                                Image("dolby", bundle: .musicSearchKitBundle)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit) 
                                    .frame(height: 10)
                                    .opacity(showDetails ? 1 : 0)
                            }
                            Text(qualityString)
                                .padding(.horizontal, showDetails ? 0 : 4)
                                .opacity(showDetails ? 1 : 0)
                        }

                        // Dolby Atmos
                        HStack(spacing: 6) {
                            Image("dolbyAtmosHorizontal", bundle: .musicSearchKitBundle)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 12)
                        }
                        .opacity((quality?.immersive ?? false && !showDetails) ? 1 : 0)

                        // Lossless
                        HStack(spacing: 6) {
                            Image("lossless", bundle: .musicSearchKitBundle)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text("Lossless")
                        }
                        .opacity((quality?.lossless ?? false && !showDetails) ? 1 : 0)
                    }
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .glassForegroundAudio()
            } else {
                Text(qualityString)
                    .padding(.horizontal, 4)
                    .opacity(qualityString.isEmpty ? 0 : 1)
            }
        }
        .opacity(quality == nil ? 0 : 1)
        .foregroundStyle(.primary.opacity(0.8))
    }
}
