<p align="center">
  <img src="assets/fathom.png" alt="Fathom" width="140">
</p>

# Fathom

**Dive into your media.**

Fathom is an all-in-one client for [Jellyfin](https://jellyfin.org), on desktop and Android. It brings your whole setup into one window: movies, shows, music, and Live TV, plus most of Jellyfin's server-side management, so you rarely need the web dashboard. Two optional integrations, [Seerr](features.md#requests-ratings-and-watch-together) requests and a full [YouTube](youtube.md) client, live right inside the app.

Everything plays through mpv (via [media_kit](https://github.com/media-kit/media-kit) / libmpv), so you get direct play, hardware decoding, and real subtitle and audio track control.

<div class="grid cards" markdown>

- :material-download: **[Install](install.md)**: Linux (AppImage), Windows, and Android (APK).
- :material-play-circle: **[First-run setup](setup.md)**: connect to your Jellyfin server and turn on the optional integrations.
- :material-tune: **[Features](features.md)**: the library, the player, radio, casting, and more.
- :material-youtube: **[YouTube](youtube.md)**: a complete built-in client, no account and no ads.
- :material-update: **[Updates and channels](updates.md)**: how the in-app updater and the Stable / Dev channels work.
- :material-lifebuoy: **[Troubleshooting](troubleshooting.md)**: the common launch and playback fixes.

</div>

## Highlights

- **One player for everything.** Jellyfin and YouTube share the same control bar, seek bar, speed control, track pickers, and keyboard shortcuts.
- **mpv-grade playback** with direct play, a transcode fallback, hardware decoding, and proper subtitle and audio track selection. A **Playback Info** overlay shows exactly what is happening (codecs, resolution, the live hardware-decode path, dropped frames).
- **Run your server from the app**: users, libraries, scheduled tasks, transcoding, Live TV and DVR, and more, without opening the web dashboard.
- **YouTube, built in** (optional): search, subscriptions, local playlists, SponsorBlock, DeArrow, downloads, theater mode. Nothing is sent to YouTube.
- **Requests and ratings**: Seerr browse-and-request with approve / decline / manage in place, plus Rotten Tomatoes, IMDb, and more.
- **Internet radio** with live time-shift, so you can pause and rewind a live station.
- **Watch together** over SyncPlay, interoperable with the official Jellyfin apps.
- **Make it yours**: light, dark, and AMOLED themes with a custom accent, a rearrangeable Home, in-app updates, and a fully translatable interface.

## Platforms

Fathom runs on **Linux**, **Windows**, and **Android** (phones and tablets) today, with **Android TV** supported but experimental for now. Linux and Windows have a self-contained download each, and Android installs from the APK. macOS and iOS are on the radar but need Mac hardware. See [Install](install.md) for details.

!!! info "Free and open source"
    Fathom is free software under the [AGPL-3.0](https://github.com/Fathom-Media/fathom/blob/main/LICENSE) license, built and maintained by one person. If it is useful to you, a [star on GitHub](https://github.com/Fathom-Media/fathom) or a [Ko-fi](https://ko-fi.com/traceapps) helps.
