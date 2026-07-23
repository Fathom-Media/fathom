#!/usr/bin/env bash
# Installs Fathom's .desktop entry and hicolor icons into ~/.local so KDE (and
# other desktops) match the running window to the icon and show it in the
# taskbar, launcher, and alt-tab. Points the launcher at the locally built
# release bundle. Re-run after moving the build. This is the same registration
# a real package (Flatpak, .deb, AUR) performs, just scoped to the current user.
set -euo pipefail

APP_ID="app.fathom.player"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
bundle="$repo_root/build/linux/x64/release/bundle"
exe="$bundle/fathom"

if [[ ! -x "$exe" ]]; then
  echo "Release build not found at $exe" >&2
  echo "Build it first:  flutter build linux --release" >&2
  exit 1
fi

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
apps_dir="$data_home/applications"
mkdir -p "$apps_dir"

# Install the hicolor icons under the app-id name that the .desktop references.
for png in "$here"/icons/fathom-*.png; do
  size="$(basename "$png" | sed -E 's/^fathom-([0-9]+)\.png$/\1/')"
  dest="$data_home/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dest"
  cp -f "$png" "$dest/$APP_ID.png"
done

# Install the .desktop, rewriting Exec to the absolute bundle path so a
# double-click launches the built binary rather than relying on PATH.
sed "s|^Exec=fathom$|Exec=$exe|" "$here/$APP_ID.desktop" > "$apps_dir/$APP_ID.desktop"

# Refresh caches so the desktop picks up the new entry/icons immediately.
update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
touch "$data_home/icons/hicolor" >/dev/null 2>&1 || true
gtk-update-icon-cache -f "$data_home/icons/hicolor" >/dev/null 2>&1 || true

echo "Installed $APP_ID.desktop and icons into $data_home"
echo "If the taskbar still shows the old icon, fully close Fathom and relaunch it."
