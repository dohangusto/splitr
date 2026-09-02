//
//  splitrApp.swift
//  splitr
//

import CloudKit
import SwiftUI
import SplitBillSync

extension Notification.Name {
    static let splitrAcceptedShare = Notification.Name("splitr.acceptedShare")
    static let splitrOpenURL = Notification.Name("splitr.openURL")
}

/// Composition root: one place decides which `RoomStoring` the app runs on.
/// Simulator → mock store with demo rooms (no iCloud account needed);
/// device → CloudKit-backed store. Previews construct `MockRoomStore`
/// directly.
@MainActor
enum AppComposition {
    static let store: any RoomStoring = {
        #if targetEnvironment(simulator)
        return MockRoomStore()
        #else
        // Set this to true ONLY if you are using a Paid Apple Developer Account 
        // and have configured CloudKit container entitlements for "iCloud.com.bryan.splitr".
        // Free/personal developer accounts will crash on startup if this is true.
        let useCloudKit = false
        
        if useCloudKit {
            return CloudKitRoomStore()
        } else {
            return MockRoomStore()
        }
        #endif
    }()

    /// The CloudKit store when active — push + share entry points need it.
    static var cloudStore: CloudKitRoomStore? {
        store as? CloudKitRoomStore
    }

    /// MainActor bridge for the nonisolated push delegate: returns a plain
    /// Bool so nothing non-Sendable crosses isolation.
    static func refetchFromPush() async -> Bool {
        guard let store = cloudStore else { return false }
        return await store.refetchFromPush()
    }
}

@main
struct splitrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isShowingSplash = true
    @State private var inviteRoomID: UUID?

    var body: some Scene {
        WindowGroup {
            Group {
                if isShowingSplash && inviteRoomID == nil {
                    SplashScreen {
                        isShowingSplash = false
                    }
                } else if hasCompletedOnboarding || inviteRoomID != nil {
                    HomePageView(
                        store: AppComposition.store,
                        initialRoomID: inviteRoomID,
                        onInitialRoomOpened: { inviteRoomID = nil }
                    )
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .onOpenURL { url in
                handleInviteURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitrOpenURL)) { notification in
                guard let url = notification.object as? URL else { return }
                handleInviteURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitrAcceptedShare)) { notification in
                guard let roomID = notification.object as? UUID else { return }
                openAcceptedRoom(roomID)
            }
        }
    }

    @MainActor
    private func handleInviteURL(_ url: URL) {
        Task {
            guard await AppComposition.store.acceptShare(from: url) else { return }
            guard let roomID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "id" })?.value
                .flatMap(UUID.init) else {
                // Real CKShare links are delivered through SceneDelegate below;
                // custom mock links contain the room ID in their query.
                return
            }
            openAcceptedRoom(roomID)
        }
    }

    @MainActor
    private func openAcceptedRoom(_ roomID: UUID) {
        Task {
            guard await AppComposition.store.waitForRoom(id: roomID) else { return }
            var profile = UserProfile.load()
            var name = profile.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                name = "Friend"
                profile.name = name
                profile.save()
            }
            AppComposition.store.joinFromInvite(named: name, emoji: profile.avatar, roomID: roomID)
            isShowingSplash = false
            hasCompletedOnboarding = true
            inviteRoomID = roomID
        }
    }
}

/// Registers for CloudKit silent pushes and routes CKShare acceptance.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        NotificationCenter.default.post(name: .splitrOpenURL, object: url)
        return true
    }

    /// nonisolated: UIKit delivers this off the main actor, and the payload
    /// dictionary is not Sendable — parse it here and cross isolation with
    /// nothing but Sendable values.
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.notificationType == .database else {
            return .noData
        }
        let fetched = await AppComposition.refetchFromPush()
        return fetched ? .newData : .noData
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Member taps a share link → the system hands us CKShare metadata here.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        guard let url = URLContexts.first?.url else { return }
        NotificationCenter.default.post(name: .splitrOpenURL, object: url)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            guard let cloudStore = AppComposition.cloudStore else { return }
            await cloudStore.acceptShare(metadata: cloudKitShareMetadata)
            let zoneName = cloudKitShareMetadata.rootRecordID.zoneID.zoneName
            let prefix = "room-"
            guard zoneName.hasPrefix(prefix),
                  let roomID = UUID(uuidString: String(zoneName.dropFirst(prefix.count))) else {
                return
            }
            NotificationCenter.default.post(
                name: .splitrAcceptedShare,
                object: roomID
            )
        }
    }
}
