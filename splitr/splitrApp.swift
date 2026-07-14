//
//  splitrApp.swift
//  splitr
//

import CloudKit
import SwiftUI
import SplitBillSync

/// Composition root: one place decides which `RoomStoring` the app runs on.
/// Simulator → mock store with demo rooms (no iCloud account needed);
/// device → CloudKit-backed store. Previews construct `MockRoomStore`
/// directly.
@MainActor
enum AppComposition {
    static let store: any RoomStoring = {
        #if targetEnvironment(simulator)
        MockRoomStore(rooms: MockData.rooms())
        #else
        CloudKitRoomStore()
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

    var body: some Scene {
        WindowGroup {
            RoomListView(store: AppComposition.store)
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
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await AppComposition.cloudStore?.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
