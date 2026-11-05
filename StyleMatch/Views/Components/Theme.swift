import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 1.0, green: 0.23, blue: 0.42)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.48, blue: 0.22), Color(red: 1.0, green: 0.18, blue: 0.46)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pass = Color(red: 0.98, green: 0.27, blue: 0.33)
    static let like = Color(red: 0.13, green: 0.80, blue: 0.52)
    static let buy = Color(red: 0.20, green: 0.58, blue: 1.0)
    static let undo = Color(red: 1.0, green: 0.74, blue: 0.18)
}

@MainActor
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
