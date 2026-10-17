
import AppKit
import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class AudioMonitor {

    private(set) var isRunning = false
    private(set) var lastError: String?

    var onAudioActivityChanged: ((Bool) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?

    private var audioFormat = AudioStreamBasicDescription()

    private var activeSince: TimeInterval?
    private var quietSince: TimeInterval?
    private var audioIsActive = false

    private let threshold = 0.012
    private let activationDelay: TimeInterval = 0.25
    private let releaseDelay: TimeInterval = 0.65

    func start() -> Bool {
        guard !isRunning else {
            return true
        }

        lastError = nil

        guard #available(macOS 14.2, *) else {
            return fail("macOS 14.2 or later is required.")
        }

        guard let spotify = NSRunningApplication
            .runningApplications(
                withBundleIdentifier: "com.spotify.client"
            )
            .first else {
            return fail("Open Spotify before enabling monitoring.")
        }

        do {
            try createTap(excluding: spotify.processIdentifier)
            try createAggregateDevice()
            try readAudioFormat()
            try startAudioIO()

            isRunning = true
            onStatusChanged?("Audio monitoring is running")
            return true
        } catch {
            stop()
            return fail(error.localizedDescription)
        }
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown,
           let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(
                aggregateDeviceID,
                ioProcID
            )
        }

        ioProcID = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = kAudioObjectUnknown
        }

        isRunning = false
        activeSince = nil
        quietSince = nil
        audioIsActive = false

        onAudioActivityChanged?(false)
    }

    private func fail(_ message: String) -> Bool {
        lastError = message
        onStatusChanged?("Audio monitoring failed: \(message)")
        NSLog("AudioMonitor: %@", message)
        return false
    }

        @available(macOS 14.2, *)
        private func createTap(excluding spotifyPID: pid_t) throws {
        var pid = spotifyPID
        var processObjectID = AudioObjectID(kAudioObjectUnknown)

        var address = AudioObjectPropertyAddress(
            mSelector:
                kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let translateStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &processObjectID
        )

        guard translateStatus == noErr,
              processObjectID != kAudioObjectUnknown else {
            throw MonitorError.coreAudio(
                "Could not identify Spotify's audio process",
                translateStatus
            )
        }

        let description = CATapDescription(
            stereoGlobalTapButExcludeProcesses: [processObjectID]
        )

        description.name = "Spotify Media Controller Monitor"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)

        let status = AudioHardwareCreateProcessTap(
            description,
            &newTapID
        )

        guard status == noErr else {
            throw MonitorError.coreAudio(
                "Could not create the process tap",
                status
            )
        }

        tapID = newTapID
    }

    private func readTapUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &size,
                UnsafeMutableRawPointer(pointer)
            )
        }

        guard status == noErr else {
            throw MonitorError.coreAudio(
                "Could not read the process tap UID",
                status
            )
        }

        return uid as String
    }

    private func createAggregateDevice() throws {
        let tapUID = try readTapUID()

        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey as String: tapUID
        ]

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String:
                "Spotify Media Controller Audio Monitor",
            kAudioAggregateDeviceUIDKey as String:
                UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String:
                true,
            kAudioAggregateDeviceTapAutoStartKey as String:
                true,
            kAudioAggregateDeviceTapListKey as String:
                [tapEntry]
        ]

        var newDeviceID = AudioObjectID(kAudioObjectUnknown)

        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &newDeviceID
        )

        guard status == noErr else {
            throw MonitorError.coreAudio(
                "Could not create the aggregate audio device",
                status
            )
        }

        aggregateDeviceID = newDeviceID
    }

    private func readAudioFormat() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var format = AudioStreamBasicDescription()
        var size = UInt32(
            MemoryLayout<AudioStreamBasicDescription>.size
        )

        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &size,
            &format
        )

        guard status == noErr else {
            throw MonitorError.coreAudio(
                "Could not read the audio format",
                status
            )
        }

        audioFormat = format
    }

    private func startAudioIO() throws {
        let queue = DispatchQueue(
            label: "com.spotifymediacontroller.audio-monitor"
        )

        let format = audioFormat
        var newProcID: AudioDeviceIOProcID?

        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newProcID,
            aggregateDeviceID,
            queue
        ) { [weak self] _, inputData, _, _, _ in

            let level = Self.measureRMS(
                inputData,
                format: format
            )

            Task { @MainActor [weak self] in
                self?.consumeAudioLevel(level)
            }
        }

        guard createStatus == noErr, let newProcID else {
            throw MonitorError.coreAudio(
                "Could not create the audio callback",
                createStatus
            )
        }

        ioProcID = newProcID

        let startStatus = AudioDeviceStart(
            aggregateDeviceID,
            newProcID
        )

        guard startStatus == noErr else {
            throw MonitorError.coreAudio(
                "Could not start audio monitoring",
                startStatus
            )
        }
    }

    private nonisolated static func measureRMS(
        _ inputData: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription
    ) -> Double {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )

        var sumSquares = 0.0
        var sampleCount = 0

        for buffer in buffers {
            guard let data = buffer.mData,
                  buffer.mDataByteSize > 0 else {
                continue
            }

            if format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
               format.mBitsPerChannel == 32 {

                let samples = data.assumingMemoryBound(to: Float.self)
                let count = Int(buffer.mDataByteSize)
                    / MemoryLayout<Float>.size

                for index in 0..<count {
                    let value = Double(samples[index])
                    sumSquares += value * value
                }

                sampleCount += count

            } else if format.mFormatFlags
                        & kAudioFormatFlagIsSignedInteger != 0,
                      format.mBitsPerChannel == 16 {

                let samples = data.assumingMemoryBound(to: Int16.self)
                let count = Int(buffer.mDataByteSize)
                    / MemoryLayout<Int16>.size

                for index in 0..<count {
                    let value = Double(samples[index]) / 32768.0
                    sumSquares += value * value
                }

                sampleCount += count

            } else {
                // Do not interpret an unsupported format as Float.
                return 0
            }
        }

        guard sampleCount > 0 else {
            return 0
        }

        return sqrt(sumSquares / Double(sampleCount))
    }

    private func consumeAudioLevel(_ level: Double) {
        guard isRunning else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime

        if level >= threshold {
            quietSince = nil

            if activeSince == nil {
                activeSince = now
            }

            if !audioIsActive,
               let started = activeSince,
               now - started >= activationDelay {
                audioIsActive = true
                onAudioActivityChanged?(true)
                onStatusChanged?("Other audio detected")
            }
        } else {
            activeSince = nil

            if quietSince == nil {
                quietSince = now
            }

            if audioIsActive,
               let quietStart = quietSince,
               now - quietStart >= releaseDelay {
                audioIsActive = false
                onAudioActivityChanged?(false)
                onStatusChanged?("Other audio stopped")
            }
        }
    }

    enum MonitorError: LocalizedError {
        case coreAudio(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .coreAudio(let message, let status):
                return "\(message) (Core Audio error \(status))."
            }
        }
    }
}
