// Mirrors the snapshot the backend broadcasts. Every phone in the group gets
// the same snapshot, so the payment popup looks identical for everyone.

enum SplitMode {
  byItem('by_item', 'By item'),
  even('even', 'Evenly');

  const SplitMode(this.wire, this.label);
  final String wire;
  final String label;

  static SplitMode fromWire(String value) =>
      values.firstWhere((m) => m.wire == value, orElse: () => byItem);
}

class SplitItem {
  const SplitItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
    required this.claimedBy,
  });

  final int id;
  final String name;
  final int quantity;
  final int unitPriceCents;
  final int totalCents;
  final List<int> claimedBy;

  factory SplitItem.fromJson(Map<String, dynamic> json) => SplitItem(
    id: json['id'] as int,
    name: json['name'] as String,
    quantity: json['quantity'] as int,
    unitPriceCents: json['unitPriceCents'] as int,
    totalCents: json['totalCents'] as int,
    claimedBy: List<int>.from(json['claimedBy'] ?? const []),
  );
}

/// The card someone's share is charged to, as the group sees it.
class BillCard {
  const BillCard({
    required this.brand,
    required this.last4,
    this.chosen = false,
  });

  factory BillCard.fromJson(Map<String, dynamic> json) => BillCard(
    brand: json['brand'] as String?,
    last4: json['last4'] as String,
    chosen: json['chosen'] == true,
  );

  final String? brand;
  final String last4;

  /// Picked for this bill rather than their default card.
  final bool chosen;

  String get label {
    final name = brand == null || brand!.isEmpty
        ? 'Card'
        : brand![0].toUpperCase() + brand!.substring(1);
    return '$name •••• $last4';
  }
}

class SplitParticipant {
  const SplitParticipant({
    required this.userId,
    required this.username,
    required this.isHost,
    required this.owedCents,
    required this.waivedCents,
    required this.chargeCents,
    required this.paymentStatus,
    required this.cardOnFile,
    this.card,
  });

  final int userId;
  final String username;
  final bool isHost;
  final int owedCents;
  final int waivedCents;
  final int chargeCents;

  /// pending | not_required | processing | succeeded | failed | requires_action
  final String paymentStatus;
  final bool cardOnFile;

  /// The card their share is charged to; null if they have none.
  final BillCard? card;

  String get paymentLabel => switch (paymentStatus) {
    'succeeded' => 'Paid',
    'processing' => 'Charging…',
    'failed' => 'Card declined',
    'requires_action' => 'Needs card check',
    'refunded' => 'Refunded',
    'disputed' => 'Disputed',
    'not_required' => isHost ? 'Host' : 'Nothing owed',
    _ => 'Not charged yet',
  };

  factory SplitParticipant.fromJson(Map<String, dynamic> json) =>
      SplitParticipant(
        userId: json['userId'] as int,
        username: json['username'] as String,
        isHost: json['isHost'] == true,
        owedCents: json['owedCents'] as int? ?? 0,
        waivedCents: json['waivedCents'] as int? ?? 0,
        chargeCents: json['chargeCents'] as int? ?? 0,
        paymentStatus: json['paymentStatus'] as String? ?? 'pending',
        cardOnFile: json['cardOnFile'] == true,
        card: json['card'] is Map<String, dynamic>
            ? BillCard.fromJson(json['card'] as Map<String, dynamic>)
            : null,
      );
}

class SplitBill {
  const SplitBill({
    required this.id,
    required this.groupId,
    required this.title,
    required this.status,
    required this.mode,
    required this.taxCents,
    required this.tipCents,
    required this.version,
    required this.items,
    required this.participants,
    required this.subtotalCents,
    required this.totalCents,
    required this.collectedCents,
    required this.unclaimedItemIds,
    this.receiptId,
  });

  final int id;
  final int groupId;
  final String title;

  /// claiming | confirmed | settled | cancelled
  final String status;
  final SplitMode mode;
  final int taxCents;
  final int tipCents;
  final int version;
  final List<SplitItem> items;
  final List<SplitParticipant> participants;
  final int subtotalCents;
  final int totalCents;
  final int collectedCents;
  final List<int> unclaimedItemIds;

  /// Photo of the receipt, if the host attached one.
  final int? receiptId;

  bool get isClaiming => status == 'claiming';
  bool get isConfirmed => status == 'confirmed';
  bool get isFinished => status == 'settled' || status == 'cancelled';

  int get hostCoveredCents => totalCents - collectedCents;

  SplitParticipant? participantNamed(String username) {
    for (final p in participants) {
      if (p.username == username) return p;
    }
    return null;
  }

  String usernameOf(int userId) {
    for (final p in participants) {
      if (p.userId == userId) return p.username;
    }
    return '?';
  }

  factory SplitBill.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return SplitBill(
      id: json['id'] as int,
      groupId: json['groupId'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      mode: SplitMode.fromWire(json['mode'] as String),
      taxCents: json['taxCents'] as int? ?? 0,
      tipCents: json['tipCents'] as int? ?? 0,
      version: json['version'] as int,
      items: (json['items'] as List)
          .map((i) => SplitItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      participants: (json['participants'] as List)
          .map((p) => SplitParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      subtotalCents: totals['subtotalCents'] as int? ?? 0,
      totalCents: totals['totalCents'] as int? ?? 0,
      collectedCents: totals['collectedCents'] as int? ?? 0,
      unclaimedItemIds: List<int>.from(totals['unclaimedItemIds'] ?? const []),
      receiptId: json['receiptId'] as int?,
    );
  }
}

/// One line of a bill being entered by the host.
class NewBillItem {
  const NewBillItem({
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
  });

  final String name;
  final int quantity;
  final int unitPriceCents;

  Map<String, Object> toJson() => {
    'name': name,
    'quantity': quantity,
    'unitPriceCents': unitPriceCents,
  };
}
