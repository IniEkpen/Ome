import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';

/// In-memory stand-in for the Keychain-backed store.
class _MemoryStore implements SessionStore {
  Session? saved;

  @override
  Future<Session?> read() async => saved;

  @override
  Future<void> write(Session session) async => saved = session;

  @override
  Future<void> clear() async => saved = null;
}

AuthService _auth(_MemoryStore store, MockClientHandler handler) {
  late final AuthService auth;
  auth = AuthService(
    client: ApiClient(
      httpClient: MockClient(handler),
      tokenProvider: () => auth.session?.token,
    ),
    store: store,
    devLogin: false,
  );
  return auth;
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  test('login is saved and restored on the next launch', () async {
    final store = _MemoryStore();
    await _auth(
      store,
      (_) async => _json({'token': 't1', 'id': 7, 'username': 'Demo'}),
    ).login(username: 'demo', password: 'password123');
    expect(store.saved?.token, 't1');
    expect(store.saved?.username, 'Demo');

    String? sentToken;
    final next = _auth(store, (request) async {
      sentToken = request.headers['Authorization'];
      return _json({'id': 7, 'username': 'Demo'});
    });
    await next.restore();
    expect(next.isAuthenticated, isTrue);
    expect(next.session?.userId, 7);
    expect(sentToken, 'Bearer t1');
  });

  test('an expired saved session is dropped', () async {
    final store = _MemoryStore()
      ..saved = const Session(username: 'demo', token: 'old', userId: 7);
    final auth = _auth(store, (_) async => _json({'code': 'x'}, 401));
    await auth.restore();
    expect(auth.isAuthenticated, isFalse);
    expect(store.saved, isNull);
  });

  test('offline at launch keeps the saved session', () async {
    final store = _MemoryStore()
      ..saved = const Session(username: 'demo', token: 't1', userId: 7);
    final auth = _auth(store, (_) async => throw http.ClientException('down'));
    await auth.restore();
    expect(auth.isAuthenticated, isTrue);
  });

  test('logout clears the saved session', () async {
    final store = _MemoryStore()
      ..saved = const Session(username: 'demo', token: 't1', userId: 7);
    final auth = _auth(store, (_) async => _json({}));
    await auth.restore();
    auth.logout();
    expect(store.saved, isNull);
  });

  test('deleting the account signs out; a refusal keeps you in', () async {
    final store = _MemoryStore()
      ..saved = const Session(username: 'demo', token: 't1', userId: 7);
    var refuse = true;
    final auth = _auth(store, (request) async {
      if (request.method != 'DELETE') return _json({});
      return refuse
          ? _json({
              'error': 'You have a bill that is still open.',
              'code': 'money_pending',
            }, 409)
          : http.Response('', 204);
    });
    await auth.restore();

    await expectLater(
      auth.deleteAccount(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'money_pending'),
      ),
    );
    expect(auth.isAuthenticated, isTrue);

    refuse = false;
    await auth.deleteAccount();
    expect(auth.isAuthenticated, isFalse);
    expect(store.saved, isNull);
  });
}
