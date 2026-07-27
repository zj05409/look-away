import AppKit
import SwiftUI

struct HoldToConfirmButton: View {
    let title: String
    let holdingTitle: String
    let systemImage: String
    var holdDuration: TimeInterval = LookAwayMetrics.holdConfirmDuration
    var role: ButtonRole?
    var compact: Bool = false
    var centered: Bool = false
    var overlayGlass: Bool = false
    let onConfirm: () -> Void

    @State private var holdProgress: Double = 0
    @State private var isHolding = false
    @State private var holdTimer: Timer?

    private var cornerRadius: CGFloat { MenuPanelMetrics.cornerRadius }
    private var verticalPadding: CGFloat { MenuPanelMetrics.controlVerticalPadding }
    private var horizontalPadding: CGFloat { MenuPanelMetrics.controlHorizontalPadding }

    var body: some View {
        Button {
            // Tap alone does nothing — hold required.
        } label: {
            Label(isHolding ? holdingTitle : title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .font(MenuPanelMetrics.controlFont)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(progressFillColor.opacity(0.22))
                            .frame(width: geometry.size.width * holdProgress, height: geometry.size.height)
                    }
                    .allowsHitTesting(false)
                }
                .lookAwayGlassSurface(cornerRadius: cornerRadius, tint: glassTint, interactive: true)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding {
                        beginHold()
                    }
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
    }

    private var foregroundColor: Color {
        switch role {
        case .destructive:
            return overlayGlass ? Color(red: 1, green: 0.55, blue: 0.52) : .red
        default:
            return overlayGlass ? .white : .primary
        }
    }

    private var glassTint: Color? {
        if overlayGlass {
            return role == .destructive
                ? LookAwayGlass.overlayDestructiveTint
                : LookAwayGlass.overlayTint
        }
        return role == .destructive
            ? Color.red.opacity(0.08)
            : LookAwayGlass.menuPanelTint
    }

    private var progressFillColor: Color {
        role == .destructive ? .red : LookAwayBrand.accent
    }

    private func beginHold() {
        isHolding = true
        holdProgress = 0
        let start = Date()
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(1, elapsed / holdDuration)
                holdProgress = progress
                if progress >= 1 {
                    timer.invalidate()
                    holdTimer = nil
                    isHolding = false
                    holdProgress = 0
                    onConfirm()
                }
            }
        }
        if let holdTimer {
            RunLoop.main.add(holdTimer, forMode: .common)
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        isHolding = false
        holdProgress = 0
    }
}
