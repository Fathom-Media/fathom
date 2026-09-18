# YouTube

Fathom includes a complete YouTube client, off by default. Turn it on in **Settings**. It uses no account and shows no ads, and your subscriptions, playlists, and history stay on your device. Nothing is sent to YouTube.

## What it includes

- **Search** across videos, channels, and playlists.
- **Subscriptions and feed groups**, plus your own **local playlists**.
- **Comments, captions**, a play queue, and **theater mode**.
- **Chapters, the way YouTube shows them**: the current chapter's title sits in a pill beside the volume control and opens the chapter list, the seek bar splits into a segment per chapter, and hovering or dragging along the bar names the chapter you would land in.
- **Foldable phones**: in tabletop (half-folded with the crease across the screen) the video takes the standing half, with the details, comments, and Up Next on the flat half. Fullscreen splits the same way.
- **Shorts**: a vertical swipe pager through a channel's Shorts, with comments, a scrubbable progress bar, and portrait fullscreen.
- **Background audio**: keep listening with the screen off, with lock-screen and Android Auto controls, a queue, shuffle, and repeat.
- The same player as the rest of Fathom: one control bar, seek bar, speed control, and keyboard shortcuts.

## Cleaner viewing

- **[SponsorBlock](https://sponsor.ajay.app)** skips sponsor, intro, and self-promo segments.
- **DeArrow** replaces clickbait titles and thumbnails with community-sourced ones.
- **Return YouTube Dislike** brings back the dislike count.

Each is toggled in Settings.

## Downloads

Download videos for offline viewing:

- **Video** as MP4 or MKV.
- **Audio** as M4A or MP3.
- At a **quality** and to a **folder** you choose.

!!! tip "Install ffmpeg for the best quality"
    YouTube serves high-resolution video and audio as separate streams. `ffmpeg` merges them, so it is recommended if you want downloads above 720p. Everything else works without it.

## Playback details

The [Playback Info](features.md#playback-info) overlay works here too. On YouTube its **Play method** line shows whether you are getting a high-quality **adaptive (DASH)** stream (separate video and audio) or the **muxed** fallback.
