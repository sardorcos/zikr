import UIKit

/// Prepared feedback generators so taps feel instant.
@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        light.prepare()
        rigid.prepare()
        notification.prepare()
    }

    func play(_ outcome: TapOutcome) {
        switch outcome {
        case .counted:
            light.impactOccurred()
            light.prepare()
        case .intervalReached, .stepCompleted:
            heavy.impactOccurred()
            let generator = heavy
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                generator.impactOccurred(intensity: 0.7)
            }
        case .dailyGoalReached, .goalReached, .programCompleted:
            notification.notificationOccurred(.success)
        }
    }

    func undo() {
        rigid.impactOccurred(intensity: 0.6)
    }

    func warning() {
        notification.notificationOccurred(.warning)
    }
}
