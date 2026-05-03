//
//  MainTabView.swift
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TrackedNumbersView()
                .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.Color.accent)
    }
}
