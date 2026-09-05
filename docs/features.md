# Library and player

## Your library

- **Movies and TV**: libraries, search, rich detail pages, resume and Next Up, next and previous episode, skip intro, recap, and credits, an Up Next prompt that rolls into the next episode during the credits, chapters, and trickplay thumbnails as you scrub.
- **Favorites and Watchlist**: two separate personal lists, one for what you love, one for what you still want to watch. Toggle either from an item's detail page or its context menu (long-press, right-click, or the overflow button, they all open the same menu).
- **Music**: albums, a play queue, now playing, shuffle and repeat, synced lyrics with an online fallback, and scrobbling. The now-playing screen flips between artwork and lyrics.
- **Live TV and DVR**: a channel list, an EPG guide, recording with series rules, and tuner and guide-provider setup.

## The player

The same player drives Jellyfin and [YouTube](youtube.md): one control bar, one seek bar (with chapter and skip markers), the same speed control, track pickers, and keyboard shortcuts, so nothing feels bolted on.

- **mpv-grade playback** through media_kit and libmpv: direct play with a transcode fallback, hardware decoding, and proper subtitle and audio track selection.
- **Picture in picture**: shrink a video into a floating mini player and keep browsing, or pop it out to a resizable, always-on-top window.
- **Up Next**: for an episode that has a next one, an Up Next card or compact Netflix-style pill appears during the credits and rolls into the next episode. Pick the style, and how long it waits before auto-skipping (the whole credits or a short countdown), under **Settings → Playback**, or leave Autoplay off and use its Play Now button.
- **Audio passthrough (desktop)**: bitstream Dolby Digital, DTS, and Dolby Atmos straight to an AV receiver instead of decoding to stereo.
- **Tune it to taste**: video fit, playback speed, a control bar you can style (glass, dark, or plain), remappable keyboard shortcuts, and scrub-preview thumbnails.

### Playback Info

Open the settings gear in the control bar and choose **Playback Info** for a read-only overlay of what is really happening, read live from mpv:

- **Play method**: direct play vs transcode (or, on YouTube, adaptive vs muxed).
- **Video and audio**: codecs, resolution, frame rate, bitrates.
- **Decoder**: whether hardware decoding actually engaged (for example `Hardware (vaapi)` vs `Software`), and dropped-frame counts.
- **General**: container, buffer, and A/V sync.

It works in both the Jellyfin and YouTube players, and stays put when you enter fullscreen.

## Internet radio

Add stations by URL or search the built-in [radio-browser.info](https://www.radio-browser.info) directory. Organize them into groups and favorites, and reorder them by drag.

- **Live time-shift**: pause and rewind a live station within a buffered window, then hit **LIVE** to jump back to the edge.
- **Switch stations**: previous/next-station controls on the Now Playing screen, and on the OS media session too (the notification, Android Auto, and Linux/Windows media controls), so a keyboard media key or steering-wheel button skips to another saved station.
- **Now playing**: station art (with album-art lookup for stations that report track info), an inline volume control, and background playback.
- Radio can be cast to a speaker or TV alongside your music.

## Casting

Fathom casts to Chromecast and Google TV devices (on Android). Video direct-plays when the target supports the codecs, or falls back to a transcode for audio-only speakers, with a queue and skip that advance on the device.

## Android Auto

On Android, Fathom offers an audio-only Android Auto experience: browse your Jellyfin music, internet radio, and YouTube in tabs, search (including by voice) to play a song or playlist, and control playback, shuffle, repeat, favorites, and the up-next queue from the car's screen.

Because Fathom is sideloaded rather than installed from the Play Store, the first time you use it you need to allow apps from unknown sources in Android Auto's developer settings. See [Fathom does not appear in Android Auto](troubleshooting.md#fathom-does-not-appear-in-android-auto) if it is not listed.

## Requests, ratings, and watch together

- **Seerr (optional)**: browse and request titles, then approve, decline, or manage requests without leaving the page, with download progress shown right on the detail view. Set it up in [First-run setup](setup.md#seerr-requests).
- **Ratings that matter to you**: Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt, and others through MDBList.
- **Watch together**: SyncPlay-based shared playback that interoperates with the official Jellyfin apps and other clients, not only with other Fathom users.

## Server administration

Run most of Jellyfin from the app, without opening the web dashboard: manage users, libraries, scheduled tasks, active sessions, playback and transcoding, networking, branding, Live TV and DVR, and plugins. Each plugin's configuration is an in-app form (toggles, fields, and add/remove lists), with a raw-JSON option if you prefer, and plugin logos show in the list.

## Personalization

Light, dark, and AMOLED themes with a custom accent color, a Home layout you can rearrange, in-app updates with a Stable or Dev channel, system and in-app notifications, a Settings screen you can search, and a fully translatable interface.

## Notifications

Fathom keeps an in-app notification centre (the bell), and shows an in-app toast while you're using the app. Choose which events you care about under **Settings → Notifications**:

- **Seerr requests**: a new request (pending approval), or one of yours being approved, declined, or becoming available.
- **Download complete**: when a download to this device finishes.
- **Update available**: when a new version of Fathom is released.

While the app is open, Fathom checks Seerr for status changes every minute or so, so updates surface almost immediately as a toast and land in the bell. On **desktop**, when Fathom is in the background these also appear as system (OS) pop-ups, toggled by the master switch at the top of the section. On **mobile**, backgrounded events wait quietly in the bell rather than raising a system notification. Either way, the per-event toggles decide what gets recorded in the first place.
