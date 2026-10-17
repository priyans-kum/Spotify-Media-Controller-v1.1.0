# Spotify Media Controller for macOS (development build)

This is a separate native macOS implementation. It does not replace or modify the existing Windows controller.

## Requirements

- macOS 14.2 or newer
- Apple Silicon Mac (arm64) for the current build script
- Spotify desktop app
- Xcode Command Line Tools / Swift toolchain to build locally

## What it does

- Runs as a menu-bar utility.
- Uses Apple's Core Audio process-tap API to measure audio activity from processes other than Spotify.
- Pauses Spotify after non-Spotify audio remains above a small threshold for a short confirmation period.
- Resumes Spotify after a quiet period only when the controller previously paused it and Spotify still reports itself paused.
- Rebuilds the audio tap when Spotify starts or quits, so Spotify audio can be excluded from detection.
- Analyzes audio levels locally; it does not save or transmit captured audio samples.

## Important limitations

This is a first development implementation, not a verified release. It has **not been run on a physical Mac in this repository workflow**. The macOS build workflow can compile and package it on a hosted Mac runner, but that does not prove the Core Audio tap, permission prompts, Spotify Apple Events, or all applications behave correctly on your friend's Mac.

Audio-level detection cannot perfectly tell a media stream from a long system sound. The RMS threshold and short start-confirmation window reduce brief sound-effect triggers, but do not eliminate them. Very quiet media may not cross the threshold. Browser tabs are detected as their browser process, not individually identified.

The current script packages an Apple Silicon build only. The app is ad-hoc signed and not notarized, so macOS may display a security warning. Do not bypass security prompts if anything looks unexpected; review the source and build it yourself.

## Build on a Mac

1. Install Apple's Command Line Tools if Swift is not available:
   `xcode-select --install`
2. Open Terminal in the repository folder.
3. Run:
   `chmod +x macOS/build-macos.sh`
4. Run:
   `./macOS/build-macos.sh`
5. Open `macOS/dist/SpotifyMediaController.app`.

On first use, allow **System Audio Recording** if macOS asks. Spotify control may also trigger an Apple Events / Automation permission prompt. If the app reports a permission or Core Audio error, quit it, review System Settings → Privacy & Security, and retry.

## First verification checklist

1. Launch Spotify and start a track.
2. Launch the controller and approve the requested permissions.
3. Play a YouTube video or VLC file; Spotify should pause after a brief confirmation delay.
4. Pause the external media; Spotify should resume after the quiet timeout.
5. Pause Spotify manually, then play and stop external media; the controller must not start Spotify unless it had paused Spotify itself.
6. Test a short system alert, browser audio, a long ad, and a quiet video. Note any false triggers or missed detection.
7. Quit and reopen Spotify while the controller remains running; the tap should refresh.
8. Quit the controller and confirm audio output remains normal.

## Development status

- [x] Separate macOS source and Swift package
- [x] Menu-bar utility shell
- [x] Core Audio process tap and audio-level threshold logic
- [x] Spotify pause/resume ownership logic
- [x] macOS app bundle build script
- [ ] Successful compile confirmed by CI
- [ ] Real-Mac permission and playback verification
- [ ] Universal Intel + Apple Silicon build
- [ ] Developer ID signing and notarization
