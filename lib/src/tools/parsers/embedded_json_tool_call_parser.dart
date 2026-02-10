import 'dart:convert';
import 'tool_call_parser.dart';

/// Parser that extracts tool calls from embedded JSON within prose.
///
/// This parser handles cases where the model outputs natural language text
/// with JSON embedded in code blocks or inline. For example:
/// - "I'll check the weather. ```json {"name": "get_weather", ...} ```"
/// - "Let me call the function: {"name": "get_weather", "arguments": {...}}"
class EmbeddedJsonToolCallParser implements ToolCallParser {
  // Match JSON in code blocks (```json ... ``` or ``` ... ```)
  static final RegExp _codeBlockPattern = RegExp(
    r'```(?:json)?\s*([\s\S]*?)\s*```',
    multiLine: true,
  );

  @override
  String get name => 'EmbeddedJson';

  @override
  bool canHandle(String output) {
    // Can handle if output contains JSON-like patterns
    return output.contains('"name"') &&
        (output.contains('{') || output.contains('['));
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    // Try code block first (most explicit)
    final codeBlockMatch = _codeBlockPattern.firstMatch(output);
    if (codeBlockMatch != null) {
      final content = codeBlockMatch.group(1)!.trim();
      final result = _tryParseJson(content, output);
      if (result != null) return result;
    }

    // Try to find and extract JSON from the text
    final jsonResult = _extractAndParseJson(output);
    if (jsonResult != null) return jsonResult;

    return null;
  }

  /// Attempts to extract JSON objects/arrays from text and parse them.
  ToolCallParseResult? _extractAndParseJson(String text) {
    // Find potential JSON starting points
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '{' || char == '[') {
        final extracted = _extractBalancedJson(text, i);
        if (extracted != null) {
          final result = _tryParseJson(extracted, text);
          if (result != null) return result;
        }
      }
    }
    return null;
  }

  /// Extracts a balanced JSON object or array starting at the given index.
  String? _extractBalancedJson(String text, int startIndex) {
    final startChar = text[startIndex];
    final endChar = startChar == '{' ? '}' : ']';

    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = startIndex; i < text.length; i++) {
      final char = text[i];

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
        if (char == startChar) {
          depth++;
        } else if (char == endChar) {
          depth--;
          if (depth == 0) {
            return text.substring(startIndex, i + 1);
          }
        }
      }
    }

    return null;
  }

  ToolCallParseResult? _tryParseJson(String jsonStr, String rawOutput) {
    try {
      final json = jsonDecode(jsonStr);

      if (json is Map) {
        return _parseMap(json.cast<String, dynamic>(), rawOutput);
      } else if (json is List && json.isNotEmpty) {
        final first = json.first;
        if (first is Map) {
          return _parseMap(first.cast<String, dynamic>(), rawOutput);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  ToolCallParseResult? _parseMap(Map<String, dynamic> json, String rawOutput) {
    // Direct format: {"name": "...", "arguments": {...}}
    if (json.containsKey('name')) {
      final name = json['name'] as String?;
      if (name == null) return null;

      final args = json['arguments'] ?? json['parameters'] ?? {};
      Map<String, dynamic> argsMap;

      if (args is Map) {
        argsMap = args.cast<String, dynamic>();
      } else if (args is String) {
        try {
          final parsed = jsonDecode(args);
          if (parsed is Map) {
            argsMap = parsed.cast<String, dynamic>();
          } else {
            argsMap = {};
          }
        } catch (_) {
          argsMap = {};
        }
      } else {
        argsMap = {};
      }

      return ToolCallParseResult(
        name: name,
        arguments: argsMap,
        rawOutput: rawOutput,
        id: json['id'] as String?,
      );
    }

    // OpenAI format: {"type": "function", "function": {"name": "...", ...}}
    if (json['type'] == 'function' && json['function'] != null) {
      final function = json['function'] as Map<String, dynamic>;
      return _parseMap(function, rawOutput);
    }

    return null;
  }
}
