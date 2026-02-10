import 'dart:convert';
import 'tool_call_parser.dart';

/// Parser for Hermes-style tool calls.
///
/// Used by: Hermes models, Qwen 2.5, Qwen 3 Instruct
///
/// Format: `<tool_call>{"name": "...", "arguments": {...}}</tool_call>`
///
/// Variations:
/// - With closing tag: `<tool_call>...</tool_call>`
/// - Without closing tag: `<tool_call>...`
class HermesToolCallParser implements ToolCallParser {
  @override
  String get name => 'Hermes';

  @override
  bool canHandle(String output) {
    return output.contains('<tool_call>');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    final startIdx = output.indexOf('<tool_call>');
    if (startIdx == -1) return null;

    final afterTag = output.substring(startIdx + '<tool_call>'.length);
    final jsonStart = afterTag.indexOf('{');
    if (jsonStart == -1) return null;

    // Find matching closing brace using bracket matching
    final jsonStr = _extractJsonObject(afterTag.substring(jsonStart));
    if (jsonStr == null) return null;

    return _parseJson(jsonStr, output);
  }

  ToolCallParseResult? _parseJson(String jsonStr, String raw) {
    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map) return null;

      final name = json['name'] as String?;
      if (name == null) return null;

      final args = json['arguments'] ?? json['parameters'] ?? {};
      final argsMap =
          args is Map ? args.cast<String, dynamic>() : <String, dynamic>{};

      return ToolCallParseResult(
        name: name,
        arguments: argsMap,
        rawOutput: raw,
        id: json['id'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts a complete JSON object from a string, handling nested braces.
  String? _extractJsonObject(String str) {
    if (!str.startsWith('{')) return null;

    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < str.length; i++) {
      final char = str[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == '\\' && inString) {
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (!inString) {
        if (char == '{') depth++;
        if (char == '}') depth--;

        if (depth == 0) {
          return str.substring(0, i + 1);
        }
      }
    }

    return null;
  }
}
