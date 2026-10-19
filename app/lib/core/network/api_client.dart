import 'dart:convert';

import 'package:dio/dio.dart';

import '../storage/session_store.dart';

/// API error with the server's stable code (see server http.dart).
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status});
  final String code;
  final String message;
  final int? status;

  bool get isNotFound => status == 404;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, required this.store, this.onSessionExpired})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 75),
          contentType: 'application/json',
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) async {
        final s = await store.read();
        if (s != null) o.headers['authorization'] = 'Bearer ${s.accessToken}';
        h.next(o);
      },
      onError: (e, h) async {
        final data = e.response?.data;
        final err = data is Map ? data['error'] : null;
        final code = err is Map ? err['code'] : null;
        final retried = e.requestOptions.extra['retried'] == true;
        if (e.response?.statusCode == 401 && code == 'token_expired' && !retried) {
          if (await _refresh()) {
            final o = e.requestOptions..extra['retried'] = true;
            final s = await store.read();
            o.headers['authorization'] = 'Bearer ${s!.accessToken}';
            try {
              return h.resolve(await dio.fetch(o));
            } on DioException catch (e2) {
              return h.next(e2);
            }
          }
          onSessionExpired?.call();
        }
        h.next(e);
      },
    ));
  }

  final Dio dio;
  final SessionStore store;
  final void Function()? onSessionExpired;
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= () async {
        try {
          final s = await store.read();
          if (s == null) return false;
          final r = await Dio(BaseOptions(baseUrl: dio.options.baseUrl))
              .post<Map<String, dynamic>>('/auth/refresh', data: {'refreshToken': s.refreshToken});
          await store.updateTokens(r.data!['accessToken'] as String, r.data!['refreshToken'] as String);
          return true;
        } catch (_) {
          return false;
        } finally {
          _refreshing = null;
        }
      }();

  ApiException _map(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(err['code'] as String, err['message'] as String, status: e.response?.statusCode);
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        ApiException('network', 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.'),
      _ => ApiException('unknown', 'Beklenmeyen bir hata oluştu', status: e.response?.statusCode),
    };
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return (await dio.get<Map<String, dynamic>>(path, queryParameters: query)).data!;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> send(String method, String path, [Object? body]) async {
    try {
      return (await dio.request<Map<String, dynamic>>(path, data: body, options: Options(method: method))).data!;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Map<String, dynamic>> post(String path, [Object? body]) => send('POST', path, body);

  /// POST that reads a server-sent event stream; yields (event, data).
  Stream<(String, Map<String, dynamic>)> events(String path, Object body) async* {
    Response<ResponseBody> res;
    try {
      res = await dio.post<ResponseBody>(path,
          data: body, options: Options(responseType: ResponseType.stream, headers: {'accept': 'text/event-stream'}));
    } on DioException catch (e) {
      throw _map(e);
    }
    String? event;
    final data = StringBuffer();
    await for (final line in res.data!.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      } else if (line.isEmpty && event != null) {
        yield (event, jsonDecode(data.toString()) as Map<String, dynamic>);
        event = null;
        data.clear();
      }
    }
  }
}
