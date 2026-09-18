# Changelog

## 0.13.0

### Added
- Watchlist: a "want to watch" list, separate from Favorites. Toggle it from a detail page's bookmark icon or any item's menu, find it from the Libraries browse bar, or add it to the main navigation under Settings > Navigation. It syncs across your devices through your Jellyfin account.
- Movie Night Wheel: spin to settle what to watch, from the Watchlist or a SyncPlay session so a group can decide together. Fill it from your library or type titles in, and pick a mode: Last One Standing, Single Spin, or Best of 3.
- Sleep Timer on every player (video, music, YouTube, and radio): 15 minutes to 2 hours, or the end of the current track or episode, with the sound fading out over the last 15 seconds.
- Multi-select in library grids: choose Select from any poster's menu, then mark watched or unwatched, favorite, add to a playlist, or delete (with the right permission) all at once. YouTube downloads can be selected and deleted in bulk too.
- Remove from Continue Watching, from a card's menu. It takes the show or film off the row until you watch it again, and clears its resume point on the server so Jellyfin's other apps agree.
- Extras on detail pages: trailers, behind the scenes, deleted scenes, interviews, and other bonus material stored with a title get their own row.
- Search Subtitles Online, at the bottom of the subtitle menu: finds subtitles through the provider installed on your Jellyfin server (such as the OpenSubtitles plugin) and adds the one you pick straight to the video, with matches for your exact file listed first.
- Volume Levelling for music (Settings > Audio): Per Track or Per Album, using the ReplayGain levels in your files.
- YouTube chapters shown the way YouTube shows them: the current chapter in a pill beside the volume control, a seek bar split at each chapter, and the chapter named as you scrub.
- Foldable phones: half-fold the phone with the crease across the screen and the video takes the standing half, with the controls (or, on YouTube, the details and comments) on the flat half.
- Radio next and previous station controls, on the Now Playing screen, the Android notification, Android Auto, and the Linux and Windows media controls. (#41, thanks @Epic-dog)
- Server administration:
  - Backups: create a backup of the server (database, plus optional metadata, subtitles, and trickplay), see what each one holds, and restore one.
  - The user editor now covers everything the web dashboard offers: forced transcoding of remote sources, SyncPlay access, deletion limited to chosen libraries, device and channel allow-lists, allowed and blocked tags, access schedules, blocking unrated items by type, and sign-in providers where the server has more than one.
- A Windows installer, with a Start menu entry and an uninstaller, alongside the portable zip. (#43, thanks @Epic-dog)
- A Download Location setting (General > Storage) for downloaded Jellyfin media, organized into Movies, TV Shows, Music, and Recordings folders.
- YouTube downloads on Android now use a full ffmpeg, as on desktop: video above 360p, MKV, and MP3 all work. (#46, thanks @urtaevS)
- A floating progress pill for YouTube downloads, matching the one for Jellyfin downloads.
- Screen reader support: posters are announced as one item with their title and year, and every icon-only button carries a label.

### Changed
- Continue Watching follows what you actually watch: one card per show, whether you stopped part-way through an episode or finished one and the next is waiting, ordered by what you watched most recently. A new episode of a show you were caught up on goes near the front the day it arrives.
- The Home banner mixes a few things you are watching with what was added recently.
- Subtitle and audio tracks are named from what the server knows about them instead of a bare language code, for example English (Forced, SRT), English (Picture, PGS), English (External, SRT), and English (DTS-HD MA 5.1). Tracks that would otherwise look identical are numbered.
- Ready for Jellyfin 12: Fathom uses the server routes Jellyfin 12 documents, in place of older ones Jellyfin 12 dropped from its API, and saves parental ratings with Jellyfin 12's rating scores. Older servers keep working.
- Right-click, long-press, and the "..." button open the same menu everywhere, including Downloads, radio stations, album tracks, and Seerr requests: a dropdown at the pointer on desktop, a sheet on touch and TV.
- Messages, loading spinners, and confirmations look and behave the same throughout, and destructive confirmations start with Cancel focused.
- The Inter typeface is bundled with the app instead of fetched from Google Fonts on first launch.
- YouTube downloads are split into Downloading and Downloaded sections, and the download-complete notification opens them.
- "Add Favorite" now reads "Add to Favorites", matching the Watchlist.
- The keyboard Shortcuts settings no longer appear on phones and tablets.
- The Linux AppImage no longer carries AppImageUpdate data. Updating from inside Fathom works as before.

### Fixed
- Picture-based subtitles (Blu-ray PGS, DVD VobSub, DVB) never appeared when selected.
- Subtitle files stored beside the video, including ones a server plugin downloaded, were missing from the subtitle menu.
- YouTube chapters stopped appearing after YouTube moved them.
- Starting a title again straight after watching it could resume from an earlier spot, and on Android a resumed video could snap back to the beginning.
- Fathom crashed on startup on Linux setups with no system keyring at all, such as Steam Big Picture and gamescope. It now falls back to a local store. (#32, thanks @tangowithfoxtrot)
- Requesting through Seerr while signed in with a Jellyfin username and password failed with an API key error.
- The YouTube What's New tab could spin for minutes or come back empty with a large subscription list. (#38, thanks @jtbrauer92-p)
- On the Now Playing screens, the volume control covered the Play button or the repeat button, and the screen could go blank below the seek bar after the on-screen keyboard. (#40, thanks @urtaevS)
- Radio reconnects at the live edge after a dropped connection, resumes after another app briefly takes the audio (a call or a voice recorder), and its volume control no longer runs off-screen.
- Downloaded YouTube videos now play like online ones: resume, lock-screen details, Next, picture-in-picture, captions, and SponsorBlock.
- Several YouTube downloads at once no longer slow each other down.
- In server administration, choosing None for hardware acceleration or Auto for the encoder preset stopped the Transcoding page saving.
- The Home banner could show one title's details over another's backdrop.
- Marking an episode watched from Next Up didn't update its checkmark in the episode list.
- Dragging a video down the YouTube queue dropped it one slot too far.
- The desktop fullscreen title bar reappeared when an episode advanced to the next.
- Buttons overflowed in the Up Next card, the SyncPlay group list, and Seerr's request dialogs in some languages.
- Android Auto browsing showed an error after a dropped connection instead of recovering.
- The volume control's icon disappeared in the light theme.

### Security
- Every dependency is updated to its latest version. There are no open security advisories against Fathom's dependencies.

## 0.12.0

### Added
- Downloads is now a full offline library, organized into Movies, TV Shows, Recordings, and Music sections with the same poster covers and rating badges as your regular library. (#29)
- Opening a downloaded title shows the same detail page as its library page (backdrop, cast, ratings, overview), scoped to what's downloaded: only the episodes you have, with local-only Play, Mark Watched, and Remove that never touch your Jellyfin server.
- Download a whole series or season in one go, picking a scope (all episodes or a single season); every episode also has its own download option in its menu, and a floating pill shows progress with a Cancel All action. (#27)
- Download music, a single track or a whole album/artist; it plays in the music player with the familiar album view, and works fully offline.
- Download Live TV recordings; they land in their own Recordings section.
- Change your own password from the Profile screen (current password, new password, confirm). Leaving the new password blank removes it, the same "no password" option the official Jellyfin clients offer.
- Update checks now have a frequency setting (on/off, plus Every Launch, Daily, or Weekly) on the Updates screen.
- Shuffle and repeat for background YouTube audio, plus skip back to the previous track.
- Nix flake for Linux, so you can build and run Fathom with `nix build` / `nix run`. (thanks @numkem)

### Changed
- In a series, tapping an episode row opens its page. Tap the thumbnail or the play icon to play the episode directly. (#20, thanks @numkem)
- YouTube live streams start in a couple of seconds instead of tens of seconds.
- The Cast button reads "Cast" instead of "Cast to."
- A new build is now announced with a redesigned floating banner and a native system notification on Linux and Android, instead of a passing in-app message.

### Fixed
- YouTube playback works again. Audio and video had been blocked by YouTube's "confirm you're not a bot" gate. Fathom now resolves streams through the VISIONOS client, which plays without it.
- YouTube videos with multiple audio languages no longer default to a dubbed track. Fathom now picks the default (English) audio track instead of whichever has the highest bitrate. (#30, thanks @shiftyfox380)
- Background YouTube audio no longer freezes on an unplayable track, and recovers from brief network drops instead of stalling on the next song.
- Saved radio stations are no longer left out of settings backups.
- Importing YouTube subscriptions on Android no longer greys out files from cloud storage providers like Drive, Nextcloud, and Proton. (#23)
- The desktop window buttons (minimize, maximize, close) now hide when the YouTube player goes fullscreen on Windows and Linux.
- Detail page action buttons expand on touch on Android again.
- On Linux, settings and your Jellyfin login now persist on minimal desktops where the system keyring starts cold, such as Hyprland sessions. The app no longer returns to the setup screen on every launch. (#25, thanks @joejosephs)
- In-app updates on Android work again. A change in how builds were numbered had Android rejecting a newer build as a downgrade, so the update failed part way through. Builds are now always numbered above the last, so updates install.
- Duplicate "Fathom" launcher icons on Linux, when running the AppImage on GNOME, no longer appear. Fathom manages its own launcher entry and now tells AppImage integrators to stand down. (#28)

## 0.11.1

### Added
- Refresh Home on desktop from a button in the top-right, or with F5 / Ctrl+R.
- A volume control on the background YouTube-audio Now Playing screen.
- Episode and recording pages now link their title through to the series.

### Fixed
- Pull-to-refresh on Home fires reliably even when the page fits on screen without scrolling.
- Music Now Playing no longer needs scrolling in landscape on phones (the artwork moves beside the info).

## 0.11.0

### Added
- Android, and experimental Android TV: Fathom now runs on Android phones and tablets from the same universal APK, at parity with the desktop player (skip, trickplay, picture-in-picture, SyncPlay), with Chromecast and background YouTube audio with lock-screen controls. A native ExoPlayer backend is the default on Android TV (and optional on phones) for tunneled 4K/HDR playback. Android TV is included but experimental: D-pad navigation and a 10-foot interface are in place, with more polish to come.
- Android Auto (audio-only): browse your Jellyfin music, internet radio, and YouTube in tabs, search by voice, and control playback, shuffle, repeat, favorites, and the up-next queue from the car's screen.
- YouTube Shorts viewer: a vertical swipe pager through a channel's Shorts, with comments, a scrubbable progress bar, watch history, and portrait fullscreen.
- Up Next: episodes that have a next episode show an Up Next prompt over the credits, as a poster Card or a Netflix-style Pill, so it advances to the next episode instead of leaving you at the end of the file. Choose the style and timing under Settings, and Autoplay Next Episode decides whether it counts down on its own or waits for Play Now.
- Item context menu: a per-item menu on posters (long-press, right-click, or the hover hamburger), on each episode row, and in the detail overflow, with Play or Resume, Show Details, Mark Watched, Add to Favorites, Add to Playlist, Refresh Metadata, and Delete.
- Delete media: with the right server permission, delete a whole series, a season, a single episode, or a movie, each behind a confirmation.
- Audio passthrough: bitstream Atmos, Dolby Digital, and DTS to a receiver on the desktop player.
- Skip Recap: "Previously On" recaps get their own Skip Recap button, separate from Skip Intro.

### Changed
- Plugin configuration is now an in-app form (toggles, number and text fields, add/remove lists) instead of a raw JSON blob, with an Edit as JSON switch, plus plugin logos in the list and on the plugin page.
- Faster YouTube "What's New" and channel browsing (InnerTube, bounded hydration, cached feed metadata).
- YouTube audio now uses higher-resolution artwork.
- Your last volume is restored when playback hands off between the player and background audio.

### Fixed
- Skip Intro and Skip Credits now appear reliably (the app requests segment types from the server).
- Desktop fullscreen: the window's minimize, maximize, and close buttons are now hidden, and Space and the other player shortcuts work in fullscreen as well as windowed.
- Seerr search no longer fails on multi-word queries.

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
