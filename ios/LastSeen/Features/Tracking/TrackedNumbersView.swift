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
                Theme.Color.background.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if canAddMore { showingAdd = true } else { showingPaywall = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.Color.accent)
                    }
                }
            }
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
        }
    }

    private var canAddMore: Bool {
        // Free tier: 1 tracked number; subscription required for more.
        if subscriptions.isSubscribed { return true }
        return tracking.trackedNumbers.count < 1
    }

    @ViewBuilder
    private var contentBody: some View {
        if tracking.trackedNumbers.isEmpty {
            EmptyState(
                systemImage: "person.crop.circle.badge.plus",
                title: "No numbers yet",
                message: "Add a phone number to start tracking WhatsApp activity."
            )
            .overlay(alignment: .bottom) {
                PrimaryButton(title: "Add a number", systemImage: "plus") {
                    showingAdd = true
                }
                .padding(Theme.Spacing.xl)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(tracking.trackedNumbers) { tn in
                        Button { pickedTrackedNumber = tn } label: {
                            TrackedNumberRow(
                                trackedNumber: tn,
                                live: tracking.liveStatuses[tn.id]
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { try? await tracking.remove(tn.id) }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }
}

struct TrackedNumberRow: View {
    let trackedNumber: TrackedNumber
    let live: LiveStatus?

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.lg) {
                Avatar(initials: initials)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trackedNumber.displayName ?? trackedNumber.e164)
                        .font(.headline)
                        .foregroundStyle(Theme.Color.primaryText)
                    if trackedNumber.displayName != nil {
                        Text(trackedNumber.e164)
                            .font(.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    StatusPill(isOnline: live?.isOnline ?? false, label: statusLabel)
                        .padding(.top, 2)
                }
                Spacer()
                if !(trackedNumber.scraperAccount?.status.isReady ?? true) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Color.warning)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
    }

    private var initials: String {
        if let name = trackedNumber.displayName, !name.isEmpty {
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

struct Avatar: View {
    let initials: String
    var body: some View {
        ZStack {
            Circle().fill(Theme.Color.surfaceElevated)
            Text(initials)
                .font(.headline)
                .foregroundStyle(Theme.Color.primaryText)
        }
        .frame(width: 44, height: 44)
    }
}
