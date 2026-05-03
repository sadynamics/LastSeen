//
//  LastSeenApp.swift
//  LastSeen
//

import SwiftUI

@main
struct LastSeenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.auth)
                .environment(dependencies.subscriptions)
                .environment(dependencies.tracking)
                .environment(dependencies.notifications)
                .preferredColorScheme(.dark)
                .task {
                    await dependencies.bootstrap()
                    if let pending = AppDelegate.pendingToken {
                        await dependencies.notifications.handleAPNsToken(pending)
                        AppDelegate.pendingToken = nil
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .apnsTokenReceived)) { note in
                    if let data = note.object as? Data {
                        Task { await dependencies.notifications.handleAPNsToken(data) }
                    }
                }
        }
    }
}
