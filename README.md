# Fathom

A modern Jellyfin client for the desktop, with a built-in YouTube player.

Built with Flutter and [media_kit](https://github.com/media-kit/media-kit)
(libmpv), so playback is mpv-grade: direct play with transcode fallback, proper
subtitle and audio track handling, and hardware decoding.

## Features

- **Movies and TV** — libraries, search, detail pages, resume, next-up,
  skip intro/credits, chapters, trickplay previews on the scrubber
- **Music** — albums, queue, now playing, shuffle and repeat, scrobbling
- **Live TV and DVR** — channel list, EPG guide, recording, series rules,
  tuner and guide-provider management
- **YouTube** — search (videos, channels, playlists), subscriptions, feed
  groups, local playlists, comments, captions, chapters, a play queue, theater
  mode (press `T`), and downloads. No account, no ads; everything is kept on
  this device.
- **Seerr** — discovery and requests, if you run Jellyseerr
- **Server administration** — users, libraries, tasks, sessions, plugins

## Building

```
flutter build linux --release
```

Linux is the primary target. `ffmpeg` is optional but recommended: YouTube
serves video and audio together only up to 360p, so higher-quality downloads are
merged from two streams.

## Translations

Fathom's interface is internationalized with Flutter's built-in ARB
localization, the same approach the wider Jellyfin ecosystem uses. English
([`lib/l10n/app_en.arb`](lib/l10n/app_en.arb)) is the source of truth; every
other language ships as an `app_<lang>.arb` beside it. After editing ARB files,
regenerate the bindings with `flutter gen-l10n`.

Translations are welcome by pull request, and the setup is Weblate-ready for a
hosted workflow. Only English is edited in-repo; all other locales flow in from
translators.

## Tests

```
flutter test                          # offline, deterministic
flutter test --tags live --run-skipped   # hits real YouTube/network endpoints
```

## License

Fathom is free software, licensed under the
[GNU Affero General Public License v3.0](LICENSE).

SponsorBlock data, when enabled, comes from the
[SponsorBlock](https://sponsor.ajay.app) API and is used under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
