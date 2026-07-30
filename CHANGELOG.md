# Changelog

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
