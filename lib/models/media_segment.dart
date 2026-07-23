import '../l10n/generated/app_localizations.dart';

/// A skippable segment of a video (intro, credits, recap, etc.) from the
/// server's Media Segments provider.
class MediaSegment {
  final String type; // Intro, Outro, Recap, Preview, Commercial, Unknown
  final int startTicks;
  final int endTicks;

  const MediaSegment({
    required this.type,
    required this.startTicks,
    required this.endTicks,
  });

  Duration get start => Duration(microseconds: startTicks ~/ 10);
  Duration get end => Duration(microseconds: endTicks ~/ 10);

  /// Localized display label for the segment's category, shown on the player's
  /// seek-bar marker. The [type] field stays the raw server token used by the
  /// matching logic below.
  String categoryLabel(AppLocalizations l) {
    switch (type) {
      case 'Intro':
        return l.miscSegmentIntro;
      case 'Recap':
        return l.miscSegmentRecap;
      case 'Outro':
        return l.miscSegmentOutro;
      case 'Preview':
        return l.miscSegmentPreview;
      case 'Commercial':
        return l.miscSegmentCommercial;
      default:
        return l.miscSegmentUnknown;
    }
  }

  bool get isIntro => type == 'Intro' || type == 'Recap';
  bool get isCredits => type == 'Outro';
  bool get isSkippable =>
      isIntro || isCredits || type == 'Preview' || type == 'Commercial';

  bool contains(Duration position) => position >= start && position < end;

  factory MediaSegment.fromJson(Map<String, dynamic> json) => MediaSegment(
        type: json['Type'] as String? ?? 'Unknown',
        startTicks: (json['StartTicks'] as num?)?.toInt() ?? 0,
        endTicks: (json['EndTicks'] as num?)?.toInt() ?? 0,
      );
}
