import 'dart:io';

import 'package:dbus/dbus.dart';

const _rootIface = 'org.mpris.MediaPlayer2';
const _playerIface = 'org.mpris.MediaPlayer2.Player';

/// Exposes Fathom as an MPRIS media player on the D-Bus session bus, so the
/// desktop's media controls (KDE/GNOME panel applet, keyboard media keys, lock
/// screen) can see and control playback. Hand-rolled because the ready-made
/// Dart MPRIS packages are pinned to Dart 2. Linux only; a no-op elsewhere.
///
/// The app feeds it state via [update] and wires the on* callbacks to the
/// active player.
class MprisService {
  DBusClient? _client;
  _MprisObject? _object;

  // Callbacks the desktop can invoke.
  void Function()? onPlayPause;
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onStop;
  void Function()? onNext;
  void Function()? onPrevious;
  void Function()? onRaise;
  void Function(int offsetUs)? onSeek; // relative
  void Function(int positionUs)? onSetPosition; // absolute
  void Function(double volume)? onSetVolume; // 0..1

  // Current state.
  String _status = 'Stopped';
  Map<String, DBusValue> _metadata = {};
  double _volume = 1.0;
  int _positionUs = 0;
  bool _canNext = false;
  bool _canPrev = false;

  Future<void> init() async {
    if (!Platform.isLinux) return;
    try {
      final client = DBusClient.session();
      final object = _MprisObject(this);
      await client.registerObject(object);
      await client.requestName('org.mpris.MediaPlayer2.fathom');
      _client = client;
      _object = object;
    } catch (_) {
      _client = null;
      _object = null;
    }
  }

  bool get _ready => _object != null;

  /// Pushes new state and notifies the desktop of what changed.
  void update({
    String? status,
    Map<String, DBusValue>? metadata,
    double? volume,
    int? positionUs,
    bool? canNext,
    bool? canPrev,
  }) {
    if (!_ready) return;
    final changed = <String, DBusValue>{};
    if (status != null && status != _status) {
      _status = status;
      changed['PlaybackStatus'] = DBusString(_status);
    }
    if (metadata != null) {
      _metadata = metadata;
      changed['Metadata'] = _metadataValue();
    }
    if (volume != null && volume != _volume) {
      _volume = volume;
      changed['Volume'] = DBusDouble(_volume);
    }
    if (canNext != null && canNext != _canNext) {
      _canNext = canNext;
      changed['CanGoNext'] = DBusBoolean(_canNext);
    }
    if (canPrev != null && canPrev != _canPrev) {
      _canPrev = canPrev;
      changed['CanGoPrevious'] = DBusBoolean(_canPrev);
    }
    // Position isn't a change-notified property in MPRIS; callers read it live.
    if (positionUs != null) _positionUs = positionUs;
    if (changed.isNotEmpty) {
      _object!.emitPropertiesChanged(_playerIface, changedProperties: changed);
    }
  }

  Future<void> dispose() async {
    await _client?.close();
    _client = null;
    _object = null;
  }

  DBusValue _metadataValue() => DBusDict(
        DBusSignature('s'),
        DBusSignature('v'),
        {
          for (final e in _metadata.entries)
            DBusString(e.key): DBusVariant(e.value),
        },
      );

  DBusValue? _rootProp(String name) => switch (name) {
        'CanQuit' => DBusBoolean(false),
        'CanRaise' => DBusBoolean(true),
        'HasTrackList' => DBusBoolean(false),
        'Identity' => DBusString('Fathom'),
        'DesktopEntry' => DBusString('app.fathom.player'),
        'SupportedUriSchemes' =>
          DBusArray(DBusSignature('s'), const <DBusValue>[]),
        'SupportedMimeTypes' =>
          DBusArray(DBusSignature('s'), const <DBusValue>[]),
        _ => null,
      };

  DBusValue? _playerProp(String name) => switch (name) {
        'PlaybackStatus' => DBusString(_status),
        'LoopStatus' => DBusString('None'),
        'Rate' => DBusDouble(1.0),
        'MinimumRate' => DBusDouble(1.0),
        'MaximumRate' => DBusDouble(1.0),
        'Shuffle' => DBusBoolean(false),
        'Metadata' => _metadataValue(),
        'Volume' => DBusDouble(_volume),
        'Position' => DBusInt64(_positionUs),
        'CanGoNext' => DBusBoolean(_canNext),
        'CanGoPrevious' => DBusBoolean(_canPrev),
        'CanPlay' => DBusBoolean(true),
        'CanPause' => DBusBoolean(true),
        'CanSeek' => DBusBoolean(true),
        'CanControl' => DBusBoolean(true),
        _ => null,
      };

  DBusValue? prop(String iface, String name) => iface == _rootIface
      ? _rootProp(name)
      : iface == _playerIface
          ? _playerProp(name)
          : null;

