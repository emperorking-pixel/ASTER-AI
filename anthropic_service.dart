// anthropic_service.dart
//
// Talks directly to Anthropic's Messages API using the API key the user
// enters themselves (see secure_key_store.dart). No backend server involved —
// this app calls https://api.anthropic.com directly, which is fine for a
// native app (CORS only restricts browsers, not native HTTP clients).
//
// Cost note: every call is billed to the user's own Anthropic account.
// Swap kModel below to trade off cost vs. quality.

import 'dart:convert';
import 'package:http/http.dart' as http;

// Current model strings (per Anthropic's own product docs):
//   claude-sonnet-5              -> balanced default, use this unless you have a reason not to
//   claude-haiku-4-5-20251001    -> fastest / cheapest
//   claude-opus-5                -> highest quality, most expensive
const String kModel = 'claude-sonnet-5';
const String kAnthropicVersion = '2023-06-01';
const int kMaxTokens = 1024;

class AnthropicMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  AnthropicMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AnthropicService {
  final String apiKey;
  AnthropicService(this.apiKey);

  /// Sends the full running conversation (oldest first) and returns Aster's
  /// reply text. Throws an [AnthropicException] on any failure so the UI can
  /// show a clear message instead of failing silently.
  Future<String> send(List<AnthropicMessage> conversation, {String? systemPrompt}) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');

    final body = <String, dynamic>{
      'model': kModel,
      'max_tokens': kMaxTokens,
      'messages': conversation.map((m) => m.toJson()).toList(),
    };
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      body['system'] = systemPrompt;
    }

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': kAnthropicVersion,
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw AnthropicException('Could not reach Anthropic — check your internet connection.');
    }

    if (resp.statusCode == 401) {
      throw AnthropicException('That API key was rejected. Double-check it in Settings.');
    }
    if (resp.statusCode == 429) {
      throw AnthropicException('Rate limited — wait a moment and try again.');
    }
    if (resp.statusCode >= 500) {
      throw AnthropicException('Anthropic\'s servers had a problem. Try again shortly.');
    }
    if (resp.statusCode != 200) {
      throw AnthropicException('Request failed (HTTP ${resp.statusCode}): ${resp.body}');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw AnthropicException('Got a reply that could not be read.');
    }

    final content = data['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw AnthropicException('Empty reply from the model.');
    }

    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] ?? '');
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw AnthropicException('Empty reply from the model.');
    }
    return text;
  }
}

class AnthropicException implements Exception {
  final String message;
  AnthropicException(this.message);
  @override
  String toString() => message;
}
