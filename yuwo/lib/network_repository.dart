import 'transactiongraph.dart';

//used when calling from backend
abstract class NetworkRepository {
  // Load public transactions within a selected layer
  Future<NetworkPayload> loadLayer({
    required String viewerId,
    required int depth,
  });

  // Search for users by username
  Future<List<Party>> searchUsers(String query);

  // Backend BFS over public transactions only
  //reuturn null if no connection found
  Future<NetworkPayload?> findPublicPath({
    required String viewerId,
    required String targetId,
  });

  // Return only private transactions of user signed in now to app
  Future<NetworkPayload> loadMyPrivateTransactions();
}

class NetworkPayload {
  const NetworkPayload({
    required this.parties,
    required this.transactions,
    this.path = const [],
  });

  final List<Party> parties;
  final List<TransactionRecord> transactions;
  final List<String> path;
}
