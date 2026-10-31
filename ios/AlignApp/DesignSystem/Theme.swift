import SwiftUI
import UIKit

/// Small design system: one calm accent, a muted caution tone, semantic system backgrounds,
/// a spacing scale and a couple of shared containers.
enum Theme {
    /// Muted teal. Darker in light mode for contrast on white, lighter in dark mode.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.74, blue: 0.71, alpha: 1)
            : UIColor(red: 0.13, green: 0.45, blue: 0.45, alpha: 1)
    })

    /// Soft amber for "outside your range". Always paired with an icon or text.
    static let caution = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.72, blue: 0.36, alpha: 1)
            : UIColor(red: 0.66, green: 0.40, blue: 0.02, alpha: 1)
    })

    static let background = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let hairline = Color(uiColor: .separator)

    static let cornerRadius: CGFloat = 16
    /// Minimum hit target (Human Interface Guidelines).
    static let minimumTapTarget: CGFloat = 44

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

/// A rounded, grouped-background container used on the dashboard and similar screens.
struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            content
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Icon + text status line. The icon carries meaning together with the text, never color alone.
struct StatusLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

/// Small uppercase-free section caption used inside cards.
struct CardTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Full-width prominent button label.
struct WideButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget - 16)
    }
}
