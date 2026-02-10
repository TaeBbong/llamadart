import 'dart:async';
import 'dart:math';

import 'llama_engine.dart';
import '../models/llama_chat_message.dart';
import '../models/llama_chat_role.dart';
import '../models/llama_content_part.dart';
import '../models/generation_params.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_call_format.dart';
import '../tools/tool_call_format_config.dart';

/// High-level chat interface with history management and tool support.
///
/// [ChatSession] provides a stateful interface over [LlamaEngine], handling
/// conversation history and automatically ensuring that the total token count
/// stays within the model's context window limits by truncating older messages.
///
/// For stateless single-turn chat, use the static [singleTurn] method.
///
/// Example:
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('model.gguf');
///
/// final session = ChatSession(engine);
/// session.systemPrompt = 'You are a helpful assistant.';
///
/// await for (final token in session.chat('Hello!')) {
///   print(token);
/// }
/// ```
class ChatSession {
  final LlamaEngine _engine;
  final List<LlamaChatMessage> _history = [];

  /// The format configuration for tool calling.
  late final ToolCallFormatConfig _formatConfig;

  /// The maximum number of tokens allowed in the context window.
  ///
  /// If null, this value will be automatically retrieved from the engine's
  /// model metadata (e.g., `llama.context_length` or `n_ctx`).
  int? maxContextTokens;

  /// Creates a new [ChatSession] wrapping the given [engine].
  ///
  /// Optionally sets [maxContextTokens] to override the model's default limit,
  /// [systemPrompt] to define the initial persona or instructions,
  /// [toolRegistry] to enable tool calling for this session, and
  /// [toolCallFormat] to specify the tool call format for the model.
  ChatSession(
    this._engine, {
    this.maxContextTokens,
    this.systemPrompt,
    this.toolRegistry,
    this.forceToolCall = false,
    this.toolsEnabled = true,
    this.toolCallFormat = ToolCallFormat.json,
  }) {
    _formatConfig = ToolCallFormatConfig(toolCallFormat);
  }

  /// The underlying engine instance.
  LlamaEngine get engine => _engine;

  /// The current message history, excluding the [systemPrompt].
  ///
  /// Returns an unmodifiable list of [LlamaChatMessage].
  List<LlamaChatMessage> get history => List.unmodifiable(_history);

  /// The system prompt for this session.
  ///
  /// If set, this prompt is automatically prepended to the message list
  /// during every [chat] request. It persists until manually changed or
  /// cleared via [reset].
  String? systemPrompt;

  /// The tool registry for this session.
  ///
  /// If set, the model will have access to these tools for function calling.
  /// See [forceToolCall] to control whether tools are mandatory.
  ToolRegistry? toolRegistry;

  /// Whether to force the model to make a tool call.
  ///
  /// - `false` (default): Model decides when to use tools based on context.
  /// - `true`: Grammar constraints force the model to output a tool call.
  ///
  /// Set to `true` for weaker models that don't reliably call tools on their own.
  bool forceToolCall = false;

  /// Whether tools are currently enabled for this session.
  ///
  /// Defaults to `true`. If `false`, tools will not be used even if [toolRegistry] is set.
  bool toolsEnabled = true;

  /// The format to use for tool calling.
  ///
  /// Different models use different formats for tool calls. Choose the format
  /// that matches your model:
  /// - [ToolCallFormat.json]: OpenAI-style JSON (default, most compatible)
  /// - [ToolCallFormat.hermes]: Qwen 2.5, Qwen 3, Hermes models
  /// - [ToolCallFormat.llama]: Llama 3.1+ models
  /// - [ToolCallFormat.mistral]: Mistral/Mixtral models
  /// - [ToolCallFormat.auto]: Try all formats (no grammar enforcement)
  final ToolCallFormat toolCallFormat;

  /// Adds a custom [message] directly to the history.
  ///
  /// Useful for pre-seeding a conversation or restoring a previous state.
  void addMessage(LlamaChatMessage message) {
    _history.add(message);
  }

  /// Clears all messages from the conversation history.
  ///
  /// Note: This does not affect the [systemPrompt]. Use [reset] for a full cleanup.
  void clearHistory() {
    _history.clear();
  }

  /// Resets the session state.
  ///
  /// By default, [keepSystemPrompt] is true, meaning only the message history
  /// is cleared. Set [keepSystemPrompt] to false to also clear the [systemPrompt].
  /// Set [keepToolRegistry] to false to also clear the [toolRegistry].
  void reset({bool keepSystemPrompt = true, bool keepToolRegistry = true}) {
    _history.clear();
    if (!keepSystemPrompt) {
      systemPrompt = null;
    }
    if (!keepToolRegistry) {
      toolRegistry = null;
    }
  }

