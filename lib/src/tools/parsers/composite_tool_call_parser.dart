import 'tool_call_parser.dart';
import 'hermes_tool_call_parser.dart';
import 'qwen_coder_tool_call_parser.dart';
import 'llama31_json_tool_call_parser.dart';
import 'llama31_func_tool_call_parser.dart';
import 'llama31_builtin_tool_call_parser.dart';
import 'mistral_tool_call_parser.dart';
import 'pythonic_tool_call_parser.dart';
import 'openai_tool_call_parser.dart';
import 'embedded_json_tool_call_parser.dart';

/// A composite parser that tries multiple tool call parsers in order.
///
/// The parser attempts to parse tool calls using specialized parsers first
/// (which match specific formats), then falls back to more generic parsers.
///
/// Parser priority order:
/// 1. Hermes (Qwen 2.5, Qwen 3 Instruct) - `<tool_call>...</tool_call>`
/// 2. Qwen Coder - `<function=name><parameter=key>value</parameter></function>`
/// 3. Llama 3.1 JSON - `<|python_tag|>{...}<|eom_id|>`
/// 4. Llama 3.1 Func - `<function=name>{...}</function>`
/// 5. Llama 3.1 Builtin - `tool.call(...)`
/// 6. Mistral - `[TOOL_CALLS] [{...}]`
/// 7. Pythonic - `[func_name(...)]` or `func_name(...)`
/// 8. OpenAI (fallback) - Generic JSON format
class CompositeToolCallParser implements ToolCallParser {
  /// The ordered list of parsers to try.
  final List<ToolCallParser> parsers;

  /// The parser that last successfully parsed a tool call.
  ToolCallParser? lastMatchedParser;

  /// Creates a composite parser with the default parser set.
  CompositeToolCallParser()
      : parsers = [
          HermesToolCallParser(),
          QwenCoderToolCallParser(),
          Llama31JsonToolCallParser(),
          Llama31FuncToolCallParser(),
          Llama31BuiltinToolCallParser(),
          MistralToolCallParser(),
          PythonicToolCallParser(),
          OpenAIToolCallParser(), // Fallback - most generic JSON
          EmbeddedJsonToolCallParser(), // Last resort - extract from prose
        ];

  /// Creates a composite parser with a custom list of parsers.
  CompositeToolCallParser.custom(this.parsers);

  @override
  String get name => 'Composite';

  @override
  bool canHandle(String output) {
    return parsers.any((p) => p.canHandle(output));
  }

  @override
  ToolCallParseResult? tryParse(String output) {
    // First, try parsers that explicitly can handle the output
    for (final parser in parsers) {
      if (parser.canHandle(output)) {
        final result = parser.tryParse(output);
        if (result != null) {
          lastMatchedParser = parser;
          return result;
        }
      }
    }

    // Fallback: try all parsers even if canHandle returned false
    // (some parsers might have conservative canHandle checks)
    for (final parser in parsers) {
      final result = parser.tryParse(output);
      if (result != null) {
        lastMatchedParser = parser;
        return result;
      }
    }

    return null;
  }

  /// Returns a summary of all available parsers.
  List<String> get availableFormats => parsers.map((p) => p.name).toList();
}
