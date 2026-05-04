//
//  TrackedNumbersView.swift
//

import SwiftUI

struct TrackedNumbersView: View {
    @Environment(TrackingService.self) private var tracking
    @Environment(SubscriptionService.self) private var subscriptions
    @State private var showingAdd = false
    @State private var showingPaywall = false
    @State private var pickedTrackedNumber: TrackedNumber?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                contentBody
                if !tracking.trackedNumbers.isEmpty {
                    fab
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await tracking.refresh() }
            .task {
                await tracking.refresh()
                tracking.startPolling()
            }
            .onDisappear { tracking.stopPolling() }
            .sheet(isPresented: $showingAdd) {
                AddNumberView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .navigationDestination(item: $pickedTrackedNumber) { tn in
                TrackedNumberDetailView(trackedNumber: tn)
            }
            .trackScreen("activity", className: "TrackedNumbersView")
        }
    }

    private var canAddMore: Bool {
        if subscriptions.isSubscribed { return true }
        return tracking.trackedNumbers.count < 1
    }

    private func handleAdd() {
        if canAddMore {
            LSAnalytics.shared.log(.addNumberOpened(source: "activity"))
            showingAdd = true
        } else {
            LSAnalytics.shared.log(.upgradeTapped(source: "add_number_blocked"))
            showingPaywall = true
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if tracking.trackedNumbers.isEmpty {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                EmptyState(
                    systemImage: "person.crop.circle.badge.plus",
                    title: "No numbers yet",
                    message: "Add a phone number to start tracking WhatsApp activity, online sessions, and weekly trends."
                )
                Spacer()
                PrimaryButton(title: "Add a number", systemImage: "plus") {
                    handleAdd()
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md, pinnedViews: []) {
                    overviewCard
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.sm)

                    SectionHeader(title: "Tracked numbers", subtitle: nil, trailing: nil)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.md)

                    ForEach(tracking.trackedNumbers) { tn in
                        Button { pickedTrackedNumber = tn } label: {
                            TrackedNumberRow(
                                trackedNumber: tn,
                                live: tracking.liveStatuses[tn.id]
                            )
                        }
                        .buttonStyle(ScalePressStyle(scale: 0.98))
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { try? await tracking.remove(tn.id) }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
    }

    // MARK: Overview hero

    private var overviewCard: some View {
        let online = tracking.trackedNumbers.filter { tracking.liveStatuses[$0.id]?.isOnline == true }.count
        let total = tracking.trackedNumbers.count

        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    IconBadge(systemImage: "waveform.path.ecg",
                              tint: Theme.Color.accent,
                              size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live activity")
                            .font(Theme.Font.headline)
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("Updated just now")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    Spacer()
                }

                HStack(spacing: Theme.Spacing.md) {
                    StatTile(label: "Tracked",
                             value: "\(total)",
                             systemImage: "person.2.fill",
                             tint: Theme.Color.accentSecondary)
                    StatTile(label: "Online now",
                             value: "\(online)",
                             systemImage: "circle.fill",
                             tint: Theme.Color.online)
                }
            }
        }
    }

    // MARK: Floating Action Button

    private var fab: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton(systemImage: "plus") {
                    handleAdd()
                }
                .padding(.trailing, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }
}

// MARK: - Row

struct TrackedNumberRow: View {
    let trackedNumber: TrackedNumber
    let live: LiveStatus?

    var body: some View {
        Card(padding: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                GradientAvatar(initials: initials,
                               seed: trackedNumber.e164,
                               size: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text(trackedNumber.displayName ?? trackedNumber.e164)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.primaryText)
                        .lineLimit(1)
                    if trackedNumber.displayName != nil {
                        Text(trackedNumber.e164)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    StatusPill(isOnline: live?.isOnline ?? false, label: statusLabel)
                }
                Spacer()
                if !(trackedNumber.scraperAccount?.status.isReady ?? true) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.Color.warning)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
    }

    private var initials: String {
        if let name = trackedNumber.displayName, !name.isEmpty {
            let parts = name.split(separator: " ")
            if parts.count >= 2,
               let first = parts.first?.first,
               let second = parts.dropFirst().first?.first {
                return "\(first)\(second)".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return String(trackedNumber.e164.suffix(2))
    }

    private var statusLabel: String {
        guard let live else { return "Just added" }
        if live.isOnline {
            if let since = live.onlineSince {
                let secs = Int(Date.now.timeIntervalSince(since))
                return "Online for \(secs.asDuration)"
            }
            return "Online"
        }
        if let secs = live.lastSeenSecondsAgo {
            return "Last seen \(secs.asDuration) ago"
        }
        return "Offline"
    }
}
