import SwiftUI
import UIKit

/// Black, distraction-free counting for night use. The whole screen is the tap target,
/// the screen does not lock, and on OLED displays the black background emits no light.
struct NightModeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showHint = true
    @State private var showCompleted = false

    var body: some View {
        let settings = store.data.settings
        let opacity = settings.nightDigitsOpacity
        ZStack {
            Color.black.ignoresSafeArea()

            if settings.nightShowDigits, let status = store.activeStatus {
                VStack(spacing: 8) {
                    Text(status.stepTitle ?? status.title)
                        .font(.title3)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(store.num(status.value))
                        .font(.system(size: 120, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(status.value)))
                    if let target = status.target {
                        Text(store.f("face.outOf", store.num(target)))
                            .font(.title3)
                    }
                }
                .foregroundStyle(Color.white.opacity(opacity))
                .padding(.horizontal, 24)
                .animation(.snappy(duration: 0.15), value: status.value)
                .accessibilityHidden(true)
            }

            if showCompleted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 64))
                    Text(store.t("completion.title")).font(.title3)
                }
                .foregroundStyle(Color.zAccent.opacity(max(0.5, opacity)))
                .transition(.opacity.combined(with: .scale))
                .accessibilityHidden(true)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel(store.t("night.exit"))
                    Spacer()
                    Button {
                        store.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel(store.t("action.undo"))
                }
                .foregroundStyle(Color.white.opacity(max(0.25, opacity * 0.8)))
                .padding(.horizontal, 12)
                Spacer()
                if showHint {
                    Text(store.t("night.hint"))
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.tap() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.height > 120 { dismiss() }
            }
        )
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(store.t("face.a11yHint"))) { store.tap() }
        .onAppear {
            if settings.keepScreenOn { UIApplication.shared.isIdleTimerDisabled = true }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { showHint = false }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Keep the usual 2-minute grace period after leaving night mode.
            store.keepAwakeWhileCounting()
        }
        .storeAlert()
        .onChange(of: store.nightCompletionToken) {
            withAnimation(.easeOut(duration: 0.2)) { showCompleted = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeIn(duration: 0.4)) { showCompleted = false }
            }
        }
    }
}
