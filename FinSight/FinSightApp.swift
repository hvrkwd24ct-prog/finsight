import SwiftUI
import UIKit

/// FinSight for iPhone.
///
/// The dashboard itself is one self-contained `index.html` in the app bundle — React, Babel,
/// pdf.js and the typefaces are all inline, so there is no build step, no bundler and nothing
/// fetched at runtime. This target is the iPhone app around it.
///
/// It is deliberately not a browser pointed at a page. Everything a web view cannot do for
/// itself lives here in Swift: the Face ID gate that runs before the dashboard is even loaded,
/// the shade that hides your balances in the app switcher, Files import and share-sheet export,
/// Home Screen quick actions, and haptics. The web layer asks for those through one bridge and
/// works without them when they are absent, which is what keeps the same file opening in a
/// browser on a desktop.
@main
struct FinSightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lock = AppLock()
    @StateObject private var router = QuickActionRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(lock)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    lock.handle(phase: phase)
                }
        }
    }
}

/// The dashboard's own page background (`--bg: #0a0b0e`). Painted behind the web view so the
/// safe areas and the moment before first paint are never white.
let finSightBackground = Color(red: 10 / 255, green: 11 / 255, blue: 14 / 255)

struct RootView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var router: QuickActionRouter

    var body: some View {
        ZStack {
            finSightBackground.ignoresSafeArea()

            WebHost(pendingAction: $router.pending)
                .ignoresSafeArea(.container, edges: .bottom)
                // Hidden rather than removed: tearing the web view down and rebuilding it would
                // restart the dashboard, and a locked app that forgets where you were is a worse
                // app. It stays alive behind the shade with its state intact.
                .opacity(lock.isCovered ? 0 : 1)
                .accessibilityHidden(lock.isCovered)

            if lock.isCovered {
                PrivacyShade(state: lock.state, retry: { lock.authenticate() })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: lock.isCovered)
        .task { lock.begin() }
    }
}

/// What sits over the dashboard when it is not yours to look at: in the app switcher, and
/// whenever the Face ID gate has not been passed. Deliberately says nothing about your money.
struct PrivacyShade: View {
    let state: AppLock.State
    let retry: () -> Void

    var body: some View {
        ZStack {
            finSightBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("F")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(Color(red: 15 / 255, green: 82 / 255, blue: 60 / 255), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if case .locked(let message) = state {
                    Text("FinSight is locked")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                    if let message {
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 44)
                    }
                    Button(action: retry) {
                        Text("Unlock")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 26).padding(.vertical, 11)
                            .background(Color(red: 15 / 255, green: 82 / 255, blue: 60 / 255), in: Capsule())
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Quick actions

/// Long-press the Home Screen icon and go straight to the thing you opened the app to do.
/// The dashboard is a single page, so these arrive as a message the web layer acts on once it
/// is ready — and are held until it is, since the app is usually cold-launched by one.
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()
    @Published var pending: String?

    /// Matches the `UIApplicationShortcutItems` types declared in the Info.plist build settings.
    func handle(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case "com.ryanwalsh.FinSight.balances": pending = "balances"
        case "com.ryanwalsh.FinSight.payslip":  pending = "payslip"
        case "com.ryanwalsh.FinSight.spend":    pending = "spend"
        default: break
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// Quick actions arrive by two different doors and the common one is easy to miss. With scenes
/// enabled — which they are, the Info.plist generates a scene manifest — a shortcut that launched
/// the app cold is in the scene's `connectionOptions`, not in `didFinishLaunchingWithOptions`.
/// One that was used while the app was already running comes through `performActionFor`. Both
/// are needed; only handling the second means the icon menu works except when you actually use
/// it, which is from a standing start.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let item = options.shortcutItem { QuickActionRouter.shared.handle(item) }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickActionRouter.shared.handle(shortcutItem)
        completionHandler(true)
    }
}
