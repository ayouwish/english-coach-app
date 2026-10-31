import SwiftUI

@main
struct EnglishCoachApp: App {
    @State private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()

            switch app.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                LoginView()
            case .signedIn:
                PracticeListView()
            }
        }
        // 角色能力统一下发：页面/组件读 @Environment(\.capabilities)，不写 role == .child。
        .environment(\.capabilities, app.capabilities)
        .task {
            await app.restoreIfNeeded()
        }
    }
}

private struct LaunchView: View {
    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Tokens.Colors.onPrimary)
                .frame(width: 88, height: 88)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Tokens.Colors.primary, Tokens.Colors.primary.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
            Text("English Coach")
                .font(AppFont.titleLarge(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            ProgressView()
                .tint(Tokens.Colors.primary)
            Text("正在恢复登录…")
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }
}
