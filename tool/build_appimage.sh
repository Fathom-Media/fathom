#!/usr/bin/env bash
#
# Builds a Fathom AppImage from a Flutter Linux release bundle.
#
#   ./tool/build_appimage.sh            # full: flutter build + package
#   SKIP_BUILD=1 ./tool/build_appimage.sh   # package an existing release bundle
#
# Output: build/Fathom-x86_64.AppImage
#
# PORTABILITY: an AppImage inherits the glibc of the machine that builds it, so
# one built on Arch needs a recent glibc and won't run on older distros. For a
# widely-distributable artifact, run this in CI on the OLDEST base you support
# (e.g. Ubuntu 22.04). Locally it produces an AppImage that runs on this machine.
set -euo pipefail

APP_ID="app.fathom.player"
BIN="fathom"
ARCH="x86_64"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pkg="$root/linux/packaging"
bundle="$root/build/linux/x64/release/bundle"
work="$root/build/appimage"
cache="$work/tools"

# 1. Release build ---------------------------------------------------------
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "==> flutter build linux --release"
  ( cd "$root" && flutter build linux --release )
fi
if [[ ! -x "$bundle/$BIN" ]]; then
  echo "Release bundle not found at $bundle/$BIN" >&2
  echo "Run 'flutter build linux --release' first (or don't set SKIP_BUILD)." >&2
  exit 1
fi

# 2. Fetch linuxdeploy + the GTK plugin ------------------------------------
mkdir -p "$cache"
fetch() { # url dest
  if [[ ! -x "$2" ]]; then
    echo "==> downloading $(basename "$2")"
    wget -qO "$2" "$1"
    chmod +x "$2"
  fi
}
ld="$cache/linuxdeploy-$ARCH.AppImage"
ldgtk="$cache/linuxdeploy-plugin-gtk.sh"
appimagetool="$cache/appimagetool-$ARCH.AppImage"
fetch "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage" "$ld"
fetch "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" "$ldgtk"
fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage" "$appimagetool"
export PATH="$cache:$PATH"

# 3. Assemble the AppDir ---------------------------------------------------
appdir="$work/AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/metainfo"

# Flutter expects lib/ and data/ next to the executable, so keep the bundle
# intact under usr/bin (rpath is $ORIGIN/lib).
cp -a "$bundle/." "$appdir/usr/bin/"

cp "$pkg/$APP_ID.desktop" "$appdir/usr/share/applications/$APP_ID.desktop"
cp "$pkg/$APP_ID.metainfo.xml" "$appdir/usr/share/metainfo/$APP_ID.metainfo.xml"
for png in "$pkg"/icons/fathom-*.png; do
  size="$(basename "$png" | sed -E 's/^fathom-([0-9]+)\.png$/\1/')"
  dest="$appdir/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dest"
  cp "$png" "$dest/$APP_ID.png"
done

# 4. libmpv is deliberately NOT bundled.
# media_kit uses the host's libmpv (the release bundle itself ships no libmpv and
# plays fine that way). Bundling libmpv drags in its driver-coupled GPU stack
# (libGL/EGL/vulkan/vaapi), and a bundled libmpv then aborts inside its renderer
# because that stack doesn't match the host's Mesa/NVIDIA driver. Using the host
# libmpv keeps one consistent, driver-matched media stack — the same reason the
# raw bundle works. Trade-off: the AppImage requires `mpv`/`libmpv` installed
# (documented; on Arch `mpv`, on Debian/Ubuntu `libmpv2`/`libmpv-dev`).
extra=()

# 5. Build the AppImage ----------------------------------------------------
export DEPLOY_GTK_VERSION=3
# Skip stripping: linuxdeploy's bundled `strip` can't parse the modern
# `.relr.dyn` ELF section emitted by recent toolchains (Arch), which aborts the
# run. Unstripped just means a larger AppImage, not a broken one.
export NO_STRIP=1
# Force the SYSTEM patchelf: linuxdeploy's bundled one is too old to rewrite the
# rpath of libraries that use DT_RELR / .relr.dyn (modern glibc), and silently
# CORRUPTS them, so the app then segfaults inside ld-linux.so on launch. A
# patchelf >= 0.18 is required when building on a bleeding-edge distro.
if command -v patchelf >/dev/null 2>&1; then
  export PATCHELF="$(command -v patchelf)"
else
  echo "WARNING: system patchelf not found; the AppImage may crash in ld-linux." >&2
  echo "         Install patchelf (>= 0.18):  sudo pacman -S patchelf" >&2
fi
export OUTPUT="$root/build/Fathom-$ARCH.AppImage"

