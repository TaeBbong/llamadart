import 'dart:convert';

import '../models/llama_chat_role.dart';
import 'tool_call_format.dart';
import 'tool_definition.dart';
import 'tool_param.dart';
import 'parsers/parsers.dart';

/// Configuration and utilities for a specific [ToolCallFormat].
///
/// This class provides format-specific:
/// - System prompt instructions
/// - Tool result formatting
/// - Parser selection
/// - Grammar generation
class ToolCallFormatConfig {
  /// The format this config is for.
  final ToolCallFormat format;

  /// Creates a config for the given format.
  const ToolCallFormatConfig(this.format);

  /// Formats a tool result for inclusion in the conversation.
  ///
  /// Different formats expect tool results in different structures.
  String formatToolResult(String name, Object? result, {String? callId}) {
    String resultStr;
    if (result is String) {
      resultStr = result;
    } else {
      try {
        resultStr = jsonEncode(result);
      } catch (_) {
        resultStr = result.toString();
      }
    }

    switch (format) {
      case ToolCallFormat.json:
        return jsonEncode({'name': name, 'result': result});

      case ToolCallFormat.hermes:
        return '<tool_response>{"name": "$name", "content": $resultStr}</tool_response>';

      case ToolCallFormat.llama:
        return jsonEncode({'name': name, 'output': result});

      case ToolCallFormat.mistral:
        final id = callId ?? name;
        return '[TOOL_RESULTS] {"call_id": "$id", "content": $resultStr}';

      case ToolCallFormat.auto:
        // Default to simple JSON for auto mode
        return jsonEncode({'name': name, 'result': result});
    }
  }

  /// The role to use for tool result messages.
  ///
  /// Most formats use 'tool' role, but some (like Hermes) use 'assistant'.
  LlamaChatRole get toolResultRole {
    switch (format) {
      case ToolCallFormat.hermes:
        // Hermes format uses assistant role for tool responses
        return LlamaChatRole.assistant;
      default:
        return LlamaChatRole.tool;
    }
  }

  /// Returns the appropriate parser for this format.
  ToolCallParser getParser() {
    switch (format) {
      case ToolCallFormat.json:
        return OpenAIToolCallParser();
      case ToolCallFormat.hermes:
        return HermesToolCallParser();
      case ToolCallFormat.llama:
        return Llama31JsonToolCallParser();
      case ToolCallFormat.mistral:
        return MistralToolCallParser();
      case ToolCallFormat.auto:
        return CompositeToolCallParser();
    }
  }

  /// Whether this format supports grammar-based enforcement.
  bool get supportsGrammar {
    switch (format) {
      case ToolCallFormat.json:
      case ToolCallFormat.hermes:
      case ToolCallFormat.llama:
      case ToolCallFormat.mistral:
        return true;
      case ToolCallFormat.auto:
        return false;
    }
  }

  /// Generates GBNF grammar for this format.
  ///
  /// Returns null if grammar is not supported or tools is empty.
  String? generateGrammar(List<ToolDefinition> tools) {
    if (tools.isEmpty || !supportsGrammar) return null;

    switch (format) {
      case ToolCallFormat.json:
        return _generateJsonGrammar(tools);
      case ToolCallFormat.hermes:
        return _generateHermesGrammar(tools);
      case ToolCallFormat.llama:
        return _generateLlamaGrammar(tools);
      case ToolCallFormat.mistral:
        return _generateMistralGrammar(tools);
      case ToolCallFormat.auto:
        return null;
    }
  }

  /// Generates JSON/OpenAI format grammar.
  String _generateJsonGrammar(List<ToolDefinition> tools) {
    final buffer = StringBuffer();

    // Whitespace rule
    buffer.writeln('ws ::= [ \\t\\n]*');
    buffer.writeln();

    // Generate tool-specific rules
    final toolRules = <String>[];
    for (final tool in tools) {
      final ruleName = 'tool-${tool.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';
      toolRules.add(ruleName);

      final paramsRule = _generateParamsRule(tool, ruleName);
      buffer.writeln(paramsRule);
    }

    // Main rule: {"type": "function", "function": {"name": "...", "parameters": ...}}
    buffer.writeln();
    buffer.writeln('root ::= "{" ws "\\"type\\"" ws ":" ws "\\"function\\"" ws "," ws "\\"function\\"" ws ":" ws "{" ws "\\"name\\"" ws ":" ws tool-name ws "," ws "\\"parameters\\"" ws ":" ws tool-params ws "}" ws "}"');
    buffer.writeln();

    // Tool name alternatives
    final nameAlts = tools.map((t) => '"\\"${t.name}\\""').join(' | ');
    buffer.writeln('tool-name ::= $nameAlts');

    // Tool params alternatives (simplified - uses any valid JSON object)
    buffer.writeln('tool-params ::= ${toolRules.map((r) => '$r-params').join(' | ')}');

    return buffer.toString();
  }

