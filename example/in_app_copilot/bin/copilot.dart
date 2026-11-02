import 'dart:io';

import 'package:args/args.dart';
import 'package:in_app_copilot_example/src/copilot.dart';
import 'package:in_app_copilot_example/src/ledger.dart';
import 'package:in_app_copilot_example/src/model.dart';
import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'size',
      allowed: ['2b', '4b'],
      defaultsTo: '4b',
      help: 'Qwen3.5 to download when --model is not given.',
    )
    ..addOption('model', help: 'Qwen3.5 GGUF path.')
    ..addFlag('yes', help: 'Approve every deletion.', negatable: false)
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
      'Talks to the copilot over the sample ledger, one request per '
      'argument, in one conversation.\n\n'
      'dart run bin/copilot.dart [options] <request>...\n\n${parser.usage}',
    );
    return;
  }

  int? shown = -1;
  final modelPath = args.option('model');
  final pinned = args.option('size') == '2b' ? qwen35Small : qwen35Large;
  final engine = await loadAgentModel(
    modelPath == null
        ? pinned.load(vision: false)
        : LlamaModel(ModelSource.path(modelPath)),
    label: modelPath ?? pinned.label,
    cpu: args.flag('cpu'),
    onStatus: (message, fraction) {
      final percent = fraction == null ? null : (fraction * 10).floor();
      if (percent != shown) stderr.writeln(message);
      shown = percent;
    },
  );
  final ledger = Ledger.sample(DateTime.now());
  try {
    stderr.writeln('Running on ${await engine.getBackendName()}');
    final copilot = Copilot(
      engine,
      ledger,
      confirm: (question) async {
        stdout.writeln('? $question');
        if (args.flag('yes')) return true;
        stdout.write('Approve? [y/N] ');
        return stdin.readLineSync()?.trim().toLowerCase() == 'y';
      },
    );
    for (final request in args.rest) {
      await _ask(copilot, request);
    }
  } finally {
    await engine.dispose();
    await ledger.close();
  }
}

Future<void> _ask(Copilot copilot, String request) async {
  stdout.writeln('> $request');
  final stopwatch = Stopwatch()..start();
  final reply = await copilot.ask(
    request,
    onActivity: (a) {
      if (a.result == null) stdout.writeln('  ${a.signature}');
    },
  );
  stdout.writeln('${reply.text} (${stopwatch.elapsedMilliseconds} ms)\n');
}
