import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Small shims over the few APIs that differ between iOS/visionOS and macOS, so the views
/// themselves stay platform-neutral.
extension Color {
    /// The screen background behind cards.
    static var groupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// The background of a card sitting on `groupedBackground`.
    static var cardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// The background of a text field inside a card.
    static var fieldBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}

/// Put `text` on the system clipboard.
func copyToPasteboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}

extension View {
    /// A compact navigation title on platforms that have one.
    func inlineNavigationTitle() -> some View {
        #if canImport(UIKit)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// A keyboard with digits, "-", "." and ":", which covers both numbers and Clock's times.
    func valueKeyboard() -> some View {
        #if canImport(UIKit)
        keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
