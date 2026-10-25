import '../network_repository.dart';
import '../transactiongraph.dart';
import 'auth_service.dart';

/// [NetworkRepository] backed by the /network API. The server always answers
/// for the signed-in user, so pass `session.userId.toString()` as the map's
/// `viewerId`. Amounts and notes come back as 0/null for payments you
/// weren't part of.
class ApiNetworkRepository implements NetworkRepository {
  const ApiNetworkRepository(this._auth);

  final AuthService _auth;

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = (await _auth.client.get(
      path,
      query: query,
    )).orThrow("Couldn't load the network.");
    return response.json ?? const {};
  }

  static List<Map<String, dynamic>> _rows(Object? list) => [
    for (final row in list is List ? list : const [])
      if (row is Map<String, dynamic>) row,
  ];

  static Party _party(Map<String, dynamic> json) =>
      Party(id: json['id'] as String, label: json['label'] as String);

  static NetworkPayload _payload(Map<String, dynamic> json) => NetworkPayload(
    parties: _rows(json['parties']).map(_party).toList(),
    transactions: [
      for (final tx in _rows(json['transactions']))
        TransactionRecord(
          id: tx['id'] as String,
          senderId: tx['senderId'] as String,
          recipientId: tx['recipientId'] as String,
          amount: (tx['amount'] as num? ?? 0).toDouble(),
          isPrivate: tx['isPrivate'] == true,
          timestamp: DateTime.tryParse(tx['timestamp'] as String? ?? '')
              ?.toLocal(),
          note: tx['note'] as String?,
        ),
    ],
    path: List<String>.from(json['path'] ?? const []),
  );

  @override
  Future<NetworkPayload> loadLayer({
    required String viewerId,
    required int depth,
  }) async => _payload(await _get('/network', {'depth': '$depth'}));

  @override
  Future<List<Party>> searchUsers(String query) async {
    final json = await _get('/network/search', {'q': query});
    return _rows(json['users']).map(_party).toList();
  }

  @override
  Future<NetworkPayload?> findPublicPath({
    required String viewerId,
    required String targetId,
  }) async {
    final path = (await _get('/network/path/$targetId'))['path'];
    return path is Map<String, dynamic> ? _payload(path) : null;
  }

  @override
  Future<NetworkPayload> loadMyPrivateTransactions() async =>
      _payload(await _get('/network/private'));
}
