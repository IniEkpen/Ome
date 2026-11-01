import 'auth_service.dart';

/// One of your saved cards. The card itself stays with Stripe; this is just
/// what's shown.
class SavedCard {
  const SavedCard({
    required this.id,
    required this.last4,
    this.brand,
    this.expMonth,
    this.expYear,
    this.isDefault = false,
    this.expired = false,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    brand: json['brand'] as String?,
    last4: json['last4'] as String? ?? '????',
    expMonth: json['expMonth'] as int?,
    expYear: json['expYear'] as int?,
    isDefault: json['isDefault'] == true,
    expired: json['expired'] == true,
  );

  /// Stripe's payment method id.
  final String id;
  final String? brand;
  final String last4;
  final int? expMonth;
  final int? expYear;
  final bool isDefault;
  final bool expired;

  String get label {
    final name = brand == null || brand!.isEmpty
        ? 'Card'
        : brand![0].toUpperCase() + brand!.substring(1);
    return '$name •••• $last4';
  }

  String get expiry => expMonth == null || expYear == null
      ? ''
      : '${expMonth.toString().padLeft(2, '0')}/${expYear! % 100}';
}

/// Your saved cards. Adding one goes through PaymentService.addCard (Stripe's
/// card sheet); a newly added card becomes the default.
class CardService {
  const CardService(this._auth);

  final AuthService _auth;

  static List<SavedCard> _cards(Map<String, dynamic>? json) => [
    for (final card
        in json?['cards'] is List ? json!['cards'] as List : const [])
      if (card is Map<String, dynamic>) SavedCard.fromJson(card),
  ];

  /// Default first.
  Future<List<SavedCard>> list() async => _cards(
    (await _auth.client.get(
      '/payments/cards',
    )).orThrow("Couldn't load your cards.").json,
  );

  Future<List<SavedCard>> makeDefault(SavedCard card) async => _cards(
    (await _auth.client.post(
      '/payments/cards/${Uri.encodeComponent(card.id)}/default',
    )).orThrow("Couldn't change your default card.").json,
  );

  Future<List<SavedCard>> remove(SavedCard card) async => _cards(
    (await _auth.client.delete(
      '/payments/cards/${Uri.encodeComponent(card.id)}',
    )).orThrow("Couldn't remove that card.").json,
  );
}
