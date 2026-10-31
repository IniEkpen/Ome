import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'split_model.dart';

/// REST calls for a bill. Every call returns the fresh snapshot, which is
/// also pushed to everyone else in the group over [LiveSplit].
class SplitService {
  const SplitService(this._auth);

  final AuthService _auth;

  SplitBill? _split(ApiResponse response, String fallback) {
    final json = response.orThrow(fallback).json?['split'];
    return json is Map<String, dynamic> ? SplitBill.fromJson(json) : null;
  }

  Future<SplitBill?> activeSplit(int groupId) async => _split(
    await _auth.client.get('/groups/$groupId/split'),
    "Couldn't load the bill.",
  );

  /// Group owner only. Opens the payment popup on every member's phone.
  Future<SplitBill> startSplit(
    int groupId, {
    required String title,
    required List<NewBillItem> items,
    required int taxCents,
    required int tipCents,
    required List<String> coHosts,
    String? merchantName,
    String? receiptDate,
    int? receiptId,
  }) async {
    final split = _split(
      await _auth.client.post(
        '/groups/$groupId/splits',
        body: {
          'title': title,
          'items': items.map((i) => i.toJson()).toList(),
          'taxCents': taxCents,
          'tipCents': tipCents,
          'hostUsernames': coHosts,
          'merchantName': ?merchantName,
          'receiptDate': ?receiptDate,
          'receiptId': ?receiptId,
        },
      ),
      "Couldn't start the bill.",
    );
    return split!;
  }

  /// Which of your saved cards pays your share (null = your default).
  Future<SplitBill?> chooseCard(int splitId, String? paymentMethodId) async =>
      _split(
        await _auth.client.put(
          '/splits/$splitId/card',
          body: {'paymentMethodId': paymentMethodId},
        ),
        "Couldn't change your card.",
      );

  Future<SplitBill?> setClaim(int splitId, int itemId, bool claimed) async =>
      _split(
        await _auth.client.put(
          '/splits/$splitId/items/$itemId/claim',
          body: {'claimed': claimed},
        ),
        "Couldn't update your items.",
      );

  // Host only from here down.

  Future<SplitBill?> setMode(int splitId, SplitMode mode) async => _split(
    await _auth.client.put('/splits/$splitId/mode', body: {'mode': mode.wire}),
    "Couldn't change how the bill is split.",
  );

  Future<SplitBill?> setWaiver(
    int splitId,
    int userId,
    int waivedCents,
  ) async => _split(
    await _auth.client.put(
      '/splits/$splitId/participants/$userId/waiver',
      body: {'waivedCents': waivedCents},
    ),
    "Couldn't update that amount.",
  );

  Future<SplitBill?> confirm(int splitId) async => _split(
    await _auth.client.post('/splits/$splitId/confirm'),
    "Couldn't confirm the bill.",
  );

  Future<SplitBill?> cancel(int splitId) async => _split(
    await _auth.client.post('/splits/$splitId/cancel'),
    "Couldn't cancel the bill.",
  );

  Future<SplitBill?> retryCharges(int splitId) async => _split(
    await _auth.client.post('/splits/$splitId/retry-charges'),
    "Couldn't retry the charges.",
  );
}

/// Holds the group's current bill and keeps it in sync with the server over
/// a live connection, reconnecting with backoff if it drops. Everyone looking
/// at the group sees the same state at the same time.
class LiveSplit extends ChangeNotifier {
  LiveSplit(this._auth, this.groupId) {
    _connect();
  }

  final AuthService _auth;
  final int groupId;

  SplitBill? _split;
  bool _connected = false;
  bool _disposed = false;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _retry;
  int _failures = 0;

  SplitBill? get split => _split;
  bool get connected => _connected;

  /// Applies a snapshot from a live event or our own request's response,
  /// ignoring anything older than what we already show.
  void apply(SplitBill? next) {
    final current = _split;
    if (next != null &&
        current != null &&
        next.id == current.id &&
        next.version < current.version) {
      return;
    }
    _split = next;
    notifyListeners();
  }

  void _connect() {
    if (_disposed) return;
    _subscription = _auth.client
        .events('/groups/$groupId/events')
        .listen(
          (event) {
            _failures = 0;
            if (!_connected) {
              _connected = true;
              notifyListeners();
            }
            if (event['type'] == 'split') {
              final json = event['split'];
              apply(
                json is Map<String, dynamic> ? SplitBill.fromJson(json) : null,
              );
            }
          },
          onError: (Object _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _connected = false;
    notifyListeners();
    _failures++;
    final seconds = (1 << _failures.clamp(1, 4)).clamp(2, 15);
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
