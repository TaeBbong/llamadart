/// Result of parsing a tool call from model output.
class ToolCallParseResult {
  /// The name of the function to be called.
  final String name;

  /// The arguments for the function as a Map.
  final Map<String, dynamic> arguments;

  /// The raw string that was parsed.
  final String rawOutput;

  /// Optional unique identifier for this call.
  final String? id;

  /// Creates a tool call parse result.
  const ToolCallParseResult({
    required this.name,
    required this.arguments,
    required this.rawOutput,
    this.id,
  });

  @override
  String toString() => 'ToolCallParseResult(name: $name, arguments: $arguments)';
}

/// Abstract interface for tool call parsers.
///
/// Each parser implementation handles a specific format of tool call output
/// from different LLM models.
abstract class ToolCallParser {
  /// Human-readable name for this parser (e.g., "Hermes", "Llama 3.1").
  String get name;

  /// Attempts to parse a tool call from the model [output].
  ///
  /// Returns a [ToolCallParseResult] if successful, or `null` if the output
  /// does not match this parser's expected format.
  ToolCallParseResult? tryParse(String output);

  /// Quick check to see if this parser might be able to handle the output.
  ///
  /// This is used for early filtering before attempting full parsing.
  /// Returns `true` if the output looks like it could be handled by this parser.
  bool canHandle(String output);
}
