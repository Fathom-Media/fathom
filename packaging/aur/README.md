# AUR package

`PKGBUILD` builds `fathom-bin`, which repackages the released AppImage into a
normal system install (`/opt/app.fathom.player` plus a `/usr/bin/fathom`
symlink, the `.desktop` entry, the metainfo and the hicolor icons).

It depends on the system `mpv`/libmpv rather than carrying a copy, because
libmpv talks directly to the host GPU drivers.

## Publishing a release

1. Set `pkgver` to the new version (no `v` prefix) and reset `pkgrel=1`.
2. `updpkgsums` to replace the `SKIP` checksums with the real ones. This needs
   the release to be published, since it downloads the AppImage.
3. `makepkg --printsrcinfo > .SRCINFO`
4. `makepkg -si` to check it builds and installs locally.
5. Commit `PKGBUILD` and `.SRCINFO` to the AUR repo
   (`ssh://aur@aur.archlinux.org/fathom-bin.git`).

Only stable tags belong on the AUR; dev builds stay on GitHub Releases.
