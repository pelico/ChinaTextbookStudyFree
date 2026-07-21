import SwiftUI

/// Role-based typography — the app's single type scale.
///
/// Duolingo's personality lives in one heavy, rounded typeface applied on a
/// small, strict scale. We use SF Rounded (`design: .rounded`) at eight roles
/// instead of the ~30 ad-hoc `.font(.system(size:))` sizes that were scattered
/// across the app. Prefer `.duoFont(.heading)` over raw sizes in new code.
///
/// Every role scales with Dynamic Type via `relativeTo:` so accessibility text
/// sizes still work.
enum DuoFont {
    case display    // 34 — result splash, big numbers
    case title      // 28 — screen titles
    case heading    // 22 — section / question instruction
    case subhead    // 18 — card titles, emphasized body
    case body       // 16 — default reading text
    case button     // 17 — chunky button labels
    case caption    // 13 — metadata, chips
    case micro      // 11 — tiny labels, badges

    var size: CGFloat {
        switch self {
        case .display: return 34
        case .title:   return 28
        case .heading: return 22
        case .subhead: return 18
        case .body:    return 16
        case .button:  return 17
        case .caption: return 13
        case .micro:   return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title, .heading, .button: return .heavy
        case .subhead, .caption, .micro:          return .bold
        case .body:                               return .medium
        }
    }

    /// The `TextStyle` this role scales relative to (for Dynamic Type).
    var relativeTo: Font.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .title:   return .title
        case .heading: return .title2
        case .subhead: return .title3
        case .body:    return .body
        case .button:  return .headline
        case .caption: return .footnote
        case .micro:   return .caption2
        }
    }

    var font: Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Apply a typography role. Optionally override the weight for one-offs.
    func duoFont(_ role: DuoFont, weight: Font.Weight? = nil) -> some View {
        self.font(.system(size: role.size, weight: weight ?? role.weight, design: .rounded))
    }

    /// Numeric text that shouldn't jitter as digits change (XP, streak, timers).
    func duoNumeral(_ role: DuoFont, weight: Font.Weight? = nil) -> some View {
        self
            .font(.system(size: role.size, weight: weight ?? .heavy, design: .rounded))
            .monospacedDigit()
    }
}

extension Font {
    /// Non-View contexts (e.g. `Text(...).font(DuoFont.body.font)`), and
    /// convenience for `prompt:` / attributed strings.
    static func duo(_ role: DuoFont, weight: Font.Weight? = nil) -> Font {
        .system(size: role.size, weight: weight ?? role.weight, design: .rounded)
    }
}
