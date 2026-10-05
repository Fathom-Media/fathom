# audio_service 0.18.19, patched for Fathom

A copy of [audio_service](https://pub.dev/packages/audio_service) 0.18.19 (MIT, see LICENSE),
used through `dependency_overrides` in Fathom's pubspec.yaml. The example and tests are left
out. The only change is on Android:

- `AudioService.onCreate` reconnects the static `listener` (via the new
  `AudioServicePlugin.currentHandlerListener()`) when it is null.
- A small in-memory log of what Android delivers to the service (service started and
  stopped, play, pause, stop, next, previous, and every media button with its key code,
  telling the notification's own buttons apart from earbuds and headsets), each marked when
  the service was not connected to the app. `AudioService.fathomEvents()` returns it;
  Fathom's MainActivity serves it as `mediaEvents` and the Diagnostics report appends it.
  A press that never shows up there was sent to another app by Android.

**Why:** `AudioService.onDestroy` sets `listener = null`, and the plugin only calls
`AudioService.init` when the Flutter engine first attaches. Stopping playback puts the handler
in the idle state, which stops and destroys the service; with Fathom still open its engine lives
on, so the next playback starts a new service with no listener. Every command from the media
notification, the lock screen and Bluetooth or wired headset buttons then hit
`if (listener == null) return;` and was dropped, while the app's own controls kept working.
Reproduce on the unpatched package: play, stop in the app, play again, then pause from the
notification.

**Upgrading:** copy the new release over this folder (android, darwin, lib, LICENSE,
pubspec.yaml, README.md, CHANGELOG.md, analysis_options.yaml), re-apply the patch unless
upstream has fixed it, and keep this file.
