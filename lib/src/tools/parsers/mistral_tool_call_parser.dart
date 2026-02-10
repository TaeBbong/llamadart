import 'dart:convert';
import 'tool_call_parser.dart';

/// Parser for Mistral-style tool calls.
///
/// Format: `[TOOL_CALLS] [{"name": "...", "arguments": {...}}]`
///
/// Variations:
/// - Single tool call: `[TOOL_CALLS] [{"name": "...", ...}]`
/// - Multiple tool calls: `[TOOL_CALLS] [{"name": "..."}, {"name": "..."}]`
/// - Plain JSON array (some models skip the marker): `[{"name": "...", ...}]`
class MistralToolCallParser implements ToolCallParser {
  static final RegExp _pattern = RegExp(
    r'\[TOOL_CALLS\]\s*(\[.*\])',
    dotAll: true,
  );

  @override
  String get name => 'Mistral';

  @override
  bool canHandle(String output) {
    final trimmed = output.trim();
    // Handle both with and without [TOOL_CALLS] prefix
    return output.contains('[TOOL_CALLS]') || trimmed.startsWith('[');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    String? jsonArrayStr;

    // Try with [TOOL_CALLS] prefix first
    final match = _pattern.firstMatch(output);
    if (match != null) {
      jsonArrayStr = match.group(1);
    } else {
      // Try parsing as plain JSON array (model skipped [TOOL_CALLS] marker)
      final trimmed = output.trim();
      if (trimmed.startsWith('[')) {
        jsonArrayStr = trimmed;
      }
    }

    if (jsonArrayStr == null) return null;

    try {
      final json = jsonDecode(jsonArrayStr);
      if (json is! List || json.isEmpty) return null;

      // Parse the first tool call
      final first = json.first;
      if (first is! Map) return null;

      final name = first['name'] as String?;
      if (name == null) return null;

      final args = first['arguments'] ?? first['parameters'] ?? {};
      Map<String, dynamic> argsMap;

      if (args is Map) {
        argsMap = args.cast<String, dynamic>();
      } else if (args is String) {
        // Some models return arguments as JSON string
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
        rawOutput: output,
        id: first['id'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
