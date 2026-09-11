#!/usr/bin/env bash
#
# Builds a Fathom .deb from a Flutter Linux release bundle.
#
#   ./tool/build_deb.sh                 # full: flutter build + package
#   SKIP_BUILD=1 ./tool/build_deb.sh    # package an existing release bundle
#
# Output: build/fathom_<version>_<arch>.deb
#
# PORTABILITY: like the AppImage, the binaries inherit the glibc of the machine
# that builds them, so build this on the oldest base you support (CI uses Ubuntu
# 24.04, which is also the floor for media_kit's libmpv). Unlike the AppImage,
# this package deliberately depends on the distro's own GTK and libmpv rather
# than carrying copies: that is the point of a native package, and it is what
# lets libmpv talk to the host's GPU drivers.
set -euo pipefail

APP_ID="app.fathom.player"
BIN="fathom"
ARCH="${ARCH:-x86_64}"
case "$ARCH" in
  x86_64)  flutter_arch="x64";   deb_arch="amd64" ;;
  aarch64) flutter_arch="arm64"; deb_arch="arm64" ;;
  *) echo "Unsupported ARCH: $ARCH (use x86_64 or aarch64)" >&2; exit 1 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pkg="$root/linux/packaging"
bundle="$root/build/linux/${flutter_arch}/release/bundle"
work="$root/build/deb"

command -v dpkg-deb >/dev/null || {
  echo "dpkg-deb not found (Debian/Ubuntu: apt-get install dpkg-dev)" >&2
  exit 1
}

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  flutter build linux --release
fi
if [[ ! -x "$bundle/$BIN" ]]; then
  echo "Release bundle not found at $bundle/$BIN" >&2
  exit 1
fi

# The version Debian sees comes from pubspec (CI stamps it from the tag). Strip
# the +build suffix, and turn a pre-release dash into a tilde so that
# 0.13.0~dev01 sorts BEFORE 0.13.0, which is what a pre-release should do.
version="$(sed -n 's/^version: *//p' "$root/pubspec.yaml" | head -1)"
version="${version%%+*}"
version="${version/-/\~}"

rm -rf "$work"
root_dir="$work/pkgroot"
mkdir -p "$root_dir/DEBIAN" "$root_dir/opt/$APP_ID" "$root_dir/usr/bin" \
         "$root_dir/usr/share/applications" "$root_dir/usr/share/metainfo"

# Flutter needs lib/ and data/ next to the executable (rpath is $ORIGIN/lib),
# so the bundle stays intact under /opt and /usr/bin gets a symlink.
cp -a "$bundle/." "$root_dir/opt/$APP_ID/"
ln -s "/opt/$APP_ID/$BIN" "$root_dir/usr/bin/$BIN"

cp "$pkg/$APP_ID.desktop" "$root_dir/usr/share/applications/$APP_ID.desktop"
cp "$pkg/$APP_ID.metainfo.xml" "$root_dir/usr/share/metainfo/$APP_ID.metainfo.xml"
for png in "$pkg"/icons/fathom-*.png; do
  size="$(basename "$png" | sed -E 's/^fathom-([0-9]+)\.png$/\1/')"
  dest="$root_dir/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dest"
  cp "$png" "$dest/$APP_ID.png"
done

installed_kb="$(du -ks "$root_dir" | cut -f1)"

cat > "$root_dir/DEBIAN/control" <<EOF
Package: fathom
Version: $version
Section: video
Priority: optional
Architecture: $deb_arch
Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1, libsecret-1-0, libayatana-appindicator3-1 | libappindicator3-1
Recommends: mpv
Installed-Size: $installed_kb
Maintainer: Fathom <noreply@github.com>
Homepage: https://github.com/Fathom-Media/fathom
Description: A modern Jellyfin client
 Fathom plays your Jellyfin library on the desktop: films, shows, music and
 live TV, with YouTube and Jellyseerr alongside them.
EOF

cat > "$root_dir/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  update-desktop-database -q /usr/share/applications || true
  gtk-update-icon-cache -qf /usr/share/icons/hicolor || true
fi
EOF
# Same caches, refreshed after the files are gone, so the launcher entry and
# icon actually disappear.
cat > "$root_dir/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
  update-desktop-database -q /usr/share/applications || true
  gtk-update-icon-cache -qf /usr/share/icons/hicolor || true
fi
EOF
chmod 755 "$root_dir/DEBIAN/postinst" "$root_dir/DEBIAN/postrm"

out="$root/build/fathom_${version}_${deb_arch}.deb"
dpkg-deb --build --root-owner-group "$root_dir" "$out"
echo "Built $out"
