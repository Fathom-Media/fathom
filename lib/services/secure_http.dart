import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show rootBundle;

SecurityContext? _ctx;

/// A [SecurityContext] that trusts the bundled Mozilla CA roots.
///
/// Windows' Dart/BoringSSL doesn't read the OS certificate store, so verifying
/// a normal public cert (GitHub, its download CDN) fails with
/// CERTIFICATE_VERIFY_FAILED. Shipping the CA bundle and trusting it fixes
/// HTTPS everywhere without weakening verification. Built with
/// `withTrustedRoots: false` so the bundle is the whole trust set (adding it on
/// top of the built-in roots throws on duplicates).
Future<SecurityContext> _trustContext() async {
  final cached = _ctx;
  if (cached != null) return cached;
  final ctx = SecurityContext(withTrustedRoots: false);
  final data = await rootBundle.load('assets/cacert.pem');
  ctx.setTrustedCertificatesBytes(data.buffer.asUint8List());
  _ctx = ctx;
  return ctx;
}

/// A [Dio] that trusts the bundled CA roots. Use for outbound HTTPS that must
/// work on Windows too (update checks, update downloads).
Future<Dio> secureDio({BaseOptions? options}) async {
  final ctx = await _trustContext();
  final dio = Dio(options);
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient(context: ctx),
  );
  return dio;
}

class _SecureHttpOverrides extends HttpOverrides {
  final SecurityContext _ctx;
  _SecureHttpOverrides(this._ctx);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _ctx);
}

/// Makes the bundled CA roots the process-wide default trust store, so every
/// `HttpClient` (Dio, the http package used by youtube_explode, google_fonts,
/// etc.) verifies against them.
///
/// Windows only: its Dart/BoringSSL doesn't read the OS certificate store, so
/// public HTTPS (YouTube search, stream resolution, fonts) fails with
/// CERTIFICATE_VERIFY_FAILED. macOS/Linux trust the OS roots fine, so this is a
/// no-op there. Self-signed servers aren't supported either way, so this doesn't
/// change that. Call once at startup.
Future<void> installSecureHttpOverrides() async {
  if (!Platform.isWindows) return;
  final ctx = await _trustContext();
  HttpOverrides.global = _SecureHttpOverrides(ctx);
}
