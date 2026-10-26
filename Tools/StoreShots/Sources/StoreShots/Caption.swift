import AppKit
import SwiftUI

/// A shot's headline and the line under it, in the theme's typeface
/// (SF Pro Rounded unless the theme says otherwise), wrapped so its lines
/// are about even and no word is left alone on the last.
struct Caption: View {
    let title: String
    let subtitle: String?
    let theme: Theme
    let titleSize: CGFloat
    /// The widest the caption may be.
    let width: CGFloat
    var alignment: TextAlignment = .center

    var subtitleSize: CGFloat { titleSize * 0.47 }

    var body: some View {
        let style = TypeStyle(theme)
        VStack(alignment: horizontal, spacing: titleSize * 0.3) {
            Text(Self.emphasised(title, accent: theme.accent?.color))
                .font(.system(size: titleSize, weight: style.titleWeight, design: style.design))
                .tracking(-titleSize * 0.012)
                .lineSpacing(-titleSize * 0.06)
                .foregroundStyle((theme.title ?? .white).color)
                .multilineTextAlignment(alignment)
                .frame(width: balancedWidth(title, font: style.font(size: titleSize, weight: style.titleNSWeight),
                                            tracking: -titleSize * 0.012))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: subtitleSize, weight: .medium, design: style.design))
                    .foregroundStyle((theme.subtitle ?? HexColor(red: 1, green: 1, blue: 1, alpha: 0.78)).color)
                    .multilineTextAlignment(alignment)
                    .lineSpacing(subtitleSize * 0.12)
                    .frame(width: balancedWidth(subtitle, font: style.font(size: subtitleSize, weight: .medium), tracking: 0))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(0.25), radius: titleSize * 0.18, y: titleSize * 0.04)
    }

    private var horizontal: HorizontalAlignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }

    /// The narrowest width that keeps as few lines as the full width needs.
    private func balancedWidth(_ text: String, font: NSFont, tracking: CGFloat) -> CGFloat {
        let plain = text.replacingOccurrences(of: "*", with: "")
        let attributed = NSAttributedString(string: plain, attributes: [.font: font, .kern: tracking])
        func lines(_ width: CGFloat) -> Int {
            let height = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            return Int((height / (font.ascender - font.descender + font.leading)).rounded())
        }
        let target = lines(width)
        guard target > 1 else { return width }
        var low = width * 0.4, high = width
        while high - low > 2 {
            let middle = (low + high) / 2
            if lines(middle) > target { low = middle } else { high = middle }
        }
        // A little slack: SwiftUI's line breaking measures a hair wider.
        return min(width, high * 1.03 + 4)
    }

    /// `*words*` in the accent colour.
    static func emphasised(_ text: String, accent: Color?) -> AttributedString {
        var result = AttributedString()
        for (index, part) in text.split(separator: "*", omittingEmptySubsequences: false).enumerated() {
            var piece = AttributedString(String(part))
            if index % 2 == 1, let accent { piece.foregroundColor = accent }
            result += piece
        }
        return result
    }
}

/// The theme's typeface, for SwiftUI and for measuring with AppKit.
struct TypeStyle {
    let design: Font.Design
    let titleWeight: Font.Weight
    let titleNSWeight: NSFont.Weight
    private let nsDesign: NSFontDescriptor.SystemDesign

    init(_ theme: Theme) {
        switch theme.design {
        case "default": (design, nsDesign) = (.default, .default)
        case "serif": (design, nsDesign) = (.serif, .serif)
        default: (design, nsDesign) = (.rounded, .rounded)
        }
        switch theme.titleWeight {
        case "heavy": (titleWeight, titleNSWeight) = (.heavy, .heavy)
        case "black": (titleWeight, titleNSWeight) = (.black, .black)
        case "semibold": (titleWeight, titleNSWeight) = (.semibold, .semibold)
        default: (titleWeight, titleNSWeight) = (.bold, .bold)
        }
    }

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(nsDesign) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}