  /// Generates Hermes format grammar.
  String _generateHermesGrammar(List<ToolDefinition> tools) {
    final buffer = StringBuffer();

    buffer.writeln('ws ::= [ \\t\\n]*');
    buffer.writeln();

    // Generate tool-specific rules
    final toolRules = <String>[];
    for (final tool in tools) {
      final ruleName = 'tool-${tool.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';
      toolRules.add(ruleName);

      final paramsRule = _generateParamsRule(tool, ruleName);
      buffer.writeln(paramsRule);
    }

    // Main rule: <tool_call>{"name": "...", "arguments": ...}</tool_call>
    buffer.writeln();
    buffer.writeln('root ::= "<tool_call>" ws "{" ws "\\"name\\"" ws ":" ws tool-name ws "," ws "\\"arguments\\"" ws ":" ws tool-params ws "}" ws "</tool_call>"');
    buffer.writeln();

    final nameAlts = tools.map((t) => '"\\"${t.name}\\""').join(' | ');
    buffer.writeln('tool-name ::= $nameAlts');
    buffer.writeln('tool-params ::= ${toolRules.map((r) => '$r-params').join(' | ')}');

    return buffer.toString();
  }

  /// Generates Llama 3.1 format grammar.
  String _generateLlamaGrammar(List<ToolDefinition> tools) {
    final buffer = StringBuffer();

    buffer.writeln('ws ::= [ \\t\\n]*');
    buffer.writeln();

    // Generate tool-specific rules
    final toolRules = <String>[];
    for (final tool in tools) {
      final ruleName = 'tool-${tool.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';
      toolRules.add(ruleName);

      final paramsRule = _generateParamsRule(tool, ruleName);
      buffer.writeln(paramsRule);
    }

    // Main rule: <|python_tag|>{"name": "...", "parameters": ...}
    buffer.writeln();
    buffer.writeln('root ::= "<|python_tag|>" ws "{" ws "\\"name\\"" ws ":" ws tool-name ws "," ws "\\"parameters\\"" ws ":" ws tool-params ws "}"');
    buffer.writeln();

    final nameAlts = tools.map((t) => '"\\"${t.name}\\""').join(' | ');
    buffer.writeln('tool-name ::= $nameAlts');
    buffer.writeln('tool-params ::= ${toolRules.map((r) => '$r-params').join(' | ')}');

    return buffer.toString();
  }

  /// Generates Mistral format grammar.
  String _generateMistralGrammar(List<ToolDefinition> tools) {
    final buffer = StringBuffer();

    buffer.writeln('ws ::= [ \\t\\n]*');
    buffer.writeln();

    // Generate tool-specific rules
    final toolRules = <String>[];
    for (final tool in tools) {
      final ruleName = 'tool-${tool.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';
      toolRules.add(ruleName);

      final paramsRule = _generateParamsRule(tool, ruleName);
      buffer.writeln(paramsRule);
    }

    // Main rule: [TOOL_CALLS] [{"name": "...", "arguments": ...}]
    buffer.writeln();
    buffer.writeln('root ::= "[TOOL_CALLS]" ws "[" ws "{" ws "\\"name\\"" ws ":" ws tool-name ws "," ws "\\"arguments\\"" ws ":" ws tool-params ws "}" ws "]"');
    buffer.writeln();

    final nameAlts = tools.map((t) => '"\\"${t.name}\\""').join(' | ');
    buffer.writeln('tool-name ::= $nameAlts');
    buffer.writeln('tool-params ::= ${toolRules.map((r) => '$r-params').join(' | ')}');

    return buffer.toString();
  }

  /// Generates parameter rules for a tool.
  String _generateParamsRule(ToolDefinition tool, String ruleName) {
    final buffer = StringBuffer();
    final params = tool.parameters;

    if (params.isEmpty) {
      buffer.writeln('$ruleName-params ::= "{" ws "}"');
      return buffer.toString();
    }

    // Build parameter entries
    final paramEntries = <String>[];
    for (final param in params) {
      final valueRule = _getValueRuleForParam(param);
      paramEntries.add('"\\"${param.name}\\"" ws ":" ws $valueRule');
    }

    // Simplified: all params in order (not handling optional params for now)
    buffer.writeln('$ruleName-params ::= "{" ws ${paramEntries.join(' ws "," ws ')} ws "}"');

    return buffer.toString();
  }

  /// Gets the GBNF value rule for a ToolParam.
  String _getValueRuleForParam(ToolParam param) {
    final schema = param.toJsonSchema();
    final type = schema['type'] as String?;

    switch (type) {
      case 'string':
        return 'string';
      case 'integer':
        return 'integer';
      case 'number':
        return 'number';
      case 'boolean':
        return 'boolean';
      case 'array':
        return 'array';
      case 'object':
        return 'object';
      default:
        return 'value';
    }
  }
}
