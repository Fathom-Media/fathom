import 'dart:convert';

import '../models/youtube_channel.dart';

/// Reads and writes the subscription files other YouTube clients produce.
///
/// Subscriptions here are local, so the only way to arrive with more than a
/// handful is to bring them from somewhere. The two that matter in practice are
/// what NewPipe itself imports: Google Takeout's CSV, and NewPipe's own JSON
/// backup. Export writes NewPipe's format, so these subscriptions can leave
/// again — they shouldn't be trapped in this app either.
class SubscriptionTransfer {
  SubscriptionTransfer._();

  /// NewPipe tags each subscription with the service it came from. 0 is
  /// YouTube; anything else (SoundCloud, PeerTube…) is skipped.
  static const _youtubeServiceId = 0;

  /// Parses either supported format, chosen by content rather than by file
  /// extension — Takeout exports have been renamed by the time they reach us
  /// often enough that trusting the name is a bad bet.
  static List<YoutubeChannel> parse(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return parseNewPipeJson(content);
    }
    return parseTakeoutCsv(content);
  }

  /// NewPipe's backup: {"subscriptions":[{"service_id":0,"url":…,"name":…}]}.
  static List<YoutubeChannel> parseNewPipeJson(String content) {
    final out = <YoutubeChannel>[];
    try {
      final decoded = jsonDecode(content);
      // Accept either the wrapper or a bare array, since people hand-edit these.
      final list = decoded is Map ? decoded['subscriptions'] : decoded;
      if (list is! List) return const [];

      for (final entry in list.whereType<Map>()) {
        final serviceId = entry['service_id'];
        if (serviceId is int && serviceId != _youtubeServiceId) continue;
        final id = channelIdFromUrl('${entry['url'] ?? ''}');
        if (id == null) continue;
        out.add(YoutubeChannel(
          id: id,
          title: '${entry['name'] ?? ''}'.trim(),
          logoUrl: '',
        ));
      }
    } catch (_) {
      return const [];
    }
    return _dedupe(out);
  }

  /// Google Takeout's subscriptions.csv:
  ///   Channel Id,Channel Url,Channel Title
  ///
  /// The header is localised in non-English exports, so it isn't matched on;
  /// any row whose first field looks like a channel id is taken, which skips
  /// the header for free.
  static List<YoutubeChannel> parseTakeoutCsv(String content) {
    final out = <YoutubeChannel>[];
    for (final line in const LineSplitter().convert(content)) {
      if (line.trim().isEmpty) continue;
      final fields = _splitCsvLine(line);
      if (fields.isEmpty) continue;

      final id = fields.first.trim();
      if (!_looksLikeChannelId(id)) continue;
      out.add(YoutubeChannel(
        id: id,
        title: fields.length >= 3 ? fields[2].trim() : '',
        logoUrl: '',
      ));
    }
    return _dedupe(out);
  }

  /// NewPipe's JSON, so these can be carried to another client.
  static String exportNewPipeJson(List<YoutubeChannel> channels) {
    return const JsonEncoder.withIndent('  ').convert({
      'app_version': 'Fathom',
      'app_version_int': 0,
      'subscriptions': [
        for (final c in channels)
          {
            'service_id': _youtubeServiceId,
            'url': 'https://www.youtube.com/channel/${c.id}',
            'name': c.title,
          },
      ],
    });
  }

  /// The channel id out of any of the URL shapes these files carry. Handle URLs
  /// (/@name, /c/name, /user/name) can't be resolved without a network lookup,
  /// so they're rejected rather than guessed at.
  static String? channelIdFromUrl(String url) {
    final match = RegExp(r'/channel/(UC[A-Za-z0-9_-]{20,})').firstMatch(url);
    if (match != null) return match.group(1);
    // A bare id is also accepted: some tools export just that column.
    final bare = url.trim();
    return _looksLikeChannelId(bare) ? bare : null;
  }

  static bool _looksLikeChannelId(String s) =>
      RegExp(r'^UC[A-Za-z0-9_-]{20,}$').hasMatch(s);

  /// Minimal CSV: handles quoted fields and doubled quotes, which is all
  /// Takeout emits. Channel titles routinely contain commas.
  static List<String> _splitCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"'); // an escaped quote
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    fields.add(buffer.toString());
    return fields;
  }

  static List<YoutubeChannel> _dedupe(List<YoutubeChannel> channels) {
    final byId = <String, YoutubeChannel>{};
    for (final c in channels) {
      byId.putIfAbsent(c.id, () => c);
    }
    return byId.values.toList();
  }
}
