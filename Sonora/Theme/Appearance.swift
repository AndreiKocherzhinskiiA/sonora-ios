import Observation
import SwiftUI
import UIKit

/// The nine palettes of the desktop `ui::ThemeKind`, with `system` following the device.
enum ThemeKind: String, CaseIterable, Identifiable {
    case system, dark, light, midnight, forest, ocean, rose, lavender, amber

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        case .midnight: "Midnight"
        case .forest: "Forest"
        case .ocean: "Ocean"
        case .rose: "Rose"
        case .lavender: "Lavender"
        case .amber: "Amber"
        }
    }

    /// The palette to draw with, given whether the device is currently in dark mode.
    func palette(systemIsDark: Bool) -> Palette {
        switch self {
        case .system: systemIsDark ? .dark : .light
        case .dark: .dark
        case .light: .light
        case .midnight: .midnight
        case .forest: .forest
        case .ocean: .ocean
        case .rose: .rose
        case .lavender: .lavender
        case .amber: .amber
        }
    }
}

/// One theme's colors, copied from the desktop `Theme::*()` constructors.
struct Palette {
    let isDark: Bool
    let background: UInt32
    let foreground: UInt32
    let secondary: UInt32
    let muted: UInt32
    let mutedForeground: UInt32
    let popover: UInt32
    let primary: UInt32
    let primaryForeground: UInt32
    let selection: UInt32
    let border: UIColor
    let hover: UIColor

    static let dark = Palette(
        isDark: true, background: 0x0a0a0a, foreground: 0xfafafa, secondary: 0x171717, muted: 0x262626,
        mutedForeground: 0x909090, popover: 0x141414, primary: 0xfafafa, primaryForeground: 0x171717,
        selection: 0x1d4ed8, border: UIColor(hex: 0x505050, alpha: 0.4), hover: UIColor(hex: 0x363636, alpha: 0.4))
    static let light = Palette(
        isDark: false, background: 0xfafafa, foreground: 0x171717, secondary: 0xf5f5f5, muted: 0xe5e5e5,
        mutedForeground: 0x606060, popover: 0xffffff, primary: 0x171717, primaryForeground: 0xfafafa,
        selection: 0x2563eb, border: UIColor(hex: 0x9b9b9b, alpha: 0.4), hover: UIColor(hex: 0xd5d5d5, alpha: 0.4))
    static let midnight = Palette(
        isDark: true, background: 0x07111f, foreground: 0xe6edf7, secondary: 0x102238, muted: 0x15283d,
        mutedForeground: 0x8296ad, popover: 0x0b1a2c, primary: 0x38bdf8, primaryForeground: 0x07111f,
        selection: 0x0284c7, border: UIColor(hex: 0x406892, alpha: 0.4), hover: UIColor(hex: 0x234770, alpha: 0.4))
    static let forest = Palette(
        isDark: true, background: 0x0b1410, foreground: 0xecf7ef, secondary: 0x16261d, muted: 0x203328,
        mutedForeground: 0x86a58f, popover: 0x101d16, primary: 0x86efac, primaryForeground: 0x0b1410,
        selection: 0x16a34a, border: UIColor(hex: 0x4e7a60, alpha: 0.4), hover: UIColor(hex: 0x304a3a, alpha: 0.4))
    static let ocean = Palette(
        isDark: true, background: 0x06171a, foreground: 0xe6edf7, secondary: 0x0f292d, muted: 0x17373b,
        mutedForeground: 0x7fa9ad, popover: 0x0a2024, primary: 0x5eead4, primaryForeground: 0x06171a,
        selection: 0x0d9488, border: UIColor(hex: 0x3f8086, alpha: 0.4), hover: UIColor(hex: 0x244f54, alpha: 0.4))
    static let rose = Palette(
        isDark: true, background: 0x180b10, foreground: 0xfafafa, secondary: 0x2b161e, muted: 0x3b2029,
        mutedForeground: 0xb58a98, popover: 0x211018, primary: 0xfda4af, primaryForeground: 0x180b10,
        selection: 0xe11d48, border: UIColor(hex: 0x984e67, alpha: 0.4), hover: UIColor(hex: 0x55303c, alpha: 0.4))
    static let lavender = Palette(
        isDark: true, background: 0x120e1c, foreground: 0xfafafa, secondary: 0x241c35, muted: 0x302745,
        mutedForeground: 0xa99bc2, popover: 0x191326, primary: 0xc4b5fd, primaryForeground: 0x120e1c,
        selection: 0x7c3aed, border: UIColor(hex: 0x7e66b2, alpha: 0.4), hover: UIColor(hex: 0x473a64, alpha: 0.4))
    static let amber = Palette(
        isDark: true, background: 0x171108, foreground: 0xfafafa, secondary: 0x291f11, muted: 0x382b18,
        mutedForeground: 0xad9878, popover: 0x20170c, primary: 0xfcd34d, primaryForeground: 0x171108,
        selection: 0xd97706, border: UIColor(hex: 0x94703c, alpha: 0.4), hover: UIColor(hex: 0x513f24, alpha: 0.4))
}

