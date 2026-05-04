//
//  MainTabView.swift
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TrackedNumbersView()
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.Color.accentLight)
    }
}
