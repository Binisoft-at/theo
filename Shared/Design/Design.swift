import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(watchOS)
import WatchKit
#endif

/// Theo's motion: a small set of springs, so everything that moves moves alike. Lines that
/// come and go, sections that open, chips that light up and panels that grow all use one of
/// these instead of a curve of their own.
enum Motion {
    /// Taps and toggles: a check, a chip, a fold chevron, a selected segment.
    static let tap: Animation = .snappy(duration: 0.24)
    /// A button or tile giving way under the finger, and coming back.
    static let press: Animation = .snappy(duration: 0.18)
    /// Lines that come, go or move in a list, and sections that open or close.
    static let list: Animation = .smooth(duration: 0.36)
    /// Panels, cards and banners that appear or change size.
    static let layout: Animation = .smooth(duration: 0.42)
    /// A small moment of joy: a task checked off, a day's goal reached.
    static let celebrate: Animation = .bouncy(duration: 0.42, extraBounce: 0.1)
    /// Hover and highlight on the Mac.
    static let hover: Animation = .easeOut(duration: 0.12)
    /// What stands in for movement when Reduce Motion is on: a short cross-fade.
    static let reduced: Animation = .easeInOut(duration: 0.18)

    /// Reduce Motion (Settings → Accessibility → Motion).
    @MainActor static var reduceMotion: Bool {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif os(watchOS)
        WKAccessibilityIsReduceMotionEnabled()
        #else
        false
        #endif
    }

    /// `animation`, or the short cross-fade when Reduce Motion is on.
    @MainActor static func resolved(_ animation: Animation) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// `withAnimation`, respecting Reduce Motion.
    @MainActor @discardableResult
    static func animate<Result>(_ animation: Animation = list, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(resolved(animation), body)
    }
}

/// Theo's colours for what things mean. The same meaning always gets the same colour, on every
/// page and device: Today is orange, Tomorrow and anything planned indigo, deadlines blue, Power
/// Hours teal, done green, deleting red, Off Plan grey.
enum Tint {
    static let today: Color = .orange
    static let tomorrow: Color = .indigo
    static let planned: Color = .indigo
    static let offPlan: Color = .gray
    static let deadline: Color = .blue
    /// A deadline that has passed. Calm, not alarming: it's ranked at the top anyway.
    static let overdue: Color = .orange
    static let powerHours: Color = .teal
    static let done: Color = .green
    static let delete: Color = .red
    static let move: Color = .brown
    static let priority: Color = .purple
    static let ongoing: Color = .teal
}

/// A tile, chip or card that gives way a little under the finger and springs back, like
/// Apple's own. Use it for custom tappable surfaces outside lists: never inside a `List` or
/// `Form` row, where a custom button style can make the whole row act as the button (use
/// `.plain` or `.borderless` there). Standard buttons keep their own styles.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// See `PressableStyle`.
    static var pressable: PressableStyle { PressableStyle() }
}

/// Small numbers that change (counts, Power Hours, percentages) roll to their new value instead
/// of jumping.
struct RollingNumber: ViewModifier {
    let value: Double

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(Motion.tap, value: value)
    }
}

extension View {
    /// See `RollingNumber`.
    func rollingNumber(_ value: Double) -> some View {
        modifier(RollingNumber(value: value))
    }

    /// See `RollingNumber`.
    func rollingNumber(_ value: Int) -> some View {
        modifier(RollingNumber(value: Double(value)))
    }
}
