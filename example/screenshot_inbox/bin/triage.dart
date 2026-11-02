import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:image/image.dart' as img;
import 'package:llamadart/llamadart.dart';
import 'package:screenshot_inbox_example/src/model.dart';
import 'package:screenshot_inbox_example/src/triage.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'size',
      allowed: ['2b', '4b'],
      defaultsTo: '4b',
      help: 'Qwen3.5 to download when --model is not given.',
    )
    ..addOption('model', help: 'Qwen3.5 GGUF path.')
    ..addOption('projector', help: 'Its mmproj GGUF path.')
    ..addOption('language', defaultsTo: 'en', help: 'Language for summaries.')
    ..addFlag('cpu', help: 'Run on the CPU.', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  if (args.flag('help') || args.rest.isEmpty) {
    stdout.writeln(
      'Sorts screenshot files the way the app does.\n\n'
      'dart run bin/triage.dart [options] <image>...\n\n${parser.usage}',
    );
    return;
  }
  final modelPath = args.option('model');
  final projectorPath = args.option('projector');
  if ((modelPath == null) != (projectorPath == null)) {
    stderr.writeln('Pass --model and --projector together.');
    exitCode = 64;
    return;
  }

  int? shown = -1;
  final pinned = args.option('size') == '2b' ? qwen35Small : qwen35Large;
  final engine = await loadAgentModel(
    modelPath == null
        ? pinned.load()
        : LlamaModel(
            ModelSource.path(modelPath),
            projector: ModelSource.path(projectorPath!),
          ),
    label: modelPath ?? pinned.label,
    cpu: args.flag('cpu'),
    onStatus: (message, fraction) {
      final percent = fraction == null ? null : (fraction * 10).floor();
      if (percent != shown) stderr.writeln(message);
      shown = percent;
    },
  );
  try {
    stderr.writeln('Running on ${await engine.getBackendName()}');
    final triager = ScreenshotTriager(
      engine,
      language: args.option('language')!,
    );
    for (final path in args.rest) {
      final triage = await triager.triage(await _preview(path));
      stdout.writeln(
        '$path\n  ${triage.kind.title}: ${triage.summary} '
        '(${triage.elapsed.inMilliseconds} ms)',
      );
      for (final action in triage.actions) {
        stdout.writeln('  - ${_describe(action)}');
      }
    }
  } finally {
    await engine.dispose();
  }
}

/// The image at [path] as a JPEG at most [previewEdge] pixels on its long
/// edge, the size the app sends.
Future<Uint8List> _preview(String path) async {
  final image = img.decodeImage(await File(path).readAsBytes());
  if (image == null) throw FormatException('Not an image', path);
  final resized = image.width >= image.height
      ? img.copyResize(image, width: image.width.clamp(1, previewEdge))
      : img.copyResize(image, height: image.height.clamp(1, previewEdge));
  return img.encodeJpg(resized, quality: 90);
}

String _describe(InboxAction action) => switch (action) {
  AddEventAction(:final title, :final start, :final allDay, :final location) =>
    'add_event: $title, ${allDay ? '${start.toString().substring(0, 10)} (all day)' : start}'
        '${location == null ? '' : ', $location'}',
  OpenMapAction(:final query) => 'open_map: $query',
  CopyTextAction(:final label, :final text) => 'copy_text: $label = $text',
};
