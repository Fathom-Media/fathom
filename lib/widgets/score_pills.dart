import 'package:flutter/material.dart';

import '../state/preferences.dart';

/// Builds the rating pills (Rotten Tomatoes critics + audience, IMDb, and the
/// community/TMDB score) shared by the Jellyfin and Seerr detail pages. Each
/// pill appears only when its value is present AND its preference is enabled,
/// so scores look identical everywhere.
List<Widget> scorePills({
  int? rtCritic, // 0-100
  int? rtAudience, // 0-100
  double? imdb, // 0-10
  double? community, // 0-10 (Jellyfin CommunityRating / TMDB vote average)
  // MDBList-sourced extras, passed as normalized 0-100 scores and formatted to
  // each source's native scale here, so we don't depend on MDBList's raw value
  // field (whose scale varies by source).
  int? letterboxd,
  int? metacritic,
  int? metacriticUser,
  int? trakt,
  int? rogerEbert,
  int? myAnimeList,
  required Prefs prefs,
}) {
  String five(int s) => (s / 20).toStringAsFixed(1); // -> x.x / 5
  String ten(int s) => (s / 10).toStringAsFixed(1); // -> x.x / 10
  String four(int s) => (s / 25).toStringAsFixed(1); // -> x.x / 4
  return [
    if (prefs.showRtCritics && rtCritic != null)
      ScorePill(emoji: rtCritic >= 60 ? '🍅' : '🤢', text: '$rtCritic%'),
    if (prefs.showRtAudience && rtAudience != null)
      ScorePill(emoji: rtAudience >= 60 ? '🍿' : '🥤', text: '$rtAudience%'),
    if (prefs.showImdbRating && imdb != null)
      ScorePill(
        leading: const ImdbLogo(),
        text: imdb.toStringAsFixed(1),
      ),
    if (prefs.showCommunityRating && community != null && community > 0)
      ScorePill(
        icon: Icons.star_rounded,
        iconColor: Colors.amber,
        text: community.toStringAsFixed(1),
      ),
    if (prefs.showLetterboxd && letterboxd != null)
      ScorePill(leading: const LetterboxdLogo(), text: five(letterboxd)),
    if (prefs.showMetacritic && metacritic != null)
      ScorePill(leading: MetacriticLogo(score: metacritic), text: '$metacritic'),
    if (prefs.showMetacriticUser && metacriticUser != null)
      ScorePill(
          leading: MetacriticLogo(score: metacriticUser),
          text: ten(metacriticUser)),
    if (prefs.showTrakt && trakt != null)
      ScorePill(leading: const TraktLogo(), text: '$trakt%'),
    if (prefs.showRogerEbert && rogerEbert != null)
      ScorePill(emoji: '👍', text: four(rogerEbert)),
    if (prefs.showMyAnimeList && myAnimeList != null)
      ScorePill(leading: const MalLogo(), text: ten(myAnimeList)),
  ];
}

/// A soft rounded rating pill with an optional emoji, icon, custom leading
/// widget, or bold label prefix.
class ScorePill extends StatelessWidget {
  final String? emoji;
  final String? label;
  final Color? labelColor;
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String text;
  const ScorePill({
    super.key,
    this.emoji,
    this.label,
    this.labelColor,
    this.icon,
    this.iconColor,
    this.leading,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 5),
          ],
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor ?? scheme.onSurfaceVariant),
            const SizedBox(width: 5),
          ],
          if (label != null) ...[
            Text(label!,
                style: TextStyle(
                    color: labelColor ?? scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

/// The IMDb wordmark: black text on the signature amber-yellow rounded chip.
class ImdbLogo extends StatelessWidget {
  const ImdbLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C518),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text('IMDb',
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: -0.5,
              height: 1.25)),
    );
  }
}

/// Letterboxd's three dots (orange, green, blue), rendered in the app's style.
class LetterboxdLogo extends StatelessWidget {
  const LetterboxdLogo({super.key});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(const Color(0xFFFF8000)),
        const SizedBox(width: 2),
        dot(const Color(0xFF00E054)),
        const SizedBox(width: 2),
        dot(const Color(0xFF40BCF4)),
      ],
    );
  }
}

/// A small "M" badge tinted by the Metacritic score band (green/yellow/red).
class MetacriticLogo extends StatelessWidget {
  final int? score; // 0-100
  const MetacriticLogo({super.key, this.score});

  @override
  Widget build(BuildContext context) {
    final s = score ?? 60;
    final color = s >= 61
        ? const Color(0xFF00CE7A)
        : s >= 40
            ? const Color(0xFFFFBD3F)
            : const Color(0xFFFF6874);
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: const Text('M',
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              height: 1.0)),
    );
  }
}

/// Trakt wordmark chip.
class TraktLogo extends StatelessWidget {
  const TraktLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
          color: const Color(0xFFED1C24),
          borderRadius: BorderRadius.circular(3)),
      child: const Text('trakt',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              height: 1.25)),
    );
  }
}

/// MyAnimeList wordmark chip.
class MalLogo extends StatelessWidget {
  const MalLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
          color: const Color(0xFF2E51A2),
          borderRadius: BorderRadius.circular(3)),
      child: const Text('MAL',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              height: 1.25)),
    );
  }
}
