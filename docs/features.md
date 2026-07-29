# Library and player

## Your library

- **Movies and TV**: libraries, search, rich detail pages, resume and Next Up, next and previous episode, skip intro and credits, chapters, and trickplay thumbnails as you scrub.
- **Music**: albums, a play queue, now playing, shuffle and repeat, synced lyrics with an online fallback, and scrobbling. The now-playing screen flips between artwork and lyrics.
- **Live TV and DVR**: a channel list, an EPG guide, recording with series rules, and tuner and guide-provider setup.

## The player

The same player drives Jellyfin and [YouTube](youtube.md): one control bar, one seek bar (with chapter and skip markers), the same speed control, track pickers, and keyboard shortcuts, so nothing feels bolted on.

- **mpv-grade playback** through media_kit and libmpv: direct play with a transcode fallback, hardware decoding, and proper subtitle and audio track selection.
- **Picture in picture**: shrink a video into a floating mini player and keep browsing, or pop it out to a resizable, always-on-top window.
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
- **Now playing**: station art (with album-art lookup for stations that report track info), an inline volume control, and background playback.
- Radio can be cast to a speaker or TV alongside your music.

## Casting

Fathom casts to Chromecast and Google TV devices (on Android). Video direct-plays when the target supports the codecs, or falls back to a transcode for audio-only speakers, with a queue and skip that advance on the device.

## Requests, ratings, and watch together

- **Seerr (optional)**: browse and request titles, then approve, decline, or manage requests without leaving the page, with download progress shown right on the detail view. Set it up in [First-run setup](setup.md#seerr-requests).
- **Ratings that matter to you**: Rotten Tomatoes, IMDb, and community scores, plus Letterboxd, Metacritic, Trakt, and others through MDBList.
- **Watch together**: SyncPlay-based shared playback that interoperates with the official Jellyfin apps and other clients, not only with other Fathom users.

## Server administration

Run most of Jellyfin from the app, without opening the web dashboard: manage users, libraries, scheduled tasks, active sessions, playback and transcoding, networking, branding, Live TV and DVR, and plugins.

## Personalization

Light, dark, and AMOLED themes with a custom accent color, a Home layout you can rearrange, in-app updates with a Stable or Beta channel, desktop and in-app notifications, a Settings screen you can search, and a fully translatable interface.
