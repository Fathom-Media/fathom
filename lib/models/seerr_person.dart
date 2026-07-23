import 'seerr_result.dart';

/// A person (actor/creator) from Seerr, with the titles they've appeared in.
class SeerrPerson {
  final int id;
  final String name;
  final String? biography;
  final String? birthday;
  final String? deathday;
  final String? placeOfBirth;
  final String? knownForDepartment;
  final String? profilePath;
  final List<String> alsoKnownAs;

  /// Their appearances, most notable first, as requestable results.
  final List<SeerrResult> credits;

  const SeerrPerson({
    required this.id,
    required this.name,
    this.biography,
    this.birthday,
    this.deathday,
    this.placeOfBirth,
    this.knownForDepartment,
    this.profilePath,
    this.alsoKnownAs = const [],
    this.credits = const [],
  });

  String? get profileUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w300$profilePath'
      : null;

  List<SeerrResult> get movies =>
      credits.where((c) => c.mediaType == 'movie').toList();
  List<SeerrResult> get series =>
      credits.where((c) => c.mediaType == 'tv').toList();

  /// Backdrops of their work, for the rotating header.
  List<String> get backdrops => [
        for (final c in credits)
          if (c.backdropUrl != null) c.backdropUrl!,
      ];

  factory SeerrPerson.fromJson(
          Map<String, dynamic> j, List<SeerrResult> credits) =>
      SeerrPerson(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        biography: j['biography'] as String?,
        birthday: j['birthday'] as String?,
        deathday: j['deathday'] as String?,
        placeOfBirth: j['placeOfBirth'] as String?,
        knownForDepartment: j['knownForDepartment'] as String?,
        profilePath: j['profilePath'] as String?,
        alsoKnownAs: [
          for (final a in (j['alsoKnownAs'] as List?) ?? const [])
            if (a is String && a.isNotEmpty) a,
        ],
        credits: credits,
      );
}
