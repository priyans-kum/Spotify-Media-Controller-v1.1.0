
import AppKit
import SwiftUI

@main
struct SpotifyMediaControllerApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra(
            "Spotify Media Controller",
            systemImage: model.isEnabled
                ? "music.note"
                : "music.note.slash"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Spotify Media Controller")
                    .font(.headline)

                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Button(
                    model.isEnabled
                        ? "Disable Monitoring"
                        : "Enable Monitoring"
                ) {
                    model.toggleEnabled()
                }

                Button("Check Spotify") {
                    model.checkSpotify()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 260)
        }
        .menuBarExtraStyle(.window)
    }
}
