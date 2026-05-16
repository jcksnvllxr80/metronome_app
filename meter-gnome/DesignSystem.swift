//
//  DesignSystem.swift
//  meter-gnome
//
//  Swift constants for the tokens defined in DESIGN.md. First pass —
//  asset-catalog Color sets are a follow-up so light-mode variants work
//  out of the box. Until then, these hex values are dark-mode only.
//

import SwiftUI

enum DS {
    enum DSColor {
        static let bgBase      = Color(red: 0x0A/255, green: 0x0B/255, blue: 0x0E/255)
        static let bgElevated  = Color(red: 0x15/255, green: 0x17/255, blue: 0x1C/255)
        static let bgRecessed  = Color(red: 0x06/255, green: 0x07/255, blue: 0x0A/255)
        static let textPrimary = Color(red: 0xF4/255, green: 0xEF/255, blue: 0xE6/255)
        static let textMuted   = Color(red: 0x7A/255, green: 0x7F/255, blue: 0x8A/255)
        static let textDim     = Color(red: 0x3D/255, green: 0x42/255, blue: 0x4B/255)
        static let accentTempo = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x2C/255)
        static let semanticOk  = Color(red: 0x67/255, green: 0xD3/255, blue: 0x91/255)
        static let semanticWarn = Color(red: 0xFF/255, green: 0xB2/255, blue: 0x3F/255)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    /// Typography. Numeric / mono surfaces use JetBrains Mono (bundled .ttf,
    /// registered via Info.plist UIAppFonts). Body + UI fall back to SF Pro
    /// per DESIGN.md.
    enum Font {
        static let bpmHero    = SwiftUI.Font.custom("JetBrainsMono-Bold",    size: 180)
        static let bpmNormal  = SwiftUI.Font.custom("JetBrainsMono-Bold",    size: 96)
        static let display    = SwiftUI.Font.custom("JetBrainsMono-Medium",  size: 32)
        static let headline   = SwiftUI.Font.system(size: 22,  weight: .semibold)
        static let body       = SwiftUI.Font.system(size: 17,  weight: .regular)
        static let label      = SwiftUI.Font.system(size: 13,  weight: .medium)
        static let monoData   = SwiftUI.Font.custom("JetBrainsMono-Regular", size: 13)
    }
}
