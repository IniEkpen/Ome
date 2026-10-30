import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:plough/plough.dart' as gv;

class Party {
  const Party({
    required this.id,
    required this.label,
    this.imageAsset,
    this.imageUrl,
    this.description,
    this.name,
  });

  final String id;
  final String label;
  final String? imageAsset;
  // Profile picture from the server; preferred over imageAsset.
  final String? imageUrl;
  final String? description;

  /// Full name, when the server sends one (e.g. /network/search results).
  final String? name;

  String? get image => imageUrl ?? imageAsset;

  // "Ada Lovelace" -> "AL", "ben" -> "BE"; shown when there's no picture.
  // Uses the full name when there is one, otherwise the username.
  String get initials {
    final words = (name ?? label).trim().split(RegExp(r'[\s._-]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, w.length < 2 ? w.length : 2).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}

class TransactionRecord {
  TransactionRecord({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.amount,
    required this.isPrivate,
    DateTime? timestamp,
    this.note,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final String senderId;
  final String recipientId;
  final double amount;
  final bool isPrivate;
  final DateTime timestamp;
  final String? note;
}

class TransactionGraphBuilder {
  TransactionGraphBuilder({required this.viewerId});

  final String viewerId;

  final Map<String, Party> _parties = {};
  final Map<String, TransactionRecord> _records = {};

  Iterable<Party> get parties => _parties.values;

  Iterable<TransactionRecord> get transactions => _records.values;

  Party? party(String id) => _parties[id];

  void addParty(Party party) {
    _parties[party.id] = party;
  }

  // Add a transaction and its two parties.
  void recordTransaction({
    required String id,
    required Party sender,
    required Party recipient,
    required double amount,
    bool isPrivate = false,
    DateTime? timestamp,
    String? note,
  }) {
    if (isPrivate && sender.id != viewerId && recipient.id != viewerId) {
      throw StateError('Private transaction does not belong to viewer');
    }

    addParty(sender);
    addParty(recipient);

    // Stable transaction IDs prevent duplicates.
    _records[id] = TransactionRecord(
      id: id,
      senderId: sender.id,
      recipientId: recipient.id,
      amount: amount,
      isPrivate: isPrivate,
      timestamp: timestamp,
      note: note,
    );
  }

  // Build adjacency from public transactions.
  Map<String, Set<String>> _adjacency({bool includeOwnPrivate = false}) {
    final adj = <String, Set<String>>{};

    for (final tx in _records.values) {
      if (tx.isPrivate &&
          !(includeOwnPrivate &&
              (tx.senderId == viewerId || tx.recipientId == viewerId))) {
        continue;
      }

      adj.putIfAbsent(tx.senderId, () => <String>{}).add(tx.recipientId);

      adj.putIfAbsent(tx.recipientId, () => <String>{}).add(tx.senderId);
    }

    return adj;
  }

  // BFS to determine degrees of separation.
  Map<String, int> depths(String origin, int maxDepth) {
    final adj = _adjacency();

    final depth = <String, int>{origin: 0};

    final queue = Queue<String>()..add(origin);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      if (depth[current]! >= maxDepth) {
        continue;
      }

      for (final neighbor in adj[current] ?? <String>{}) {
        if (depth.containsKey(neighbor)) {
          continue;
        }

        depth[neighbor] = depth[current]! + 1;
        queue.add(neighbor);
      }
    }

    return depth;
  }

  // BFS shortest path using public transactions only
  List<String>? shortestPublicPath(String origin, String target) {
    if (origin == target) return [origin];

    final adj = _adjacency();

    final parents = <String, String?>{origin: null};

    final queue = Queue<String>()..add(origin);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      for (final neighbor in adj[current] ?? <String>{}) {
        if (parents.containsKey(neighbor)) {
          continue;
        }

        parents[neighbor] = current;

        if (neighbor == target) {
          final path = <String>[];

          String? cursor = target;

          while (cursor != null) {
            path.add(cursor);
            cursor = parents[cursor];
          }

          return path.reversed.toList();
        }

        queue.add(neighbor);
      }
    }

    return null;
  }

  // Construct a graph containing only visible transactions
  gv.Graph visibleGraph({
    required int maxDepth,
    bool showMyPrivate = false,
    Set<String> extraIds = const {},
    List<String> highlightedPath = const [],
  }) {
    final visible = depths(viewerId, maxDepth).keys.toSet()..addAll(extraIds);

    // Add the viewer's private transaction partners.
    if (showMyPrivate) {
      for (final tx in _records.values.where(
        (t) =>
            t.isPrivate &&
            (t.senderId == viewerId || t.recipientId == viewerId),
      )) {
        visible.add(tx.senderId);
        visible.add(tx.recipientId);
      }
    }

    final graph = gv.Graph();

    final nodes = <String, gv.GraphNode>{};

    // Create visible nodes.
    for (final id in visible) {
      final party = _parties[id];

      if (party == null) continue;

      final node = gv.GraphNode(
        properties: {
          'id': id,
          'label': party.label,
          'description': party.description ?? '',
          if (party.image != null) 'image': party.image!,
          'initials': party.initials,
          'color': id == viewerId
              ? const Color(0xFF477ED5)
              : const Color(0xFF52A98D),
          'highlighted': highlightedPath.contains(id),
          'viewer': id == viewerId,
        },
      );

      // Nodes stay where the layout puts them, so none can be dragged
      // out of the map; pinch and pan move the whole map instead.
      node.canDrag = false;

      graph.addNode(node);
      nodes[id] = node;
    }

    // Group transactions between the same two users
    final grouped = <String, List<TransactionRecord>>{};

    for (final tx in _records.values) {
      if (!nodes.containsKey(tx.senderId) ||
          !nodes.containsKey(tx.recipientId)) {
        continue;
      }

      if (tx.isPrivate &&
          !(showMyPrivate &&
              (tx.senderId == viewerId || tx.recipientId == viewerId))) {
        continue;
      }

      final ends = [tx.senderId, tx.recipientId]..sort();

      grouped.putIfAbsent(ends.join('|'), () => []).add(tx);
    }

    // Identify links belonging to the shortest path.
    final highlightedEdges = <String>{};

    for (var i = 0; i + 1 < highlightedPath.length; i++) {
      final ends = [highlightedPath[i], highlightedPath[i + 1]]..sort();

      highlightedEdges.add(ends.join('|'));
    }

    // Add every eligible transaction link.
    for (final entry in grouped.entries) {
      final txs = entry.value;

      final ends = [txs.first.senderId, txs.first.recipientId]..sort();

      final isPath =
          highlightedEdges.contains(entry.key) && txs.any((t) => !t.isPrivate);

      graph.addLink(
        gv.GraphLink(
          source: nodes[ends[0]]!,
          target: nodes[ends[1]]!,
          direction: gv.GraphLinkDirection.none,
          properties: {
            'color': isPath
                ? const Color(0xFF16A085)
                : txs.every((t) => t.isPrivate)
                ? const Color(0xFF9D7BD8)
                : Colors.blueGrey,
            'weight': isPath ? 5.0 : (2 + txs.length).clamp(2, 10).toDouble(),
            'totalAmount': txs.fold<double>(0, (sum, tx) => sum + tx.amount),
            'transactionCount': txs.length,
            'history': txs,
            'highlighted': isPath,
          },
        ),
      );
    }

    return graph;
  }
}
