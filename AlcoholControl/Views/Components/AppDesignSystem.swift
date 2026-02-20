import SwiftUI

enum AppDesign {
    enum Colors {
        static let primary = Color(light: 0xA8B5A0, dark: 0x8C9985)
        static let secondary = Color(light: 0xD4A5A5, dark: 0xB58A8A)
        static let accent = Color(light: 0xE8DCC4, dark: 0xC9BCAB)
        static let background = Color(light: 0xFAF7F2, dark: 0x1A1C1A)
        static let surface = Color(light: 0xFFFFFF, dark: 0x252826)
        static let primaryText = Color(light: 0x2D302E, dark: 0xF2F2F2)
        static let secondaryText = Color(light: 0x6B706C, dark: 0xA0A5A1)
        static let divider = Color(light: 0xE8E6E1, dark: 0x333634)
        static let success = Color(light: 0x81C784, dark: 0xA5D6A7)
        static let error = Color(light: 0xE57373, dark: 0xEF9A9A)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppDesign.Spacing.md)
            .background(AppDesign.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.md, style: .continuous)
                    .stroke(AppDesign.Colors.divider.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(AppDesign.Colors.background)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.md, style: .continuous)
                    .fill(AppDesign.Colors.primary.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(AppDesign.Colors.primaryText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.md, style: .continuous)
                    .fill(AppDesign.Colors.accent.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }

    func appScreenBackground() -> some View {
        background(
            LinearGradient(
                colors: [
                    AppDesign.Colors.background,
                    AppDesign.Colors.background,
                    AppDesign.Colors.accent.opacity(0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
