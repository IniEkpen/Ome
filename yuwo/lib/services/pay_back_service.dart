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

/// One payment in your history: a bill payment or a pay-back, in or out.
class HistoryItem {
  const HistoryItem({
    required this.kind,
    required this.id,
    required this.incoming,
    required this.otherUsername,
    required this.amountCents,
    required this.status,
    required this.at,
    this.note,
    this.groupName,
    this.canRefund = false,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    kind: json['kind'] as String,
    id: (json['id'] as num).toInt(),
    incoming: json['direction'] == 'in',
    otherUsername:
        (json['other'] as Map<String, dynamic>)['username'] as String,
    amountCents: (json['amountCents'] as num).toInt(),
    status: json['status'] as String,
    at: DateTime.parse(json['at'] as String).toLocal(),
    note: json['note'] as String?,
    groupName: json['groupName'] as String?,
    canRefund: json['canRefund'] == true,
  );

  /// 'bill' or 'payback'.
  final String kind;
  final int id;
  final bool incoming;
  final String otherUsername;
  final int amountCents;

  /// succeeded, processing, requires_action, failed, refunded or disputed.
  final String status;
  final DateTime at;
  final String? note;
  final String? groupName;

  /// You received this pay-back and can give it back.
  final bool canRefund;

  String get title =>
      incoming ? '$otherUsername paid you' : 'You paid $otherUsername';

  /// What it was for, and where: "Concert tickets", "Pizza night · Book Club".
  String get detail => [note, groupName].whereType<String>().join(' · ');
}

class HistoryPage {
  const HistoryPage(this.items, this.nextBefore);

  final List<HistoryItem> items;

  /// Pass to [PayBackService.history] for the next page; null at the end.
  final String? nextBefore;
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

  /// Every payment in or out, newest first, a page at a time.
  Future<HistoryPage> history({String? before}) async {
    final response = (await _auth.client.get(
      '/payments/history',
      query: {'before': ?before},
    )).orThrow("Couldn't load your payments.");
    final json = response.json ?? const {};
    final items = json['items'];
    return HistoryPage([
      for (final item in items is List ? items : const [])
        if (item is Map<String, dynamic>) HistoryItem.fromJson(item),
    ], json['nextBefore'] as String?);
  }

  /// Gives a pay-back you received back to the payer, in full.
  Future<void> refund(int paymentId) async {
    (await _auth.client.post(
      '/payments/direct/$paymentId/refund',
    )).orThrow("We couldn't refund that payment.");
  }

  static String newIdempotencyKey() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
