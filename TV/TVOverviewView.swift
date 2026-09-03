import SonosKit
import SwiftUI
import CoreImage.CIFilterBuiltins

struct TVOverviewView: View {
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    let urlString = "https://cue.dance/help"
    
    @FocusState private var isDiscoverFocused: Bool

    var qrCodeImage: UIImage? {
        let data = Data(urlString.utf8)
        filter.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 20, y: 20) // Increase QR size
        if let outputImage = filter.outputImage?.transformed(by: transform),
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 32) {
            Text("Welcome to the Cue for Sonos")
                .font(.largeTitle)
                .bold()
                .multilineTextAlignment(.center)

            Text("To get started, ensure your Sonos system is online and connected to the same network.")
                .multilineTextAlignment(.center)
                .padding()

            if let qrImage = qrCodeImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(.white)
                    .cornerRadius(12)
                    .shadow(radius: 4)

                Text("Scan to learn more")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Text(urlString)
                .font(.footnote)
                .foregroundColor(.blue)
            
            Button {
                SonosService.shared.monitor()
            } label: {
                Label("Search for Sonos Devices", systemImage: "network")
            }
            .buttonBorderShape(.capsule)
            .focused($isDiscoverFocused)
        }
        .padding()
        .focusSection()
        .fontDesign(.rounded)
        .onAppear {
            isDiscoverFocused = true
        }
    }
}
