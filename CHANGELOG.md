# Changelog

## 0.11.0

### Added
- Android, and experimental Android TV: Fathom now runs on Android phones and tablets from the same universal APK, with a native ExoPlayer backend at parity with the desktop player (skip, trickplay, picture-in-picture, SyncPlay), Chromecast, and background YouTube audio with lock-screen controls. Android TV is included but experimental: D-pad navigation and a 10-foot interface are in place, with more polish to come.
- Android Auto (audio-only): browse your Jellyfin music, internet radio, and YouTube in tabs, search by voice, and control playback, shuffle, repeat, favorites, and the up-next queue from the car's screen.
- YouTube Shorts viewer: a vertical swipe pager through a channel's Shorts, with comments, a scrubbable progress bar, watch history, and portrait fullscreen.
- Up Next: episodes that have a next episode show an Up Next prompt over the credits, as a poster Card or a Netflix-style Pill, so it advances to the next episode instead of leaving you at the end of the file. Choose the style and timing under Settings, and Autoplay Next Episode decides whether it counts down on its own or waits for Play Now.
- Item context menu: a per-item menu on posters (long-press, right-click, or the hover hamburger), on each episode row, and in the detail overflow, with Play or Resume, Show Details, Mark Watched, Add to Favorites, Add to Playlist, Refresh Metadata, and Delete.
- Delete media: with the right server permission, delete a whole series, a season, a single episode, or a movie, each behind a confirmation.
- Audio passthrough: bitstream Atmos, Dolby Digital, and DTS to a receiver on the desktop player.
- In-app plugin configuration: a real form with toggles, number and text fields, and add/remove lists instead of a raw JSON blob, with an Edit as JSON switch, plus plugin logos in the list and on the plugin page.
- Skip Recap: "Previously On" recaps get their own Skip Recap button, separate from Skip Intro.

### Changed
- Faster YouTube "What's New" and channel browsing (InnerTube, bounded hydration, cached feed metadata).
- The Android TV YouTube player gains an actions sheet (Subscribe, Add to Playlist, open Channel) and higher-resolution audio artwork.
- Your last volume is restored when playback hands off between the player and background audio.

### Fixed
- Skip Intro and Skip Credits now appear reliably (the app requests segment types from the server).
- Android (ExoPlayer): 4:3 video is pillarboxed instead of stretched to a 16:9 screen, and seeking near the end of an episode no longer jumps to the next one.
- Android TV: selecting an episode now plays it, and the Skip and Up Next buttons are reachable and clickable with the D-pad.
- Desktop fullscreen: the window's minimize, maximize, and close buttons are hidden, the video no longer blanks when entering fullscreen, and Space and the other shortcuts work in both windowed and fullscreen.
- The cast button now hides when no Cast device is reachable, and fades away with the rest of the player controls.
- Android Auto: switching from YouTube audio to internet radio or music now updates the car display with the correct title, artwork, and time, instead of keeping the previous YouTube track's info.
- Seerr search no longer fails on multi-word queries.
- The YouTube Listen queue no longer gets stuck when a track fails to open.

## 0.10.1

### Added
- OS media controls: Fathom now responds to your system media keys and on-screen controls on Windows (SMTC) and Linux (MPRIS), covering video, Live TV, YouTube, and internet radio, with play, pause, stop, and next/previous.
- YouTube playlist queue: open a playlist and play straight through it.

### Fixed
- Windows: HTTPS connections now work reliably (Fathom trusts a bundled set of certificate roots), which fixes YouTube playback and secure Jellyfin servers on Windows.
- Music now pauses when a YouTube video starts, so the two no longer play over each other.
- Internet radio search no longer fails on directory mirrors that return a non-standard response.
- Faster, cleaner window close on desktop.

## 0.10.0

### Added
- Backup & Restore: export and import your Fathom settings to a portable file, selectable by group (general, appearance, player, YouTube, internet radio and its stations, and server addresses). Passwords, tokens, and API keys are never included, so you sign in again after importing. Under Settings → System → Backup & Restore.

### Changed
- Reorganized Settings: a new System section groups Updates, Backup & Restore, and Diagnostics, separate from About.
- Notifications: "Desktop Notifications" is now "System Notifications", with a new "Update Available" toggle.
- Seerr request status now refreshes faster while the app is open.

### Fixed
- Request cards no longer clip a long status label such as "Partially Available".

## 0.9.1

### Added
- Internet radio: add stations by URL or from the radio-browser.info directory, organize them into groups and favorites, with live time-shift to pause and rewind a live station, plus background playback and casting.
- Playback Info overlay in the video and YouTube players: play method, codecs, resolution, frame rate, bitrates, the hardware-decode path, and dropped frames.
- aarch64 (ARM64) Linux builds alongside x86_64, for Asahi Linux, Raspberry Pi, and similar.
- Diagnostics screen with exportable logs.
- Display Sync option for smoother playback on high-refresh displays.
- Internal/external server address switching that auto-picks a reachable address.
- A documentation site at https://fathom-media.github.io/fathom.

### Changed
- Redesigned the now-playing volume as an inline speaker that expands a slider.
- Now-playing artwork/lyrics card-flip and favorite-heart animations.
- The video mini-player and desktop pop-out now auto-hide their controls when idle.
- Unified search, drag-to-reorder lists, and customizable navigation and Home.
- Faster YouTube channel browsing.

### Fixed
- In-app updates verify the download's size and architecture before installing, so a truncated or wrong-architecture update can't break the app.

## 0.9.0

First public release for Linux and Windows.

- Jellyfin movies, TV, music, and Live TV
- One shared player with picture-in-picture and desktop pop-out
- Optional YouTube client with SponsorBlock, DeArrow, and downloads
- Optional Seerr requests from the detail page, with Jellyfin, local, or API-key sign-in
- In-app updates with a stable or beta channel
- Ratings, SyncPlay, and server administration
- Themes, searchable settings, and a translatable interface
