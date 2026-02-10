import 'dart:convert';

import 'package:jinja/jinja.dart';

import '../backend/llama_backend_interface.dart';
import '../models/llama_chat_message.dart';
import '../models/llama_chat_template_result.dart';
import '../models/llama_content_part.dart';
import '../tools/tool_definition.dart';

/// Processes chat templates using the model's Jinja template from GGUF metadata.
///
/// Falls back to the native `llama_chat_apply_template()` FFI call if Jinja
/// rendering fails (e.g., unsupported template features).
class ChatTemplateProcessor {
  final LlamaBackend _backend;
  final int _modelHandle;

  // Cached metadata and compiled template
  Map<String, String>? _metadata;
  String? _jinjaTemplateStr;
  Template? _compiledTemplate;
  bool _jinjaAvailable = true;

  /// Creates a new [ChatTemplateProcessor] for the given model.
  ChatTemplateProcessor(this._backend, this._modelHandle);

  /// Lazy-loads and caches model metadata.
  Future<Map<String, String>> _getMetadata() async {
    _metadata ??= await _backend.modelMetadata(_modelHandle);
    return _metadata!;
  }

  /// Applies the model's chat template to a list of messages.
  ///
  /// When [tools] is provided, tool definitions are passed as Jinja context
  /// variables so the model's own template handles tool formatting.
  Future<LlamaChatTemplateResult> apply(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<ToolDefinition>? tools,
  }) async {
    if (_jinjaAvailable) {
      try {
        return await _applyJinja(
          messages,
          addAssistant: addAssistant,
          tools: tools,
        );
      } catch (_) {
        // Jinja failed — disable for this model and fall back to FFI
        _jinjaAvailable = false;
      }
    }

    return _backend.applyChatTemplate(
      _modelHandle,
      messages,
      addAssistant: addAssistant,
    );
  }

  Future<LlamaChatTemplateResult> _applyJinja(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<ToolDefinition>? tools,
  }) async {
    final metadata = await _getMetadata();

    if (_compiledTemplate == null) {
      _jinjaTemplateStr =
          metadata['tokenizer.chat_template'] ?? metadata['chat_template'];
      if (_jinjaTemplateStr == null || _jinjaTemplateStr!.isEmpty) {
        throw StateError('No chat template in model metadata');
      }
      final env = Environment(
        trimBlocks: true,
        leftStripBlocks: true,
        globals: {
          'raise_exception': (String msg) => throw Exception(msg),
        },
      );
      _compiledTemplate = env.fromString(_jinjaTemplateStr!);
    }

    final context = _buildContext(
      messages,
      metadata,
      addAssistant: addAssistant,
      tools: tools,
    );
    final prompt = _compiledTemplate!.render(context);
    final stops = _detectStopSequences(metadata);

    return LlamaChatTemplateResult(
      prompt: prompt,
      stopSequences: stops,
    );
  }

  Map<String, dynamic> _buildContext(
    List<LlamaChatMessage> messages,
    Map<String, String> metadata, {
    bool addAssistant = true,
    List<ToolDefinition>? tools,
  }) {
    final msgList = messages.map((m) {
      final entry = <String, dynamic>{
        'role': m.role.name,
        'content': m.content,
      };

      // Map tool call parts to HuggingFace convention
      final toolCallParts =
          m.parts.whereType<LlamaToolCallContent>().toList();
      if (toolCallParts.isNotEmpty) {
        entry['tool_calls'] = toolCallParts
            .map((tc) => {
                  'id': tc.id ?? tc.name,
                  'type': 'function',
                  'function': {
                    'name': tc.name,
                    'arguments': tc.arguments,
                  },
                })
            .toList();
        if (m.content.isEmpty) {
          entry['content'] = null;
        }
      }

      // Map tool result parts
      final toolResultParts =
          m.parts.whereType<LlamaToolResultContent>().toList();
      if (toolResultParts.isNotEmpty) {
        final tr = toolResultParts.first;
        entry['tool_call_id'] = tr.id ?? tr.name;
        if (entry['content'] == '' || entry['content'] == null) {
          try {
            entry['content'] = jsonEncode(tr.result);
          } catch (_) {
            entry['content'] = tr.result.toString();
          }
        }
      }

      return entry;
    }).toList();

    final context = <String, dynamic>{
      'messages': msgList,
      'add_generation_prompt': addAssistant,
      'bos_token': _resolveSpecialToken(metadata, 'bos_token'),
      'eos_token': _resolveSpecialToken(metadata, 'eos_token'),
    };

    if (tools != null && tools.isNotEmpty) {
      context['tools'] = tools
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.toJsonSchema(),
                },
              })
          .toList();
    }

    return context;
  }

  String _resolveSpecialToken(Map<String, String> metadata, String name) {
    // Modern GGUF format: tokenizer.<name>.content
    final content = metadata['tokenizer.$name.content'];
    if (content != null && content.isNotEmpty) return content;

    // Legacy format
    final legacy = metadata['tokenizer.$name'];
    if (legacy != null && legacy.isNotEmpty) {
      // Some models store JSON-encoded token strings
      if (legacy.startsWith('"') || legacy.startsWith('{')) {
        try {
          final decoded = jsonDecode(legacy);
          if (decoded is String) return decoded;
          if (decoded is Map && decoded.containsKey('content')) {
            return decoded['content'] as String;
          }
        } catch (_) {}
      }
      return legacy;
    }

    return '';
  }

  List<String> _detectStopSequences(Map<String, String> metadata) {
    final stops = <String>{};

    final eos = _resolveSpecialToken(metadata, 'eos_token');
    if (eos.isNotEmpty) stops.add(eos);

    final tmpl = _jinjaTemplateStr ?? '';
    if (tmpl.contains('im_end')) {
      stops.add('<|im_end|>');
      stops.add('<|endoftext|>');
    }
    if (tmpl.contains('eot_id')) stops.add('<|eot_id|>');
    if (tmpl.contains('end_of_turn')) stops.add('<|end_of_turn|>');

    return stops.toList();
  }

  /// Automatically identifies stop sequences for the current model.
  Future<List<String>> detectStopSequences() async {
    final result = await apply([]);
    return result.stopSequences;
  }
}
