import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('openai');

class OpenAiException implements Exception {
  OpenAiException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'OpenAiException($status)';
}

/// Minimal OpenAI client (Responses + Embeddings). Runs only on the server.
class OpenAiClient {
  OpenAiClient({
    required this.apiKey,
    required this.model,
    required this.embedModel,
    this.reasoningEffort,
    this.baseUrl = 'https://api.openai.com/v1',
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String apiKey;
  final String model;
  final String embedModel;
  final String? reasoningEffort;
  final String baseUrl;
  final http.Client _http;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode >= 300) {
      _log.warning('OpenAI $path ${res.statusCode}');
      throw OpenAiException(res.statusCode, res.body);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<List<double>>> embed(List<String> inputs) async {
    final r = await _post('/embeddings', {'model': embedModel, 'input': inputs});
    final data = (r['data'] as List).cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
    return [
      for (final d in data) (d['embedding'] as List).map((e) => (e as num).toDouble()).toList()
    ];
  }

  /// Responses API call with a strict JSON schema; returns the parsed object.
  Future<Map<String, dynamic>> structured({
    required String instructions,
    required String input,
    required String schemaName,
    required Map<String, dynamic> schema,
  }) async {
    final r = await _post('/responses', {
      'model': model,
      'instructions': instructions,
      'input': input,
      'store': false,
      if (reasoningEffort != null) 'reasoning': {'effort': reasoningEffort},
      'text': {
        'format': {'type': 'json_schema', 'name': schemaName, 'schema': schema, 'strict': true},
      },
    });
    for (final item in (r['output'] as List? ?? const [])) {
      if (item is Map && item['type'] == 'message') {
        for (final c in (item['content'] as List? ?? const [])) {
          if (c is Map && c['type'] == 'output_text') {
            return jsonDecode(c['text'] as String) as Map<String, dynamic>;
          }
          if (c is Map && c['type'] == 'refusal') {
            throw OpenAiException(422, 'refusal');
          }
        }
      }
    }
    throw OpenAiException(502, 'no output_text');
  }
}
