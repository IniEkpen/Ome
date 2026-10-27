import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'social_sign_in.dart';

class Session {
  const Session({required this.username, this.token, this.userId});

  static Session? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final username = json['username'];
    final token = json['token'];
    final userId = json['userId'];
    if (username is! String || token is! String) return null;
    return Session(
      username: username,
      token: token,
      userId: userId is int ? userId : null,
    );
  }

  Map<String, Object?> toJson() => {
    'username': username,
    'token': token,
    'userId': userId,
  };

  final String username;

  /// Server id, used where the API refers to people by id (the network map).
  /// Null for local dev sessions the server didn't issue.
  final int? userId;

  /// Bearer token issued by the backend, sent on every request.
  final String? token;
}

/// Keeps the signed-in session between launches. Only the server's token is
/// stored (never the password), in the iOS Keychain / Android Keystore, or
/// the browser's storage on web.
class SessionStore {
  const SessionStore();

  static const _key = 'session';
  static const _storage = FlutterSecureStorage();

  Future<Session?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : Session.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unreadable (e.g. restored from a backup to a new device): sign in again.
      return null;
    }
  }

  Future<void> write(Session session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}

/// Owns the signed-in state. Routing listens to this, so protected screens
/// are only reachable while [isAuthenticated] is true.
///
/// With a [store], server sessions survive restarts; without one (tests),
/// they're held in memory only. Dev sessions without a token are never saved.
class AuthService extends ChangeNotifier {
  AuthService({
    ApiClient? client,
    this.store,
    this.devLogin = devLoginDefault,
  }) {
    _client = client ?? ApiClient(tokenProvider: () => _session?.token);
  }

  final SessionStore? store;

  /// Development only: any username/password signs in. Still tries the
  /// server first so you get a real token when it accepts you; otherwise you
  /// get a local session with no token (server calls will answer 401).
  /// On in debug builds; turn off with --dart-define=DEV_LOGIN=false.
  /// Always off in release builds because kDebugMode is const false there.
  static const devLoginDefault =
      kDebugMode && bool.fromEnvironment('DEV_LOGIN', defaultValue: true);

  final bool devLogin;

  late final ApiClient _client;
  Session? _session;

  ApiClient get client => _client;
  Session? get session => _session;
  bool get isAuthenticated => _session != null;

  // Same message for unknown user and wrong password so the login form
  // can't be used to discover which usernames exist.
  static const _invalidCredentials = ApiException(
    'Incorrect username or password.',
  );

  Future<void> login({
    required String username,
    required String password,
  }) async {
    if (devLogin) {
      try {
        await _serverLogin(username: username, password: password);
      } on ApiException {
        _session = Session(username: username);
        notifyListeners();
      }
      return;
    }
    await _serverLogin(username: username, password: password);
  }

  Future<void> _serverLogin({
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      '/users/login',
      body: {'username': username, 'password': password},
    );
    final json = response.json;
    final token = json?['token'];
    final userExists = json?['UserExists'];
    if (!response.isSuccess ||
        (token == null && (userExists == null || userExists == false))) {
      throw _invalidCredentials;
    }
    // Older servers answered UserExists without a token; keep accepting that.
    _acceptSignIn(json!, fallbackUsername: username, requireToken: false);
  }

  /// "Continue with Google": [idToken] comes from the google_sign_in plugin.
  /// Returns true when this created a new account.
  Future<bool> signInWithGoogle(String idToken) async {
    final response = (await _client.post(
      '/users/oauth/google',
      body: {'idToken': idToken},
    )).orThrow("We couldn't sign you in with Google. Please try again.");
    return _acceptSignIn(response.json ?? const {});
  }

  /// "Sign in with Apple". Apple only shares the person's name with the app,
  /// and only the first time, so it's passed along here. [rawNonce] is the
  /// value whose SHA-256 was given to Apple.
  Future<bool> signInWithApple({
    required String identityToken,
    required String rawNonce,
    String? authorizationCode,
    String? firstName,
    String? lastName,
  }) async {
    final response = (await _client.post(
      '/users/oauth/apple',
      body: {
        'identityToken': identityToken,
        'nonce': rawNonce,
        'authorizationCode': authorizationCode,
        'firstName': firstName,
        'lastName': lastName,
      },
    )).orThrow("We couldn't sign you in with Apple. Please try again.");
    return _acceptSignIn(response.json ?? const {});
  }

  /// Stores the session from a successful sign-in response. Returns whether
  /// the server just created the account.
  bool _acceptSignIn(
    Map<String, dynamic> json, {
    String fallbackUsername = '',
    bool requireToken = true,
  }) {
    final token = json['token'];
    final id = json['id'];
    final username = json['username'];
    if (token is! String && requireToken) throw _invalidCredentials;
    _setSession(
      Session(
        username: username is String ? username : fallbackUsername,
        token: token is String ? token : null,
        userId: id is int ? id : null,
      ),
    );
    return json['isNewUser'] == true;
  }

  void _setSession(Session? session) {
    _session = session;
    notifyListeners();
    final token = session?.token;
    if (session != null && token != null) {
      store?.write(session);
    } else {
      store?.clear();
    }
  }

  /// Signs back in with the saved session, if there is one and the server
  /// still accepts it. Call once before showing the app.
  Future<void> restore() async {
    final saved = await store?.read();
    if (saved == null) return;
    _session = saved;
    try {
      final response = await _client.get('/users/me');
      if (response.statusCode == 401) {
        _setSession(null);
        return;
      }
    } catch (_) {
      // Offline or the server is waking up: keep the session; requests
      // will ask the user to sign in again if the token turns out invalid.
    }
    notifyListeners();
  }

  Future<void> signup({
    required String username,
    required String email,
    required String phone,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final response = await _client.post(
      '/users/signup',
      body: {
        'username': username,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'password': password,
      },
    );
    response.orThrow(
      "We couldn't create your account. Try a different username or email.",
    );
    await login(username: username, password: password);
  }

  void logout() {
    _setSession(null);
    // So the next "Continue with Google" shows the account picker.
    SocialSignIn.signOut();
  }

  /// Permanently deletes the account on the server, then signs out.
  /// Throws an [ApiException] (code `money_pending`) while money is moving.
  Future<void> deleteAccount() async {
    (await _client.delete(
      '/users/me',
    )).orThrow("We couldn't delete your account. Please try again.");
    logout();
  }
}

/// Makes the [AuthService] available to the widget tree.
class AuthScope extends InheritedNotifier<AuthService> {
  const AuthScope({
    super.key,
    required AuthService service,
    required super.child,
  }) : super(notifier: service);

  /// Rebuilds the caller when auth state changes.
  static AuthService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()!.notifier!;

  /// For callbacks: reads without subscribing to changes.
  static AuthService read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AuthScope>()!.widget
              as AuthScope)
          .notifier!;
}
