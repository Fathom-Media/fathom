import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/models/youtube_channel.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/youtube_providers.dart';

class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      store[key];

  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProviderContainer c;

  setUp(() {
    c = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(_FakeStorage())]);
  });
  tearDown(() => c.dispose());

  Future<YoutubeFeedGroups> groups() async {
    await c.read(youtubeFeedGroupsProvider.future);
    return c.read(youtubeFeedGroupsProvider.notifier);
  }

  test('create, add channels, rename, delete', () async {
    final g = await groups();
    final music = await g.create('Music');
    await g.toggleChannel(music.id, 'UC_a');
    await g.toggleChannel(music.id, 'UC_b');

    var list = c.read(youtubeFeedGroupsProvider).asData!.value;
    expect(list.single.channelIds, ['UC_a', 'UC_b']);
    expect(list.single.countLabel, '2 channels');

    await g.rename(music.id, 'Tunes');
    expect(c.read(youtubeFeedGroupsProvider).asData!.value.single.name, 'Tunes');

    await g.delete(music.id);
    expect(c.read(youtubeFeedGroupsProvider).asData!.value, isEmpty);
  });

  test('toggling a channel twice removes it', () async {
    final g = await groups();
    final grp = await g.create('News');
    await g.toggleChannel(grp.id, 'UC_a');
    await g.toggleChannel(grp.id, 'UC_a');
    expect(c.read(youtubeFeedGroupsProvider).asData!.value.single.channelIds,
        isEmpty);
  });

  test('an unnamed group still gets a name', () async {
    final g = await groups();
    await g.create('   ');
    expect(c.read(youtubeFeedGroupsProvider).asData!.value.single.name,
        'Untitled');
  });

  test('unsubscribing does not strand the id in a group', () async {
    // Left behind, the id would silently filter that group's feed against a
    // channel that no longer exists.
    final g = await groups();
    final grp = await g.create('Music');
    await g.toggleChannel(grp.id, 'UC_a');
    await g.toggleChannel(grp.id, 'UC_b');

    await c.read(youtubeSubscriptionsProvider.future);
    final subs = c.read(youtubeSubscriptionsProvider.notifier);
    await subs.subscribe(
        const YoutubeChannel(id: 'UC_a', title: 'A', logoUrl: ''));
    await subs.unsubscribe('UC_a');
    // The unsubscribe fires the cleanup without awaiting it.
    await Future<void>.delayed(Duration.zero);

    expect(c.read(youtubeFeedGroupsProvider).asData!.value.single.channelIds,
        ['UC_b'],
        reason: 'the unsubscribed channel is dropped from every group');
  });

  test('groups persist across a restart', () async {
    final storage = _FakeStorage();
    final c1 = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storage)]);
    await c1.read(youtubeFeedGroupsProvider.future);
    final grp = await c1.read(youtubeFeedGroupsProvider.notifier).create('Music');
    await c1.read(youtubeFeedGroupsProvider.notifier)
        .toggleChannel(grp.id, 'UC_a');
    c1.dispose();

    final c2 = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(storage)]);
    addTearDown(c2.dispose);
    final back = await c2.read(youtubeFeedGroupsProvider.future);
    expect(back.single.name, 'Music');
    expect(back.single.channelIds, ['UC_a']);
  });
}
