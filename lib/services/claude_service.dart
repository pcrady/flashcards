import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LlmException implements Exception {
  final String message;
  LlmException(this.message);
  @override
  String toString() => message;
}

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String text;
  ChatMessage(this.role, this.text);
}

/// Calls the Anthropic Messages API over raw HTTP (there is no official
/// Dart SDK). The API key is read from settings, falling back to the
/// ANTHROPIC_API_KEY environment variable. Used for translations, and for
/// the tutor chat when the Anthropic provider is selected.
class ClaudeService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const defaultModel = 'claude-opus-4-8';
  static const apiKeyPref = 'anthropic_api_key';

  static Future<String?> apiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(apiKeyPref);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final env = Platform.environment['ANTHROPIC_API_KEY'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    return null;
  }

  static Future<String> complete({
    required String system,
    required List<Map<String, String>> messages,
    String model = defaultModel,
    int maxTokens = 1024,
  }) async {
    final key = await apiKey();
    if (key == null) {
      throw LlmException(
          'No Anthropic API key set. Add one in Settings (gear icon).');
    }

    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': maxTokens,
              'system': system,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on SocketException {
      throw LlmException('Network error — check your connection.');
    }

    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode != 200) {
      final msg = (body is Map && body['error'] is Map)
          ? body['error']['message'] as String? ?? 'Unknown API error'
          : 'API error (HTTP ${resp.statusCode})';
      throw LlmException(msg);
    }

    if (body['stop_reason'] == 'refusal') {
      throw LlmException('The model declined to answer this request.');
    }

    final content = body['content'] as List<dynamic>;
    final buffer = StringBuffer();
    for (final block in content) {
      if (block['type'] == 'text') buffer.write(block['text']);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw LlmException('Empty response from the API.');
    return text;
  }
}
