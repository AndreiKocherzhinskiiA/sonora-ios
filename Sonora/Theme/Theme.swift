import SwiftUI
import UIKit

/// Design tokens mirrored from the desktop `ui::Theme` and `ui::Metrics`. Colors, radius and the
/// type scale come from `Appearance.shared`, so views that read them refresh when a setting changes.
enum Theme {
    private static var look: Appearance { .shared }
    private static var palette: Palette { look.palette }

    /// The page background, nudged toward the playing artwork when the adaptive theme is on.
    static var background: Color {
        let base = UIColor(hex: palette.background)
        guard look.adaptive, let tint = look.tint else { return Color(base) }
        return Color(base.mixed(with: tint, amount: 0.16))
    }
    static var foreground: Color { Color(UIColor(hex: palette.foreground)) }
    static var secondary: Color { Color(UIColor(hex: palette.secondary)) }
    static var muted: Color { Color(UIColor(hex: palette.muted)) }
    static var mutedForeground: Color { Color(UIColor(hex: palette.mutedForeground)) }
    static var popover: Color { Color(UIColor(hex: palette.popover)) }
    static var primary: Color { Color(UIColor(hex: palette.primary)) }
    static var primaryForeground: Color { Color(UIColor(hex: palette.primaryForeground)) }
    static var selection: Color { Color(UIColor(hex: palette.selection)) }
    static var danger: Color { Color(UIColor(hex: palette.isDark ? 0xef4444 : 0xb91c1c)) }
    static var border: Color { Color(palette.border) }
    static var hover: Color { Color(palette.hover) }

    /// Corner radius from the chosen `Rounding`.
    static var radius: CGFloat { look.corners.radius }
    /// Gutter around page content, `Metrics::inset` scaled down for a phone.
    static let inset: CGFloat = 20
    static var listRow: CGFloat { max(56, (look.fontSize * 4).rounded()) }
    static let thumb: CGFloat = 40
    static let control: CGFloat = 36
    static let tabBar: CGFloat = 52
    static let playerBar: CGFloat = 64
    static let hairline: CGFloat = 1
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    /// This color blended toward `other` by `amount` (0 keeps this color, 1 becomes `other`).
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: a1
        )
    }
}

/// Inter faces bundled from `assets/fonts`, the same files the desktop app embeds.
enum InterWeight {
    case regular, medium, semibold, bold

    var face: String {
        switch self {
        case .regular: "Inter-Regular"
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold: "Inter-Bold"
        }
    }

    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Type scale from `ui::metrics::Text`, applied to the chosen base font size and typeface.
extension Font {
    private static var base: CGFloat { CGFloat(Appearance.shared.fontSize) }

    static func inter(_ size: CGFloat, _ weight: InterWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        switch Appearance.shared.typeface {
        case .inter: .custom(weight.face, size: size, relativeTo: style)
        case .system: .system(size: size, weight: weight.system, design: .default)
        case .rounded: .system(size: size, weight: weight.system, design: .rounded)
        case .serif: .system(size: size, weight: weight.system, design: .serif)
        case .monospaced: .system(size: size, weight: weight.system, design: .monospaced)
        }
    }

    static var tiny: Font { .inter(base * 0.77, .medium, relativeTo: .caption2) }
    static var small: Font { .inter(base * 0.85, .regular, relativeTo: .caption) }
    static var label: Font { .inter(base * 0.92, .medium, relativeTo: .footnote) }
    static var bodyText: Font { .inter(base, .regular) }
    static var bodyStrong: Font { .inter(base, .medium) }
    static var largeText: Font { .inter(base * 1.38, .semibold, relativeTo: .title3) }
    static var titleText: Font { .inter(base * 1.69, .bold, relativeTo: .title2) }
    static var displayText: Font { .inter(base * 2.15, .bold, relativeTo: .title) }
}

/// An icon from the active pack, tinted by `foregroundStyle` like the desktop `icons::path`.
/// A name the pack lacks falls back to Lucide.
struct Icon: View {
    let name: String
    let size: CGFloat

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var image: Image {
        #if SWIFT_PACKAGE
        // xtool builds cannot compile asset catalogs, so the packs ship as @3x PNGs instead.
        let pack = Appearance.shared.iconPack.rawValue
        for folder in [pack, "lucide"] {
            if let path = Bundle.module.path(forResource: name, ofType: "png", inDirectory: "Icons/\(folder)"),
               let icon = UIImage(contentsOfFile: path),
               let scaled = icon.cgImage.map({ UIImage(cgImage: $0, scale: 3, orientation: .up) }) {
                return Image(uiImage: scaled)
            }
        }
        return Image(systemName: "questionmark")
        #else
        let pack = "Icons/\(Appearance.shared.iconPack.rawValue)/\(name)"
        return Image(UIImage(named: pack) != nil ? pack : "Icons/lucide/\(name)")
        #endif
    }
}

/// Small uppercase section label, the desktop `eyebrow`.
struct Eyebrow: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.tiny)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.mutedForeground)
    }
}

/// Flat icon button with the desktop ghost look: no chrome until pressed.
struct GhostButtonStyle: ButtonStyle {
    var size: CGFloat = Theme.control

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.hover : .clear)
            )
            .contentShape(Rectangle())
    }
}

/// Solid button, the desktop `primary` variant.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyStrong)
            .foregroundStyle(Theme.primaryForeground)
            .padding(.horizontal, 16)
            .frame(height: Theme.control)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.primary.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

/// Outlined button, the desktop `secondary` variant.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyStrong)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 16)
            .frame(height: Theme.control)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.hover : Theme.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            )
    }
}

/// One-pixel divider in the theme border color.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.hairline)
    }
}

/// Centered empty state with an icon, a title, a message and optional actions, the desktop `Vacancy`.
struct Vacancy<Actions: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let actions: Actions

    init(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Icon(icon, size: 28).foregroundStyle(Theme.mutedForeground)
            Text(title).font(.largeText).foregroundStyle(Theme.foreground)
            if let message {
                Text(message)
                    .font(.bodyText)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            actions.padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Vacancy where Actions == EmptyView {
    init(icon: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

/// Page scaffold: title header with an optional trailing control, then scrolling content.
/// Replaces the stock large navigation title with the desktop page header.
struct Page<Trailing: View, Content: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing
    let content: Content

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.titleText).foregroundStyle(Theme.foreground)
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 12)
            .padding(.bottom, 12)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension Page where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(title, trailing: { EmptyView() }, content: content)
    }
}
