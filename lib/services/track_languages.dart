import 'package:flutter/widgets.dart' show Locale;

import '../l10n/generated/app_localizations.dart';

/// The languages Fathom offers for audio and subtitle tracks, keyed by the
/// three-letter code Jellyfin uses.
///
/// Shared so the preference pickers and the online subtitle search all speak
/// the same list, in the same order, with the same codes: a search asks the
/// server for one language at a time, so the code has to be one the server's
/// providers recognise.
Map<String, String> trackLanguages(AppLocalizations l) => {
      'eng': l.prefsLanguageEnglish,
      'spa': l.prefsLanguageSpanish,
      'fre': l.prefsLanguageFrench,
      'ger': l.prefsLanguageGerman,
      'ita': l.prefsLanguageItalian,
      'jpn': l.prefsLanguageJapanese,
      'kor': l.prefsLanguageKorean,
      'chi': l.prefsLanguageChinese,
      'por': l.prefsLanguagePortuguese,
      'rus': l.prefsLanguageRussian,
      'nld': l.prefsLanguageDutch,
    };

/// A language's name for display, or the code itself when it isn't one of the
/// listed ones (a server can carry any language at all).
String languageName(AppLocalizations l, String code) =>
    trackLanguages(l)[code] ?? code;

/// The language to search first when the user hasn't set a preferred subtitle
/// language: the device's own, so a French phone doesn't start with English.
/// Falls back to English for a language Fathom doesn't list.
String deviceTrackLanguage(Locale locale) {
  const byCode = {
    'en': 'eng',
    'es': 'spa',
    'fr': 'fre',
    'de': 'ger',
    'it': 'ita',
    'ja': 'jpn',
    'ko': 'kor',
    'zh': 'chi',
    'pt': 'por',
    'ru': 'rus',
    'nl': 'nld',
  };
  return byCode[locale.languageCode.toLowerCase()] ?? 'eng';
}

