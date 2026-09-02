import Foundation
import Testing
@testable import MiniWhisper

@Suite struct OnboardingModelTests {
    /// Mutable grant state plus a request log, so one model can be driven through the
    /// wizard the way the user granting permissions in System Settings would.
    private final class Permissions {
        var granted: Set<OnboardingPermission> = []
        var requested: [OnboardingPermission] = []

        func model() -> OnboardingModel {
            OnboardingModel(
                isGranted: { [self] in granted.contains($0) },
                request: { [self] in requested.append($0) }
            )
        }
    }

    @Test func stepsAreMicrophoneThenAccessibility() {
        #expect(OnboardingModel.steps == [.microphone, .accessibility])
    }

    @Test func advancesPastGrantedSteps() {
        let permissions = Permissions()
        permissions.granted = [.microphone]
        var model = permissions.model()
        model.start()
        #expect(model.currentStep == 1)
        #expect(model.granted(.microphone))
        #expect(!model.granted(.accessibility))
    }

    @Test func requestsOnlyCurrentStep() {
        let permissions = Permissions()
        var model = permissions.model()
        model.start()
        #expect(permissions.requested == [.microphone])

        permissions.granted = [.microphone]
        model.poll()
        #expect(permissions.requested == [.microphone, .accessibility])
        #expect(model.currentStep == 1)

        permissions.granted = [.microphone, .accessibility]
        model.poll()
        #expect(permissions.requested == [.microphone, .accessibility])
    }

    @Test func continueEnabledWhenAllGranted() {
        let permissions = Permissions()
        var model = permissions.model()
        model.start()
        #expect(!model.continueEnabled)

        permissions.granted = [.microphone, .accessibility]
        model.poll()
        #expect(model.continueEnabled)
        #expect(model.allGranted)
    }

    @Test func statusLabelTexts() {
        let permissions = Permissions()
        var model = permissions.model()
        model.start()
        #expect(model.statusText == "Please grant Microphone access.")

        permissions.granted = [.microphone]
        model.poll()
        #expect(model.statusText == "Please grant Accessibility access.")

        permissions.granted = [.microphone, .accessibility]
        model.poll()
        #expect(model.statusText == "All permissions granted!")

        // Revoked after the wizard walked past both steps.
        permissions.granted = []
        model.poll()
        #expect(model.statusText == "Grant all permissions to continue.")
    }

    @Test func deepLinks() {
        #expect(
            OnboardingPermission.microphone.settingsURL
                == URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        )
        #expect(
            OnboardingPermission.accessibility.settingsURL
                == URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
    }
}
