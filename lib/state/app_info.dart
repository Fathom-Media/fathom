import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app version straight from the bundle (pubspec `version:`), so anywhere
/// that shows it, e.g. About, is always correct without a second hardcoded
/// string to keep in sync.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version.isNotEmpty ? info.version : '0.9.0';
});
