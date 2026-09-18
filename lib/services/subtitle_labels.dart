import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';

/// Naming subtitle and audio tracks, and telling apart the subtitle tracks the
/// app can draw itself.
///
/// The player knows only what the file says: often a bare language code, so a
/// disc rip listed "en" three times over with no way to tell which was which.
/// The server knows more, and this turns that into something readable.

/// A track's name from what the server knows: its own title if it has one,
/// otherwise the language spelled out, plus the tags that say why two English
/// tracks aren't the same.
String serverSubtitleLabel(AppLocalizations l, SubtitleStream s) {
  final title = s.title?.trim();
  final name = (title != null && title.isNotEmpty)
      ? title
      : languageFromDisplayTitle(s) ?? s.language ?? l.playerSubtitles;
  final tags = [
    if (s.isForced) l.playerSubtitleForced,
    if (!s.isTextSubtitleStream) l.playerSubtitlePicture,
    if (s.isExternal) l.playerSubtitleFile,
    // The format last, and only when it's known: SRT and ASS are both text but
    // ASS carries its own styling, and for a picture track the format is why
    // it behaves differently.
    ?subtitleFormatName(s.codec),
  ];
  return tags.isEmpty ? name : '$name (${tags.join(', ')})';
}

/// The language, spelled out, out of the server's own label for the track
/// ("English - Default - Forced - SUBRIP"). Taken from there rather than
/// mapped from the code, so it's the server's spelling in the server's
/// language, and every code is covered.
String? languageFromDisplayTitle(SubtitleStream s) {
  final display = s.displayTitle?.trim();
  if (display == null || display.isEmpty) return null;
  final first = display.split(' - ').first.trim();
  return first.isEmpty ? null : first;
}

/// Makes repeated names tellable apart: a disc rip really can carry three
/// English picture tracks, and the file says nothing about how they differ.
List<String> numberRepeats(List<String> labels) {
  final total = <String, int>{};
  for (final l in labels) {
    total[l] = (total[l] ?? 0) + 1;
  }
  final seen = <String, int>{};
  return [
    for (final l in labels)
      if ((total[l] ?? 0) > 1) '$l ${seen[l] = (seen[l] ?? 0) + 1}' else l,
  ];
}

/// Whether a track is pictures rather than text (Blu-ray PGS, DVD VobSub,
/// DVB). The app's own subtitle layer can only draw text, so these have to be
/// handed to the player, which draws them over the video.
bool isImageSubtitleCodec(String? codec) {
  final c = (codec ?? '').toLowerCase();
  return c.contains('pgs') ||
      c.contains('dvd_sub') ||
      c.contains('dvdsub') ||
      c.contains('dvb_sub') ||
      c.contains('dvbsub') ||
      c.contains('vobsub') ||
      c.contains('xsub');
}

/// An audio track's name from what the server knows: its own title if it has
/// one (a commentary says so), otherwise the language spelled out, followed by
/// the format and channel layout. The player reports little more than a
/// language code, so without this a film with a commentary listed "en" twice.
String serverAudioLabel(AppLocalizations l, AudioStream s) {
  final title = s.title?.trim();
  final name = (title != null && title.isNotEmpty)
      ? title
      : audioLanguageFromDisplayTitle(s) ?? s.language ?? l.playerAudio;
  final format = _formatName(s);
  final layout = _channelLayout(s);
  final tags = [
    if (format != null && format.isNotEmpty) format,
    ?layout,
  ];
  return tags.isEmpty ? name : '$name (${tags.join(' ')})';
}

/// The format to show: the profile when it spells out the codec ("DTS-HD MA"
/// for dts), otherwise the codec itself. AAC's profile is "LC", which names
/// nothing anyone recognises, so it isn't used.
String? _formatName(AudioStream s) {
  final codec = s.codec?.trim();
  final profile = s.profile?.trim();
  if (profile != null && profile.isNotEmpty && codec != null) {
    final root = codec.toLowerCase().split(RegExp(r'[_\-]')).first;
    if (profile.toLowerCase().contains(root)) return profile;
  }
  return codec?.toUpperCase();
}

/// "5.1", "7.1", "Stereo", "Mono": the layout as the server spells it, tidied,
/// or worked out from the channel count when it doesn't say.
String? _channelLayout(AudioStream s) {
  final layout = s.channelLayout?.trim();
  if (layout != null && layout.isNotEmpty) {
    if (layout.length > 1 && RegExp(r'^[a-z]').hasMatch(layout)) {
      return layout[0].toUpperCase() + layout.substring(1);
    }
    return layout;
  }
  switch (s.channels) {
    case 1:
      return 'Mono';
    case 2:
      return 'Stereo';
    case 6:
      return '5.1';
    case 8:
      return '7.1';
  }
  return null;
}

/// The language out of the server's own label ("English - DTS-HD MA - 5.1").
String? audioLanguageFromDisplayTitle(AudioStream s) {
  final display = s.displayTitle?.trim();
  if (display == null || display.isEmpty) return null;
  final first = display.split(' - ').first.trim();
  return first.isEmpty ? null : first;
}

/// The format under the name people know it by. The server reports the
/// container's own spelling ("subrip", "PGSSUB"), which reads like jargon.
String? subtitleFormatName(String? codec) {
  switch ((codec ?? '').toLowerCase()) {
    case 'subrip':
    case 'srt':
      return 'SRT';
    case 'ass':
      return 'ASS';
    case 'ssa':
      return 'SSA';
    case 'webvtt':
    case 'vtt':
      return 'VTT';
    case 'mov_text':
      return 'MP4';
    case 'pgssub':
    case 'hdmv_pgs_subtitle':
      return 'PGS';
    case 'dvdsub':
    case 'dvd_subtitle':
    case 'vobsub':
      return 'VobSub';
    case 'dvbsub':
    case 'dvb_subtitle':
      return 'DVB';
    case 'dvb_teletext':
      return 'Teletext';
    default:
      return null;
  }
}