  /// Sends a user [text] message and returns a stream of generated response tokens.
  Stream<String> chat(
    String text, {
    GenerationParams? params,
    ToolRegistry? toolRegistryOverride,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    final userMsg = LlamaChatMessage.text(
      role: LlamaChatRole.user,
      content: text,
    );
    _history.add(userMsg);
    onMessageAdded?.call(userMsg);

    final effectiveRegistry = toolRegistryOverride ?? toolRegistry;

    // Ensure we are within context limits before sending
    await _enforceContextLimit(toolRegistry: effectiveRegistry);

    final messages = _getMessagesForEngine();
    String fullResponse = "";

    await for (final token in _generateWithMessages(
      messages,
      params: params,
      toolRegistry: effectiveRegistry,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
      onMessageAdded: onMessageAdded,
    )) {
      fullResponse += token;
      yield token;
    }

    final assistantMsg = LlamaChatMessage.text(
      role: LlamaChatRole.assistant,
      content: fullResponse.trim(),
    );
    _history.add(assistantMsg);
    onMessageAdded?.call(assistantMsg);
  }

  /// Sends a user [text] message and returns the full response string.
  Future<String> chatText(
    String text, {
    GenerationParams? params,
    ToolRegistry? toolRegistryOverride,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async {
    final buffer = StringBuffer();
    await for (final token in chat(
      text,
      params: params,
      toolRegistryOverride: toolRegistryOverride,
      onMessageAdded: onMessageAdded,
    )) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  /// Stateless single-turn chat. Does not track history.
  static Future<String> singleTurn(
    LlamaEngine engine,
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    ToolRegistry? toolRegistry,
    bool forceToolCall = false,
    bool toolsEnabled = true,
    ToolCallFormat toolCallFormat = ToolCallFormat.json,
  }) async {
    final buffer = StringBuffer();
    await for (final token in singleTurnStream(
      engine,
      messages,
      params: params,
      toolRegistry: toolRegistry,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
      toolCallFormat: toolCallFormat,
    )) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  /// Stateless single-turn chat as a stream. Does not track history.
  static Stream<String> singleTurnStream(
    LlamaEngine engine,
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    ToolRegistry? toolRegistry,
    bool forceToolCall = false,
    bool toolsEnabled = true,
    ToolCallFormat toolCallFormat = ToolCallFormat.json,
  }) {
    // Create a temporary session just for processing
    final tempSession = ChatSession(
      engine,
      toolCallFormat: toolCallFormat,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
    );
    final finalMessages = tempSession._getMessagesForEngine(
      history: messages,
    );
    return tempSession._generateWithMessages(
      finalMessages,
      params: params,
      toolRegistry: toolRegistry,
      forceToolCall: forceToolCall,
      toolsEnabled: toolsEnabled,
    );
  }

  /// Internal: generates a response from a list of messages.
  Stream<String> _generateWithMessages(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    ToolRegistry? toolRegistry,
    int maxToolCalls = 5,
    bool forceToolCall = false,
    bool toolsEnabled = true,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    // Process multimodal content - ensure media markers are present
    final processedMessages = _processMultimodalMessages(messages);

    // If tools are provided and not empty, use tool-augmented generation
    if (toolsEnabled && toolRegistry != null && toolRegistry.isNotEmpty) {
      yield* _generateWithTools(
        processedMessages,
        toolRegistry,
        params: params,
        maxToolCalls: maxToolCalls,
        forceToolCall: forceToolCall,
        onMessageAdded: onMessageAdded,
      );
      return;
    }

    // Standard generation without tools
    final result = await _engine.chatTemplate(processedMessages);
    final stops = {...result.stopSequences, ...?params?.stopSequences}.toList();

    // Collect all parts from all messages
    final allParts = processedMessages.expand((m) => m.parts).toList();

    yield* _engine.generate(
      result.prompt,
      params: (params ?? const GenerationParams()).copyWith(
        stopSequences: stops,
      ),
      parts: allParts,
    );
  }

  /// Internal: handles tool-augmented generation.
  Stream<String> _generateWithTools(
    List<LlamaChatMessage> messages,
    ToolRegistry registry, {
    GenerationParams? params,
    int maxToolCalls = 5,
    bool forceToolCall = false,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) async* {
    // Process grammar based on format
    String? grammar;
    if (forceToolCall && _formatConfig.supportsGrammar) {
      grammar = _formatConfig.generateGrammar(registry.tools);
    }

    var toolCallCount = 0;
    var currentMessages = List<LlamaChatMessage>.from(messages);

    while (toolCallCount < maxToolCalls) {
      final buffer = StringBuffer();
      final result = await _engine.chatTemplate(
        currentMessages,
        tools: registry.tools,
      );

      // Use grammar only if forcing tool calls AND we haven't called any tools yet
      final useGrammar = forceToolCall && toolCallCount == 0;
      final genParams = (params ?? const GenerationParams()).copyWith(
        grammar: useGrammar ? grammar : null,
        stopSequences: result.stopSequences,
      );

      final allParts = currentMessages.expand((m) => m.parts).toList();
      bool isLikelyToolCall = false;
      bool checkedType = false;

      // For auto format, always buffer the entire output since models may
      // output prose before the tool call JSON
      final alwaysBuffer = toolCallFormat == ToolCallFormat.auto;

      await for (final token in _engine.generate(
        result.prompt,
        params: genParams,
        parts: allParts,
      )) {
        buffer.write(token);

        if (alwaysBuffer) {
          // In auto mode, buffer everything and parse at the end
          continue;
        }

        if (!checkedType) {
          final trimmedSoFar = buffer.toString().trimLeft();
          if (trimmedSoFar.isNotEmpty) {
            // Check if output looks like any tool call format
            if (_looksLikeToolCall(trimmedSoFar)) {
              isLikelyToolCall = true;
            } else {
              // Not a tool call, start streaming immediately
              yield buffer.toString();
              buffer.clear();
              isLikelyToolCall = false;
            }
            checkedType = true;
          }
        } else if (!isLikelyToolCall) {
          // Streaming plain text
          yield token;
        }
      }

      // For auto format, check if the buffered output contains a tool call
      if (alwaysBuffer) {
        final response = buffer.toString().trim();
        final parseResult = _formatConfig.getParser().tryParse(response);
        if (parseResult == null) {
          // No tool call found, yield the entire response
          yield response;
          return;
        }
        // Tool call found, continue to process it below
        isLikelyToolCall = true;
      }

      if (!isLikelyToolCall) {
        return;
      }

      final response = buffer.toString().trim();

      // Try to parse as tool call using the format-specific parser
      final parseResult = _formatConfig.getParser().tryParse(response);
      if (parseResult != null) {
        try {
          // Invoke the tool
          final toolResult = await registry.invoke(
            parseResult.name,
            parseResult.arguments,
          );
          toolCallCount++;

          // Create assistant message with tool call part
          final toolCallMsg = LlamaChatMessage.multimodal(
            role: LlamaChatRole.assistant,
            parts: [
              LlamaToolCallContent(
                name: parseResult.name,
                arguments: parseResult.arguments,
                rawJson: parseResult.rawOutput,
                id: parseResult.id,
              ),
            ],
          );
          currentMessages.add(toolCallMsg);
          _history.add(toolCallMsg);
          onMessageAdded?.call(toolCallMsg);

          // Create tool message with result part
          // Format the result according to the tool call format
          final formattedResult = _formatConfig.formatToolResult(
            parseResult.name,
            toolResult,
            callId: parseResult.id,
          );
          final toolResultMsg = LlamaChatMessage.text(
            role: _formatConfig.toolResultRole,
            content: formattedResult,
          );
          currentMessages.add(toolResultMsg);
          _history.add(toolResultMsg);
          onMessageAdded?.call(toolResultMsg);

          // Generate final response WITHOUT grammar (let model respond naturally)
          final finalResult = await _engine.chatTemplate(
            currentMessages,
            tools: registry.tools,
          );
          final finalParams = (params ?? const GenerationParams()).copyWith(
            stopSequences: finalResult.stopSequences,
          );

          final finalParts = currentMessages.expand((m) => m.parts).toList();
          yield* _engine.generate(
            finalResult.prompt,
            params: finalParams,
            parts: finalParts,
          );
          return;
        } catch (e) {
          // Tool invocation failed - treat as normal response
        }
      }

      // Not a tool call, yield as final response
      yield response;
      return;
    }

    // Max tool calls reached, do one final generation without tools
    final finalResult = await _engine.chatTemplate(
      currentMessages,
      tools: registry.tools,
    );
    final finalParams = params ?? const GenerationParams();
    yield* _engine.generate(
      finalResult.prompt,
      params: finalParams.copyWith(stopSequences: finalResult.stopSequences),
      parts: currentMessages.expand((m) => m.parts).toList(),
    );
  }

  /// Quick check if the output looks like any known tool call format.
  ///
  /// This is used for early detection during streaming to decide whether
  /// to buffer the output or stream it directly.
  bool _looksLikeToolCall(String output) {
    final trimmed = output.trimLeft();
    if (trimmed.isEmpty) return false;

    // JSON-based formats (OpenAI, etc.)
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return true;

    // Hermes/Qwen format
    if (trimmed.startsWith('<tool_call>')) return true;

    // Qwen Coder / Llama 3.1 Func format
    if (trimmed.startsWith('<function=')) return true;

    // Llama 3.1 JSON format
    if (trimmed.startsWith('<|python_tag|>')) return true;

    // Mistral format
    if (trimmed.startsWith('[TOOL_CALLS]')) return true;

    return false;
  }

  /// Process multimodal messages to ensure media markers are present.
  List<LlamaChatMessage> _processMultimodalMessages(
    List<LlamaChatMessage> messages,
  ) {
    return messages.map((m) {
      final mediaParts = m.parts.where(
        (p) => p is LlamaImageContent || p is LlamaAudioContent,
      );
      if (mediaParts.isEmpty) return m;

      // Count existing markers across all text parts of this message
      final markerCount = m.parts.whereType<LlamaTextContent>().fold(
        0,
        (count, p) => count + '<__media__>'.allMatches(p.text).length,
      );

      if (markerCount < mediaParts.length) {
        final missingMarkers = mediaParts.length - markerCount;
        final injection = ('<__media__>\n' * missingMarkers);

        final newParts = List<LlamaContentPart>.from(m.parts);
        int textIndex = newParts.indexWhere((p) => p is LlamaTextContent);
        if (textIndex != -1) {
          final oldText = (newParts[textIndex] as LlamaTextContent).text;
          newParts[textIndex] = LlamaTextContent('$injection$oldText');
        } else {
          newParts.insert(0, LlamaTextContent(injection.trim()));
        }
        return LlamaChatMessage.multimodal(role: m.role, parts: newParts);
      }
      return m;
    }).toList();
  }

  List<LlamaChatMessage> _getMessagesForEngine({
    List<LlamaChatMessage>? history,
  }) {
    final messages = <LlamaChatMessage>[];
    final sourceHistory = history ?? _history;

    // Get the base system prompt (prefer one in history if it exists)
    final systemInHistory = sourceHistory
        .where((m) => m.role == LlamaChatRole.system)
        .firstOrNull;
    final baseSystemPrompt = systemInHistory?.content ?? systemPrompt;

    if (baseSystemPrompt != null && baseSystemPrompt.isNotEmpty) {
      messages.add(
        LlamaChatMessage.text(
          role: LlamaChatRole.system,
          content: baseSystemPrompt,
        ),
      );
    }

    // Add all non-system messages from history
    messages.addAll(sourceHistory.where((m) => m.role != LlamaChatRole.system));
    return messages;
  }

  /// Truncates history if it exceeds the context limit.
  Future<void> _enforceContextLimit({
    ToolRegistry? toolRegistry,
  }) async {
    final limit = maxContextTokens ?? await _engine.getContextSize();
    if (limit <= 0) return;

    // Estimate reserve (buffer for response)
    final reserve = (limit * 0.1).clamp(128, 512).toInt();
    final targetLimit = limit - reserve;

    while (_history.isNotEmpty) {
      final messages = _getMessagesForEngine();
      final template = await _engine.chatTemplate(
        messages,
        tools: toolRegistry?.tools,
      );

      if (template.tokenCount != null && template.tokenCount! < targetLimit) {
        break;
      }

      // If tokenCount is null (though chatTemplate should return it), fallback to getTokenCount
      final tokenCount =
          template.tokenCount ?? await _engine.getTokenCount(template.prompt);

      if (tokenCount < targetLimit) {
        break;
      }

      // Remove in chunks if we are way over limit to avoid O(N^2) tokenization
      final overBy = tokenCount - targetLimit;
      if (overBy > 500 && _history.length > 4) {
        // Remove 2 turns at once
        _history.removeRange(0, min(4, _history.length - 1));
      } else {
        // Remove the oldest non-system message
        _history.removeAt(0);
        // If it was a user message, remove the corresponding assistant message too
        if (_history.isNotEmpty &&
            _history[0].role == LlamaChatRole.assistant) {
          _history.removeAt(0);
        }
      }
    }
  }
}
