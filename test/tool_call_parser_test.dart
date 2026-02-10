import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  group('OpenAIToolCallParser', () {
    final parser = OpenAIToolCallParser();

    test('parses standard OpenAI format', () {
      const input = '''
{"type": "function", "function": {"name": "get_weather", "parameters": {"location": "London"}}}
''';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['location'], 'London');
    });

    test('parses shortened function format', () {
      const input = '{"function": {"name": "search", "parameters": {"query": "AI"}}}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['query'], 'AI');
    });

    test('parses direct name/parameters format', () {
      const input = '{"name": "calculate", "parameters": {"expression": "2+2"}}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'calculate');
      expect(result.arguments['expression'], '2+2');
    });

    test('parses array of tool calls', () {
      const input = '[{"type": "function", "function": {"name": "get_weather", "parameters": {"city": "Tokyo"}}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Tokyo');
    });

    test('parses arguments as JSON string', () {
      const input = '{"name": "test", "arguments": "{\\"key\\": \\"value\\"}"}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(result.arguments['key'], 'value');
    });

    test('returns null for invalid JSON', () {
      const input = 'not json at all';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });

    test('returns null for plain text', () {
      const input = 'The weather in London is sunny.';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('HermesToolCallParser', () {
    final parser = HermesToolCallParser();

    test('parses Hermes format with closing tag', () {
      const input = '<tool_call>{"name": "get_weather", "arguments": {"city": "London"}}</tool_call>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'London');
    });

    test('parses Hermes format without closing tag', () {
      const input = '<tool_call>{"name": "search", "arguments": {"query": "test"}}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['query'], 'test');
    });

    test('parses with whitespace', () {
      const input = '''
<tool_call>
  {"name": "calculate", "arguments": {"x": 10, "y": 20}}
</tool_call>
''';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'calculate');
      expect(result.arguments['x'], 10);
      expect(result.arguments['y'], 20);
    });

    test('parses parameters instead of arguments', () {
      const input = '<tool_call>{"name": "test", "parameters": {"key": "value"}}</tool_call>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(result.arguments['key'], 'value');
    });

    test('returns null for non-Hermes format', () {
      const input = '{"name": "test", "parameters": {}}';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('QwenCoderToolCallParser', () {
    final parser = QwenCoderToolCallParser();

    test('parses Qwen Coder format', () {
      const input = '<function=get_weather><parameter=city>London</parameter><parameter=unit>celsius</parameter></function>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'London');
      expect(result.arguments['unit'], 'celsius');
    });

    test('parses with numeric values', () {
      const input = '<function=calculate><parameter=x>42</parameter><parameter=y>3.14</parameter></function>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'calculate');
      expect(result.arguments['x'], 42);
      expect(result.arguments['y'], 3.14);
    });

    test('parses with boolean values', () {
      const input = '<function=toggle><parameter=enabled>true</parameter></function>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'toggle');
      expect(result.arguments['enabled'], true);
    });

    test('returns null for non-Qwen Coder format', () {
      const input = '{"name": "test"}';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('Llama31JsonToolCallParser', () {
    final parser = Llama31JsonToolCallParser();

    test('parses with python_tag and eom_id', () {
      const input = '<|python_tag|>{"name": "get_weather", "parameters": {"city": "Tokyo"}}<|eom_id|>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Tokyo');
    });

    test('parses without eom_id', () {
      const input = '<|python_tag|>{"name": "search", "arguments": {"q": "test"}}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['q'], 'test');
    });

    test('returns null for non-Llama format', () {
      const input = '{"name": "test"}';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('Llama31FuncToolCallParser', () {
    final parser = Llama31FuncToolCallParser();

    test('parses function tag with JSON', () {
      const input = '<function=get_weather>{"city": "Paris", "unit": "celsius"}</function>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Paris');
      expect(result.arguments['unit'], 'celsius');
    });

    test('does not parse Qwen Coder format', () {
      const input = '<function=test><parameter=x>1</parameter></function>';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('Llama31BuiltinToolCallParser', () {
    final parser = Llama31BuiltinToolCallParser();

    test('parses builtin tool call format', () {
      const input = 'brave_search.call(query="weather in London")';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'brave_search');
      expect(result.arguments['query'], 'weather in London');
    });

    test('parses multiple arguments', () {
      const input = 'get_weather.call(city="Tokyo", unit="celsius")';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Tokyo');
      expect(result.arguments['unit'], 'celsius');
    });

    test('parses numeric arguments', () {
      const input = 'calculate.call(x=42, y=3.14)';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'calculate');
      expect(result.arguments['x'], 42);
      expect(result.arguments['y'], 3.14);
    });

    test('returns null for non-builtin format', () {
      const input = '{"name": "test"}';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('PythonicToolCallParser', () {
    final parser = PythonicToolCallParser();

    test('parses bracketed function call', () {
      const input = '[get_weather(city="London")]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'London');
    });

    test('parses unbracketed function call', () {
      const input = 'search(query="AI news")';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['query'], 'AI news');
    });

    test('parses multiple arguments', () {
      const input = '[calculate(x=10, y=20)]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'calculate');
      expect(result.arguments['x'], 10);
      expect(result.arguments['y'], 20);
    });

    test('ignores Python keywords', () {
      const input = 'print("hello")';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });

    test('does not match .call() format', () {
      const input = 'test.call(x=1)';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('MistralToolCallParser', () {
    final parser = MistralToolCallParser();

    test('parses Mistral format', () {
      const input = '[TOOL_CALLS] [{"name": "get_weather", "arguments": {"city": "London"}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'London');
    });

    test('parses with parameters instead of arguments', () {
      const input = '[TOOL_CALLS] [{"name": "search", "parameters": {"q": "test"}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['q'], 'test');
    });

    test('parses multiple tool calls (returns first)', () {
      const input = '[TOOL_CALLS] [{"name": "first", "arguments": {}}, {"name": "second", "arguments": {}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'first');
    });

    test('returns null for non-Mistral format', () {
      const input = '{"name": "test"}';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });

    test('parses plain JSON array without TOOL_CALLS marker', () {
      const input = '[{"name": "get_weather", "arguments": {"city": "Seoul"}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Seoul');
    });

    test('parses plain JSON array with parameters', () {
      const input = '[{"name": "search", "parameters": {"query": "test"}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['query'], 'test');
    });
  });

  group('EmbeddedJsonToolCallParser', () {
    final parser = EmbeddedJsonToolCallParser();

    test('parses JSON in code block', () {
      const input = '''
I'll check the weather for you.
```json
{"name": "get_weather", "arguments": {"city": "Tokyo"}}
```
''';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Tokyo');
    });

    test('parses JSON in code block without json tag', () {
      const input = '''
Let me call the function:
```
{"name": "search", "arguments": {"query": "AI news"}}
```
''';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'search');
      expect(result.arguments['query'], 'AI news');
    });

    test('parses inline JSON object', () {
      const input = 'I will use the tool: {"name": "calculate", "arguments": {"x": 10}}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'calculate');
      expect(result.arguments['x'], 10);
    });

    test('parses inline JSON array', () {
      const input = 'Calling: [{"name": "get_weather", "arguments": {"city": "London"}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'London');
    });

    test('returns null for plain text', () {
      const input = 'The weather is nice today.';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });

    test('returns null for JSON without name field', () {
      const input = 'Here is some data: {"key": "value"}';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });
  });

  group('CompositeToolCallParser', () {
    final parser = CompositeToolCallParser();

    test('parses OpenAI format', () {
      const input = '{"type": "function", "function": {"name": "test", "parameters": {}}}';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'OpenAI');
    });

    test('parses Hermes format', () {
      const input = '<tool_call>{"name": "test", "arguments": {}}</tool_call>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'Hermes');
    });

    test('parses Qwen Coder format', () {
      const input = '<function=test><parameter=x>1</parameter></function>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'QwenCoder');
    });

    test('parses Llama 3.1 JSON format', () {
      const input = '<|python_tag|>{"name": "test", "parameters": {}}<|eom_id|>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'Llama31Json');
    });

    test('parses Llama 3.1 Func format', () {
      const input = '<function=test>{"x": 1}</function>';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'Llama31Func');
    });

    test('parses Llama 3.1 Builtin format', () {
      const input = 'test.call(x=1)';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'Llama31Builtin');
    });

    test('parses Mistral format', () {
      const input = '[TOOL_CALLS] [{"name": "test", "arguments": {}}]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'Mistral');
    });

    test('parses Pythonic format', () {
      const input = '[test(x=1)]';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'test');
      expect(parser.lastMatchedParser?.name, 'Pythonic');
    });

    test('returns null for plain text', () {
      const input = 'The weather is nice today.';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });

    test('returns null for empty string', () {
      const input = '';
      final result = parser.tryParse(input);
      expect(result, isNull);
    });

    test('lists all available formats', () {
      final formats = parser.availableFormats;
      expect(formats, contains('OpenAI'));
      expect(formats, contains('Hermes'));
      expect(formats, contains('QwenCoder'));
      expect(formats, contains('Llama31Json'));
      expect(formats, contains('Llama31Func'));
      expect(formats, contains('Llama31Builtin'));
      expect(formats, contains('Pythonic'));
      expect(formats, contains('Mistral'));
      expect(formats, contains('EmbeddedJson'));
    });

    test('parses embedded JSON in prose using EmbeddedJson parser', () {
      const input = '''
To get the weather, I will call the function:
```json
{"name": "get_weather", "arguments": {"city": "Seoul"}}
```
''';
      final result = parser.tryParse(input);

      expect(result, isNotNull);
      expect(result!.name, 'get_weather');
      expect(result.arguments['city'], 'Seoul');
      expect(parser.lastMatchedParser?.name, 'EmbeddedJson');
    });
  });
}
