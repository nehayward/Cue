import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct NowPlayingWidgetView: View {
    var entry: NowPlayingProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            NowPlayingWidgetViewMedium(entry: entry)
        default:
            if let info = entry.info {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: UIImage(data: info.data!)!)
                        .resizable()
                    Label(info.room, systemImage: "hifispeaker.fill")
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                    
                }
                .overlay(alignment: .topLeading) {
                    Text(info.track)
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
                .fontDesign(.rounded)
                .containerBackground(.thickMaterial, for: .widget)
                
            } else {
                VStack {
                    Text("No Wifi")
                        .containerBackground(.fill.tertiary, for: .widget)
                }
            }
        }
    }
}

struct NowPlayingWidgetViewMedium: View {
    var entry: NowPlayingProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let info = entry.info,
           let data = entry.info?.data,
           let image = UIImage(data: data) {

            HStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                    .shadow(radius: 10)

                VStack(alignment: .leading) {
                    Label(info.room, systemImage: "hifispeaker.fill")
                    Text(info.track)
                    Text(info.artist)
                }
                .foregroundStyle(.thinMaterial)
                VStack {
                    Image(systemName: "play")
                    Image(systemName: "forward.end.fill")
                }
                .padding()
            }
            .fontDesign(.rounded)
            .containerBackground(Color(image.averageColor!).gradient, for: .widget)
        } else {
            VStack {
                Text("Nothing playing")
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
NowPlayingEntry(date: .now, configuration: .duaLipaInGarage,info: NowPlayingEntry.Info(data: UIImage.duaLipa.jpegData(compressionQuality: 1), room: "Kitchen", track: "Cry", artist: ""))
//    NowPlayingEntry(date: .now, configuration: .duaLipaInGarage, data: UIImage.barbie.jpegData(compressionQuality: 1), track: "Cry Your Heart Out")
}

extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
}
