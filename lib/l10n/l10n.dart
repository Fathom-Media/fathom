import 'dart:ui' show Locale, PlatformDispatcher;

import 'generated/app_localizations.dart';

/// The app's currently resolved locale, set from [MaterialApp]'s builder (which
/// runs inside a Localizations scope). It lets code paths WITHOUT a
/// BuildContext — background workers, the notification/state layer — still
/// translate, via [tr].
Locale? activeLocale;

/// Context-free access to translations, for code with no BuildContext (e.g.
/// background download/request workers posting OS notifications). Widgets must
/// still use `AppLocalizations.of(context)`.
///
/// Resolves to [activeLocale] (or the platform locale), constrained to a
/// supported locale, falling back to the template locale (English).
AppLocalizations get tr {
  final want = activeLocale ?? PlatformDispatcher.instance.locale;
  final supported = AppLocalizations.supportedLocales;
  final match = supported.firstWhere(
    (l) => l.languageCode == want.languageCode,
    orElse: () => supported.first,
  );
  return lookupAppLocalizations(match);
}
