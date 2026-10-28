import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_service.dart';

/// Only the *publishable* key ever ships in the app; the secret key stays on
/// the server. By default it's fetched from the server (GET /payments/config,
/// set by STRIPE_PUBLISHABLE_KEY there). A build can also bake one in:
///   flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
abstract final class StripeConfig {
  static const _buildKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static String _publishableKey = _buildKey;
  static Future<void>? _loading;

  static String get publishableKey => _publishableKey;

  // PaymentSheet only exists on Android and iOS.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isConfigured => _publishableKey.isNotEmpty && isSupported;

  /// Call once from main() after WidgetsFlutterBinding.ensureInitialized().
  /// Without a build-time key, the server's key loads in the background.
  static Future<void> init() async {
    if (!isSupported) return;
    if (_buildKey.isNotEmpty) return _apply();
    unawaited(ready());
  }

  /// Completes once a key is loaded, or the server couldn't provide one.
  /// Tries the server again if an earlier attempt failed.
  static Future<void> ready() {
    if (isConfigured || !isSupported) return Future.value();
    return _loading ??= _loadFromServer().whenComplete(() => _loading = null);
  }

  static Future<void> _loadFromServer() async {
    try {
      final response = await http
          .get(ApiConfig.uri('/payments/config'))
          .timeout(ApiConfig.timeout);
      final json = jsonDecode(response.body);
      final key = json is Map<String, dynamic> ? json['publishableKey'] : null;
      if (response.statusCode == 200 && key is String && key.startsWith('pk_')) {
        _publishableKey = key;
        await _apply();
      }
    } catch (_) {
      // Card entry stays unavailable for now; callers show a message.
    }
  }

  static Future<void> _apply() async {
    Stripe.publishableKey = _publishableKey;
    await Stripe.instance.applySettings();
  }
}

class CardStatus {
  const CardStatus({
    required this.hasValidCard,
    this.brand,
    this.last4,
    this.expMonth,
    this.expYear,
    this.payoutsEnabled = false,
  });

  static const none = CardStatus(hasValidCard: false);

  final bool hasValidCard;
  final String? brand;
  final String? last4;
  final int? expMonth;
  final int? expYear;
  final bool payoutsEnabled;

  String get label {
    if (last4 == null) return 'No card on file';
    final name = brand == null
        ? 'Card'
        : brand![0].toUpperCase() + brand!.substring(1);
    final expiry = expMonth == null
        ? ''
        : ' · exp ${expMonth.toString().padLeft(2, '0')}/${expYear! % 100}';
    return '$name •••• $last4$expiry';
  }

  factory CardStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    return CardStatus(
      hasValidCard: json['hasValidCard'] == true,
      brand: json['brand'] as String?,
      last4: json['last4'] as String?,
      expMonth: json['expMonth'] as int?,
      expYear: json['expYear'] as int?,
      payoutsEnabled: json['payoutsEnabled'] == true,
    );
  }
}

/// Card on file + host payouts. Card details go straight from Stripe's sheet
/// to Stripe; this app and our server only ever see ids and the last 4 digits.
class PaymentService {
  const PaymentService(this._auth);

  final AuthService _auth;

  Future<CardStatus> cardStatus() async {
    final response = (await _auth.client.get(
      '/payments/card',
    )).orThrow("We couldn't load your card.");
    return CardStatus.fromJson(response.json?['card'] as Map<String, dynamic>?);
  }

  /// Opens Stripe's card sheet and saves the card as the default for splits.
  /// Returns null if the user closed the sheet without adding a card.
  Future<CardStatus?> addCard() async {
    await StripeConfig.ready();
    if (!StripeConfig.isConfigured) {
      throw const ApiException(
        "Adding a card isn't available in this build yet.",
      );
    }
    final setup = (await _auth.client.post(
      '/payments/card/setup-intent',
    )).orThrow("We couldn't start adding your card.").json!;

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          setupIntentClientSecret: setup['clientSecret'] as String,
          merchantDisplayName: 'Yuwo',
        ),
      );
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return null;
      throw ApiException(
        e.error.localizedMessage ?? "Your card couldn't be added.",
      );
    }

    final saved = (await _auth.client.post(
      '/payments/card/confirm',
      body: {'setupIntentId': setup['setupIntentId']},
    )).orThrow("We couldn't save your card.");
    return CardStatus.fromJson(saved.json?['card'] as Map<String, dynamic>?);
  }

  /// Client secret for Stripe Connect's embedded onboarding, so a host can
  /// receive the money members pay them.
  Future<String> connectOnboardingSecret() async {
    final response = (await _auth.client.post(
      '/payments/connect/account-session',
    )).orThrow("We couldn't start payout setup.");
    return response.json!['clientSecret'] as String;
  }
}
