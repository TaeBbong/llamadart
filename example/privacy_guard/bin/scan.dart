import 'dart:io';

import 'package:args/args.dart';
import 'package:llamadart/llamadart.dart';
import 'package:privacy_guard_example/src/model.dart';
import 'package:privacy_guard_example/src/redaction.dart';
import 'package:privacy_guard_example/src/scanner.dart';

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
    ..addOption('out', help: 'Folder for the redacted copies.')
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
      'Checks photos the way the app does.\n\n'
      'dart run bin/scan.dart [options] <image>...\n\n${parser.usage}',
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
    final scanner = PrivacyScanner(engine);
    final out = args.option('out');
    for (final path in args.rest) {
      final bytes = await File(path).readAsBytes();
      final photo = preparePhoto(bytes);
      final report = await scanner.scan(photo.modelImage);
      stdout.writeln(
        '$path\n  ${report.verdict} (${report.elapsed.inMilliseconds} ms)'
        '${photo.hasLocation ? '\n  - GPS location in metadata' : ''}',
      );
      for (final f in report.findings) {
        stdout.writeln('  - ${f.kind.title}: ${f.label} ${f.box}');
      }
      if (out != null) {
        final name = path.split(Platform.pathSeparator).last.split('.').first;
        final file = File('$out${Platform.pathSeparator}$name-redacted.jpg');
        await file.writeAsBytes(
          redactPhoto(bytes, [for (final f in report.findings) f.box]),
        );
      }
    }
  } finally {
    await engine.dispose();
  }
}
