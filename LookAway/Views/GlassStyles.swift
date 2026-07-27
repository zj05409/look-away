import SwiftUI

// MARK: - Design tokens (Apple Liquid Glass guidelines)

enum LookAwayGlass {
    /// Spacing for `GlassEffectContainer` — controls when adjacent effects blend.
    static let containerSpacing: CGFloat = MenuPanelMetrics.spacing

    static let panelCornerRadius: CGFloat = 22
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = MenuPanelMetrics.cornerRadius
    static let insetCornerRadius: CGFloat = MenuPanelMetrics.cornerRadius * 0.8

    static func accentTint(_ opacity: Double = 0.08) -> Color {
        LookAwayBrand.accent.opacity(opacity)
    }

    static var menuPanelTint: Color {
        accentTint(0.08)
    }

    static var overlayTint: Color {
        LookAwayBrand.accent.opacity(0.14)
    }

    static var overlayDestructiveTint: Color {
        Color(red: 1, green: 0.45, blue: 0.42).opacity(0.18)
    }

    /// Inner control fill — no nested glass inside the menu panel.
    static func controlFill(tint: Color? = nil) -> some ShapeStyle {
        if let tint {
            return AnyShapeStyle(tint)
        }
        return AnyShapeStyle(Color.primary.opacity(0.07))
    }

    #if LIQUID_GLASS
    static var panelGlass: Glass {
        .regular.tint(menuPanelTint)
    }

    static func controlGlass(tint: Color? = menuPanelTint, interactive: Bool = false) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
    #endif
}

// MARK: - Panel + control glass

extension View {
    /// Subtle fill for controls inside the menu panel (avoids nested glass corner artifacts).
    func lookAwayControlSurface(
        cornerRadius: CGFloat = LookAwayGlass.controlCornerRadius,
        tint: Color? = LookAwayGlass.menuPanelTint
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LookAwayGlass.controlFill(tint: tint))
        }
    }

    func lookAwayCapsuleSurface(tint: Color? = LookAwayGlass.menuPanelTint) -> some View {
        background {
            Capsule(style: .continuous)
                .fill(LookAwayGlass.controlFill(tint: tint))
        }
    }
}

#if LIQUID_GLASS
extension View {
    func lookAwayGlassEffect(
        _ glass: Glass = LookAwayGlass.panelGlass,
        cornerRadius: CGFloat = LookAwayGlass.controlCornerRadius
    ) -> some View {
        glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    func lookAwayCapsuleGlass(tint: Color? = LookAwayGlass.menuPanelTint, interactive: Bool = false) -> some View {
        lookAwayGlassEffect(
            LookAwayGlass.controlGlass(tint: tint, interactive: interactive),
            cornerRadius: LookAwayGlass.controlCornerRadius
        )
    }
}

/// Single outer glass shell for the menu panel — no container wrapper, no extra clip.
struct LookAwayGlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // glassEffect already clips to its shape. An extra continuous clipShape
        // over a circular `.rect(cornerRadius:)` caused the double-corner artifact.
        content
            .glassEffect(
                LookAwayGlass.panelGlass,
                in: .rect(cornerRadius: LookAwayGlass.panelCornerRadius)
            )
    }
}
#else
extension View {
    func lookAwayGlassEffect(cornerRadius: CGFloat = LookAwayGlass.controlCornerRadius, tint: Color? = LookAwayGlass.menuPanelTint) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    }
                }
        }
    }

    func lookAwayCapsuleGlass(tint: Color? = LookAwayGlass.menuPanelTint, interactive: Bool = false) -> some View {
        background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    if let tint {
                        Capsule(style: .continuous).fill(tint)
                    }
                }
        }
    }
}

struct LookAwayGlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .lookAwayGlassEffect(
                cornerRadius: LookAwayGlass.panelCornerRadius,
                tint: LookAwayGlass.menuPanelTint
            )
            .clipShape(RoundedRectangle(cornerRadius: LookAwayGlass.panelCornerRadius, style: .continuous))
    }
}
#endif

// MARK: - Button styles

struct LookAwayGlassButtonStyle: ButtonStyle {
    var role: ButtonRole?
    var centered: Bool = false
    var overlay: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MenuPanelMetrics.controlFont)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, MenuPanelMetrics.controlHorizontalPadding)
            .padding(.vertical, MenuPanelMetrics.controlVerticalPadding)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .modifier(LookAwayGlassButtonBackground(role: role, overlay: overlay))
            .contentShape(RoundedRectangle(cornerRadius: LookAwayGlass.controlCornerRadius, style: .continuous))
    }

    private var foregroundColor: Color {
        switch role {
        case .destructive:
            return overlay ? Color(red: 1, green: 0.55, blue: 0.52) : .red
        default:
            return overlay ? .white : .primary
        }
    }
}

private struct LookAwayGlassButtonBackground: ViewModifier {
    let role: ButtonRole?
    let overlay: Bool

    func body(content: Content) -> some View {
        content.lookAwayControlSurface(
            cornerRadius: LookAwayGlass.controlCornerRadius,
            tint: backgroundTint
        )
    }

    private var backgroundTint: Color? {
        switch role {
        case .destructive:
            return overlay ? LookAwayGlass.overlayDestructiveTint : Color.red.opacity(0.08)
        default:
            return overlay ? LookAwayGlass.overlayTint : LookAwayGlass.menuPanelTint
        }
    }
}

typealias MenuActionButtonStyle = LookAwayGlassButtonStyle
typealias GlassActionButtonStyle = LookAwayGlassButtonStyle

extension View {
    func lookAwayGlassSurface(
        cornerRadius: CGFloat = LookAwayGlass.controlCornerRadius,
        tint: Color? = LookAwayGlass.menuPanelTint,
        interactive: Bool = false
    ) -> some View {
        lookAwayControlSurface(cornerRadius: cornerRadius, tint: tint)
    }
}
