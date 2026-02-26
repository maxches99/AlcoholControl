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

        static let darkScreenTop = Color(red: 0.06, green: 0.08, blue: 0.08)
        static let darkScreenMiddle = Color(red: 0.07, green: 0.10, blue: 0.09)
        static let darkScreenBottom = Color(red: 0.08, green: 0.10, blue: 0.09)
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
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 30
    }

    enum Typography {
        static let screenTitle = Font.system(size: 44, weight: .bold, design: .rounded)
        static let sectionHeader = Font.system(.subheadline, design: .rounded).weight(.bold)
        static let rowTitle = Font.system(.body, design: .rounded).weight(.semibold)
        static let iconBadge = Font.system(size: 12, weight: .semibold)
        static let rowIcon = Font.system(size: 16, weight: .semibold)
    }

    enum Gradients {
        static let darkScreen = LinearGradient(
            colors: [Colors.darkScreenTop, Colors.darkScreenMiddle, Colors.darkScreenBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

struct AppIconBadge: View {
    let icon: String
    let size: CGFloat
    let iconFont: Font
    var fill: Color = Color.white.opacity(0.09)
    var foreground: Color = Color.white.opacity(0.62)

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(iconFont)
                    .foregroundStyle(foreground)
            )
    }
}

struct AppSectionHeader: View {
    let title: String
    var foreground: Color = Color.white.opacity(0.86)

    var body: some View {
        HStack {
            Text(title)
                .font(AppDesign.Typography.sectionHeader)
                .foregroundStyle(foreground)
                .textCase(nil)
            Spacer()
        }
    }
}

struct AppElevatedCardModifier: ViewModifier {
    var fill: Color = Color.white.opacity(0.06)
    var stroke: Color = Color.white.opacity(0.08)
    var cornerRadius: CGFloat = AppDesign.Radius.xl
    var padding: CGFloat = AppDesign.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }

    func appElevatedCard(
        fill: Color = Color.white.opacity(0.06),
        stroke: Color = Color.white.opacity(0.08),
        cornerRadius: CGFloat = AppDesign.Radius.xl,
        padding: CGFloat = AppDesign.Spacing.md
    ) -> some View {
        modifier(
            AppElevatedCardModifier(
                fill: fill,
                stroke: stroke,
                cornerRadius: cornerRadius,
                padding: padding
            )
        )
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

    func appDarkScreenBackground() -> some View {
        background(AppDesign.Gradients.darkScreen.ignoresSafeArea())
    }
}
