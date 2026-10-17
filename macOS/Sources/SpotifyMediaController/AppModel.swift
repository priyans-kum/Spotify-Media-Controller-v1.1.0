import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Monitoring is disabled"

    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var autoStartMonitoringEnabled = true

    let spotify = SpotifyController()
    private let audioMonitor = AudioMonitor()
    private let loginItemManager = LoginItemManager()

    private var pausedSpotifyByController = false
    private var autoStartTask: Task<Void, Never>?

    private let autoStartPreferenceKey =
        "SpotifyMediaController.AutoStartMonitoring"

    init() {
        launchAtLoginEnabled = loginItemManager.isEnabled

        let defaults = UserDefaults.standard

        if defaults.object(forKey: autoStartPreferenceKey) != nil {
            autoStartMonitoringEnabled =
                defaults.bool(forKey: autoStartPreferenceKey)
        } else {
            // Enable automatic monitoring by default.
            autoStartMonitoringEnabled = true
            defaults.set(true, forKey: autoStartPreferenceKey)
        }

        audioMonitor.onAudioActivityChanged = { [weak self] active in
            Task { @MainActor [weak self] in
                self?.updateOtherAudioDetected(active)
            }
        }

        audioMonitor.onStatusChanged = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.statusText = message
            }
        }

        if autoStartMonitoringEnabled {
            startAutomaticMonitoring()
        }
    }

    // MARK: - Monitoring

    func toggleEnabled() {
        if isEnabled {
            autoStartTask?.cancel()
            autoStartTask = nil

            audioMonitor.stop()
            isEnabled = false

            resumeSpotifyIfWePausedIt()
            statusText = "Monitoring disabled"
            return
        }

        startMonitoring()
    }

    @discardableResult
    private func startMonitoring() -> Bool {
        guard !isEnabled else {
            return true
        }

        guard audioMonitor.start() else {
            statusText = audioMonitor.lastError
                ?? "Could not start audio monitoring"
            return false
        }

        isEnabled = true
        statusText = "Audio monitoring is running"

        autoStartTask?.cancel()
        autoStartTask = nil

        return true
    }

    private func startAutomaticMonitoring() {
        guard autoStartTask == nil, !isEnabled else {
            return
        }

        autoStartTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                if self.isEnabled {
                    return
                }

                if self.spotify.isSpotifyRunning {
                    if self.startMonitoring() {
                        return
                    }
                } else {
                    self.statusText = "Waiting for Spotify to launch"
                }

                do {
                    try await Task.sleep(
                        nanoseconds: 2_000_000_000
                    )
                } catch {
                    return
                }
            }
        }
    }

    func setAutoStartMonitoringEnabled(_ enabled: Bool) {
        autoStartMonitoringEnabled = enabled

        UserDefaults.standard.set(
            enabled,
            forKey: autoStartPreferenceKey
        )

        if enabled {
            statusText = "Automatic monitoring enabled"
        } else {
            autoStartTask?.cancel()
            autoStartTask = nil
            statusText = "Automatic monitoring disabled"
        }
    }

    // MARK: - Login item

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try loginItemManager.setEnabled(enabled)
            launchAtLoginEnabled = loginItemManager.isEnabled

            if launchAtLoginEnabled {
                statusText = "Launch at Login enabled"
            } else {
                statusText = "Launch at Login disabled"
            }
        } catch {
            launchAtLoginEnabled = loginItemManager.isEnabled
            statusText = error.localizedDescription
        }
    }

    // MARK: - Spotify

    func checkSpotify() {
        if spotify.isSpotifyInstalled {
            statusText = spotify.isSpotifyRunning
                ? "Spotify is installed and running"
                : "Spotify is installed but not running"
        } else {
            statusText = "Spotify was not found"
        }
    }

    func updateOtherAudioDetected(_ detected: Bool) {
        guard isEnabled else {
            return
        }

        if detected {
            pauseSpotifyIfNeeded()
        } else {
            resumeSpotifyIfWePausedIt()
        }
    }

    private func pauseSpotifyIfNeeded() {
        guard !pausedSpotifyByController else {
            return
        }

        switch spotify.currentState() {
        case .playing:
            if spotify.pause() {
                pausedSpotifyByController = true
                statusText = "Spotify paused for other audio"
            } else {
                statusText = "Could not pause Spotify"
            }

        case .paused:
            statusText = "Spotify was already paused"

        case .stopped:
            statusText = "Spotify is stopped"

        case .unknown:
            statusText = "Could not determine Spotify playback state"
        }
    }

    private func resumeSpotifyIfWePausedIt() {
        guard pausedSpotifyByController else {
            return
        }

        if spotify.play() {
            pausedSpotifyByController = false
            statusText = "Spotify resumed"
        } else {
            statusText = "Could not resume Spotify"
        }
    }
}
