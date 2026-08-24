import SwiftUI

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
                PlaceholderHome()
            } else {
                SplashView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeOut(duration: 0.3)) { bootstrapped = true }
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

/// Temporary space until the home screen lands; replaced in next milestone.
struct PlaceholderHome: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Kino Studio")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Image(systemName: "clapperboard")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Engine bootstrap running")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
extension KinoApp {
    static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("--uitest") }
}
#endif
