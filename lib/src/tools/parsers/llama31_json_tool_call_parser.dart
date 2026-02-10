import 'dart:convert';
import 'tool_call_parser.dart';

/// Parser for Llama 3.1 JSON-style tool calls with special tokens.
///
/// Format: `<|python_tag|>{"name": "...", "parameters": {...}}<|eom_id|>`
///
/// Variations:
/// - With or without closing `<|eom_id|>` tag
/// - JSON may contain `arguments` instead of `parameters`
class Llama31JsonToolCallParser implements ToolCallParser {
  @override
  String get name => 'Llama31Json';

  @override
  bool canHandle(String output) {
    return output.contains('<|python_tag|>');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    final tagIdx = output.indexOf('<|python_tag|>');
    if (tagIdx == -1) return null;

    final afterTag = output.substring(tagIdx + '<|python_tag|>'.length);
    final jsonStr = _extractJsonObject(afterTag.trimLeft());
    if (jsonStr == null) return null;

    return _parseJson(jsonStr, output);
  }

  ToolCallParseResult? _parseJson(String jsonStr, String raw) {
    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map) return null;

      final name = json['name'] as String?;
      if (name == null) return null;

      final args = json['parameters'] ?? json['arguments'] ?? {};
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
