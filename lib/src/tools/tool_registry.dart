import 'tool_definition.dart';

/// Manages a collection of [ToolDefinition]s for use with LLM tool calling.
///
/// The registry provides:
/// - Tool registration via [register] or the constructor.
/// - Tool lookup and invocation via [invoke].
/// - Schema generation for all registered tools via [toJsonSchemaList].
///
/// Example:
/// ```dart
/// final registry = ToolRegistry([
///   ToolDefinition(
///     name: 'get_time',
///     description: 'Get the current time',
///     parameters: [],
///     handler: (params) async => DateTime.now().toIso8601String(),
///   ),
/// ]);
///
/// // Later, invoke a tool by name
/// final result = await registry.invoke('get_time', {});
/// ```
class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};

  /// Creates a [ToolRegistry] with an optional initial list of tools.
  ToolRegistry([List<ToolDefinition>? tools]) {
    if (tools != null) {
      for (final tool in tools) {
        register(tool);
      }
    }
  }

  /// Registers a [tool] with the registry.
  ///
  /// If a tool with the same name already exists, it will be replaced.
  void register(ToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  /// Unregisters a tool by [name].
  ///
  /// Returns `true` if the tool was removed, `false` if it didn't exist.
  bool unregister(String name) {
    return _tools.remove(name) != null;
  }

  /// Returns `true` if a tool with [name] is registered.
  bool has(String name) => _tools.containsKey(name);

  /// Gets a tool by [name], or `null` if not found.
  ToolDefinition? get(String name) => _tools[name];

  /// Returns a list of all registered tool names.
  List<String> get names => _tools.keys.toList();

  /// Returns all registered tools.
  List<ToolDefinition> get tools => _tools.values.toList();

  /// Returns `true` if no tools are registered.
  bool get isEmpty => _tools.isEmpty;

  /// Returns `true` if at least one tool is registered.
  bool get isNotEmpty => _tools.isNotEmpty;

  /// Invokes a tool by [name] with the given [args].
  ///
  /// Throws [ArgumentError] if the tool is not found.
  Future<Object?> invoke(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      throw ArgumentError('Tool not found: $name');
    }
    return tool.invoke(args);
  }

  /// Converts all registered tools to a list of JSON Schema maps.
  ///
  /// Each entry contains:
  /// - `name`: The tool name.
  /// - `description`: The tool description.
  /// - `parameters`: The JSON Schema for the tool's parameters.
  ///
  /// This is used internally for GBNF grammar generation.
  List<Map<String, dynamic>> toJsonSchemaList() {
    return _tools.values.map((tool) {
      return {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.toJsonSchema(),
      };
    }).toList();
  }

  @override
  String toString() => 'ToolRegistry(${_tools.keys.join(', ')})';
}
