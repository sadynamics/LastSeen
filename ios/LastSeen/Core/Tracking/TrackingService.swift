//
//  TrackingService.swift
//

import Foundation
import Observation

@MainActor
@Observable
final class TrackingService {
    private(set) var trackedNumbers: [TrackedNumber] = []
    private(set) var liveStatuses: [String: LiveStatus] = [:]
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private let api: APIClient
    private var pollTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list: TrackedNumbersList = try await api.get("/v1/tracked-numbers")
            trackedNumbers = list.items
            LSAnalytics.shared.setTrackedNumberCount(trackedNumbers.count)
            await refreshLiveStatuses()
        } catch APIError.unauthorized {
            trackedNumbers = []
        } catch {
            lastError = error.localizedDescription
            LSAnalytics.shared.logError(error, context: ["operation": "tracked_numbers_refresh"])
        }
    }

    func add(phone: String, defaultCountry: String?, displayName: String?) async throws -> TrackedNumber {
        let body = CreateTrackedNumberRequest(phone: phone, defaultCountry: defaultCountry, displayName: displayName)
        do {
            let resp: TrackedNumberWrapper = try await api.post("/v1/tracked-numbers", body: body)
            LSAnalytics.shared.log(.trackedNumberAdded(country: defaultCountry))
            await refresh()
            return resp.item
        } catch {
            LSAnalytics.shared.logError(error, context: ["operation": "tracked_number_add",
                                                          "country": defaultCountry ?? "unknown"])
            throw error
        }
    }

    func remove(_ trackedNumberId: String) async throws {
        do {
            try await api.delete("/v1/tracked-numbers/\(trackedNumberId)")
            trackedNumbers.removeAll { $0.id == trackedNumberId }
            liveStatuses.removeValue(forKey: trackedNumberId)
            LSAnalytics.shared.log(.trackedNumberRemoved)
            LSAnalytics.shared.setTrackedNumberCount(trackedNumbers.count)
        } catch {
            LSAnalytics.shared.logError(error, context: ["operation": "tracked_number_remove"])
            throw error
        }
    }

    func sessions(for trackedNumberId: String, day: String) async throws -> SessionsForDay {
        try await api.get("/v1/tracked-numbers/\(trackedNumberId)/sessions",
                          query: [URLQueryItem(name: "day", value: day)])
    }

    func weeklyReport(for trackedNumberId: String) async throws -> WeeklyReport {
        try await api.get("/v1/tracked-numbers/\(trackedNumberId)/reports/weekly")
    }

    func updatePrefs(for trackedNumberId: String, prefs: NotificationPrefs) async throws -> NotificationPrefs {
        do {
            let resp: PrefsWrapper = try await api.put("/v1/tracked-numbers/\(trackedNumberId)/notifications", body: prefs)
            if let idx = trackedNumbers.firstIndex(where: { $0.id == trackedNumberId }) {
                trackedNumbers[idx].prefs = resp.prefs
            }
            return resp.prefs
        } catch {
            LSAnalytics.shared.logError(error, context: ["operation": "update_notification_prefs"])
            throw error
        }
    }

    func startPolling(intervalSeconds: TimeInterval = 20) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                if Task.isCancelled { break }
                await self?.refreshLiveStatuses()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshLiveStatuses() async {
        let ids = trackedNumbers.map(\.id)
        await withTaskGroup(of: (String, LiveStatus?).self) { group in
            for id in ids {
                group.addTask { @MainActor [api] in
                    do {
                        let status: LiveStatus = try await api.get("/v1/tracked-numbers/\(id)/live")
                        return (id, status)
                    } catch {
                        return (id, nil)
                    }
                }
            }
            for await (id, status) in group {
                if let status { liveStatuses[id] = status }
            }
        }
    }
}
