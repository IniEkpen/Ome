import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';

class Session {
  const Session({required this.username, this.token});

  final String username;

  /// Bearer token issued by the backend, sent on every request.
  final String? token;
}

/// Owns the signed-in state. Routing listens to this, so protected screens
/// are only reachable while [isAuthenticated] is true.
///
/// The session is held in memory only, so credentials never touch disk.
class AuthService extends ChangeNotifier {
  AuthService({ApiClient? client, this.devLogin = devLoginDefault}) {
    _client = client ?? ApiClient(tokenProvider: () => _session?.token);
  }

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
    _session = Session(
      username: username,
      token: token is String ? token : null,
    );
    notifyListeners();
  }

  Future<void> signup({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    final response = await _client.post(
      '/users/signup',
      body: {
        'username': username,
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
    _session = null;
    notifyListeners();
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
