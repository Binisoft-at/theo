import SwiftUI
import TheoCore

extension Priority {
    var color: Color {
        switch self {
        case .normal: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}

enum TheoColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .graphite: .gray
        }
    }

    var title: String { rawValue.capitalized }

    /// Stable color for a tag name so the same tag always looks the same on every device.
    static func forTag(_ tag: String) -> TheoColor {
        let palette: [TheoColor] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .mint, .brown, .cyan]
        var hash: UInt64 = 5381
        for byte in tag.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

/// Accent colors offered in Settings. Yellow is the Apple Notes look.
enum AccentChoice: String, CaseIterable, Identifiable {
    case notes, orange, blue, indigo, green, pink, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Notes Yellow"
        case .orange: "Orange"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .green: "Green"
        case .pink: "Pink"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .notes: Color(red: 0.89, green: 0.68, blue: 0.13)
        case .orange: .orange
        case .blue: .blue
        case .indigo: .indigo
        case .green: .green
        case .pink: .pink
        case .graphite: .gray
        }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CompletedMode: String, CaseIterable, Identifiable {
    case bottom, hide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: "Move to Bottom"
        case .hide: "Hide"
        }
    }
}

enum NewTaskPlacement: String, CaseIterable, Identifiable {
    case bottom, top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: "Bottom of Section"
        case .top: "Top of Section"
        }
    }
}

enum TodayGrouping: String, CaseIterable, Identifiable {
    case groups, priority, deadline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groups: "Groups"
        case .priority: "Priority"
        case .deadline: "Deadline"
        }
    }

    var symbol: String {
        switch self {
        case .groups: "rectangle.grid.1x2"
        case .priority: "exclamationmark.3"
        case .deadline: "calendar"
        }
    }
}

/// UserDefaults keys shared between views.
enum Prefs {
    static let appearance = "appearance"
    static let accent = "accent"
    static let dayStartHour = "dayStartHour"
    static let showAge = "showAge"
    static let completedMode = "completedMode"
    static let newTaskPlacement = "newTaskPlacement"
    static let quickEntryCollapsed = "quickEntryCollapsed"
    static let todayGrouping = "todayGrouping"
    static let showNotesPreview = "showNotesPreview"
}

/// Curated SF Symbols for groups.
enum GroupSymbols {
    static let all: [String] = [
        "list.bullet", "tray.full", "briefcase", "house", "cart", "person", "person.2",
        "heart", "star", "flag", "bolt", "lightbulb", "hammer", "wrench.and.screwdriver",
        "laptopcomputer", "iphone", "book", "graduationcap", "pencil", "doc.text",
        "folder", "calendar", "clock", "phone", "envelope", "paperplane", "airplane",
        "car", "figure.run", "dumbbell", "fork.knife", "cup.and.saucer", "leaf", "pawprint",
        "gift", "creditcard", "banknote", "chart.line.uptrend.xyaxis", "music.note", "camera",
        "paintbrush", "gamecontroller", "sparkles", "target", "checklist", "shippingbox"
    ]
}
