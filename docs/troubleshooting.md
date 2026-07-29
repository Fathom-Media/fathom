# Troubleshooting

## Launching (Linux)

### `command not found`

You used Windows-style syntax. In a Linux shell, run it with a forward slash:

```bash
./Fathom-x86_64.AppImage
```

### The AppImage will not open

An AppImage needs FUSE. On distributions that ship only fuse3 (Arch, for example), do one of:

```bash
sudo pacman -S fuse2                     # install the fuse2 compatibility library
./Fathom-x86_64.AppImage --appimage-extract-and-run   # or run without FUSE
```

Also make sure it is executable: `chmod +x Fathom-x86_64.AppImage`.

### `cannot execute binary file: Exec format error`

The file is for a different CPU, or the download is incomplete.

- Confirm you have the right one: **`Fathom-x86_64.AppImage`** for a normal PC, **`Fathom-aarch64.AppImage`** for ARM64. On an x86_64 machine the aarch64 build gives this exact error.
- Check the size against the Releases page (`ls -la Fathom-x86_64.AppImage`). A much smaller file was truncated; download it again.

## Updating

### The update did not relaunch, or the app will not start afterward

Usually the download was grabbed while a release was still publishing (a partial file), or an older build fetched the wrong-architecture file. Newer builds guard against both automatically, but to recover now, download the correct build for your machine directly from [Releases](https://github.com/Fathom-Media/fathom/releases/latest) and run it:

```bash
cd ~/Downloads
rm -f Fathom-x86_64.AppImage
curl -L -o Fathom-x86_64.AppImage \
  https://github.com/Fathom-Media/fathom/releases/latest/download/Fathom-x86_64.AppImage
ls -la Fathom-x86_64.AppImage    # sanity-check the size
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

After you are on a current build, in-app updates check the download's size and architecture before installing, so a bad download can no longer replace a working app.

## Playback

### A video will not play, or plays with no picture

Fathom lets mpv direct-play the file and only falls back to a server transcode on failure. Open the settings gear in the player and choose **[Playback Info](features.md#playback-info)** to see the play method, the codecs, and whether hardware decoding engaged. If direct play fails, the fallback transcode usually recovers it.

### I want to see what is actually happening

The [Playback Info](features.md#playback-info) overlay is the fastest way: it reports the real decode path (hardware vs software), dropped frames, resolution, and codecs, live from mpv.

## Diagnostics

For anything harder to pin down, turn on **Diagnostic Logging** in Settings, reproduce the problem, and export the log. It captures app errors and playback details in one place, which is the best thing to attach to a bug report.

## Still stuck?

Open an issue at [github.com/Fathom-Media/fathom/issues](https://github.com/Fathom-Media/fathom/issues) with your platform, the build version (Settings → Updates shows it), and a diagnostics export if you have one.