  Map<String, DBusValue> allProps(String iface) {
    const rootNames = [
      'CanQuit',
      'CanRaise',
      'HasTrackList',
      'Identity',
      'DesktopEntry',
      'SupportedUriSchemes',
      'SupportedMimeTypes',
    ];
    const playerNames = [
      'PlaybackStatus',
      'LoopStatus',
      'Rate',
      'MinimumRate',
      'MaximumRate',
      'Shuffle',
      'Metadata',
      'Volume',
      'Position',
      'CanGoNext',
      'CanGoPrevious',
      'CanPlay',
      'CanPause',
      'CanSeek',
      'CanControl',
    ];
    final names = iface == _rootIface ? rootNames : playerNames;
    return {
      for (final n in names)
        if (prop(iface, n) != null) n: prop(iface, n)!,
    };
  }
}

class _MprisObject extends DBusObject {
  final MprisService s;
  _MprisObject(this.s)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'), isObjectManager: false);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall m) async {
    if (m.interface == _rootIface) {
      switch (m.name) {
        case 'Raise':
          s.onRaise?.call();
          return DBusMethodSuccessResponse();
        case 'Quit':
          return DBusMethodSuccessResponse();
      }
      return DBusMethodErrorResponse.unknownMethod();
    }
    if (m.interface == _playerIface) {
      switch (m.name) {
        case 'PlayPause':
          s.onPlayPause?.call();
          return DBusMethodSuccessResponse();
        case 'Play':
          s.onPlay?.call();
          return DBusMethodSuccessResponse();
        case 'Pause':
          s.onPause?.call();
          return DBusMethodSuccessResponse();
        case 'Stop':
          s.onStop?.call();
          return DBusMethodSuccessResponse();
        case 'Next':
          s.onNext?.call();
          return DBusMethodSuccessResponse();
        case 'Previous':
          s.onPrevious?.call();
          return DBusMethodSuccessResponse();
        case 'Seek':
          s.onSeek?.call((m.values[0] as DBusInt64).value);
          return DBusMethodSuccessResponse();
        case 'SetPosition':
          s.onSetPosition?.call((m.values[1] as DBusInt64).value);
          return DBusMethodSuccessResponse();
        case 'OpenUri':
          return DBusMethodSuccessResponse();
      }
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final v = s.prop(interface, name);
    if (v == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(v);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(s.allProps(interface));
  }

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface == _playerIface && name == 'Volume' && value is DBusDouble) {
      s.onSetVolume?.call(value.value);
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.propertyReadOnly();
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectMethod method(String name) => DBusIntrospectMethod(name);
    DBusIntrospectProperty ro(String n, String sig) => DBusIntrospectProperty(
        n, DBusSignature(sig),
        access: DBusPropertyAccess.read);
    return [
      DBusIntrospectInterface(_rootIface, methods: [
        method('Raise'),
        method('Quit'),
      ], properties: [
        ro('CanQuit', 'b'),
        ro('CanRaise', 'b'),
        ro('HasTrackList', 'b'),
        ro('Identity', 's'),
        ro('DesktopEntry', 's'),
        ro('SupportedUriSchemes', 'as'),
        ro('SupportedMimeTypes', 'as'),
      ]),
      DBusIntrospectInterface(_playerIface, methods: [
        method('PlayPause'),
        method('Play'),
        method('Pause'),
        method('Stop'),
        method('Next'),
        method('Previous'),
        DBusIntrospectMethod('Seek', args: [
          DBusIntrospectArgument(
              DBusSignature('x'), DBusArgumentDirection.in_,
              name: 'Offset'),
        ]),
        DBusIntrospectMethod('SetPosition', args: [
          DBusIntrospectArgument(
              DBusSignature('o'), DBusArgumentDirection.in_,
              name: 'TrackId'),
          DBusIntrospectArgument(
              DBusSignature('x'), DBusArgumentDirection.in_,
              name: 'Position'),
        ]),
      ], signals: [
        DBusIntrospectSignal('Seeked', args: [
          DBusIntrospectArgument(
              DBusSignature('x'), DBusArgumentDirection.out,
              name: 'Position'),
        ]),
      ], properties: [
        ro('PlaybackStatus', 's'),
        DBusIntrospectProperty('Volume', DBusSignature('d'),
            access: DBusPropertyAccess.readwrite),
        ro('Metadata', 'a{sv}'),
        ro('Position', 'x'),
        ro('Rate', 'd'),
        ro('MinimumRate', 'd'),
        ro('MaximumRate', 'd'),
        ro('CanGoNext', 'b'),
        ro('CanGoPrevious', 'b'),
        ro('CanPlay', 'b'),
        ro('CanPause', 'b'),
        ro('CanSeek', 'b'),
        ro('CanControl', 'b'),
      ]),
    ];
  }
}
