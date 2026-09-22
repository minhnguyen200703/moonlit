import SwiftUI
import UserNotifications
import UIKit

@main
struct MoonlitApp: App {
    @UIApplicationDelegateAdaptor(MoonlitAppDelegate.self) private var appDelegate
    @StateObject private var store = MomentStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refreshMoments() } }
                }
        }
    }
}

final class MoonlitAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.userInfo["destination"] as? String == "camera" else { return }
        await MainActor.run {
            UserDefaults.standard.set(true, forKey: "moonlitPendingCameraRoute")
            NotificationCenter.default.post(name: .openMoonlitCamera, object: nil)
        }
    }
}

extension Notification.Name {
    static let openMoonlitCamera = Notification.Name("openMoonlitCamera")
}
