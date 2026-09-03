import SwiftUI

struct PreBreakWarningView: View {
    @ObservedObject var engine: TimerEngine

    private var countdown: String {
        let total = Int(max(0, engine.remainingSeconds).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LookAwayBrand.accent)
            Text("即将进入强制休息")
                .font(.system(.title, design: .rounded, weight: .bold))
            Text("还有 (countdown)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(engine.reminderMessage)
                .font(.system(.body, design: .rounded, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(LookAwayBrand.accent.opacity(0.45), lineWidth: 2))
        .padding(4)
    }
}

struct BreakOverlayView: View {
    @ObservedObject var engine: TimerEngine
    let onSkipBreak: () -> Void
    let onStartWorking: () -> Void

    private var formattedTime: String {
        let total = Int(max(0, engine.remainingSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 20) {
                    if engine.phase == .breakComplete {
                        completionDisplay
                    } else {
                        timerDisplay
                    }

                    Text(engine.reminderMessage)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }

                Spacer(minLength: 0)

                Group {
                    if engine.phase == .breakComplete {
                        startWorkingControl
                    } else {
                        skipControl
                    }
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
        // The completion state is an explicit user choice: tapping anywhere on
        // the overlay is a reliable fallback when a full-screen app or display
        // scaling makes the button difficult to target.
        .contentShape(Rectangle())
        .onTapGesture {
            if engine.phase == .breakComplete {
                onStartWorking()
            }
        }
    }

    private var completionDisplay: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.green)

            Text("休息已达标")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            Text("准备好后，再开始下一轮工作")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var timerDisplay: some View {
        Text(formattedTime)
            .font(.system(size: 80, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 44)
            .padding(.vertical, 22)
            .lookAwayOverlayTimerGlass()
    }

    private var skipControl: some View {
        HoldToConfirmButton(
            title: "Skip",
            holdingTitle: "Keep holding…",
            systemImage: "forward.end.fill",
            role: .destructive,
            centered: true,
            overlayGlass: true,
            onConfirm: onSkipBreak
        )
        .frame(maxWidth: 160)
        .opacity(0.2)
    }

    private var startWorkingControl: some View {
        Button(action: onStartWorking) {
            Label("开始工作", systemImage: "play.fill")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
        }
        .buttonStyle(.borderedProminent)
        .tint(LookAwayBrand.accent)
        .keyboardShortcut(.defaultAction)
        .frame(minWidth: 240, minHeight: 64)
    }
}

private struct LookAwayOverlayTimerGlass: ViewModifier {
    func body(content: Content) -> some View {
        #if LIQUID_GLASS
        content.glassEffect(
            .regular.tint(LookAwayBrand.accent.opacity(0.16)),
            in: .rect(cornerRadius: 36)
        )
        #else
        content
            .background {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .strokeBorder(LookAwayBrand.accent.opacity(0.22), lineWidth: 1)
                    }
            }
        #endif
    }
}

private extension View {
    func lookAwayOverlayTimerGlass() -> some View {
        modifier(LookAwayOverlayTimerGlass())
    }
}
