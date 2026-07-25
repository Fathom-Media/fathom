# Roadmap

What's done, what's planned, what's parked. Fathom is in beta (v0.9.0); the core client is built and the current focus is release and reach.

## Phase 0 — Foundation ✅ DONE

- [x] Connect to a Jellyfin server, sign in, and switch between multiple accounts
- [x] Home, libraries, search, and rich detail pages

## Phase 1 — Movies, TV, and music ✅ DONE

- [x] mpv-grade playback: direct play, transcode fallback, hardware decoding, proper subtitle and audio track handling
- [x] Resume, Next Up, next and previous episode, skip intro and credits, chapters, trickplay previews on the scrubber
- [x] Music: albums, a play queue, now playing, shuffle and repeat, synced lyrics, scrobbling

## Phase 2 — Live TV, YouTube, and integrations ✅ DONE

- [x] Live TV, an EPG guide, and DVR with series rules
- [x] Built-in ad-free YouTube client: search, subscriptions, playlists, comments, chapters, a play queue, SponsorBlock, DeArrow, and downloads
- [x] Seerr requests, ratings (Rotten Tomatoes, IMDb, community, and MDBList sources), watch together (SyncPlay), and server administration

## Phase 3 — Player and interface ✅ DONE

- [x] One shared player across Jellyfin and YouTube
- [x] Picture-in-picture mini player and a pop-out, always-on-top desktop window
- [x] A control bar you can style, remappable keyboard shortcuts, themes, and a searchable settings screen
- [x] Full interface internationalization (English source of truth, Weblate-ready)

## Phase 4 — Release and reach

- [x] Self-contained Linux AppImage
- [x] Self-contained Windows build (portable zip)
- [x] In-app updates (Linux and Windows), with a stable or beta channel
- [ ] AUR package for Arch
- [ ] Flathub submission
- [ ] Community translations via Weblate
- [ ] Android app
- [ ] macOS and iOS builds (pending Mac hardware and a paid Apple Developer account)

## Phase 5 — Planned features

- [ ] YouTube channel video sorting (Latest, Popular, Oldest)
- [ ] A dedicated portrait Shorts viewer
- [ ] Scrubber markers for chapters, intro, and credits
- [ ] YouTube background and audio-only playback

## Parked

- Chromecast, DLNA, and AirPlay casting: not viable on Linux with Flutter, and "Play on device" remote control already covers the use case
- YouTube watch-together (SyncPlay for YouTube): tiny audience and fragile against YouTube changes
- A full phone-style Shorts swipe feed: over-engineered for a desktop, mouse-first app
