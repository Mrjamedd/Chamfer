import AppKit
import SwiftUI

/// The design system's vocabulary. Nothing in `ChamferUI` hardcodes a colour,
/// a radius or a font size — if a value is worth using twice it belongs here.
public enum Chamfer {}

// MARK: - Colour

public extension Chamfer {
    enum Palette {
        /// Warm graphite and brass: the app is named after a machined edge, so
        /// the surfaces are metal-neutral and the one accent is a warm metal.
        public static let canvas = dynamic(light: 0xF6F5F3, dark: 0x171614)
        public static let surface = dynamic(light: 0xFFFFFF, dark: 0x1F1E1B)
        public static let sunken = dynamic(light: 0xEFEDE9, dark: 0x131211)
        public static let stroke = dynamic(light: 0xE2DED7, dark: 0x312F2B)

        public static let textPrimary = dynamic(light: 0x1C1A17, dark: 0xF2EFE9)
        public static let textSecondary = dynamic(light: 0x6B655C, dark: 0x9C948A)
        public static let textTertiary = dynamic(light: 0x968F84, dark: 0x6F6961)

        public static let accent = dynamic(light: 0xA9761F, dark: 0xD9A441)
        public static let accentSoft = dynamic(light: 0xF3E7CF, dark: 0x38301F)

        public static let positive = dynamic(light: 0x2F7D4F, dark: 0x5FBE86)
        public static let positiveSoft = dynamic(light: 0xE2F1E7, dark: 0x1B2B21)
        public static let warning = dynamic(light: 0xA9761F, dark: 0xE0AC4E)
        public static let danger = dynamic(light: 0xB03A2B, dark: 0xE0705C)
        public static let dangerSoft = dynamic(light: 0xF7E5E1, dark: 0x2E1D19)

        /// Builds a colour that resolves per appearance. Only `UInt32` values
        /// are captured, so the provider stays concurrency-safe.
        static func dynamic(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(rgb: isDark ? dark : light)
            })
        }
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Space, shape, motion

public extension Chamfer {
    enum Space {
        public static let hair: CGFloat = 2
        public static let tight: CGFloat = 4
        public static let snug: CGFloat = 8
        public static let regular: CGFloat = 12
        public static let roomy: CGFloat = 16
        public static let loose: CGFloat = 24
        public static let section: CGFloat = 32
    }

    enum Radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
        public static let large: CGFloat = 14
        public static let pill: CGFloat = 999
    }

    enum Motion {
        public static let quick = Animation.easeOut(duration: 0.14)
        public static let settle = Animation.spring(response: 0.34, dampingFraction: 0.86)
    }
}

// MARK: - Type

public extension Chamfer {
    /// Not named `Type` — `Chamfer.Type` would collide with metatype syntax.
    enum TypeScale {
        public static let display = Font.system(size: 22, weight: .semibold)
        public static let title = Font.system(size: 15, weight: .semibold)
        public static let body = Font.system(size: 13, weight: .regular)
        public static let bodyStrong = Font.system(size: 13, weight: .medium)
        public static let caption = Font.system(size: 11, weight: .regular)
        public static let captionStrong = Font.system(size: 11, weight: .semibold)
        public static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    }
}

// MARK: - Relative time

/// Formats against a supplied reference rather than the wall clock, so the
/// gallery renders identically on every launch.
public enum RelativeTime {
    public static func string(_ date: Date, since reference: Date) -> String {
        let seconds = Int(reference.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3_600) hr ago"
        case ..<604_800: return "\(seconds / 86_400) d ago"
        default: return "\(seconds / 604_800) wk ago"
        }
    }
}
