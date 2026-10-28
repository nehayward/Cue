import SwiftUI
import SonosKit

/// The lossless / Dolby Atmos badge in the scrubber row, expanding to bit
/// depth and sample rate on a tap. Takes the quality itself so the local
/// player can show what this device is decoding the same way the Sonos
/// player shows what a speaker reported. Plain text on the backdrop, like
/// the times either side of it — no capsule behind it.
struct AudioInfoView: View {
    var quality: SonosTrackQuality?
    @State private var showDetails: Bool = false

    init(quality: SonosTrackQuality?) {
        self.quality = quality
    }

    init(group: GroupRoom) {
        self.quality = group.audioQuality
    }

    var body: some View {
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
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    // A caption is a small target: a little more either
                    // side, but none above, where the scrubber is (a 24 pt
                    // minimum height reached up into it and took the drag).
                    .padding(.horizontal, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
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
