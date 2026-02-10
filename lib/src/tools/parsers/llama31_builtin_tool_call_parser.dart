import 'tool_call_parser.dart';

/// Parser for Llama 3.1 built-in tool call format.
///
/// Format: `tool.call(arg="value", ...)`
///
/// Examples:
/// - `brave_search.call(query="weather in London")`
/// - `calculator.call(expression="2+2")`
/// - `get_weather.call(city="Tokyo", unit="celsius")`
class Llama31BuiltinToolCallParser implements ToolCallParser {
  static final RegExp _pattern = RegExp(
    r'(\w+)\.call\(\s*(.*?)\s*\)',
    dotAll: true,
  );

  static final RegExp _argPattern = RegExp(
    r'''(\w+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^,\s\)]+))''',
  );

  @override
  String get name => 'Llama31Builtin';

  @override
  bool canHandle(String output) {
    return output.contains('.call(');
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    final match = _pattern.firstMatch(output);
    if (match == null) return null;

    final funcName = match.group(1);
    final argsStr = match.group(2) ?? '';

    if (funcName == null) return null;

    final arguments = <String, dynamic>{};

    for (final argMatch in _argPattern.allMatches(argsStr)) {
      final argName = argMatch.group(1);
      // Groups 2, 3, 4 are for different quote styles and unquoted values
      final argValue =
          argMatch.group(2) ?? argMatch.group(3) ?? argMatch.group(4);

      if (argName != null && argValue != null) {
        arguments[argName] = _parseValue(argValue);
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
