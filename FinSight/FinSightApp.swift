import SwiftUI

@main
struct FinSightApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1340, height: 880)
        .windowResizability(.contentMinSize)
        #endif
    }
}

/// The dashboard's own page background (--bg: #0a0b0e), used behind the web view so
/// safe-area insets and window resizing never flash white.
let finSightBackground = Color(red: 10 / 255, green: 11 / 255, blue: 14 / 255)

struct ContentView: View {
    var body: some View {
        ZStack {
            finSightBackground.ignoresSafeArea()
            FinSightWebView()
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 620)
        #endif
    }
}
