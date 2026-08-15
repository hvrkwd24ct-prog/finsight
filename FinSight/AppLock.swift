import SwiftUI
import LocalAuthentication

/// The gate in front of the dashboard, and the shade over it in the app switcher.
///
/// The web dashboard has a PIN screen of its own, and it is honest about being a privacy screen
/// rather than encryption. This is the same idea moved down a layer, where it is worth more: the
/// check is `LAContext`, so it is Face ID or the device passcode — the real ones, evaluated by
/// the system, with the system's own lockout after repeated failures rather than a counter in a
/// page that a reload resets. The dashboard is not shown until it passes.
///
/// It is still not encryption. Data lives in the app's container, and anyone who can read that
/// container reads it without meeting this screen. What it stops is the person holding your
/// unlocked phone, which is the threat that actually happens.
///
/// Opt-in, and off until you turn it on, because an app that demands your face before it will
/// show you anything is an app you stop opening. The web layer writes the preference through the
/// bridge when you set it in Settings.
@MainActor
final class AppLock: ObservableObject {

    enum State: Equatable {
        case open                    // unlocked, or never enabled
        case locked(String?)         // covered, with an optional reason to show
    }

    @Published private(set) var state: State = .open

    /// True while anything other than the dashboard should be on screen. Backgrounding sets this
    /// even when the lock is off: the app switcher snapshot is taken while the app is inactive,
    /// and a card in the switcher showing somebody's balances is the one leak that needs no
    /// attacker at all.
    @Published private(set) var isCovered = false

    private var authenticating = false

    init() {
        // Locked from the first frame when it is on, so the dashboard is never briefly visible
        // while we make up our mind.
        if UserDefaults.standard.bool(forKey: Self.key) {
            state = .locked(nil)
            isCovered = true
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.key) }
        set { UserDefaults.standard.set(newValue, forKey: Self.key) }
    }
    private static let key = "finsight.appLock.enabled"

    /// Whether this device can do it at all — asked before offering the setting.
    static var biometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "your passcode"
        }
    }

    // MARK: lifecycle

    func begin() {
        guard isEnabled else { state = .open; isCovered = false; return }
        if case .locked = state { authenticate() }
    }

    func handle(phase: ScenePhase) {
        switch phase {
        case .active:
            // Back at the front: ask if we are locked, otherwise just lift the switcher shade.
            guard isEnabled else { state = .open; isCovered = false; return }
            if case .locked = state { authenticate() } else { isCovered = false }
        case .inactive, .background:
            // Cover first, decide later. Doing it on .inactive is what gets the shade into the
            // snapshot; waiting for .background is too late, the picture is already taken.
            if isEnabled { state = .locked(nil) }
            isCovered = true
        @unknown default:
            isCovered = true
        }
    }

    // MARK: the gate

    func authenticate() {
        guard isEnabled else { state = .open; isCovered = false; return }
        guard !authenticating else { return }
        authenticating = true

        let context = LAContext()
        context.localizedFallbackTitle = ""      // the passcode sheet is the fallback, below
        let reason = "Unlock FinSight to see your accounts."

        // .deviceOwnerAuthentication, not ...WithBiometrics: a face that will not scan, a new
        // pair of glasses or a wet thumb should fall through to the passcode rather than shutting
        // somebody out of their own figures with no way back in.
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] ok, error in
            Task { @MainActor in
                guard let self else { return }
                self.authenticating = false
                if ok {
                    self.state = .open
                    self.isCovered = false
                } else {
                    self.state = .locked(Self.message(for: error))
                    self.isCovered = true
                }
            }
        }
    }

    /// Turned on or off from the dashboard's own Settings screen, through the bridge.
    func setEnabled(_ on: Bool) {
        isEnabled = on
        if on {
            state = .open           // already looking at it; ask on the next return, not now
            isCovered = false
        } else {
            state = .open
            isCovered = false
        }
    }

    private static func message(for error: Error?) -> String? {
        guard let error = error as? LAError else { return nil }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return nil                                  // they dismissed it; the button is right there
        case .biometryLockout:
            return "Too many attempts. Use your device passcode."
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "\(biometryName) is not set up on this device."
        case .passcodeNotSet:
            return "Set a device passcode to use the app lock."
        default:
            return "That was not recognised."
        }
    }
}
