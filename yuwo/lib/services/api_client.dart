import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL can be overridden at build time:
///   flutter run --dart-define=API_BASE_URL=https://staging.example.com
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ome-o9wx.onrender.com',
  );

  // Render free instances can take a while to wake up.
  static const timeout = Duration(seconds: 30);

  static Uri uri(String path) {
    final base = Uri.parse(baseUrl);
    final isLocal = base.host == 'localhost' || base.host == '10.0.2.2';
    if (base.scheme != 'https' && !isLocal) {
      // Never send credentials over plain HTTP outside local development.
      throw StateError('API_BASE_URL must use https: $baseUrl');
    }
    return base.replace(path: path);
  }
}

/// A user-facing error. [message] is safe to show in the UI; it never
/// contains raw server output.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiResponse {
  const ApiResponse(this.statusCode, this.json);

  final int statusCode;
  final Map<String, dynamic>? json;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Single place for HTTP so every request gets the same headers, timeout,
/// HTTPS enforcement and auth token.
class ApiClient {
  ApiClient({http.Client? httpClient, this.tokenProvider})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String? Function()? tokenProvider;

  Future<ApiResponse> post(String path, {Map<String, Object?>? body}) async {
    final headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    final token = tokenProvider?.call();
    if (token != null) headers['Authorization'] = 'Bearer $token';

    try {
      final response = await _http
          .post(
            ApiConfig.uri(path),
            headers: headers,
            body: jsonEncode(body ?? const {}),
          )
          .timeout(ApiConfig.timeout);
      return ApiResponse(response.statusCode, _decode(response.body));
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const ApiException(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
