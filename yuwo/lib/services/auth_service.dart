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
  AuthService({ApiClient? client}) {
    _client = client ?? ApiClient(tokenProvider: () => _session?.token);
  }

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
    if (!response.isSuccess) {
      throw ApiException(
        "We couldn't create your account. Try a different username or email.",
        statusCode: response.statusCode,
      );
    }
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
