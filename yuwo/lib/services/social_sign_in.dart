import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Settings and helpers for "Continue with Google" and "Sign in with Apple".
/// Both are off until configured, so the app works the same without them.
///
/// Google OAuth client ids from the Yuwo project in Google Cloud. They're
/// public (Google expects them inside apps), so they're built in: the iOS
/// one on iPhone, the Web one in Chrome. Override at build time with
/// `--dart-define=GOOGLE_CLIENT_ID=...`, or turn Google off with an empty
/// value. Android needs `--dart-define=GOOGLE_SERVER_CLIENT_ID=<Web id>`.
/// Every id used must also be in the server's GOOGLE_CLIENT_IDS.
abstract final class SocialSignIn {
  static const _iosClientId =
      '236020339900-q76lub834imsf77m5qrb737ce419mj90.apps.googleusercontent.com';
  static const _webClientId =
      '236020339900-mfe4i7llegf0mgi7b9jnqan6tp3hhc4a.apps.googleusercontent.com';

  static const _clientIdOverride = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '-',
  );

  static String get googleClientId => _clientIdOverride != '-'
      ? _clientIdOverride
      : kIsWeb
      ? _webClientId
      : _iOS
      ? _iosClientId
      : '';

  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static bool get _iOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get googleEnabled =>
      (kIsWeb || _iOS) && googleClientId.isNotEmpty ||
      _android && googleServerClientId.isNotEmpty;

  /// iPhone only. App Review (guideline 4.8) requires it whenever Google
  /// sign-in is offered, so it turns on with Google; APPLE_SIGN_IN=true
  /// shows it on its own.
  static bool get appleEnabled =>
      _iOS && (googleEnabled || const bool.fromEnvironment('APPLE_SIGN_IN'));

  static Future<void>? _googleReady;

  /// Safe to call repeatedly; the plugin is initialised once.
  static Future<void> ensureGoogle() =>
      _googleReady ??= GoogleSignIn.instance.initialize(
        // Android reads its client from the app's Google config instead.
        clientId: _android ? null : googleClientId,
        serverClientId: googleServerClientId.isEmpty
            ? null
            : googleServerClientId,
      );

  /// Forgets the Google account on this device, so the next sign-in shows
  /// the account picker. Does nothing if Google was never used.
  static Future<void> signOut() async {
    final ready = _googleReady;
    if (ready == null) return;
    try {
      await ready;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Already signed out, or the plugin isn't available here.
    }
  }

  /// A random value for Apple's replay protection. Apple gets its SHA-256
  /// (see [sha256Of]); the server gets this raw value to compare.
  static String newNonce() {
    final random = Random.secure();
    return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
  }

  static String sha256Of(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
