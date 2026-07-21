import SwiftUI

/// Shared spacing scale — an ~8pt rhythm. Use these instead of magic numbers so
/// every screen breathes the same way.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Shared corner radii. Collapsed from the ~11 literals that were floating
/// around into four intentional steps.
enum Radius {
    static let control: CGFloat = 12   // small buttons, chips
    static let card: CGFloat = 16      // cards, sheets, option cards
    static let large: CGFloat = 20     // hero cards, modals
    static let pill: CGFloat = 999      // capsules
}

/// The three motion curves the whole app shares. One "press" feel, one "reveal"
/// feel, one "bounce" feel — so interactions read as engineered, not assembled.
enum Motion {
    /// Fast tactile press — buttons, option cards, chips.
    static let press: Animation = .spring(response: 0.15, dampingFraction: 0.7)
    /// Content sliding/appearing — feedback panels, progress fills.
    static let reveal: Animation = .spring(response: 0.35, dampingFraction: 0.72)
    /// Playful overshoot — celebrations, mascot reactions, node pops.
    static let bounce: Animation = .spring(response: 0.3, dampingFraction: 0.55)
    /// Gentle looping idle (current node bob, mascot breathe).
    static let idle: Animation = .easeInOut(duration: 0.7)
}
