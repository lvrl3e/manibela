import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for the ManibelApp backend (see /backend in the repo).
///
/// `localhost` works for the Windows desktop build and iOS simulator, and
/// for a USB-connected Android device once you've run
/// `adb reverse tcp:4000 tcp:4000`. The Android *emulator* needs
/// `10.0.2.2` instead (its alias for the host machine's loopback) — swap
/// this constant if you're running against the emulator.
const String _baseUrl = 'http://localhost:4000';

/// Thrown for any non-2xx response; [message] is the backend's own
/// `{ "error": "..." }` text when available, so callers can show it
/// directly instead of a generic "something went wrong".
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin wrapper around the backend's JSON REST API. Callers get back a
/// decoded `Map<String, dynamic>` and never touch `http` directly.
class ApiClient {
  const ApiClient._();

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _send('POST', path, body: body, token: token);
  }

  static Future<Map<String, dynamic>> get(String path, {String? token}) {
    return _send('GET', path, token: token);
  }

  static Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _send('PATCH', path, body: body, token: token);
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await http.post(uri, headers: headers, body: jsonEncode(body));
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: jsonEncode(body));
        default:
          response = await http.get(uri, headers: headers);
      }
    } catch (_) {
      throw const ApiException(
        "Couldn't reach the server. Check your connection and that the backend is running.",
      );
    }

    Map<String, dynamic>? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Non-JSON body — fall through with decoded left null.
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded?['error'] as String? ?? 'Something went wrong.';
      throw ApiException(message, statusCode: response.statusCode);
    }

    return decoded ?? const {};
  }
}
