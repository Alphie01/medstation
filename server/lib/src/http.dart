import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final _log = Logger('http');

/// Error with a stable machine code the app can map to a message.
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message, {this.details});
  final int status;
  final String code;
  final String message;
  final Object? details;

  static ApiError badRequest(String m, {Object? details}) =>
      ApiError(400, 'bad_request', m, details: details);
  static ApiError unauthorized([String m = 'Oturum gerekli']) =>
      ApiError(401, 'unauthorized', m);
  static ApiError forbidden([String m = 'Yetkiniz yok']) =>
      ApiError(403, 'forbidden', m);
  static ApiError notFound([String m = 'Bulunamadı']) =>
      ApiError(404, 'not_found', m);
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response json(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Future<Map<String, dynamic>> readJson(Request req) async {
  final body = await req.readAsString();
  if (body.isEmpty) return {};
  try {
    final v = jsonDecode(body);
    if (v is Map<String, dynamic>) return v;
  } on FormatException {
    // fall through
  }
  throw ApiError.badRequest('Geçersiz JSON gövdesi');
}

Middleware errorHandler() => (inner) => (req) async {
      try {
        return await inner(req);
      } on ApiError catch (e) {
        return json({
          'error': {'code': e.code, 'message': e.message, 'details': e.details}
        }, status: e.status);
      } on FormatException catch (e) {
        return json({
          'error': {'code': 'bad_request', 'message': e.message}
        }, status: 400);
      } catch (e, st) {
        _log.severe('unhandled ${req.method} ${req.url}', e, st);
        return json({
          'error': {'code': 'internal', 'message': 'Sunucu hatası'}
        }, status: 500);
      }
    };

/// Security headers; the API is consumed by the mobile app only.
Middleware securityHeaders() => (inner) => (req) async {
      final res = await inner(req);
      return res.change(headers: {
        'x-content-type-options': 'nosniff',
        'cache-control': 'no-store',
        'referrer-policy': 'no-referrer',
      });
    };

String? q(Request r, String k) {
  final v = r.url.queryParameters[k];
  return v == null || v.trim().isEmpty ? null : v.trim();
}
