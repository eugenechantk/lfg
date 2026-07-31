import SwiftUI

/// Literal dark-mode design tokens for the new-session flow.
enum NewSessionPalette {
    static let canvas = Color.black
    static let surfaceRaised = rgb(28, 28, 30)
    static let surfaceControl = rgb(44, 44, 46)

    static let sheetFill = LinearGradient(
        colors: [Color.black.opacity(0.4), rgb(18, 18, 18)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let sheetScrim = Color.black.opacity(0.5)
    static let grabber = rgb(51, 51, 51)
    static let closeButtonFill = rgb(120, 120, 128, opacity: 0.32)
    static let confirmButtonFill = rgb(0, 145, 255)

    static let accent = rgb(10, 132, 255)
    static let searchFill = rgb(120, 120, 128, opacity: 0.24)
    static let separator = Color.white.opacity(0.12)
    static let labelPrimary = Color.white
    static let sheetTitle = rgb(245, 245, 245)
    static let labelSecondary = rgb(235, 235, 245, opacity: 0.60)
    static let labelTertiary = rgb(235, 235, 245, opacity: 0.50)
    static let placeholder = rgb(235, 235, 245, opacity: 0.45)
    static let modelChipLabel = rgb(235, 235, 245, opacity: 0.85)
    static let statusOK = rgb(48, 209, 88)
    static let statusWarn = rgb(255, 159, 10)
    static let brandOrange = rgb(255, 159, 69)

    static let attachIcon = Color.white.opacity(0.90)
    static let idleSendIcon = Color.white.opacity(0.85)

    private static func rgb(
        _ red: Double,
        _ green: Double,
        _ blue: Double,
        opacity: Double = 1
    ) -> Color {
        Color(
            .sRGB,
            red: red / 255,
            green: green / 255,
            blue: blue / 255,
            opacity: opacity
        )
    }
}
