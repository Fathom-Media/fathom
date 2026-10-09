import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Jellyfin call Fathom makes must be a route the current server
/// actually serves, with the right method. Jellyfin 12 dropped a batch of old
/// routes, and one of them (GET /QuickConnect/Initiate, issue #53) slipped
/// through to users as a 405. This reads the calls straight from the source
/// and checks them against the route list recorded from a Jellyfin 12 server
/// (test/fixtures/jellyfin_routes.txt).
///
/// A call made only after the current route has failed (inside an
/// `on DioException` handler) is an old-server fallback and is allowed to use
/// a route the current server no longer has.
void main() {
  test('every Jellyfin call uses a route Jellyfin 12 serves', () {
    final routes = <String, Set<String>>{};
    for (final line in File('test/fixtures/jellyfin_routes.txt').readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final space = line.indexOf(' ');
      routes
          .putIfAbsent(_key(line.substring(space + 1)), () => {})
          .add(line.substring(0, space));
    }

    // `.get(`/`.post(`/... straight onto a '$baseUrl/...' literal, and the
    // client's own requestWithFallback('METHOD', url: '$baseUrl/...').
    final direct = RegExp(
        r"\.(get|post|put|delete|patch)(?:<[^>]*>)?\(\s*'\$\{?baseUrl\}?(/[^'?]*)");
    final wrapped = RegExp(
        r"requestWithFallback\(\s*'(\w+)',\s*url:\s*'\$\{?baseUrl\}?(/[^'?]*)");

    final checked = <String>[];
    final unknown = <String>[];
    for (final f in Directory('lib/api').listSync()) {
      if (f is! File || !f.path.contains('jellyfin')) continue;
      final src = f.readAsStringSync();
      for (final m in [...direct.allMatches(src), ...wrapped.allMatches(src)]) {
        final lineNo = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        final before = src.substring(0, m.start).split('\n');
        final context = before
            .sublist(before.length > 8 ? before.length - 8 : 0)
            .join('\n');
        if (context.contains('on DioException')) continue; // a fallback
        final method = m.group(1)!.toUpperCase();
        final path = m.group(2)!;
        checked.add('$method $path');
        if (!_served(routes, method, path)) {
          unknown.add('${f.path}:$lineNo  $method $path');
        }
      }
    }

    // Guards the scan itself: if a refactor changed how calls are written,
    // an empty or tiny list would pass while checking nothing.
    expect(checked.length, greaterThan(60));
    expect(unknown, isEmpty,
        reason: 'These calls use a route or method Jellyfin 12 does not serve. '
            'Use the current route, and keep the old one only as a fallback '
            'in an on DioException handler:\n${unknown.join('\n')}');
  });
}

/// A route in comparable form: parameters as {}, no trailing slash, any case.
String _key(String path) => path
    .replaceAll(RegExp(r'\{[^}]*\}'), '{}')
    .replaceAll(RegExp(r'/+$'), '')
    .toLowerCase();

/// Whether [path] (Dart source, with `$vars` in it) matches a served route for
/// [method]. A variable can stand for a parameter or a whole segment, and a
/// segment like `Stream.$ext` matches the route's own `Stream.{}`.
bool _served(Map<String, Set<String>> routes, String method, String path) {
  final call = _key(path
      .replaceAll(RegExp(r'\$\{[^}]+\}'), '{}')
      .replaceAll(RegExp(r'\$\w+'), '{}'));
  if (routes[call]?.contains(method) ?? false) return true;
  final callSegs = call.split('/');
  for (final entry in routes.entries) {
    if (!entry.value.contains(method)) continue;
    final segs = entry.key.split('/');
    if (segs.length != callSegs.length) continue;
    var same = true;
    for (var i = 0; i < segs.length && same; i++) {
      final a = callSegs[i], b = segs[i];
      same = a == b ||
          a == '{}' ||
          b == '{}' ||
          RegExp('^${RegExp.escape(a).replaceAll(r'\{\}', '[^/]+')}\$')
              .hasMatch(b) ||
          RegExp('^${RegExp.escape(b).replaceAll(r'\{\}', '[^/]+')}\$')
              .hasMatch(a);
    }
    if (same) return true;
  }
  return false;
}
