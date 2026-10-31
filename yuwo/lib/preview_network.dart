// TEMPORARY preview entry point: runs the network map with fake data.
// Launch with: flutter run -d chrome -t lib/preview_network.dart
import 'package:flutter/material.dart';

import 'network_repository.dart';
import 'networkmap.dart';
import 'theme/app_theme.dart';
import 'transactiongraph.dart';

void main() {
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Network(repository: FakeNetworkRepository(), viewerId: 'me'),
    ),
  );
}

class FakeNetworkRepository implements NetworkRepository {
  static const _parties = [
    Party(id: 'me', label: 'you', imageAsset: 'images/profile.png'),
    Party(id: 'ada', label: 'ada', imageAsset: 'images/profile2.png'),
    Party(id: 'ben', label: 'ben', imageAsset: 'images/profile3.png'),
    // No picture: these show initials instead.
    Party(id: 'cleo', label: 'cleo m'),
    Party(id: 'dev', label: 'dev'),
    Party(id: 'eli', label: 'eli k'),
    Party(id: 'fay', label: 'fay'),
  ];

  // (id, sender, recipient, amount, private, layer it first appears in)
  static const _txs = [
    ('1', 'me', 'ada', 24.0, false, 1),
    ('2', 'me', 'ben', 12.5, false, 1),
    ('3', 'cleo', 'me', 40.0, false, 1),
    ('4', 'ada', 'dev', 8.0, false, 2),
    ('5', 'ben', 'cleo', 15.0, false, 2),
    ('6', 'dev', 'eli', 30.0, false, 3),
    ('7', 'eli', 'fay', 9.0, false, 4),
    ('8', 'me', 'fay', 50.0, true, 0),
  ];

  List<TransactionRecord> _records(bool Function(dynamic t) keep) => [
    for (final t in _txs)
      if (keep(t))
        TransactionRecord(
          id: t.$1,
          senderId: t.$2,
          recipientId: t.$3,
          amount: t.$4,
          isPrivate: t.$5,
        ),
  ];

  @override
  Future<NetworkPayload> loadLayer({
    required String viewerId,
    required int depth,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return NetworkPayload(
      parties: _parties,
      transactions: _records((t) => !t.$5 && t.$6 <= depth),
    );
  }

  @override
  Future<List<Party>> searchUsers(String query) async => _parties
      .where((p) => p.id != 'me' && p.label.contains(query.toLowerCase()))
      .toList();

  @override
  Future<NetworkPayload?> findPublicPath({
    required String viewerId,
    required String targetId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    const paths = {
      'ada': ['me', 'ada'],
      'ben': ['me', 'ben'],
      'cleo': ['me', 'cleo'],
      'dev': ['me', 'ada', 'dev'],
      'eli': ['me', 'ada', 'dev', 'eli'],
      'fay': ['me', 'ada', 'dev', 'eli', 'fay'],
    };
    final path = paths[targetId];
    if (path == null) return null;
    return NetworkPayload(
      parties: _parties,
      transactions: _records((t) => !t.$5),
      path: path,
    );
  }

  @override
  Future<NetworkPayload> loadMyPrivateTransactions() async => NetworkPayload(
    parties: _parties,
    transactions: _records((t) => t.$5),
  );
}
