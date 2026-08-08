# Install

Fathom runs on **Linux** and **Windows** today. Each download is self-contained: libmpv and the media codecs are bundled, so there is nothing else to install.

Grab the newest build from the [Releases page](https://github.com/Fathom-Media/fathom/releases/latest).

## Linux (AppImage)

Fathom ships two Linux AppImages. Pick the one matching your CPU:

- **`Fathom-x86_64.AppImage`** for a normal PC (Intel / AMD).
- **`Fathom-aarch64.AppImage`** for ARM64 machines (Asahi Linux on Apple silicon, Raspberry Pi, and similar).

Download it, make it executable, and run it:

```bash
chmod +x Fathom-x86_64.AppImage
./Fathom-x86_64.AppImage
```

!!! warning "Run it with `./`, not `.\`"
    That is a forward slash. `.\Fathom-x86_64.AppImage` is Windows/PowerShell syntax and will fail in a Linux shell with `command not found`.

!!! tip "If it will not launch"
    An AppImage needs FUSE. On distributions that ship only fuse3 (Arch, for example), either install the compatibility library or run without FUSE:

    ```bash
    sudo pacman -S fuse2                     # or your distro's equivalent
    ./Fathom-x86_64.AppImage --appimage-extract-and-run
    ```

    See [Troubleshooting](troubleshooting.md) for the full list of launch fixes.

Once it runs, Fathom can keep itself up to date. See [Updates and channels](updates.md).

## Windows

Download **`Fathom-windows-x64.zip`**, extract it, and run `fathom.exe`. It is self-contained, with nothing else to install.

## Android

Download the APK from [Releases](https://github.com/Fathom-Media/fathom/releases) (named like `Fathom-0.11.0.apk`) and open it. Android asks you to allow installing unknown apps the first time; grant it and confirm. Fathom runs on phones and tablets, and on Android TV, where the interface is D-pad friendly. Android TV support is experimental for now and still being refined.

After that, Fathom keeps itself up to date from **Settings → Updates**: it downloads the new APK and hands it to the system installer for you to confirm. Pick the **Dev** channel there if you want the pre-release test builds.

## macOS and iOS

Not available yet. Building for either needs Mac hardware (and, for iOS, a paid Apple Developer account). If you would like to see Fathom on Apple platforms, a [Ko-fi](https://ko-fi.com/traceapps) toward that hardware helps.

## Build from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install). Then:

```bash
flutter pub get
flutter build linux --release      # or: flutter build windows --release
```

`ffmpeg` is recommended but optional: it merges YouTube's separate video and audio streams when you download in higher quality. Everything else works without it.

For the packaged, self-contained AppImage (libmpv bundled), see [`tool/build_appimage.sh`](https://github.com/Fathom-Media/fathom/blob/main/tool/build_appimage.sh) and the [Contributing](contributing.md) guide.