# Deploy libraries + GTK into the AppDir (no packaging yet — we prune first).
"$ld" --appimage-extract-and-run \
  --appdir "$appdir" \
  --executable "$appdir/usr/bin/$BIN" \
  --desktop-file "$appdir/usr/share/applications/$APP_ID.desktop" \
  --icon-file "$pkg/icons/fathom-256.png" \
  --icon-filename "$APP_ID" \
  "${extra[@]}" \
  --plugin gtk

# CRITICAL: drop the whole mpv/media stack from the bundle so the app uses the
# HOST's libmpv end-to-end, exactly like the raw release bundle (which ships no
# libmpv and plays fine). A BUNDLED libmpv aborts with
#   m_config_core.c: m_config_cache_from_shadow: Assertion `group_index >= 0'
# because its media/driver stack is inconsistent with the host. linuxdeploy keeps
# re-bundling libmpv (it follows the media_kit plugin's NEEDED), so we remove it
# and its exclusive dependencies here.
#
# "Exclusive" = mpv's ldd closure MINUS the app/GTK closure, so shared libs
# (glib, png, zlib, stdc++...) stay bundled for hosts without GTK, while the
# media/codec/driver libs come from the host alongside its libmpv.
_closure() { # print the recursive ldd sonames of the given ELF files
  ldd "$@" 2>/dev/null \
    | grep -oE '/[^ ]+\.so[^ ]*' \
    | xargs -r -n1 basename \
    | sort -u
}
host_libmpv="$(awk '/libmpv\.so\.2/{print $NF; exit}' <<< "$(ldconfig -p 2>/dev/null || true)")"
if [[ -n "${host_libmpv:-}" && -e "$host_libmpv" ]]; then
  mpv_closure="$(_closure "$host_libmpv")"
  # Diff against the GTK/Flutter UI closure specifically — NOT the fathom binary,
  # which hard-links the media_kit plugin and so already pulls the whole mpv
  # stack (diffing against it would cancel to nothing).
  ui_closure="$(_closure /usr/lib/libgtk-3.so.0 /usr/lib/libgdk_pixbuf-2.0.so.0 \
                          "$appdir/usr/bin/lib/libflutter_linux_gtk.so" 2>/dev/null)"
  to_prune="$(comm -23 <(printf '%s\n' "$mpv_closure") <(printf '%s\n' "$ui_closure"))"
  echo "==> pruning mpv/media stack (host provides it): $(wc -w <<< "$to_prune") libs"
  while read -r so; do
    [[ -z "$so" ]] && continue
    rm -f "$appdir"/usr/lib/"$so" "$appdir"/usr/lib/"${so%.so*}".so*
  done <<< "$to_prune"
  rm -f "$appdir"/usr/lib/libmpv.so*
else
  echo "WARNING: host libmpv not found; leaving the bundle as linuxdeploy built it." >&2
fi

# The linuxdeploy GTK plugin hard-forces GDK_BACKEND=x11. On a Wayland session
# that routes the whole app through XWayland — no direct scanout — which makes
# video playback choppy. Fathom runs fine on native Wayland (the raw bundle
# proves it), so prefer Wayland with an X11 fallback (and still honour a user
# override).
if grep -qs 'GDK_BACKEND=x11' "$appdir"/apprun-hooks/*gtk*.sh; then
  echo "==> patching GDK_BACKEND (x11 -> wayland,x11) so Wayland sessions use direct scanout"
  sed -i 's|export GDK_BACKEND=x11.*|export GDK_BACKEND="${GDK_BACKEND:-wayland,x11}" # patched by build_appimage.sh: XWayland made video choppy|' \
    "$appdir"/apprun-hooks/*gtk*.sh
fi

# Package the pruned AppDir.
export ARCH
"$appimagetool" --appimage-extract-and-run \
  -u "gh-releases-zsync|Fathom-Media|fathom|latest|Fathom-*$ARCH.AppImage.zsync" \
  "$appdir" "$OUTPUT"

# appimagetool writes the .zsync beside OUTPUT already; tidy any stray copies.
for z in "$PWD"/Fathom-*.AppImage.zsync "$root"/Fathom-*.AppImage.zsync; do
  [[ -f "$z" && "$(dirname "$z")" != "$root/build" ]] && mv -f "$z" "$root/build/" 2>/dev/null || true
done

echo
echo "==> Built $OUTPUT"
[[ -f "$root/build/$(basename "$OUTPUT").zsync" ]] && echo "==> Update file $root/build/$(basename "$OUTPUT").zsync"
