import 'tool_call_parser.dart';

/// Parser for Qwen 3 Coder-style tool calls.
///
/// Format: `<function=name><parameter=key>value</parameter>...</function>`
///
/// Example:
/// ```
/// <function=get_weather><parameter=city>London</parameter><parameter=unit>celsius</parameter></function>
/// ```
class QwenCoderToolCallParser implements ToolCallParser {
  static final RegExp _functionPattern = RegExp(
    r'<function=(\w+)>(.*?)</function>',
    dotAll: true,
  );

  static final RegExp _paramPattern = RegExp(
    r'<parameter=(\w+)>(.*?)</parameter>',
    dotAll: true,
  );

  @override
  String get name => 'QwenCoder';

  @override
  bool canHandle(String output) {
    // Must have <function= and </function> AND <parameter= to distinguish from Llama31Func
    return output.contains('<function=') &&
        output.contains('</function>') &&
        output.contains('<parameter=');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    final functionMatch = _functionPattern.firstMatch(output);
    if (functionMatch == null) return null;

    final funcName = functionMatch.group(1);
    if (funcName == null) return null;

    final paramsSection = functionMatch.group(2) ?? '';
    final arguments = <String, dynamic>{};

    for (final paramMatch in _paramPattern.allMatches(paramsSection)) {
      final paramName = paramMatch.group(1);
      final paramValue = paramMatch.group(2);
      if (paramName != null && paramValue != null) {
        arguments[paramName] = _parseValue(paramValue.trim());
      }
    }

    return ToolCallParseResult(
      name: funcName,
      arguments: arguments,
      rawOutput: output,
    );
  }

  /// Attempts to parse a string value into the appropriate type.
  dynamic _parseValue(String value) {
    // Try parsing as number
    final intVal = int.tryParse(value);
    if (intVal != null) return intVal;

    final doubleVal = double.tryParse(value);
    if (doubleVal != null) return doubleVal;

    // Try parsing as boolean
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;

    // Return as string
    return value;
  }
}
