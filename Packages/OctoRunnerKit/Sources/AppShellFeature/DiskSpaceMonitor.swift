import CoreModels
import Foundation
import Observation
import TelemetryKit

/// Local volume observations and opt-in alerts continue with app windows closed.
@MainActor
@Observable
public final class DiskSpaceMonitor {
    public private(set) var latestSnapshot: VolumeCapacitySnapshot?
    @ObservationIgnored private let preferences: AppPreferencesStore
    @ObservationIgnored private let notifications: AppNotificationsController
    @ObservationIgnored private let sampler: any VolumeCapacitySampling
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var episode: AppNotificationEvent?
    @ObservationIgnored private var delivered = false
    @ObservationIgnored private var thresholdBytes: Int64?

    public init(preferences: AppPreferencesStore, notifications: AppNotificationsController,
                sampler: any VolumeCapacitySampling = SystemVolumeCapacitySampler()) {
        self.preferences = preferences
        self.notifications = notifications
        self.sampler = sampler
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        latestSnapshot = nil
    }

    public func refresh() async {
        guard !Task.isCancelled, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let revision = generation
        let snapshot = await sampler.sample()
        guard !Task.isCancelled, revision == generation else { return }
        latestSnapshot = snapshot.flatMap { $0.isFresh(at: .now) ? $0 : nil }
        guard preferences.notificationPolicy.enabled, preferences.notificationPolicy.lowDiskSpace else {
            resetEpisode()
            thresholdBytes = nil
            return
        }
        // Missing data is neither low space nor evidence of recovery. Preference
        // changes above must still take effect when measurement is unavailable.
        guard let snapshot = latestSnapshot else { return }
        let threshold = Int64(preferences.storagePolicy.validated().minimumFreeSpaceGB) * 1_000_000_000
        if thresholdBytes != threshold {
            resetEpisode()
            thresholdBytes = threshold
        }
        if snapshot.availableBytes >= threshold + 2_000_000_000 {
            resetEpisode()
            return
        }
        guard snapshot.availableBytes < threshold, !delivered else { return }
        if episode == nil {
            let locale = preferences.language.locale
            let available = (Double(snapshot.availableBytes) / 1_000_000_000)
                .formatted(.number.precision(.fractionLength(1)).locale(locale))
            let limit = preferences.storagePolicy.minimumFreeSpaceGB.formatted(.number.locale(locale))
            episode = AppNotificationEvent(id: "low-disk-\(UUID().uuidString)", kind: .lowDiskSpace,
                title: AppLocalization.string("Low disk space", locale: locale),
                message: String(format: AppLocalization.string("%@ GB available on the home volume (warning threshold: %@ GB).", locale: locale),
                    locale: locale, available, limit))
        }
        guard let event = episode else { return }
        let published = await notifications.publish(event)
        guard !Task.isCancelled, revision == generation else { return }
        if published, episode?.id == event.id { delivered = true }
    }

    private func resetEpisode() {
        episode = nil
        delivered = false
    }
}
