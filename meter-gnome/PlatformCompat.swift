//
//  PlatformCompat.swift
//  meter-gnome
//
//  Cross-platform shims so the single multiplatform target builds for both
//  iOS and macOS. Several SwiftUI modifiers the views rely on are iOS-only
//  (inline nav-bar title, sheet detents, autocapitalization, the
//  `.navigationBar` toolbar placement). They're wrapped here once and become
//  no-ops — or the macOS equivalent — on macOS, so the call sites stay free
//  of `#if` clutter and read the same on both platforms.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
/// The platform image type — `UIImage` on iOS, `NSImage` on macOS.
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Placement for a primary bottom action: the bottom bar on iOS, the
/// automatic (window-toolbar) slot on macOS, which has no bottom bar.
#if os(iOS)
let compatBottomBarPlacement: ToolbarItemPlacement = .bottomBar
#else
let compatBottomBarPlacement: ToolbarItemPlacement = .automatic
#endif

extension View {
    /// Inline navigation-bar title on iOS. No-op on macOS, which has no
    /// large/inline title distinction.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Word-capitalizing text input on iOS. No-op on macOS, where the
    /// hardware keyboard owns capitalization.
    @ViewBuilder
    func wordsAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    /// Large sheet detent on iOS. No-op on macOS, where sheets are
    /// fixed-size windows and detents don't apply.
    @ViewBuilder
    func compatDetentsLarge() -> some View {
        #if os(iOS)
        presentationDetents([.large])
        #else
        self
        #endif
    }

    /// Medium + large sheet detents on iOS. No-op on macOS.
    @ViewBuilder
    func compatDetentsMediumLarge() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
        #else
        self
        #endif
    }

    /// Opaque, visible toolbar background tinted to the app's base color.
    /// Targets the navigation bar on iOS and the window toolbar on macOS.
    @ViewBuilder
    func compatBarBackground(_ color: Color) -> some View {
        #if os(iOS)
        toolbarBackground(color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        toolbarBackground(color, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        #endif
    }
}
