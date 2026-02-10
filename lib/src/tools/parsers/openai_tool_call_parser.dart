import 'dart:convert';
import 'tool_call_parser.dart';

/// Parser for OpenAI-style JSON tool calls.
///
/// Supports formats:
/// - `{"type": "function", "function": {"name": "...", "parameters": {...}}}`
/// - `{"function": {"name": "...", "parameters": {...}}}`
/// - `{"name": "...", "parameters": {...}}`
/// - Array of tool calls: `[{"type": "function", ...}]`
class OpenAIToolCallParser implements ToolCallParser {
  @override
  String get name => 'OpenAI';

  @override
  bool canHandle(String output) {
    final trimmed = output.trim();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    final trimmed = output.trim();
    if (!canHandle(trimmed)) return null;

    try {
      final json = jsonDecode(trimmed);

      if (json is Map) {
        return _parseMap(json.cast<String, dynamic>(), trimmed);
      } else if (json is List && json.isNotEmpty) {
        // Handle array of tool calls - return the first one
        final first = json.first;
        if (first is Map) {
          return _parseMap(first.cast<String, dynamic>(), trimmed);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  ToolCallParseResult? _parseMap(Map<String, dynamic> json, String raw) {
    // Standard OpenAI format: {"type": "function", "function": {...}}
    if (json['type'] == 'function' && json['function'] != null) {
      final function = json['function'] as Map<String, dynamic>;
      final name = function['name'] as String?;
      if (name == null) return null;

      final args = _extractArguments(function);
      return ToolCallParseResult(
        name: name,
        arguments: args,
        rawOutput: raw,
        id: json['id'] as String?,
      );
    }

    // Shortened format: {"function": {"name": "...", ...}}
    if (json.containsKey('function') && json['function'] is Map) {
      final function = (json['function'] as Map).cast<String, dynamic>();
      final name = function['name'] as String?;
      if (name == null) return null;

      final args = _extractArguments(function);
      return ToolCallParseResult(
        name: name,
        arguments: args,
        rawOutput: raw,
        id: json['id'] as String?,
      );
    }

    // Direct format: {"name": "...", "parameters": {...}} or {"name": "...", "arguments": {...}}
    if (json.containsKey('name') &&
        (json.containsKey('parameters') || json.containsKey('arguments'))) {
      final name = json['name'] as String?;
      if (name == null) return null;

      final args = _extractArguments(json);
      return ToolCallParseResult(
        name: name,
        arguments: args,
        rawOutput: raw,
        id: json['id'] as String?,
      );
    }

    return null;
  }

  Map<String, dynamic> _extractArguments(Map<String, dynamic> obj) {
    // Try 'parameters' first (OpenAI grammar format), then 'arguments' (API format)
    final params = obj['parameters'] ?? obj['arguments'];
    if (params is Map) {
      return params.cast<String, dynamic>();
    }
    // Some models return arguments as JSON string
    if (params is String) {
      try {
        final parsed = jsonDecode(params);
        if (parsed is Map) {
          return parsed.cast<String, dynamic>();
        }
      } catch (_) {}
    }
    return {};
  }
}
