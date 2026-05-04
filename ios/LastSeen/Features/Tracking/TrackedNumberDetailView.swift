//
//  TrackedNumberDetailView.swift
//

import Charts
import Combine
import SwiftUI

struct TrackedNumberDetailView: View {
    @Environment(TrackingService.self) private var tracking
    let trackedNumber: TrackedNumber

    @State private var sessionsToday: SessionsForDay?
    @State private var weekly: WeeklyReport?
    @State private var prefs: NotificationPrefs
    @State private var isLoading = true
    @State private var liveTick: Date = .now

    private let liveTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

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
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    heroCard
                    if let sessionsToday {
                        todayCard(sessionsToday)
                    }
                    if let weekly {
                        weeklyCard(weekly)
                    }
                    notificationsCard
                    removeButton
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            if isLoading && sessionsToday == nil {
                ProgressView().tint(Theme.Color.accent)
            }
        }
        .navigationTitle(trackedNumber.displayName ?? trackedNumber.e164)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .onReceive(liveTimer) { liveTick = $0 }
        .trackScreen("tracked_number_detail", className: "TrackedNumberDetailView")
        .onAppear { LSAnalytics.shared.log(.trackedNumberDetailViewed) }
    }

    // MARK: Hero

    private var heroCard: some View {
        let live = tracking.liveStatuses[trackedNumber.id]
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    GradientAvatar(initials: initials,
                                   seed: trackedNumber.e164,
                                   size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trackedNumber.displayName ?? trackedNumber.e164)
                            .font(Theme.Font.title3)
                            .foregroundStyle(Theme.Color.primaryText)
                            .lineLimit(1)
                        Text(trackedNumber.e164)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    Spacer()
                }

                Divider().background(Theme.Color.separator)

                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    GlowingDot(isOn: live?.isOnline ?? false, size: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(liveTitle(live))
                            .font(Theme.Font.headline)
                            .foregroundStyle(live?.isOnline == true ? Theme.Color.online : Theme.Color.primaryText)
                        Text(liveSubtitle(live))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    Spacer()
                }
            }
        }
    }

    private func liveTitle(_ live: LiveStatus?) -> String {
        guard let live else { return "Loading…" }
        if live.isOnline {
            if let since = live.onlineSince {
                let secs = Int(liveTick.timeIntervalSince(since))
                return "Online for \(secs.asDuration)"
            }
            return "Online"
        }
        if let secs = live.lastSeenSecondsAgo {
            return "Last seen \(secs.asDuration) ago"
        }
        return "No activity yet"
    }

    private func liveSubtitle(_ live: LiveStatus?) -> String {
        if live?.isOnline == true { return "Currently active on WhatsApp" }
        if live?.lastEventAt != nil { return "Updated continuously" }
        return "Activity will appear here once detected"
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

    // MARK: Today

    private func todayCard(_ sessions: SessionsForDay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Today", subtitle: nil)
                    Spacer()
                    Text(sessions.totalOnlineSeconds.asDuration)
                        .font(Theme.Font.numericMedium)
                        .foregroundStyle(Theme.Color.online)
                }
                if sessions.sessions.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(Theme.Color.tertiaryText)
                        Text("No activity yet today.")
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                } else {
                    todayTimeline(sessions)
                    HStack(spacing: Theme.Spacing.md) {
                        StatTile(label: "Sessions",
                                 value: "\(sessions.sessionCount)",
                                 systemImage: "list.bullet",
                                 tint: Theme.Color.accent)
                        StatTile(label: "Avg session",
                                 value: avgPerSession(sessions),
                                 systemImage: "stopwatch.fill",
                                 tint: Theme.Color.accentSecondary)
                    }
                    sessionList(sessions)
                }
            }
        }
    }

    private func todayTimeline(_ sessions: SessionsForDay) -> some View {
        let day = ISO8601DateFormatter.dayParser.date(from: sessions.day + "T00:00:00Z") ?? Calendar.current.startOfDay(for: .now)
        let endOfDay = day.addingTimeInterval(86_400)
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(Array(sessions.sessions.enumerated()), id: \.offset) { _, s in
                    BarMark(
                        xStart: .value("Start", s.start),
                        xEnd: .value("End", s.end),
                        y: .value("Row", "Online")
                    )
                    .foregroundStyle(Theme.Gradient.online)
                    .cornerRadius(3)
                }
            }
            .chartXScale(domain: day...endOfDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(Theme.Color.tertiaryText)
                    AxisGridLine()
                        .foregroundStyle(Theme.Color.separator)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 38)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func sessionList(_ sessions: SessionsForDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent sessions".uppercased())
                .font(Theme.Font.label)
                .tracking(1.0)
                .foregroundStyle(Theme.Color.tertiaryText)
                .padding(.top, 4)
            ForEach(Array(sessions.sessions.enumerated()), id: \.offset) { _, s in
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(Theme.Color.online)
                        .frame(width: 6, height: 6)
                    Text(s.start, format: .dateTime.hour().minute())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.Color.tertiaryText)
                    Text(s.end, format: .dateTime.hour().minute())
                        .foregroundStyle(Theme.Color.secondaryText)
                    Spacer()
                    Text(s.durationSeconds.asDuration)
                        .foregroundStyle(Theme.Color.primaryText)
                        .monospacedDigit()
                }
                .font(Theme.Font.caption)
            }
        }
    }

    // MARK: Weekly

    private func weeklyCard(_ weekly: WeeklyReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Last 7 days", subtitle: nil)
                    Spacer()
                    Text(weekly.totalOnlineSeconds.asDuration)
                        .font(Theme.Font.numericMedium)
                        .foregroundStyle(Theme.Color.online)
                }
                Chart(weekly.days) { day in
                    BarMark(
                        x: .value("Day", day.day),
                        y: .value("Minutes", day.totalOnlineSeconds / 60)
                    )
                    .foregroundStyle(Theme.Gradient.primaryButton)
                    .cornerRadius(6)
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Theme.Color.tertiaryText)
                        AxisGridLine().foregroundStyle(Theme.Color.separator)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel().foregroundStyle(Theme.Color.tertiaryText)
                    }
                }
                .frame(height: 160)

                HStack(spacing: Theme.Spacing.md) {
                    StatTile(label: "Daily avg",
                             value: weekly.averagePerDaySeconds.asDuration,
                             systemImage: "calendar",
                             tint: Theme.Color.accent)
                    StatTile(label: "Sessions",
                             value: "\(weekly.days.reduce(0) { $0 + $1.sessionCount })",
                             systemImage: "rectangle.stack.fill",
                             tint: Theme.Color.accentSecondary)
                }
            }
        }
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Notifications",
                              subtitle: "Pick what you want to be notified about.")
                toggleRow(icon: "circle.fill", tint: Theme.Color.online,
                          title: "Online", binding: prefBinding(\.onlineEnabled))
                Divider().background(Theme.Color.separator)
                toggleRow(icon: "checkmark.circle.fill", tint: Theme.Color.accent,
                          title: "Session ended", binding: prefBinding(\.sessionEndedEnabled))
                Divider().background(Theme.Color.separator)
                toggleRow(icon: "sun.max.fill", tint: Theme.Color.tintAmber,
                          title: "Daily summary", binding: prefBinding(\.dailySummaryEnabled))
            }
        }
    }

    private func toggleRow(icon: String, tint: Color, title: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconBadge(systemImage: icon, tint: tint, size: 32)
            Text(title)
                .font(Theme.Font.callout.weight(.medium))
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(Theme.Color.accent)
        }
    }

    // MARK: Remove

    private var removeButton: some View {
        Button(role: .destructive) {
            Task { try? await tracking.remove(trackedNumber.id) }
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Remove this number")
                    .font(Theme.Font.headline)
            }
            .foregroundStyle(Theme.Color.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Color.danger.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Color.danger.opacity(0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScalePressStyle())
    }

    // MARK: Helpers

    private func prefBinding(_ kp: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: kp] },
            set: { newValue in
                prefs[keyPath: kp] = newValue
                LSAnalytics.shared.log(.notificationPrefChanged(name: prefName(for: kp), enabled: newValue))
                Task {
                    if let updated = try? await tracking.updatePrefs(for: trackedNumber.id, prefs: prefs) {
                        prefs = updated
                    }
                }
            }
        )
    }

    private func prefName(for kp: WritableKeyPath<NotificationPrefs, Bool>) -> String {
        switch kp {
        case \NotificationPrefs.onlineEnabled: return "online"
        case \NotificationPrefs.offlineEnabled: return "offline"
        case \NotificationPrefs.sessionEndedEnabled: return "session_ended"
        case \NotificationPrefs.dailySummaryEnabled: return "daily_summary"
        default: return "unknown"
        }
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

// MARK: - Date helpers (kept here to avoid touching unrelated files)

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
