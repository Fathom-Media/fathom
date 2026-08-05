import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// A Jellyfin server found on the local network via UDP discovery.
class DiscoveredServer {
  final String address; // e.g. http://10.0.1.3:8096
  final String name;
  final String id;
  const DiscoveredServer(
      {required this.address, required this.name, required this.id});
}

/// Finds Jellyfin servers on the local network. Jellyfin listens for a UDP
/// broadcast of "who is JellyfinServer?" on port 7359 and replies (unicast)
/// with a JSON blob containing its Address, Name and Id — the same mechanism the
/// official apps use for "connect automatically". Cross-platform (desktop +
/// Android/TV); a no-op on web where raw sockets aren't available.
///
/// Broadcasts a few times over [timeout] and de-dupes replies by server Id.
Future<List<DiscoveredServer>> discoverJellyfinServers({
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (kIsWeb) return const [];
  final found = <String, DiscoveredServer>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final message = utf8.encode('who is JellyfinServer?');

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket?.receive();
      if (dg == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(dg.data));
        if (decoded is! Map) return;
        final data = Map<String, dynamic>.from(decoded);
        final address = (data['Address'] as String?)?.trim();
        final id = (data['Id'] as String?)?.trim();
        if (address == null || address.isEmpty || id == null || id.isEmpty) {
          return;
        }
        found[id] = DiscoveredServer(
          address: address.replaceAll(RegExp(r'/+$'), ''),
          name: (data['Name'] as String?)?.trim().isNotEmpty == true
              ? (data['Name'] as String).trim()
              : address,
          id: id,
        );
      } catch (_) {
        // Not a Jellyfin reply; ignore.
      }
    });

    // Re-broadcast a few times so a server that missed the first packet (or
    // joined the multicast group late) still answers within the window.
    final broadcast = InternetAddress('255.255.255.255');
    final rounds = (timeout.inMilliseconds / 600).ceil().clamp(1, 8);
    for (var i = 0; i < rounds; i++) {
      try {
        socket.send(message, broadcast, 7359);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  } catch (_) {
    // Binding/permission failure: return whatever (if anything) came back.
  } finally {
    socket?.close();
  }
  return found.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
