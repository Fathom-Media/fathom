import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'resilient_secure_storage.dart';

/// Whether the app is running on an Android TV (leanback) device — i.e. driven
/// by a D-pad remote with no touchscreen. Set once at startup by [detectTvMode]
/// and read synchronously everywhere (e.g. to swap the system keyboard for the
/// on-screen [TvKeyboard], since Flutter's TV text input can't be driven).
bool isTvDevice = false;

/// True on native Android (false on web and every other platform). A cheap guard
/// for Android-only features (the native ExoPlayer backend, MediaCodec probing).
bool get isAndroidPlatform => !kIsWeb && Platform.isAndroid;

/// Queries the platform once. Safe to call anywhere; no-op off Android.
Future<void> detectTvMode() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    const channel = MethodChannel('app.fathom.player/pip');
    isTvDevice = await channel.invokeMethod<bool>('isTelevision') ?? false;
  } catch (_) {
    isTvDevice = false;
  }
}

/// Applies the user's "Force TV mode" preference at startup: if set, drive the
/// 10-foot / D-pad interface even when the platform doesn't report a television
/// (an HTPC, or a desktop build on a TV). Reads the persisted prefs directly —
/// the provider layer isn't up yet this early in `main`. No-op if already a TV.
/// The prefs key + field must match [PreferencesController] / [Prefs.toJson].
Future<void> applyForcedTvMode() async {
  if (isTvDevice) return;
  try {
    const raw = ResilientSecureStorage();
    final s = await raw.read(key: 'fathom_prefs');
    if (s == null) return;
    final json = jsonDecode(s) as Map<String, dynamic>;
    if (json['forceTvMode'] == true) isTvDevice = true;
  } catch (_) {
    // Prefs unreadable this early: fall back to platform detection only.
  }
}

/// The ffmpeg/Jellyfin video-codec names this Android device can decode in
/// HARDWARE (from MediaCodec). Empty off Android or until [detectHardwareCodecs]
/// runs. The Jellyfin device profile advertises only these as direct-play, so
/// codecs without hardware support (e.g. AV1 on cheap TV sticks) transcode to
/// h264 server-side instead of stuttering through a software decoder.
Set<String> hardwareVideoCodecs = {};

/// Queries the platform's hardware video decoders once. No-op off Android.
Future<void> detectHardwareCodecs() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    const channel = MethodChannel('app.fathom.player/pip');
    final list =
        await channel.invokeMethod<List<dynamic>>('hardwareVideoCodecs');
    if (list != null) hardwareVideoCodecs = list.cast<String>().toSet();
  } catch (_) {
    hardwareVideoCodecs = {};
  }
}
