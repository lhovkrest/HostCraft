## What's new

- **Playit through its API.** HostCraft now links your Playit account, creates the Minecraft Java tunnel and reads the public address through the Playit HTTP API (the endpoints from [playit-api-java](https://github.com/playit-cloud/playit-api-java)). No more dashboard setup and no more reading the agent's log output. The Playit agent process still carries the game traffic.
- **Memory limit follows the device.** The server heap is no longer capped at 4 GB. The slider goes up to the RAM installed in your phone or computer, with a recommended ceiling and a warning when you go past it.
- **Mobile hosting fixes.** Background-activity prompt so Android does not throttle the server, a lower default heap on small phones, and a clear warning when the Playit agent cannot resolve domain names.
- **Flat redesign** with light and dark mode (system, light or dark, remembered between launches).

## Install

- **Android:** download the `.apk` (64-bit devices only: arm64 or x86_64). It is signed with a debug key, so Android will ask you to allow installs from this source.
- **Windows / Linux:** download the archive, extract it and run `hostcraft`.

The attached APK targets ARM64 Android. This release was compiled without running the app or tests. Includes a native heap pointer-tagging compatibility change for the reported Infinix Note 12 crash; on-device confirmation is pending.

