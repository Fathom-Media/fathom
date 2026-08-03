# Updates and channels

Fathom updates itself. On Linux it swaps the AppImage in place and relaunches; on Windows it replaces the portable build and relaunches. You can also just download a newer build from [Releases](https://github.com/Fathom-Media/fathom/releases) at any time.

Open **Settings → Updates** to check manually, choose a channel, and toggle checking on startup.

## Channels

| Channel | What you get |
| --- | --- |
| **Stable** | Only full releases (for example `0.10.0`). The default. |
| **Beta** | Full releases plus pre-release test builds, so you get new features and fixes early. |

The updater always offers the newest version for your channel and downloads the build that matches your platform and CPU architecture automatically (x86_64 vs aarch64 on Linux).

## How versions work

- **Stable releases** are plain versions like `0.10.0`.
- **Dev / Beta builds** are pre-releases named `0.10.1-dev.1`, `0.10.1-dev.2`, and so on. The Beta channel tracks these in order and rolls you onto the next stable release when it lands.
- A floating **`dev-latest`** pre-release always points at the newest dev build, as a stable download link. The in-app updater tracks the numbered builds, not this alias.

!!! note "Safe by design"
    Before installing, Fathom verifies the download's size and, on Linux, that the AppImage matches your machine's architecture. If something is wrong (a truncated download, or a mismatched build), it keeps your working version and reports the problem instead of installing a broken file.

## Update did not relaunch, or will not start

Almost always this is a download that was grabbed mid-publish, or a wrong-architecture file from an older build. See [Troubleshooting → Updating](troubleshooting.md#updating) for the fix.
