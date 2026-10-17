
# Spotify Media Controller — macOS

The macOS implementation of Spotify Media Controller.

## Project contents

- `Sources/SpotifyMediaController/` — Swift application source code
- `Resources/Info.plist` — application bundle metadata
- `scripts/build-macos.sh` — macOS build and packaging script

## Requirements

- A compatible Mac running macOS 14.2 or later
- Swift toolchain and Xcode Command Line Tools
- Spotify for Mac

## Build

Open Terminal on a Mac and navigate to this directory:

```bash
cd /path/to/macOS
chmod +x scripts/build-macos.sh
./scripts/build-macos.sh
```

The build script creates the application bundle under `dist/`.

## Notes

This project is intended to control Spotify playback in response to audio activity from other applications. Behavior depends on macOS audio monitoring, permissions, and the installed Spotify version.

The application may require additional security approval because a locally built application is not necessarily notarized.
