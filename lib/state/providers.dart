import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/jellyfin_client.dart';

/// A stable per-install device id. Overridden in `main()` with the real value
/// read from secure storage before the app starts.
final deviceIdProvider = Provider<String>((ref) {
  throw UnimplementedError('deviceIdProvider must be overridden in main()');
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final jellyfinClientProvider = Provider<JellyfinClient>((ref) {
  return JellyfinClient(deviceId: ref.watch(deviceIdProvider));
});
