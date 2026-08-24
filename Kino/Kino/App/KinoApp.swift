import SwiftUI
#if DEBUG
import Foundation
#endif

@main
struct KinoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var bootstrapped = false

    var body: some View {
        ZStack {
            KinoTheme.backgroundColor.ignoresSafeArea()
            if bootstrapped {
                NavigationView {
                    HomeScreen()
                }
                .navigationViewStyle(.stack)
            } else {
                SplashView()
                    .onAppear {
                        #if DEBUG
                        let args = ProcessInfo.processInfo.arguments
                        if args.contains("--fixtures") || args.contains("--demoproject") {
                            Task.detached(priority: .utility) {
                                _ = FixtureFactory.ensure()
                            }
                        }
                        #endif
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.25)) { bootstrapped = true }
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clapperboard.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(KinoTheme.accentGradient)
            Text("Kino")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Video Studio")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