/// Corner rounding, `ui::Rounding`.
enum Rounding: String, CaseIterable, Identifiable {
    case square, subtle, rounded, round

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .square: "Square"
        case .subtle: "Subtle"
        case .rounded: "Rounded"
        case .round: "Round"
        }
    }

    var radius: CGFloat {
        switch self {
        case .square: 0
        case .subtle: 6
        case .rounded: 10
        case .round: 20
        }
    }
}

/// Animation speed, `ui::Pace`.
enum Pace: String, CaseIterable, Identifiable {
    case slow, base, quick

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .slow: "Slow"
        case .base: "Standard"
        case .quick: "Quick"
        }
    }

    var scale: Double {
        switch self {
        case .slow: 1.6
        case .base: 1
        case .quick: 0.6
        }
    }
}

/// The interface typeface. `inter` is the bundled default; the others are the system designs.
enum Typeface: String, CaseIterable, Identifiable {
    case inter, system, rounded, serif, monospaced

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .inter: "Default"
        case .system: "San Francisco"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        }
    }
}

/// Icon sets bundled from `assets/icons`; each has the same names.
enum IconPack: String, CaseIterable, Identifiable {
    case lucide, iconoir, remix, solar

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

/// Every look-and-feel setting, persisted in `UserDefaults`. Colors, radius, fonts and icons in
/// `Theme` read this, so a change re-renders any view that used one of them.
@Observable
final class Appearance {
    static let shared = Appearance()

    static let fontRange: ClosedRange<Double> = 12...20
    private static let defaultFontSize = 14.0

    var theme: ThemeKind
    var adaptive: Bool
    var iconPack: IconPack
    var blur: Bool
    var corners: Rounding
    var ambient: Bool
    var ambientMotion: Bool
    var fontSize: Double
    var typeface: Typeface
    var reduceMotion: Bool
    var pace: Pace

    /// Whether the device is in dark mode, fed by the root view so `System` can follow it.
    var systemIsDark = true
    /// Dominant color of the playing artwork, applied when `adaptive` is on.
    var tint: UIColor?

    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        theme = d.string(forKey: "appearance.theme").flatMap(ThemeKind.init) ?? .system
        adaptive = d.bool(forKey: "appearance.adaptive")
        iconPack = d.string(forKey: "appearance.iconPack").flatMap(IconPack.init) ?? .lucide
        blur = d.bool(forKey: "appearance.blur")
        corners = d.string(forKey: "appearance.corners").flatMap(Rounding.init) ?? .subtle
        ambient = d.object(forKey: "appearance.ambient") as? Bool ?? true
        ambientMotion = d.object(forKey: "appearance.ambientMotion") as? Bool ?? true
        let size = d.double(forKey: "appearance.fontSize")
        fontSize = size == 0 ? Self.defaultFontSize : min(max(size, Self.fontRange.lowerBound), Self.fontRange.upperBound)
        typeface = d.string(forKey: "appearance.typeface").flatMap(Typeface.init) ?? .inter
        reduceMotion = d.bool(forKey: "appearance.reduceMotion")
        pace = d.string(forKey: "appearance.pace").flatMap(Pace.init) ?? .base
    }

    var palette: Palette { theme.palette(systemIsDark: systemIsDark) }

    /// The scheme the interface is forced into, or `nil` to follow the device for `System`.
    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        default: palette.isDark ? .dark : .light
        }
    }

    /// Animation for state changes, respecting reduce-motion and the chosen pace.
    func animation(_ base: Double = 0.25) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: base * pace.scale)
    }

    /// Restores every setting to its default, the desktop "reset" behavior.
    func reset() {
        theme = .system
        adaptive = false
        iconPack = .lucide
        blur = false
        corners = .subtle
        ambient = true
        ambientMotion = true
        fontSize = Self.defaultFontSize
        typeface = .inter
        reduceMotion = false
        pace = .base
    }

    /// A comparable digest of every persisted setting, so a view can `onChange` it and call `persist`.
    var snapshot: [String] {
        [theme.rawValue, "\(adaptive)", iconPack.rawValue, "\(blur)", corners.rawValue, "\(ambient)",
         "\(ambientMotion)", "\(fontSize)", typeface.rawValue, "\(reduceMotion)", pace.rawValue]
    }

    /// Writes every setting to `UserDefaults`.
    func persist() {
        func save(_ value: Any, _ key: String) { defaults.set(value, forKey: "appearance.\(key)") }
        save(theme.rawValue, "theme")
        save(adaptive, "adaptive")
        save(iconPack.rawValue, "iconPack")
        save(blur, "blur")
        save(corners.rawValue, "corners")
        save(ambient, "ambient")
        save(ambientMotion, "ambientMotion")
        save(fontSize, "fontSize")
        save(typeface.rawValue, "typeface")
        save(reduceMotion, "reduceMotion")
        save(pace.rawValue, "pace")
    }
}
