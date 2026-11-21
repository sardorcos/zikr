import SwiftUI
import UIKit

/// Palette with light and dark variants. Text colors meet WCAG AA (4.5:1) on `zBackground`
/// and `zSurface` in both modes.
extension Color {
    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Screen background: warm ivory / deep green-black.
    static let zBackground = dynamic(light: (0.973, 0.970, 0.952), dark: (0.043, 0.071, 0.063))
    /// Cards and grouped rows.
    static let zSurface = dynamic(light: (1.0, 1.0, 1.0), dark: (0.090, 0.129, 0.118))
    /// Primary brand color for text, icons and filled controls.
    static let zPrimary = dynamic(light: (0.059, 0.290, 0.235), dark: (0.541, 0.835, 0.702))
    /// Text/icon color placed on top of `zPrimary`.
    static let zOnPrimary = dynamic(light: (1.0, 1.0, 1.0), dark: (0.027, 0.106, 0.086))
    /// Subtle tint for chips and selected states.
    static let zSoft = dynamic(light: (0.890, 0.929, 0.882), dark: (0.133, 0.208, 0.184))
    /// Gold accent. `zAccentText` is the darker variant safe for small text.
    static let zAccent = dynamic(light: (0.760, 0.610, 0.310), dark: (0.871, 0.737, 0.455))
    static let zAccentText = dynamic(light: (0.545, 0.408, 0.133), dark: (0.871, 0.737, 0.455))
    /// Beads of the counter ring.
    static let zBead = dynamic(light: (0.098, 0.373, 0.302), dark: (0.290, 0.580, 0.475))
    static let zBeadDim = dynamic(light: (0.780, 0.840, 0.800), dark: (0.180, 0.260, 0.235))
}
