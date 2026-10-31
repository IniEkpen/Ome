import 'dart:math';

import 'auth_service.dart';

/// Someone you can pay, from the people search.
class Payee {
  const Payee({required this.id, required this.username, this.name});

  factory Payee.fromJson(Map<String, dynamic> json) => Payee(
    id: int.parse(json['id'] as String),
    username: json['label'] as String,
    name: json['name'] as String?,
  );

  final int id;
  final String username;
  final String? name;

  String get displayName => name ?? username;
}

/// "Pay back": pay one person for a stated expense, outside any group.
/// Limits (also enforced by the server): $1 to $1,000 per payment, $2,000 a
/// day, and a note saying what it's for.
class PayBackService {
  const PayBackService(this._auth);

  final AuthService _auth;

  static const minCents = 100;
  static const maxCents = 100000;
  static const noteMax = 140;

  /// People matching [query] by username or name (never yourself).
  Future<List<Payee>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final response = (await _auth.client.get(
      '/network/search',
      query: {'q': q},
    )).orThrow("Couldn't search right now.");
    final users = response.json?['users'];
    return [
      for (final user in users is List ? users : const [])
        if (user is Map<String, dynamic>) Payee.fromJson(user),
    ];
  }

  /// Charges your saved card and pays [to]. Throws an [ApiException] when
  /// setup is missing (card or verification), the card is declined, or a
  /// limit is reached. Pass the same [idempotencyKey] to retry safely after
  /// a lost connection: the server returns the first attempt instead of
  /// charging again.
  Future<void> pay({
    required Payee to,
    required int amountCents,
    required String note,
    required String idempotencyKey,
  }) async {
    (await _auth.client.post(
      '/payments/direct',
      body: {
        'recipientId': to.id,
        'amountCents': amountCents,
        'note': note.trim(),
        'idempotencyKey': idempotencyKey,
      },
    )).orThrow("We couldn't send that payment. Please try again.");
  }

  static String newIdempotencyKey() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
