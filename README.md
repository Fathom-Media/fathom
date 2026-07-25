<div align="center">

<img src="assets/icon/fathom.png" width="128" alt="Fathom">

# Fathom

**Dive into your media**

An all-in-one desktop client for Jellyfin. Your media, your server, Seerr requests, and YouTube, without leaving the app.

[![License](https://img.shields.io/github/license/Fathom-Media/fathom?color=blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Fathom-Media/fathom)](https://github.com/Fathom-Media/fathom/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Fathom-Media/fathom/total)](https://github.com/Fathom-Media/fathom/releases)
[![Stars](https://img.shields.io/github/stars/Fathom-Media/fathom)](https://github.com/Fathom-Media/fathom/stargazers)
![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20Windows-lightgrey)

</div>

---

Fathom brings your whole Jellyfin setup into one window: movies, shows, music, and Live TV, plus most of Jellyfin's server-side management (users, libraries, scheduled tasks, transcoding, Live TV and DVR, and more), so you rarely need the web dashboard. Two optional integrations, Seerr requests and a full YouTube client, live right inside the app, each toggled on or off in settings. No more bouncing between the dashboard, a requests page, and a browser tab. Everything plays through mpv (via [media_kit](https://github.com/media-kit/media-kit) / libmpv), so you get direct play, hardware decoding, and real subtitle and audio track control.

## Features

### Your library
- **Movies and TV**: libraries, search, rich detail pages, resume and Next Up, next and previous episode, skip intro and credits, chapters, and trickplay thumbnails as you scrub.
- **Music**: albums, a play queue, now playing, shuffle and repeat, synced lyrics with an online fallback, and scrobbling.
- **Live TV and DVR**: a channel list, an EPG guide, recording with series rules, and tuner and guide-provider setup.

### Run your server from the app
- **Server administration** without opening the Jellyfin web dashboard: manage users, libraries, scheduled tasks, active sessions, playback and transcoding, networking, branding, Live TV and DVR, and plugins.

### One player for everything
- **The same player everywhere.** Jellyfin and YouTube share one control bar, one seek bar (with chapter and skip markers), the same speed control, track pickers, and keyboard shortcuts, so nothing feels bolted on.
- **Picture in picture.** Shrink a video into a floating mini player and keep browsing, or pop it out to a resizable, always-on-top window on your desktop.
- **mpv-grade playback** through media_kit and libmpv: direct play with a transcode fallback, hardware decoding, and proper subtitle and audio track selection.
- **Tune it to taste**: video fit, playback speed, a control bar you can style (glass, dark, or plain), remappable keyboard shortcuts, and scrub-preview thumbnails.

### YouTube, built in (optional)
- A complete client: search across videos, channels, and playlists, subscriptions and feed groups, your own local playlists, comments, captions, chapters, a play queue, and theater mode.
- **SponsorBlock** to skip sponsor segments, **DeArrow** for non-clickbait titles and thumbnails, and dislike counts via **Return YouTube Dislike**.
- **Downloads** for offline viewing: video as MP4 or MKV, audio as M4A or MP3, at a quality and to a folder you choose.
- No account and no ads. Subscriptions, playlists, and history stay on your device, and nothing is sent to YouTube.

### Requests, ratings, and watching together
- **Seerr (optional)**: browse and request titles, then approve, decline, or manage requests without leaving the page, with download progress shown right on the detail view.
- **Ratings that matter to you**: Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt and others through MDBList.
- **Watch together**: SyncPlay-based shared playback that works with the official Jellyfin apps and other clients, not only with other Fathom users.

### Make it yours
- Light, dark, and AMOLED themes with a custom accent color, a Home layout you can rearrange, in-app updates with a stable or beta channel, desktop and in-app notifications, a settings screen you can search, and a fully translatable interface.

## Installing

Fathom runs on Linux and Windows today, with a self-contained download for each. An Android app is planned, and macOS and iOS are on the radar but need Mac hardware (see [Support](#support)).

**Linux (AppImage)**

Download the latest `Fathom-x86_64.AppImage` from the [Releases](https://github.com/Fathom-Media/fathom/releases) page, make it executable, and run it:

```
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

The AppImage is self-contained (libmpv and the media codecs are bundled), so there's nothing else to install.

**Windows**

Download `Fathom-windows-x64.zip` from the [Releases](https://github.com/Fathom-Media/fathom/releases) page, extract it, and run `fathom.exe`. It's self-contained, with nothing else to install.

**Build from source**

```
flutter build linux --release
```

`ffmpeg` is recommended: it merges YouTube's separate video and audio streams when you download in higher quality. Everything else works without it.

**Android**

Planned. Fathom is built with Flutter, so an Android build is on the roadmap, no extra hardware needed, just development time.

**macOS and iOS**

Not available yet. Building for either needs Mac hardware (and, for iOS, an iPhone and a paid Apple Developer account), which I don't currently own. If you'd like to see Fathom on Apple platforms, see [Support](#support).

## Translations

Fathom's interface is internationalized with Flutter's built-in ARB localization, the same approach the wider Jellyfin ecosystem uses. English ([`lib/l10n/app_en.arb`](lib/l10n/app_en.arb)) is the source of truth; every other language ships as an `app_<lang>.arb` beside it. After editing ARB files, regenerate the bindings with `flutter gen-l10n`.

Translations are welcome by pull request, and the setup is Weblate-ready for a hosted workflow. Only English is edited in-repo; all other locales flow in from translators.

## Tests

```
flutter test                          # offline, deterministic
flutter test --tags live --run-skipped   # hits real YouTube/network endpoints
```

## Contributing

[ARCHITECTURE.md](ARCHITECTURE.md) is a tour of the codebase and the design decisions worth knowing before touching things. [ROADMAP.md](ROADMAP.md) tracks what's planned, done, and parked. Translations are welcome, see above.

## Support

Fathom is free and open source, and always will be. It's built and maintained by one person; donations help cover real costs like Mac hardware and an Apple Developer account to enable macOS and iOS builds, plus ongoing development. Donations are appreciated but never required, and starring the repo helps with discoverability and costs nothing.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Buy_me_a_coffee-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/traceapps)

## License

Fathom is free software, licensed under the [GNU Affero General Public License v3.0](LICENSE).

SponsorBlock data, when enabled, comes from the [SponsorBlock](https://sponsor.ajay.app) API and is used under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
