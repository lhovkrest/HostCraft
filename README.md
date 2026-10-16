# HostCraft

A local Minecraft Java server manager for Android, Windows and Linux, built with Flutter.
Start a Vanilla or Paper server on your own hardware and let friends join from anywhere through Playit.

## Features

- Vanilla and Paper servers (1.21.1, 1.20.4) with a bundled or downloaded Java 21 runtime
- Live console, server settings editor, CPU and memory readout
- **Playit tunnels through the Playit API**: link your account once, HostCraft creates the tunnel and shows the public address
- Server heap limit based on the RAM of the device it runs on
- Flat design with light and dark mode
- Android foreground service so hosting keeps running in the background

## How Playit is used

HostCraft talks to `https://api.playit.gg` using the endpoints described by
[playit-api-java](https://github.com/playit-cloud/playit-api-java):
`/claim/setup` and `/claim/exchange` to link the account, `/agents/rundata` to find the agent and its tunnels,
and `/tunnels/create` to create a Minecraft Java tunnel to `127.0.0.1:<server port>`.
The client lives in `lib/services/playit_api.dart`.

The API only manages the account side. Game traffic is still relayed by the Playit agent
(`playit-agent` v0.17.1), which HostCraft starts after the tunnel exists.

## Building

```
flutter pub get
flutter build apk --release --target-platform android-arm64,android-x64
```

The Android Java runtime, the Playit agent and the native launcher are already committed under
`android/app/src/main`. To regenerate them run `python tool/prepare_android.py --ndk <path> --arch all`.

## Releasing

Run the Release workflow manually against a version tag. It builds the Android APK
(plus Windows and Linux archives) and publishes them as a GitHub release.

## Tests

```
flutter test
```

## Release validation
Version 0.2.0 is built without running the app or test suite, at the maintainer's request. Device hosting and public tunnel connectivity require user validation. Android heap pointer tagging is disabled for compatibility with the bundled JVM, including the native launcher. This addresses the reported truncated-pointer crash; it is not a confirmed device-tested fix.


