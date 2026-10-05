import Foundation
import Observation
import UIKit
import UserNotifications
import FirebaseMessaging

/// Dormant until BOTH the signed build and backend are configured for APNs.
@MainActor @Observable final class PushCoordinator {
    static let shared = PushCoordinator()
    static var isConfigured: Bool { (Bundle.main.object(forInfoDictionaryKey: "MultiversePushEnabled") as? String) == "YES" }
    var openActivity = false
    private var api: (any NotificationsAPI)?
    private var userID: String?
    private var registration: String?
    private var registrationTask: Task<Void, Never>?
    private var generation = 0
    private(set) var error: String?
    func enable(api: any NotificationsAPI, userID: String) async throws {
        guard Self.isConfigured else { throw SocialError.invalid }
        guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw PushError.permission
        }
        try await bind(api: api, userID: userID)
    }
    func resume(api: any NotificationsAPI, userID: String) async {
        guard Self.isConfigured else { return }
        do {
            let prefs = try await api.fetchNotificationPreferences()
            guard prefs.push, prefs.pushAvailable else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            try await bind(api: api, userID: userID)
        } catch { self.error = error.localizedDescription }
    }
    private func bind(api: any NotificationsAPI, userID: String) async throws {
        if self.userID == userID { UIApplication.shared.registerForRemoteNotifications(); return }
        let defaults = UserDefaults.standard
        if let oldOwner = defaults.string(forKey: "mv-push-owner"), oldOwner != userID {
            // Invalidate a token retained by a previous offline session before associating this installation again.
            try await Messaging.messaging().deleteToken()
            defaults.removeObject(forKey: "mv-push-registration")
        }
        let id = defaults.string(forKey: "mv-push-registration") ?? UUID().uuidString.lowercased()
        defaults.set(id, forKey: "mv-push-registration"); defaults.set(userID, forKey: "mv-push-owner")
        generation += 1; self.api = api; self.userID = userID; registration = id; error = nil
        Messaging.messaging().isAutoInitEnabled = true
        UIApplication.shared.registerForRemoteNotifications()
    }
    func tokenChanged(_ token: String) {
        guard Self.isConfigured, let api, let registration else { return }
        let epoch = generation, prior = registrationTask
        registrationTask = Task {
            await prior?.value
            guard epoch == generation, !Task.isCancelled else { return }
            do {
                let result = try await api.registerPushDevice(id: registration, token: token)
                guard result.saved else { throw SocialError.invalid }
                if epoch == generation { error = nil }
            } catch { if epoch == generation { self.error = error.localizedDescription } }
        }
    }
    func registeredAPNs() {
        guard Self.isConfigured, api != nil else { return }
        let epoch = generation
        Task {
            do {
                let token = try await Messaging.messaging().token()
                if epoch == generation { tokenChanged(token) }
            } catch { if epoch == generation { self.error = error.localizedDescription } }
        }
    }
    func disconnect(cleanupAPI: (any NotificationsAPI)? = nil) async {
        guard Self.isConfigured else { return }
        generation += 1
        await registrationTask?.value
        registrationTask = nil
        // Authentication invalidates feature clients before cleanup. A fresh, UID-bound
        // client may remove this device while the SDK identity is still available.
        if let api = cleanupAPI ?? api, let registration { _ = try? await api.removePushDevice(id: registration) }
        // If offline, retain owner/id so a later account cannot silently claim the old token.
        do {
            try await Messaging.messaging().deleteToken()
            UserDefaults.standard.removeObject(forKey: "mv-push-owner")
            UserDefaults.standard.removeObject(forKey: "mv-push-registration")
        } catch { self.error = error.localizedDescription }
        Messaging.messaging().isAutoInitEnabled = false
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        api = nil; userID = nil; registration = nil; openActivity = false
    }
}
enum PushError: LocalizedError {
    case permission
    var errorDescription: String? { L10n.text("Permita notificações nos Ajustes do iPhone para receber alertas.") }
}
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        if !PushCoordinator.isConfigured { Messaging.messaging().isAutoInitEnabled = false }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        PushCoordinator.shared.registeredAPNs()
    }
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in PushCoordinator.shared.tokenChanged(fcmToken) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["notificationID"] as? String, UUID(uuidString: id) != nil else { return }
        // Open the authorized account's center; never trust a lock-screen payload as a content route.
        await MainActor.run { PushCoordinator.shared.openActivity = true }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [] // Foreground activity is refreshed by the in-app center.
    }
}
