import 'tool_call_parser.dart';

/// Parser for Pythonic-style tool calls.
///
/// Format: `[func_name(arg="value", ...)]` or `func_name(arg="value", ...)`
///
/// Examples:
/// - `[get_weather(city="London", unit="celsius")]`
/// - `get_weather(city="London")`
/// - `[search(query="AI news")]`
class PythonicToolCallParser implements ToolCallParser {
  // Matches: [func_name(...)] or func_name(...)
  static final RegExp _pattern = RegExp(
    r'\[?(\w+)\(\s*(.*?)\s*\)\]?',
    dotAll: true,
  );

  static final RegExp _argPattern = RegExp(
    r'''(\w+)\s*=\s*(?:"([^"]*?)"|'([^']*?)'|([^,\s\)\]]+))''',
  );

  @override
  String get name => 'Pythonic';

  @override
  bool canHandle(String output) {
    final trimmed = output.trim();
    // Must contain function call pattern with parentheses
    // But not .call( which is Llama31Builtin format
    if (trimmed.contains('.call(')) return false;

    // Check for pattern like func_name( or [func_name(
    return RegExp(r'[\[\s]*\w+\s*\(').hasMatch(trimmed);
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    if (!canHandle(output)) return null;

    final match = _pattern.firstMatch(output);
    if (match == null) return null;

    final funcName = match.group(1);
    final argsStr = match.group(2) ?? '';

    if (funcName == null) return null;

    // Filter out common false positives (e.g., print, if, for, while)
    const keywords = {
      'print',
      'if',
      'for',
      'while',
      'return',
      'def',
      'class',
      'import',
    };
    if (keywords.contains(funcName.toLowerCase())) return null;

    final arguments = <String, dynamic>{};

    for (final argMatch in _argPattern.allMatches(argsStr)) {
      final argName = argMatch.group(1);
      // Groups 2, 3, 4 are for different quote styles and unquoted values
      final argValue =
          argMatch.group(2) ?? argMatch.group(3) ?? argMatch.group(4);

      if (argName != null && argValue != null) {
        arguments[argName] = _parseValue(argValue.replaceAll(RegExp(r'[,\)]$'), ''));
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
