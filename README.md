<div align="center">

<img src="assets/icon/fathom.png" width="128" alt="Fathom">

# Fathom

**Dive into your media**

An all-in-one client for Jellyfin, on desktop and Android. Your media, your server, Seerr requests, and YouTube, without leaving the app.

[![License](https://img.shields.io/github/license/Fathom-Media/fathom?color=blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Fathom-Media/fathom)](https://github.com/Fathom-Media/fathom/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Fathom-Media/fathom/total)](https://github.com/Fathom-Media/fathom/releases)
[![Stars](https://img.shields.io/github/stars/Fathom-Media/fathom)](https://github.com/Fathom-Media/fathom/stargazers)
![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20Windows%20%7C%20Android-lightgrey)

**[Documentation](https://fathom-media.github.io/fathom/) · [Install](https://fathom-media.github.io/fathom/install/) · [Releases](https://github.com/Fathom-Media/fathom/releases/latest)**

</div>

---

Fathom brings your whole Jellyfin setup into one window: movies, shows, music, and Live TV, plus most of Jellyfin's server-side management, so you rarely need the web dashboard. Two optional integrations, Seerr requests and a full YouTube client, live right inside the app. Everything plays through mpv (via [media_kit](https://github.com/media-kit/media-kit) / libmpv), so you get direct play, hardware decoding, and real subtitle and audio track control.

## Highlights

- **One player for everything.** Jellyfin and YouTube share the same control bar, seek bar, speed control, track pickers, and keyboard shortcuts, plus a **Playback Info** overlay that shows codecs, resolution, and the live hardware-decode path.
- **Run your server from the app**: users, libraries, scheduled tasks, transcoding, Live TV and DVR, and more, without the web dashboard.
- **YouTube, built in** (optional): search, subscriptions, local playlists, SponsorBlock, DeArrow, downloads, theater mode. No account, no ads.
- **Requests and ratings**: Seerr browse-and-request with manage-in-place, plus Rotten Tomatoes, IMDb, and more.
- **Internet radio** with live time-shift, **casting**, **watch together** over SyncPlay, **picture-in-picture**, and light / dark / AMOLED themes.

See the [feature tour](https://fathom-media.github.io/fathom/features/) for the full list.

## Install

Fathom runs on **Linux** and **Windows** (self-contained, nothing else to install) and on **Android** phones and tablets. **Android TV** is supported but experimental for now. macOS and iOS need Mac hardware.

Grab the latest build from [Releases](https://github.com/Fathom-Media/fathom/releases/latest). On Linux:

```bash
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

On Android, download the `.apk` and open it to install (allow installs from your browser or file manager if prompted). The same APK covers phones, tablets, and Android TV (Android TV is experimental for now).

Full instructions, first-run setup, and troubleshooting are in the **[documentation](https://fathom-media.github.io/fathom/install/)**.

## Documentation

The docs cover installing, connecting your server, every feature, the update channels, and troubleshooting:

**[fathom-media.github.io/fathom](https://fathom-media.github.io/fathom/)**

## Contributing

[ARCHITECTURE.md](ARCHITECTURE.md) is a tour of the codebase; [ROADMAP.md](ROADMAP.md) tracks what's planned. Build from source, tests, and the translation workflow are in the [contributing guide](https://fathom-media.github.io/fathom/contributing/). Translations are welcome by pull request.

## Support

Fathom is free and open source, and always will be. It's built and maintained by one person; donations help cover real costs like Mac hardware for macOS and iOS builds. Starring the repo helps too, and costs nothing.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Buy_me_a_coffee-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/traceapps)

## License

Fathom is free software, licensed under the [GNU Affero General Public License v3.0](LICENSE). SponsorBlock data, when enabled, comes from the [SponsorBlock](https://sponsor.ajay.app) API under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
