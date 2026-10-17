import AppKit
import Foundation

enum SpotifyPlaybackState: String {
    case playing
    case paused
    case stopped
    case unknown
}

@MainActor
final class SpotifyController {

    private let spotifyBundleIdentifier = "com.spotify.client"

    var isSpotifyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: spotifyBundleIdentifier
        ) != nil
    }

    var isSpotifyRunning: Bool {
        NSRunningApplication
            .runningApplications(
                withBundleIdentifier: spotifyBundleIdentifier
            )
            .contains { !$0.isTerminated }
    }

    func currentState() -> SpotifyPlaybackState {
        guard let result = runAppleScript(
            """
            tell application "Spotify"
                get player state as string
            end tell
            """
        ) else {
            return .unknown
        }

        return SpotifyPlaybackState(
            rawValue: result.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        ) ?? .unknown
    }

    @discardableResult
    func pause() -> Bool {
        guard runAppleScript(
            """
            tell application "Spotify"
                pause
            end tell
            """
        ) != nil else {
            return false
        }

        return waitForState(.paused)
    }

    @discardableResult
    func play() -> Bool {
        guard runAppleScript(
            """
            tell application "Spotify"
                play
            end tell
            """
        ) != nil else {
            return false
        }

        return waitForState(.playing)
    }

    private func waitForState(
        _ expectedState: SpotifyPlaybackState
    ) -> Bool {
        // Give Spotify a moment to process the command.
        for _ in 0..<10 {
            if currentState() == expectedState {
                return true
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        NSLog(
            "Spotify did not reach expected state: %@",
            expectedState.rawValue
        )
        return false
    }

    private func runAppleScript(
        _ source: String
    ) -> String? {
        guard let script = NSAppleScript(source: source) else {
            NSLog("Could not create Spotify AppleScript.")
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            NSLog("Spotify AppleScript error: %@", error)
            return nil
        }

        return result.stringValue ?? ""
    }
}
