import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Where the API is. `flutter run -d chrome` (a debug web build) talks to
/// the server on this computer (`npm run dev`); phones and release builds
/// use the deployed one. Override either way at build time:
///   flutter run --dart-define=API_BASE_URL=https://staging.example.com
abstract final class ApiConfig {
  static const _override = String.fromEnvironment('API_BASE_URL');
  static const _deployed = 'https://yuwo.onrender.com';
  static const _local = 'http://localhost:3000';

  static String get baseUrl => _override.isNotEmpty
      ? _override
      : kDebugMode && kIsWeb
      ? _local
      : _deployed;

  // Render free instances can take a while to wake up.
  static const timeout = Duration(seconds: 30);

  /// Pass query values in [query]; a '?' inside [path] would be escaped.
  static Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final isLocal = base.host == 'localhost' || base.host == '10.0.2.2';
    if (base.scheme != 'https' && !isLocal) {
      // Never send credentials over plain HTTP outside local development.
      throw StateError('API_BASE_URL must use https: $baseUrl');
    }
    return base.replace(path: path, queryParameters: query);
  }
}

/// A user-facing error. [message] is safe to show in the UI; it never
/// contains raw server output. [code] lets callers react to specific
/// failures, e.g. 'card_required'.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isCardRequired => code == 'card_required';

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;

  /// Decoded JSON: a Map, a List, or null.
  final Object? body;

  Map<String, dynamic>? get json =>
      body is Map<String, dynamic> ? body as Map<String, dynamic> : null;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// The backend only attaches a `code` to errors whose message was written
  /// for users, so those are shown as-is; anything else gets [fallback].
  ApiException error(String fallback) {
    final code = json?['code'];
    final message = json?['error'];
    return ApiException(
      code is String && message is String ? message : fallback,
      statusCode: statusCode,
      code: code is String ? code : null,
    );
  }

  /// Throws [error] unless the request succeeded.
  ApiResponse orThrow(String fallback) {
    if (!isSuccess) throw error(fallback);
    return this;
  }
}

/// Single place for HTTP so every request gets the same headers, timeout,
/// HTTPS enforcement and auth token.
class ApiClient {
  ApiClient({http.Client? httpClient, this.tokenProvider})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String? Function()? tokenProvider;

  Map<String, String> _headers({String accept = 'application/json'}) {
    final headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': accept,
    };
    final token = tokenProvider?.call();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<ApiResponse> post(String path, {Map<String, Object?>? body}) =>
      _send('POST', path, body: body);

  Future<ApiResponse> put(String path, {Map<String, Object?>? body}) =>
      _send('PUT', path, body: body);

  Future<ApiResponse> patch(String path, {Map<String, Object?>? body}) =>
      _send('PATCH', path, body: body);

  Future<ApiResponse> delete(String path) => _send('DELETE', path);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, ApiConfig.uri(path, query))
      ..headers.addAll(_headers());
    if (method != 'GET') request.body = jsonEncode(body ?? const {});

    try {
      final streamed = await _http.send(request).timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(ApiConfig.timeout);
      return ApiResponse(response.statusCode, _decode(response.body));
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const ApiException(
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Server-Sent Events: yields each `data:` payload as JSON for as long as
  /// the connection stays open. Callers reconnect when the stream ends.
  Stream<Map<String, dynamic>> events(String path) async* {
    final request = http.Request('GET', ApiConfig.uri(path))
      ..headers.addAll(_headers(accept: 'text/event-stream'));
    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const ApiException('Lost connection to the server.');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiResponse(
        response.statusCode,
        _decode(body),
      ).error('Could not connect to live updates.');
    }

    final data = StringBuffer();
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) {
        // A blank line ends one event.
        final decoded = _decode(data.toString());
        data.clear();
        if (decoded is Map<String, dynamic>) yield decoded;
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trimLeft());
      }
      // Lines starting with ':' are heartbeats and are ignored.
    }
  }

  static Object? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
