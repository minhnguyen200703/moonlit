import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MomentStore
    @AppStorage("hasCompletedMoonlitWelcome") private var hasCompletedWelcome = false
    @State private var openCameraRequest = false

    var body: some View {
        Group {
            if !hasCompletedWelcome {
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.35)) { hasCompletedWelcome = true }
                }
            } else {
                content
            }
        }
        .tint(MoonlitTheme.burgundy)
        .task(id: hasCompletedWelcome) {
            if hasCompletedWelcome { await store.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMoonlitCamera)) { _ in
            if hasCompletedWelcome { openCameraRequest = true }
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "moonlitPendingCameraRoute") {
                UserDefaults.standard.set(false, forKey: "moonlitPendingCameraRoute")
                openCameraRequest = true
            }
        }
        .alert("Moonlit", isPresented: Binding(
            get: { store.transientError != nil },
            set: { if !$0 { store.transientError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.transientError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.appState {
        case .idle, .loading:
            LoadingView()
        case .needsConfiguration(let message):
            StatusView(title: "Connect Moonlit", systemImage: "gearshape.2", message: message, retryTitle: "Try again") {
                Task { await store.retryBootstrap() }
            }
        case .pairing:
            PairingView()
        case .ready:
            MainTabView(openCameraRequest: $openCameraRequest)
        case .failed(let message):
            StatusView(title: "Could not open Moonlit", systemImage: "wifi.exclamationmark", message: message, retryTitle: "Retry") {
                Task { await store.retryBootstrap() }
            }
        }
    }
}

private struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [MoonlitTheme.burgundy, MoonlitTheme.wine], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                MoonMark(size: 132)
                VStack(spacing: 8) {
                    Text("moonlit")
                        .font(.system(size: 48, weight: .semibold, design: .serif))
                    Text("under the same moon, always ♡").font(.callout).foregroundStyle(MoonlitTheme.blush)
                }
                .foregroundStyle(MoonlitTheme.cream)
                Text("A tiny private place for two people to share the ordinary moments that make a day feel close.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MoonlitTheme.cream.opacity(0.9))
                    .padding(.horizontal, 34)
                Spacer()
                Button("Enter our little universe", action: continueAction)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(MoonlitTheme.cream, in: Capsule())
                    .foregroundStyle(MoonlitTheme.burgundy)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            MoonlitTheme.cream.ignoresSafeArea()
            VStack(spacing: 18) {
                MoonMark(size: 84)
                ProgressView("Opening your little universe…")
                    .tint(MoonlitTheme.burgundy)
            }
            .foregroundStyle(MoonlitTheme.burgundy)
        }
    }
}

private struct StatusView: View {
    let title: String
    let systemImage: String
    let message: String
    let retryTitle: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button(retryTitle, action: retry).buttonStyle(.borderedProminent)
        }
    }
}

private struct MainTabView: View {
    @Binding var openCameraRequest: Bool

    var body: some View {
        TabView {
            NavigationStack { HomeView(openCameraRequest: $openCameraRequest) }
                .tabItem { Label("Us", systemImage: "moon.stars.fill") }
            NavigationStack { TimelineView() }
                .tabItem { Label("Our sky", systemImage: "sparkles") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}
