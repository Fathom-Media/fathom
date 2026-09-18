import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/track_languages.dart';

void main() {
  test('the first search follows the device, not always English', () {
    expect(deviceTrackLanguage(const Locale('fr')), 'fre');
    expect(deviceTrackLanguage(const Locale('pt', 'BR')), 'por');
    expect(deviceTrackLanguage(const Locale('ZH')), 'chi');
    expect(deviceTrackLanguage(const Locale('en')), 'eng');
    // A language Fathom doesn't list still has to search something.
    expect(deviceTrackLanguage(const Locale('is')), 'eng');
  });
}
