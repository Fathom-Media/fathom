# Fathom

A modern desktop client for Jellyfin, with an optional built-in YouTube player and Seerr requests.

Fathom is a Jellyfin client that treats playback as the main event. Your movies, shows, music, and Live TV all live in one fast, good-looking app, and everything plays through mpv (via [media_kit](https://github.com/media-kit/media-kit) / libmpv), so you get direct play, hardware decoding, and real subtitle and audio track control instead of a lowest-common-denominator web player. Two optional extras round it out: a full, ad-free YouTube client and Seerr requests, each toggled on or off in settings. Use what you want and ignore the rest.

<!-- Screenshots: add a few under docs/ and reference them here once captured. -->

## Features

### Your library
- **Movies and TV**: libraries, search, rich detail pages, resume and Next Up, next and previous episode, skip intro and credits, chapters, and trickplay thumbnails as you scrub.
- **Music**: albums, a play queue, now playing, shuffle and repeat, synced lyrics with an online fallback, and scrobbling.
- **Live TV and DVR**: a channel list, an EPG guide, recording with series rules, and tuner and guide-provider setup.

### One player for everything
- **mpv-grade playback** through media_kit and libmpv: direct play with a transcode fallback, hardware decoding, and proper subtitle and audio track selection.
- **The same player everywhere.** Jellyfin and YouTube share one control bar, one seek bar (with chapter and skip markers), the same speed control, track pickers, and keyboard shortcuts, so nothing feels bolted on.
- **Picture in picture.** Shrink a video into a floating mini player and keep browsing, or pop it out to a resizable, always-on-top window on your desktop.
- **Tune it to taste**: video fit, playback speed, a control bar you can style (glass, dark, or plain), remappable keyboard shortcuts, and scrub-preview thumbnails.

### YouTube, built in (optional)
- A complete client: search across videos, channels, and playlists, subscriptions and feed groups, your own local playlists, comments, captions, chapters, a play queue, and theater mode.
- **SponsorBlock** to skip sponsor segments, **DeArrow** for non-clickbait titles and thumbnails, and dislike counts via **Return YouTube Dislike**.
- **Downloads** for offline viewing: video as MP4 or MKV, audio as M4A or MP3, at a quality and to a folder you choose.
- No account and no ads. Subscriptions, playlists, and history stay on your device, and nothing is sent to YouTube.

### Requests, ratings, and more
- **Seerr (optional)**: browse and request titles, then approve, decline, or manage requests without leaving the page, with download progress shown right on the detail view.
- **Ratings that matter to you**: Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt and others through MDBList.
- **Watch together**: SyncPlay-based shared playback that works with the official Jellyfin apps and other clients, not only with other Fathom users.
- **Server administration**: manage users, libraries, scheduled tasks, active sessions, playback and transcoding, networking, branding, Live TV and DVR, and plugins, all from the app.

### Make it yours
- Light, dark, and AMOLED themes with a custom accent color, a Home layout you can rearrange, desktop and in-app notifications, a settings screen you can search, and a fully translatable interface.

## Installing

Fathom is Linux-first (built and tested on Arch with KDE) and cross-platform by design.

**AppImage** (most distributions)

Download the latest `Fathom-x86_64.AppImage` from the [Releases](https://github.com/Fathom-Media/fathom/releases) page, then make it executable and run it:

```
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

It uses your system's `mpv`/`libmpv` (Arch: `mpv`, Fedora: `mpv-libs`, Debian/Ubuntu: `libmpv2`).

**Build from source**

```
flutter build linux --release
```

`ffmpeg` is recommended: it merges YouTube's separate video and audio streams when you download in higher quality. Everything else works without it.

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

## License

Fathom is free software, licensed under the [GNU Affero General Public License v3.0](LICENSE).

SponsorBlock data, when enabled, comes from the [SponsorBlock](https://sponsor.ajay.app) API and is used under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
