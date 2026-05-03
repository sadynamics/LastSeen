//
//  TrackedNumberDetailView.swift
//

import Charts
import SwiftUI

struct TrackedNumberDetailView: View {
    @Environment(TrackingService.self) private var tracking
    let trackedNumber: TrackedNumber

    @State private var sessionsToday: SessionsForDay?
    @State private var weekly: WeeklyReport?
    @State private var prefs: NotificationPrefs
    @State private var isLoading = true

    init(trackedNumber: TrackedNumber) {
        self.trackedNumber = trackedNumber
        self._prefs = State(initialValue: trackedNumber.prefs ?? NotificationPrefs(
            onlineEnabled: true,
            offlineEnabled: false,
            sessionEndedEnabled: true,
            dailySummaryEnabled: true,
            quietHoursStart: nil,
            quietHoursEnd: nil,
            timezone: TimeZone.current.identifier
        ))
    }

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    if let sessionsToday {
                        todayCard(sessionsToday)
                    }
                    if let weekly {
                        weeklyCard(weekly)
                    }
                    notificationsCard
                    removeButton
                }
                .padding(Theme.Spacing.lg)
            }
            if isLoading && sessionsToday == nil {
                ProgressView().tint(Theme.Color.accent)
            }
        }
        .navigationTitle(trackedNumber.displayName ?? trackedNumber.e164)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        Card {
            HStack(spacing: Theme.Spacing.lg) {
                Avatar(initials: String(
                    (trackedNumber.displayName ?? trackedNumber.e164).prefix(2)
                ).uppercased())
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trackedNumber.displayName ?? trackedNumber.e164)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.Color.primaryText)
                    Text(trackedNumber.e164)
                        .font(.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                    let live = tracking.liveStatuses[trackedNumber.id]
                    StatusPill(
                        isOnline: live?.isOnline ?? false,
                        label: liveLabel(live)
                    )
                    .padding(.top, 4)
                }
                Spacer()
            }
        }
    }

    private func todayCard(_ sessions: SessionsForDay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(Theme.Color.primaryText)
                    Spacer()
                    Text(sessions.totalOnlineSeconds.asDuration)
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(Theme.Color.online)
                }
                if sessions.sessions.isEmpty {
                    Text("No activity yet today.")
                        .font(.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                } else {
                    todayTimeline(sessions)
                    Divider().background(Theme.Color.surfaceElevated)
                    HStack {
                        StatChip(title: "Sessions", value: "\(sessions.sessionCount)")
                        StatChip(title: "Avg", value: avgPerSession(sessions))
                    }
                    sessionList(sessions)
                }
            }
        }
    }

    private func todayTimeline(_ sessions: SessionsForDay) -> some View {
        let day = ISO8601DateFormatter.dayParser.date(from: sessions.day + "T00:00:00Z") ?? Calendar.current.startOfDay(for: .now)
        let endOfDay = day.addingTimeInterval(86_400)
        return Chart {
            ForEach(Array(sessions.sessions.enumerated()), id: \.offset) { _, s in
                BarMark(
                    xStart: .value("Start", s.start),
                    xEnd: .value("End", s.end),
                    y: .value("Row", "Online")
                )
                .foregroundStyle(Theme.Color.online)
                .cornerRadius(2)
            }
        }
        .chartXScale(domain: day...endOfDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(Theme.Color.tertiaryText)
                AxisGridLine()
                    .foregroundStyle(Theme.Color.surfaceElevated)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 36)
    }

    private func sessionList(_ sessions: SessionsForDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sessions.sessions.enumerated()), id: \.offset) { _, s in
                HStack {
                    Text(s.start, format: .dateTime.hour().minute())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Text("→")
                        .foregroundStyle(Theme.Color.tertiaryText)
                    Text(s.end, format: .dateTime.hour().minute())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Spacer()
                    Text(s.durationSeconds.asDuration)
                        .foregroundStyle(Theme.Color.primaryText)
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func weeklyCard(_ weekly: WeeklyReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Last 7 days")
                        .font(.headline)
                        .foregroundStyle(Theme.Color.primaryText)
                    Spacer()
                    Text(weekly.totalOnlineSeconds.asDuration)
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(Theme.Color.online)
                }
                Chart(weekly.days) { day in
                    BarMark(
                        x: .value("Day", day.day),
                        y: .value("Minutes", day.totalOnlineSeconds / 60)
                    )
                    .foregroundStyle(Theme.Color.accent.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Theme.Color.tertiaryText)
                        AxisGridLine().foregroundStyle(Theme.Color.surfaceElevated)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel().foregroundStyle(Theme.Color.tertiaryText)
                    }
                }
                .frame(height: 160)
                HStack {
                    StatChip(title: "Daily avg", value: weekly.averagePerDaySeconds.asDuration)
                    StatChip(title: "Sessions", value: "\(weekly.days.reduce(0) { $0 + $1.sessionCount })")
                }
            }
        }
    }

    private var notificationsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Notifications")
                    .font(.headline)
                    .foregroundStyle(Theme.Color.primaryText)
                Toggle("Online", isOn: prefBinding(\.onlineEnabled))
                    .tint(Theme.Color.accent)
                Toggle("Session ended", isOn: prefBinding(\.sessionEndedEnabled))
                    .tint(Theme.Color.accent)
                Toggle("Daily summary", isOn: prefBinding(\.dailySummaryEnabled))
                    .tint(Theme.Color.accent)
            }
            .foregroundStyle(Theme.Color.primaryText)
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            Task { try? await tracking.remove(trackedNumber.id) }
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Remove this number")
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.Color.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Color.danger.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func prefBinding(_ kp: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: kp] },
            set: { newValue in
                prefs[keyPath: kp] = newValue
                Task {
                    if let updated = try? await tracking.updatePrefs(for: trackedNumber.id, prefs: prefs) {
                        prefs = updated
                    }
                }
            }
        )
    }

    private func liveLabel(_ live: LiveStatus?) -> String {
        guard let live else { return "Loading..." }
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
        return "No activity yet"
    }

    private func avgPerSession(_ sessions: SessionsForDay) -> String {
        guard sessions.sessionCount > 0 else { return "—" }
        return (sessions.totalOnlineSeconds / sessions.sessionCount).asDuration
    }

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        let today = Date.now.iso8601Day
        async let s = try? tracking.sessions(for: trackedNumber.id, day: today)
        async let w = try? tracking.weeklyReport(for: trackedNumber.id)
        sessionsToday = await s
        weekly = await w
    }
}

private struct StatChip: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Color.tertiaryText)
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(Theme.Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Color.surfaceElevated)
        )
    }
}

extension Date {
    var iso8601Day: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: self)
    }
}

extension ISO8601DateFormatter {
    static let dayParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
