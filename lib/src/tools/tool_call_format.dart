/// Defines the format used for tool calling with LLMs.
///
/// Different models use different formats for tool calling. This enum
/// allows you to specify which format to use based on your model.
///
/// Example:
/// ```dart
/// final session = ChatSession(
///   engine,
///   toolRegistry: registry,
///   toolCallFormat: ToolCallFormat.hermes, // For Qwen models
/// );
/// ```
enum ToolCallFormat {
  /// OpenAI-style JSON format (default, most compatible).
  ///
  /// Output: `{"type": "function", "function": {"name": "...", "parameters": {...}}}`
  ///
  /// Works well with most instruction-tuned models that understand JSON.
  json,

  /// Hermes format used by Qwen 2.5, Qwen 3 Instruct, and Hermes models.
  ///
  /// Output: `<tool_call>{"name": "...", "arguments": {...}}</tool_call>`
  ///
  /// Tool result: `<tool_response>{"name": "...", "content": ...}</tool_response>`
  hermes,

  /// Llama 3.1+ native format with python_tag.
  ///
  /// Output: `<|python_tag|>{"name": "...", "parameters": {...}}`
  ///
  /// Best for Llama 3.1, 3.2, and newer Meta models.
  llama,

  /// Mistral format with TOOL_CALLS marker.
  ///
  /// Output: `[TOOL_CALLS] [{"name": "...", "arguments": {...}}]`
  ///
  /// Best for Mistral and Mixtral models.
  mistral,

  /// Automatic format detection using all available parsers.
  ///
  /// Does not enforce a specific format via system prompt or grammar.
  /// Uses [CompositeToolCallParser] to try all parsers in order.
  ///
  /// Use this when:
  /// - You don't know which format the model uses
  /// - The model has native tool calling support in its chat template
  auto,
}
