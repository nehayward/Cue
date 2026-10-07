// Draws a QR code for a URL as an SVG, with Core Image (built into macOS), so
// the site needs no QR package. `make qr` runs it for site.testflight and
// writes public/testflight-qr.svg.
//
//   swift scripts/qr.swift <url> > out.svg
//
// The URL also goes in the SVG's <desc>, which the tests check against
// config.js so a changed link can't ship with an old code.

import CoreImage
import Foundation

guard CommandLine.arguments.count == 2 else {
	FileHandle.standardError.write("usage: swift scripts/qr.swift <url>\n".data(using: .utf8)!)
	exit(1)
}
let url = CommandLine.arguments[1]

let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(url.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let image = filter.outputImage!
let size = Int(image.extent.width)

// One pixel per module, read back as greyscale.
var pixels = [UInt8](repeating: 255, count: size * size)
let context = CIContext()
context.render(image, toBitmap: &pixels, rowBytes: size, bounds: image.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
let dark = { (x: Int, y: Int) in pixels[y * size + x] < 128 }

// Crop to the code itself, then give it a quiet zone of its own.
let modules = (0..<size).flatMap { y in (0..<size).map { x in (x, y) } }.filter(dark)
let minX = modules.map(\.0).min()!, maxX = modules.map(\.0).max()!
let minY = modules.map(\.1).min()!, maxY = modules.map(\.1).max()!
let quiet = 3
let side = (maxX - minX + 1) + 2 * quiet

// Runs of dark modules along each row, as one path.
var path = ""
for y in minY...maxY {
	var x = minX
	while x <= maxX {
		guard dark(x, y) else { x += 1; continue }
		let start = x
		while x <= maxX, dark(x, y) { x += 1 }
		path += "M\(start - minX + quiet) \(y - minY + quiet)h\(x - start)v1h-\(x - start)z"
	}
}

print("""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(side) \(side)" shape-rendering="crispEdges">\
<desc>\(url)</desc>\
<rect width="\(side)" height="\(side)" fill="#fff"/>\
<path fill="#07090a" d="\(path)"/>\
</svg>
""")
