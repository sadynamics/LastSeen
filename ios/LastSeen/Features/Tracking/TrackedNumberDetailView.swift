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
    @State private var chartsAppeared = false
    @State private var selectedSession: DaySession?

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
                    if let weekly, let sessionsToday {
                        insightsCard(weekly: weekly, today: sessionsToday)
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

    // MARK: - Hero

    private var heroCard: some View {
        let live = tracking.liveStatuses[trackedNumber.id]
        let isOnline = live?.isOnline == true
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ZStack(alignment: .bottomTrailing) {
                        GradientAvatar(initials: initials,
                                       seed: trackedNumber.e164,
                                       size: 72)
                        Circle()
                            .fill(isOnline ? Theme.Color.online : Theme.Color.offline)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(Theme.Color.surface, lineWidth: 3)
                            )
                            .ds(shadow: isOnline ? .onlineGlow : Theme.Shadow(color: .clear, radius: 0, x: 0, y: 0))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trackedNumber.displayName ?? trackedNumber.e164)
                            .font(Theme.Font.title3)
                            .foregroundStyle(Theme.Color.primaryText)
                            .lineLimit(1)
                        Text(trackedNumber.e164)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                            .monospacedDigit()
                        StatusPill(isOnline: isOnline, label: heroPillLabel(live))
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }

                liveBigStatus(live)
            }
        }
    }

    private func liveBigStatus(_ live: LiveStatus?) -> some View {
        let isOnline = live?.isOnline == true
        return VStack(alignment: .leading, spacing: 6) {
            Text(isOnline ? "ONLINE NOW" : "LAST SEEN")
                .font(Theme.Font.label)
                .tracking(1.2)
                .foregroundStyle(isOnline ? Theme.Color.online.opacity(0.85) : Theme.Color.tertiaryText)
            Text(bigLiveText(live))
                .font(Theme.Font.numericLarge)
                .foregroundStyle(isOnline ? Theme.Color.online : Theme.Color.primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: bigLiveText(live))
            Text(liveSubtitle(live))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(isOnline
                      ? Theme.Color.online.opacity(0.10)
                      : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(isOnline
                        ? Theme.Color.online.opacity(0.30)
                        : Color.white.opacity(0.06),
                        lineWidth: 0.5)
        )
    }

    private func heroPillLabel(_ live: LiveStatus?) -> String {
        guard let live else { return "Loading…" }
        if live.isOnline { return "Online" }
        if live.lastEventAt != nil { return "Offline" }
        return "Waiting for activity"
    }

    private func bigLiveText(_ live: LiveStatus?) -> String {
        guard let live else { return "—" }
        if live.isOnline {
            if let since = live.onlineSince {
                let secs = Int(liveTick.timeIntervalSince(since))
                return secs.asDuration
            }
            return "Online"
        }
        if let secs = live.lastSeenSecondsAgo {
            return "\(secs.asDuration) ago"
        }
        return "—"
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

    // MARK: - Today

    private func todayCard(_ sessions: SessionsForDay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Today", subtitle: nil)
                    Spacer()
                    Text(sessions.totalOnlineSeconds.asDuration)
                        .font(Theme.Font.numericMedium)
                        .foregroundStyle(Theme.Color.online)
                        .contentTransition(.numericText())
                }
                if sessions.sessions.isEmpty {
                    emptyToday
                } else {
                    todayTimeline(sessions)
                    hourlyHeatmap(sessions)
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

    private var emptyToday: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(Theme.Color.tertiaryText)
            Text("No activity yet today")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.secondaryText)
            Text("Sessions will appear here as soon as they go online.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    /// Horizontal 24-hour timeline with all of today's sessions as
    /// gradient-filled bars, plus a "now" rule mark and the ability to tap
    /// any session to see its details.
    private func todayTimeline(_ sessions: SessionsForDay) -> some View {
        let day = ISO8601DateFormatter.dayParser.date(from: sessions.day + "T00:00:00Z")
            ?? Calendar.current.startOfDay(for: .now)
        let endOfDay = day.addingTimeInterval(86_400)
        let nowInRange = Date.now >= day && Date.now <= endOfDay

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Color.accentLight)
                Text("Activity timeline")
                    .font(Theme.Font.label)
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.tertiaryText)
                Spacer()
                if let s = selectedSession {
                    Text("\(s.start, format: .dateTime.hour().minute()) → \(s.end, format: .dateTime.hour().minute())")
                        .font(Theme.Font.captionMono)
                        .foregroundStyle(Theme.Color.primaryText)
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(Array(sessions.sessions.enumerated()), id: \.offset) { _, s in
                    BarMark(
                        xStart: .value("Start", s.start),
                        xEnd: .value("End", s.end),
                        y: .value("Row", "Online")
                    )
                    .foregroundStyle(Theme.Gradient.online)
                    .cornerRadius(4)
                    .opacity(chartsAppeared ? 1 : 0)
                }
                if nowInRange {
                    RuleMark(x: .value("Now", liveTick))
                        .foregroundStyle(Theme.Color.accentLight.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            Text("now")
                                .font(Theme.Font.label)
                                .tracking(0.8)
                                .foregroundStyle(Theme.Color.accentLight)
                        }
                }
            }
            .chartXScale(domain: day...endOfDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(Theme.Color.tertiaryText)
                    AxisGridLine()
                        .foregroundStyle(Theme.Color.separator)
                }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xInPlot: CGFloat
                                    if let plotAnchor = proxy.plotFrame {
                                        xInPlot = value.location.x - geo[plotAnchor].origin.x
                                    } else {
                                        xInPlot = value.location.x
                                    }
                                    guard let tapped: Date = proxy.value(atX: xInPlot) else { return }
                                    selectedSession = sessions.sessions.first(where: { tapped >= $0.start && tapped <= $0.end })
                                }
                                .onEnded { _ in
                                    // Keep the selection visible briefly, then clear.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedSession = nil
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: 44)
            .animation(.easeOut(duration: 0.6), value: chartsAppeared)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }

    /// 24-cell heatmap: one cell per hour, intensity = minutes online in that
    /// hour. Highlights the contact's daily rhythm at a glance.
    private func hourlyHeatmap(_ sessions: SessionsForDay) -> some View {
        let buckets = hourlyMinutes(for: sessions)
        let peak = max(1, buckets.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Color.accentSecondary)
                Text("Hourly intensity")
                    .font(Theme.Font.label)
                    .tracking(1.0)
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let cellW = (geo.size.width - spacing * 23) / 24
                HStack(spacing: spacing) {
                    ForEach(0..<24, id: \.self) { hour in
                        let mins = buckets[hour]
                        let intensity = Double(mins) / Double(peak)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(heatmapColor(intensity: intensity))
                            .frame(width: cellW, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                    }
                }
            }
            .frame(height: 28)
            HStack {
                Text("12a")
                Spacer()
                Text("6a")
                Spacer()
                Text("12p")
                Spacer()
                Text("6p")
                Spacer()
                Text("12a")
            }
            .font(Theme.Font.label)
            .tracking(0.6)
            .foregroundStyle(Theme.Color.tertiaryText)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func heatmapColor(intensity: Double) -> Color {
        if intensity <= 0.001 { return Color.white.opacity(0.045) }
        return Theme.Color.online.opacity(0.18 + intensity * 0.72)
    }

    private func sessionList(_ sessions: SessionsForDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent sessions".uppercased())
                .font(Theme.Font.label)
                .tracking(1.0)
                .foregroundStyle(Theme.Color.tertiaryText)
                .padding(.top, 4)
            ForEach(Array(sessions.sessions.reversed().prefix(5).enumerated()), id: \.offset) { _, s in
                HStack(spacing: Theme.Spacing.sm) {
                    Capsule()
                        .fill(Theme.Gradient.online)
                        .frame(width: 3, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(s.start, format: .dateTime.hour().minute())  →  \(s.end, format: .dateTime.hour().minute())")
                            .font(Theme.Font.callout.weight(.medium))
                            .foregroundStyle(Theme.Color.primaryText)
                            .monospacedDigit()
                        Text(s.start.relativeShort)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                    }
                    Spacer()
                    Text(s.durationSeconds.asDuration)
                        .font(Theme.Font.callout.weight(.semibold))
                        .foregroundStyle(Theme.Color.online)
                        .monospacedDigit()
                }
            }
            if sessions.sessions.count > 5 {
                Text("+\(sessions.sessions.count - 5) more session\(sessions.sessions.count - 5 == 1 ? "" : "s") earlier today")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.tertiaryText)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Weekly

    private func weeklyCard(_ weekly: WeeklyReport) -> some View {
        let avgMinutes = Double(weekly.averagePerDaySeconds) / 60.0
        let todayKey = Date.now.iso8601Day
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Last 7 days", subtitle: nil)
                    Spacer()
                    Text(weekly.totalOnlineSeconds.asDuration)
                        .font(Theme.Font.numericMedium)
                        .foregroundStyle(Theme.Color.online)
                        .contentTransition(.numericText())
                }
                Chart {
                    ForEach(weekly.days) { day in
                        let mins = Double(day.totalOnlineSeconds) / 60.0
                        BarMark(
                            x: .value("Day", weekdayLabel(day.day)),
                            y: .value("Minutes", chartsAppeared ? mins : 0)
                        )
                        .foregroundStyle(
                            day.day == todayKey
                                ? Theme.Gradient.online
                                : Theme.Gradient.primaryButton
                        )
                        .cornerRadius(8)
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            if mins > 0 {
                                Text(day.totalOnlineSeconds.asDuration)
                                    .font(Theme.Font.label)
                                    .tracking(0.5)
                                    .foregroundStyle(Theme.Color.secondaryText)
                                    .opacity(chartsAppeared ? 1 : 0)
                            }
                        }
                    }
                    if avgMinutes > 0 {
                        RuleMark(y: .value("Avg", avgMinutes))
                            .foregroundStyle(Theme.Color.accentLight.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                                Text("avg")
                                    .font(Theme.Font.label)
                                    .tracking(0.6)
                                    .foregroundStyle(Theme.Color.accentLight.opacity(0.8))
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.Color.tertiaryText)
                            .font(Theme.Font.label)
                        AxisGridLine()
                            .foregroundStyle(Theme.Color.separator)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Theme.Color.secondaryText)
                            .font(Theme.Font.label)
                    }
                }
                .frame(height: 200)
                .animation(.spring(response: 0.65, dampingFraction: 0.85), value: chartsAppeared)

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

    // MARK: - Insights

    private func insightsCard(weekly: WeeklyReport, today: SessionsForDay) -> some View {
        let busiest = weekly.days.max(by: { $0.totalOnlineSeconds < $1.totalOnlineSeconds })
        let peakHour = mostFrequentPeakHour(weekly.days)
        let longestToday = today.sessions.map(\.durationSeconds).max() ?? 0
        let activeDays = weekly.days.filter { $0.totalOnlineSeconds > 0 }.count

        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Insights",
                              subtitle: "Patterns from the last 7 days.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                                    GridItem(.flexible(), spacing: Theme.Spacing.md)],
                          spacing: Theme.Spacing.md) {
                    insightTile(icon: "sun.max.fill",
                                tint: Theme.Color.tintAmber,
                                label: "Peak hour",
                                value: peakHour.map { hourLabel($0) } ?? "—")
                    insightTile(icon: "flame.fill",
                                tint: Theme.Color.tintRose,
                                label: "Busiest day",
                                value: busiest.flatMap { d in
                                    d.totalOnlineSeconds > 0 ? weekdayLabelFull(d.day) : nil
                                } ?? "—")
                    insightTile(icon: "stopwatch.fill",
                                tint: Theme.Color.tintMint,
                                label: "Longest today",
                                value: longestToday > 0 ? longestToday.asDuration : "—")
                    insightTile(icon: "calendar.badge.checkmark",
                                tint: Theme.Color.accent,
                                label: "Active days",
                                value: "\(activeDays) / 7")
                }
            }
        }
    }

    private func insightTile(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconBadge(systemImage: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Theme.Font.label)
                    .tracking(0.8)
                    .foregroundStyle(Theme.Color.tertiaryText)
                Text(value)
                    .font(Theme.Font.callout.weight(.semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Notifications

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

    // MARK: - Remove

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

    // MARK: - Helpers

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

    /// Convert today's sessions into per-hour online-minutes (24-element array).
    /// Sessions that span hour boundaries are split proportionally.
    private func hourlyMinutes(for sessions: SessionsForDay) -> [Int] {
        var buckets = Array(repeating: 0, count: 24)
        let cal = Calendar(identifier: .gregorian)
        for s in sessions.sessions {
            var cursor = s.start
            while cursor < s.end {
                let hour = cal.component(.hour, from: cursor)
                let nextHour = cal.date(bySettingHour: hour, minute: 0, second: 0, of: cursor)?
                    .addingTimeInterval(3600) ?? s.end
                let chunkEnd = min(nextHour, s.end)
                let secs = Int(chunkEnd.timeIntervalSince(cursor))
                buckets[hour] += secs / 60
                cursor = chunkEnd
            }
        }
        return buckets
    }

    /// Short 3-letter weekday label for a YYYY-MM-DD day key.
    private func weekdayLabel(_ dayKey: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let date = f.date(from: dayKey) else { return dayKey }
        let out = DateFormatter()
        out.locale = Locale.autoupdatingCurrent
        out.dateFormat = "EE"
        return out.string(from: date)
    }

    /// Full weekday label, used in insight tiles.
    private func weekdayLabelFull(_ dayKey: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let date = f.date(from: dayKey) else { return dayKey }
        let out = DateFormatter()
        out.locale = Locale.autoupdatingCurrent
        out.dateFormat = "EEEE"
        return out.string(from: date)
    }

    /// Pretty hour label, e.g. "9a", "2p", "12a".
    private func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 12) == 0) ? 12 : (hour % 12)
        let suffix = hour < 12 ? "a" : "p"
        return "\(h)\(suffix)"
    }

    private func mostFrequentPeakHour(_ days: [WeeklyDay]) -> Int? {
        var counts: [Int: Int] = [:]
        for d in days {
            if let h = d.peakHour { counts[h, default: 0] += 1 }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        let today = Date.now.iso8601Day
        async let s = try? tracking.sessions(for: trackedNumber.id, day: today)
        async let w = try? tracking.weeklyReport(for: trackedNumber.id)
        sessionsToday = await s
        weekly = await w
        // Trigger one-shot chart entrance animations.
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) {
            chartsAppeared = true
        }
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
