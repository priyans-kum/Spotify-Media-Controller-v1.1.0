import AppKit
import AudioToolbox
import CoreAudio
import Foundation

private let spotifyBundleID = "com.spotify.client"
private let minimumRMS: Double = 0.008
private let startConfirmation: TimeInterval = 0.35
private let silenceBeforeResume: TimeInterval = 1.4

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var timer: Timer?
    private var monitor: AudioMonitor?
    private var enabled = true
    private var activeSince: Date?
    private var pausedByController = false
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()

        guard #available(macOS 14.2, *) else {
            lastError = "Requires macOS 14.2 or newer."
            refreshMenu()
            return
        }

        let audioMonitor = AudioMonitor()
        monitor = audioMonitor
        do {
            try audioMonitor.start()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        refreshMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        monitor?.stop()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "♫ Focus"

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        enabledItem = NSMenuItem(title: "Pause automation", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        let spotifyItem = NSMenuItem(title: "Open Spotify", action: #selector(openSpotify), keyEquivalent: "")
        spotifyItem.target = self
        menu.addItem(spotifyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Spotify Media Controller", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        if !enabled { activeSince = nil }
        refreshMenu()
    }

    @objc private func openSpotify() {
        NSWorkspace.shared.launchApplication(withBundleIdentifier: spotifyBundleID,
                                             options: [.default],
                                             additionalEventParamDescriptor: nil,
                                             launchIdentifier: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func tick() {
        guard enabled, let monitor else {
            refreshMenu()
            return
        }

        if let error = monitor.refreshIfSpotifyProcessesChanged() {
            lastError = error
        }

        let now = Date()
        if monitor.hasRecentAudio(within: 0.45) {
            if activeSince == nil { activeSince = now }
            if let activeSince, now.timeIntervalSince(activeSince) >= startConfirmation {
                if spotifyPlayerState() == "playing" {
                    if runSpotifyCommand("pause") {
                        pausedByController = true
                    }
                }
            }
        } else {
            activeSince = nil
            if pausedByController, monitor.secondsSinceLastAudio >= silenceBeforeResume {
                if spotifyPlayerState() == "paused" {
                    _ = runSpotifyCommand("play")
                }
                pausedByController = false
            }
        }
        refreshMenu()
    }

    private func spotifyPlayerState() -> String? {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == spotifyBundleID && !$0.isTerminated
        }) else { return nil }

        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Spotify\" to get player state")
        let result = script?.executeAndReturnError(&error)
        if let error {
            lastError = "Spotify control permission may be needed: \(error[NSAppleScript.errorMessage] ?? error)"
            return nil
        }
        return result?.stringValue?.lowercased()
    }

    @discardableResult
    private func runSpotifyCommand(_ command: String) -> Bool {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == spotifyBundleID && !$0.isTerminated
        }) else { return false }

        var error: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Spotify\" to \(command)")
        _ = script?.executeAndReturnError(&error)
        if let error {
            lastError = "Spotify control permission may be needed: \(error[NSAppleScript.errorMessage] ?? error)"
            return false
        }
        lastError = nil
        return true
    }

    private func refreshMenu() {
        enabledItem?.title = enabled ? "Pause automation" : "Resume automation"
        if let lastError {
            statusMenuItem?.title = lastError
        } else if !enabled {
            statusMenuItem?.title = "Automation paused"
        } else if pausedByController {
            statusMenuItem?.title = "Spotify paused by controller"
        } else {
            statusMenuItem?.title = "Monitoring other-app audio"
        }
        statusItem?.button?.title = enabled ? "♫ Focus" : "♫ Off"
    }
}

@available(macOS 14.2, *)
private final class AudioMonitor {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var excludedSpotifyPIDs: Set<pid_t> = []
    private let audioLock = NSLock()
    private var lastLoudAudioTime = Date.distantPast

    var secondsSinceLastAudio: TimeInterval {
        audioLock.lock()
        defer { audioLock.unlock() }
        return Date().timeIntervalSince(lastLoudAudioTime)
    }

    func hasRecentAudio(within interval: TimeInterval) -> Bool {
        secondsSinceLastAudio < interval
    }

    func start() throws {
        try rebuildTap()
    }

    func refreshIfSpotifyProcessesChanged() -> String? {
        let pids = currentSpotifyPIDs()
        guard pids != excludedSpotifyPIDs else { return nil }
        do {
            try rebuildTap()
            return nil
        } catch {
            return "Audio monitor error: \(error.localizedDescription)"
        }
    }

    private func currentSpotifyPIDs() -> Set<pid_t> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier == spotifyBundleID, !app.isTerminated else { return nil }
            return app.processIdentifier
        })
    }

    private func processObjectID(for pid: pid_t) -> AudioObjectID? {
        var processPID = pid
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &processPID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifier,
                &size,
                &objectID
            )
        }
        guard status == noErr, objectID != kAudioObjectUnknown else { return nil }
        return objectID
    }

    private func rebuildTap() throws {
        stop()
        let pids = currentSpotifyPIDs()
        let processObjects = pids.compactMap(processObjectID(for:))
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: processObjects)
        description.name = "Spotify Media Controller Audio Monitor"
        description.isPrivate = true
        description.isExclusive = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr else {
            throw AudioMonitorError.coreAudio("create process tap", tapStatus)
        }
        tapID = newTapID

        let tapList: [[String: Any]] = [[
            kAudioSubTapUIDKey as String: description.uuid.uuidString,
            kAudioSubTapDriftCompensationKey as String: true
        ]]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Spotify Media Controller Audio Monitor",
            kAudioAggregateDeviceUIDKey as String: "com.priyanskum.SpotifyMediaController.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey as String: tapList,
            kAudioAggregateDeviceTapAutoStartKey as String: false,
            kAudioAggregateDeviceIsPrivateKey as String: true
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard aggregateStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            throw AudioMonitorError.coreAudio("create aggregate audio device", aggregateStatus)
        }
        aggregateID = newAggregateID

        var newIOProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProcID,
            aggregateID,
            DispatchQueue.global(qos: .userInitiated)
        ) { [weak self] _, _, inputData, _, _, _ in
            guard let self, let inputData else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            var squareSum = 0.0
            var sampleCount = 0

            for buffer in buffers {
                guard let data = buffer.mData, buffer.mDataByteSize >= UInt32(MemoryLayout<Float>.size) else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    let value = Double(samples[index])
                    squareSum += value * value
                }
                sampleCount += count
            }

            if sampleCount > 0 {
                let rms = sqrt(squareSum / Double(sampleCount))
                if rms >= minimumRMS {
                    self.audioLock.lock()
                    self.lastLoudAudioTime = Date()
                    self.audioLock.unlock()
                }
            }
            return noErr
        }
        guard ioStatus == noErr, let newIOProcID else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            throw AudioMonitorError.coreAudio("create audio callback", ioStatus)
        }
        ioProcID = newIOProcID

        let startStatus = AudioDeviceStart(aggregateID, newIOProcID)
        guard startStatus == noErr else {
            stop()
            throw AudioMonitorError.coreAudio("start audio monitor", startStatus)
        }
        excludedSpotifyPIDs = pids
    }

    func stop() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        excludedSpotifyPIDs = []
    }

    deinit { stop() }
}

private enum AudioMonitorError: LocalizedError {
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status):
            return "Could not \(operation) (Core Audio status \(status)). Check System Audio Recording permission and try again."
        }
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
