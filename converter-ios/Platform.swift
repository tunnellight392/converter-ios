import SwiftUI
import UIKit

/// Small UIKit-backed helpers shared by the views.
extension Color {
    /// The screen background behind cards.
    static var groupedBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    /// The background of a card sitting on `groupedBackground`.
    static var cardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// The background of a text field inside a card.
    static var fieldBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }
}

/// Put `text` on the system clipboard.
func copyToPasteboard(_ text: String) {
    UIPasteboard.general.string = text
}

extension View {
    /// A compact navigation title.
    func inlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    /// A keyboard with digits, "-", "." and ":", which covers both numbers and Clock's times.
    func valueKeyboard() -> some View {
        keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
    }
}
