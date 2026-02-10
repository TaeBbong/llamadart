import 'dart:convert';
import 'tool_call_parser.dart';

/// Parser for Llama 3.1 function-style tool calls.
///
/// Format: `<function=name>{"key": "value", ...}</function>`
///
/// Note: This format is different from Qwen Coder which uses
/// `<parameter=key>value</parameter>` inside the function tag.
class Llama31FuncToolCallParser implements ToolCallParser {
  static final RegExp _pattern = RegExp(
    r'<function=(\w+)>\s*(\{.*?\})\s*</function>',
    dotAll: true,
  );

  @override
  String get name => 'Llama31Func';

  @override
  bool canHandle(String output) {
    // Must have <function= and contain JSON (not <parameter= like Qwen Coder)
    if (!output.contains('<function=')) return false;
    if (!output.contains('</function>')) return false;

    // Qwen Coder uses <parameter= inside, Llama 3.1 uses JSON directly
    final funcStart = output.indexOf('<function=');
    final funcEnd = output.indexOf('</function>');
    if (funcStart == -1 || funcEnd == -1 || funcEnd < funcStart) return false;

    final content = output.substring(funcStart, funcEnd);
    // If it contains <parameter=, it's Qwen Coder format, not this format
    if (content.contains('<parameter=')) return false;

    return content.contains('{');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    final match = _pattern.firstMatch(output);
    if (match == null) return null;

    final funcName = match.group(1);
    final jsonStr = match.group(2);

    if (funcName == null || jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map) return null;

      return ToolCallParseResult(
        name: funcName,
        arguments: json.cast<String, dynamic>(),
        rawOutput: output,
      );
    } catch (_) {
      return null;
    }
  }
}
