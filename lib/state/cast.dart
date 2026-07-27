import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A discovered Chromecast device.
class CastDevice {
  final String id;
  final String name;
  final bool videoCapable; // false for audio-only speakers (Nest/Home Mini)
  const CastDevice(this.id, this.name, {this.videoCapable = true});
}

class CastState {
  final bool available; // Cast SDK / Play Services present
  final List<CastDevice> devices;
  final bool connected;
  final bool connecting; // a session is starting (tapped, not yet connected)
  final String? deviceName;
  // The cast device's playback state, streamed from the receiver.
  final bool playing;
  final int positionMs;
  final int durationMs;
  final String? currentUrl; // the item the receiver is actually playing
  const CastState({
    this.available = false,
    this.devices = const [],
    this.connected = false,
    this.connecting = false,
    this.deviceName,
    this.playing = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.currentUrl,
  });

  /// Either connected or mid-connection: local playback should be handed off.
  bool get casting => connected || connecting;

  CastState copyWith({
    bool? available,
    List<CastDevice>? devices,
    bool? connected,
    bool? connecting,
    String? deviceName,
    bool? playing,
    int? positionMs,
    int? durationMs,
    String? currentUrl,
  }) =>
      CastState(
        available: available ?? this.available,
        devices: devices ?? this.devices,
        connected: connected ?? this.connected,
        connecting: connecting ?? this.connecting,
        deviceName: deviceName ?? this.deviceName,
        playing: playing ?? this.playing,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        currentUrl: currentUrl ?? this.currentUrl,
      );
}

/// Wraps the native Google Cast bridge (Android only). Discovery streams device
/// lists and session state over an EventChannel; methods drive route selection,
/// media load, and playback control. A no-op off Android.
class CastController extends Notifier<CastState> {
  static const _methods = MethodChannel('app.fathom.player/cast');
  static const _events = EventChannel('app.fathom.player/cast/events');
  StreamSubscription<dynamic>? _sub;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  CastState build() {
    if (_supported) {
      _init();
      ref.onDispose(() => _sub?.cancel());
    }
    return const CastState();
  }

  Future<void> _init() async {
    final avail =
        await _methods.invokeMethod<bool>('available').catchError((_) => false) ??
            false;
    debugPrint('[cast] available=$avail');
    state = state.copyWith(available: avail);
    if (!avail) return;
    _sub = _events.receiveBroadcastStream().listen((e) {
      final m = Map<String, dynamic>.from(e as Map);
      switch (m['type']) {
        case 'devices':
          final list = (m['devices'] as List)
              .map((d) => Map<String, dynamic>.from(d as Map))
              .map((d) => CastDevice('${d['id']}', '${d['name']}',
                  videoCapable: d['video'] == true))
              .toList();
          debugPrint('[cast] devices=${list.map((d) => d.name).toList()}');
          state = state.copyWith(devices: list);
        case 'session':
          debugPrint(
              '[cast] session connected=${m['connected']} device=${m['device']}');
          state = state.copyWith(
              connected: m['connected'] == true,
              connecting: false,
              deviceName: m['device'] as String?);
        case 'media':
          state = state.copyWith(
            playing: m['playing'] == true,
            positionMs: (m['position'] as num?)?.toInt() ?? 0,
            durationMs: (m['duration'] as num?)?.toInt() ?? 0,
            currentUrl: m['currentUrl'] as String?,
          );
        case 'error':
          debugPrint('[cast] error: ${m['message']}');
      }
    });
  }

  Future<void> startDiscovery() async {
    if (!_supported) return;
    debugPrint('[cast] startDiscovery');
    await _methods.invokeMethod('startDiscovery');
  }

  Future<void> stopDiscovery() async {
    if (_supported) await _methods.invokeMethod('stopDiscovery');
  }

  Future<void> selectDevice(String id, {String? name}) async {
    if (!_supported) return;
    debugPrint('[cast] selectRoute $id');
    state = state.copyWith(connecting: true, deviceName: name);
    await _methods.invokeMethod('selectRoute', {'id': id});
  }

  Future<void> loadMedia({
    required String url,
    String? title,
    String? subtitle,
    String? image,
    String? contentType,
    int position = 0,
  }) async {
    if (!_supported) return;
    debugPrint('[cast] loadMedia type=$contentType url=$url');
    await _methods.invokeMethod('loadMedia', {
      'url': url,
      'title': title,
      'subtitle': subtitle,
      'image': image,
      'contentType': contentType,
      'position': position,
    });
  }

  /// Hands the whole queue to the receiver; it plays through and Skip advances
  /// on the device. Each item: {url, contentType, title, subtitle, image}.
  Future<void> loadQueue({
    required List<Map<String, dynamic>> items,
    required int startIndex,
    int position = 0,
  }) async {
    if (!_supported) return;
    debugPrint('[cast] loadQueue ${items.length} items @ $startIndex');
    await _methods.invokeMethod('loadQueue', {
      'items': items,
      'startIndex': startIndex,
      'position': position,
    });
  }

  Future<void> queueNext() async =>
      _supported ? _methods.invokeMethod('queueNext') : null;
  Future<void> queuePrev() async =>
      _supported ? _methods.invokeMethod('queuePrev') : null;

  Future<void> play() async =>
      _supported ? _methods.invokeMethod('play') : null;
  Future<void> pause() async =>
      _supported ? _methods.invokeMethod('pause') : null;
  Future<void> stop() async =>
      _supported ? _methods.invokeMethod('stop') : null;
  Future<void> seek(int position) async =>
      _supported ? _methods.invokeMethod('seek', {'position': position}) : null;
  Future<void> endSession() async {
    if (!_supported) return;
    state = state.copyWith(connected: false, connecting: false);
    await _methods.invokeMethod('endSession');
  }
}

final castControllerProvider =
    NotifierProvider<CastController, CastState>(CastController.new);
