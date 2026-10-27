import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/services/social_sign_in.dart';

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

  test('Google sign-in sends the ID token and saves the session', () async {
    final store = _MemoryStore();
    Map<String, dynamic>? sent;
    final auth = _auth(store, (request) async {
      expect(request.url.path, '/users/oauth/google');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'token': 'g1',
        'id': 3,
        'username': 'ada',
        'isNewUser': true,
      });
    });
    final isNew = await auth.signInWithGoogle('google-id-token');
    expect(sent, {'idToken': 'google-id-token'});
    expect(isNew, isTrue);
    expect(auth.session?.username, 'ada');
    expect(store.saved?.token, 'g1');
  });

  test(
    'Apple sign-in sends token, nonce, code and the one-time name',
    () async {
      Map<String, dynamic>? sent;
      final auth = _auth(_MemoryStore(), (request) async {
        expect(request.url.path, '/users/oauth/apple');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'token': 'a1', 'id': 4, 'username': 'cleo'});
      });
      final isNew = await auth.signInWithApple(
        identityToken: 'apple-jwt',
        rawNonce: 'raw',
        authorizationCode: 'code',
        firstName: 'Cleo',
        lastName: 'Park',
      );
      expect(sent, {
        'identityToken': 'apple-jwt',
        'nonce': 'raw',
        'authorizationCode': 'code',
        'firstName': 'Cleo',
        'lastName': 'Park',
      });
      expect(isNew, isFalse);
      expect(auth.isAuthenticated, isTrue);
    },
  );

  test('a rejected provider sign-in shows the server message', () async {
    final auth = _auth(
      _MemoryStore(),
      (_) async => _json({
        'error': "Signing in with Google isn't set up yet.",
        'code': 'oauth_unavailable',
      }, 503),
    );
    await expectLater(
      auth.signInWithGoogle('x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          "Signing in with Google isn't set up yet.",
        ),
      ),
    );
    expect(auth.isAuthenticated, isFalse);
  });

  test('Apple nonce: random each time, hashed with SHA-256', () {
    final a = SocialSignIn.newNonce();
    expect(a, isNot(SocialSignIn.newNonce()));
    expect(a.length, greaterThanOrEqualTo(43));
    // SHA-256 of "abc", hex.
    expect(
      SocialSignIn.sha256Of('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
