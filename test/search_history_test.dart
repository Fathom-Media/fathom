import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/resilient_secure_storage.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/youtube_providers.dart';

/// In-memory stand-in so tests don't touch the real keyring.
class _FakeStorage implements ResilientSecureStorage {
  final Map<String, String> store = {};

  @override
  Future<String?> read({required String key}) async => store[key];

  @override
  Future<void> write({required String key, required String value}) async {
    store[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    store.remove(key);
  }
}

void main() {
  late ProviderContainer c;
  late _FakeStorage storage;

  setUp(() {
    storage = _FakeStorage();
    c = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storage)]);
  });
  tearDown(() => c.dispose());

  Future<YoutubeSearchHistory> history() async {
    await c.read(youtubeSearchHistoryProvider.future);
    return c.read(youtubeSearchHistoryProvider.notifier);
  }

  test('most recent first', () async {
    final h = await history();
    await h.record('flutter');
    await h.record('dart');
    expect(c.read(youtubeSearchHistoryProvider).asData?.value,
        ['dart', 'flutter']);
  });

  test('re-running a search moves it up rather than duplicating', () async {
    final h = await history();
    await h.record('flutter');
    await h.record('dart');
    await h.record('flutter');
    expect(c.read(youtubeSearchHistoryProvider).asData?.value,
        ['flutter', 'dart']);
  });

  test('matching is case-insensitive, so Dart and dart are one entry', () async {
    final h = await history();
    await h.record('Dart');
    await h.record('dart');
    expect(c.read(youtubeSearchHistoryProvider).asData?.value, ['dart']);
  });

  test('blank searches are not recorded', () async {
    final h = await history();
    await h.record('   ');
    expect(c.read(youtubeSearchHistoryProvider).asData?.value, isEmpty);
  });

  test('the list stays bounded', () async {
    final h = await history();
    for (var i = 0; i < 40; i++) {
      await h.record('query $i');
    }
    final list = c.read(youtubeSearchHistoryProvider).asData!.value;
    expect(list.length, lessThanOrEqualTo(30));
    expect(list.first, 'query 39', reason: 'newest survives, oldest is dropped');
  });

  test('remove and clear', () async {
    final h = await history();
    await h.record('a');
    await h.record('b');
    await h.remove('a');
    expect(c.read(youtubeSearchHistoryProvider).asData?.value, ['b']);
    await h.clear();
    expect(c.read(youtubeSearchHistoryProvider).asData?.value, isEmpty);
  });

  test('survives a restart', () async {
    final h = await history();
    await h.record('persisted');
    // A fresh container reading the same storage.
    final c2 = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storage)]);
    addTearDown(c2.dispose);
    expect(await c2.read(youtubeSearchHistoryProvider.future), ['persisted']);
  });
}
