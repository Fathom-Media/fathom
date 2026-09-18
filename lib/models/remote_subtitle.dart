/// A subtitle the server's providers offer for a title, from a search.
///
/// Downloading one is the server's job: it fetches the file and stores it
/// beside the video, where it becomes an ordinary external track.
class RemoteSubtitle {
  const RemoteSubtitle({
    required this.id,
    required this.name,
    this.providerName,
    this.format,
    this.author,
    this.comment,
    this.language,
    this.downloadCount,
    this.communityRating,
    this.isHashMatch = false,
  });

  final String id;
  final String name;
  final String? providerName;
  final String? format;
  final String? author;
  final String? comment;
  final String? language;
  final int? downloadCount;
  final double? communityRating;

  /// The provider matched the actual file, not just the title, so the timing
  /// should line up with this exact release.
  final bool isHashMatch;

  factory RemoteSubtitle.fromJson(Map<String, dynamic> json) => RemoteSubtitle(
        id: '${json['Id'] ?? ''}',
        name: (json['Name'] as String?)?.trim().isNotEmpty == true
            ? (json['Name'] as String).trim()
            : '${json['ProviderName'] ?? 'Subtitle'}',
        providerName: json['ProviderName'] as String?,
        format: json['Format'] as String?,
        author: json['Author'] as String?,
        comment: json['Comment'] as String?,
        language: json['ThreeLetterISOLanguageName'] as String?,
        downloadCount: (json['DownloadCount'] as num?)?.toInt(),
        communityRating: (json['CommunityRating'] as num?)?.toDouble(),
        isHashMatch: json['IsHashMatch'] as bool? ?? false,
      );
}

/// Best first: a match on the file itself beats everything (its timing fits
/// this exact release), then rating, then how many people took it.
List<RemoteSubtitle> sortRemoteSubtitles(List<RemoteSubtitle> subs) {
  final out = [...subs];
  out.sort((a, b) {
    if (a.isHashMatch != b.isHashMatch) return a.isHashMatch ? -1 : 1;
    final rating =
        (b.communityRating ?? 0).compareTo(a.communityRating ?? 0);
    if (rating != 0) return rating;
    return (b.downloadCount ?? 0).compareTo(a.downloadCount ?? 0);
  });
  return out;
}
