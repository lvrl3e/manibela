import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Base URL for the ManibelApp backend (see /backend in the repo).
///
/// Defaults to `localhost`, which works for the Windows desktop build and
/// iOS simulator, and for a USB-connected Android device once you've run
/// `adb reverse tcp:4000 tcp:4000`. The Android *emulator* needs
/// `10.0.2.2` instead (its alias for the host machine's loopback) — pass
/// `--dart-define=API_BASE_URL=http://10.0.2.2:4000` when running against
/// the emulator, and the real production URL the same way for release
/// builds (e.g. `flutter build apk --release
/// --dart-define=API_BASE_URL=https://api.manibelapp.example`).
const String _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:4000',
);

/// Thrown for any non-2xx response; [message] is the backend's own
/// `{ "error": "..." }` text when available, so callers can show it
/// directly instead of a generic "something went wrong". [body] is the
/// full decoded response, for the rarer case where an error response
/// carries more than just the message (e.g. a login blocked pending
/// verification also returns `verificationStatus`).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}

/// Thin wrapper around the backend's JSON REST API. Callers get back a
/// decoded `Map<String, dynamic>` and never touch `http` directly.
class ApiClient {
  const ApiClient._();

  /// Set once at app startup (see SessionGuard.install in main.dart) —
  /// called whenever any response comes back with
  /// `code: "ACCOUNT_DEACTIVATED"` (see requireAuth in the backend's
  /// auth.ts), so a deactivation forces an immediate logout no matter
  /// which screen — or background polling Timer, with no BuildContext of
  /// its own — happened to be the one that discovered it.
  static void Function()? onAccountDeactivated;

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

  static Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    return _send('DELETE', path, body: body, token: token);
  }

  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _send('PUT', path, body: body, token: token);
  }

  /// Turns a relative path the backend returned (e.g. a `photoUrl` like
  /// `/uploads/xyz.png`) into a fully-qualified URL an `Image.network`
  /// can load — using the *same* base URL as every other request, so it
  /// resolves correctly whether that's localhost, 10.0.2.2, or a LAN IP.
  static String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_baseUrl$path';
  }

  /// Uploads the file at [filePath] as multipart/form-data under
  /// [fieldName]. Used for endpoints that take binary data (photos) —
  /// [post]/[patch] above only ever send JSON.
  static Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    required String fieldName,
    String? token,
  }) {
    return uploadFiles(path, files: {fieldName: filePath}, token: token);
  }

  /// Like [uploadFile], but for endpoints that take more than one file in
  /// a single request (e.g. an ID's front + back) — [files] maps each
  /// multipart field name to the local path of the file for it. [fields]
  /// carries along any plain text fields the endpoint also expects (e.g.
  /// an ID type) — multipart/form-data is the only way to mix binary
  /// files and text in the same request, so these can't ride along as
  /// separate JSON the way [post]/[patch] send everything else.
  static Future<Map<String, dynamic>> uploadFiles(
    String path, {
    required Map<String, String> files,
    Map<String, String>? fields,
    String? token,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (fields != null) request.fields.addAll(fields);

    http.Response response;
    try {
      for (final entry in files.entries) {
        request.files.add(
          await http.MultipartFile.fromPath(
            entry.key,
            entry.value,
            // MultipartFile.fromPath defaults to application/octet-stream
            // otherwise, which the backend's multer fileFilter rejects
            // outright since it only allows image/jpeg|png|webp.
            contentType: _contentTypeFor(entry.value),
          ),
        );
      }
      response = await http.Response.fromStream(await request.send());
    } catch (_) {
      throw const ApiException(
        "Couldn't reach the server. Check your connection and that the backend is running.",
      );
    }

    return _decode(response);
  }

  static MediaType _contentTypeFor(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('application', 'octet-stream');
    }
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
        case 'PUT':
          response = await http.put(uri, headers: headers, body: jsonEncode(body));
        case 'DELETE':
          response = await http.delete(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        default:
          response = await http.get(uri, headers: headers);
      }
    } catch (_) {
      throw const ApiException(
        "Couldn't reach the server. Check your connection and that the backend is running.",
      );
    }

    return _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response response) {
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
      if (decoded?['code'] == 'ACCOUNT_DEACTIVATED') {
        onAccountDeactivated?.call();
      }
      throw ApiException(message, statusCode: response.statusCode, body: decoded);
    }

    return decoded ?? const {};
  }
}
