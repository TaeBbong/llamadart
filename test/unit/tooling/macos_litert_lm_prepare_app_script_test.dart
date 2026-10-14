@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('macos_litert_lm_prepare_app.sh', () {
    test('chat app embeds the macOS runtime after Flutter assembly', () {
      final project = File(
        path.join(
          'example',
          'chat_app',
          'macos',
          'Runner.xcodeproj',
          'project.pbxproj',
        ),
      ).readAsStringSync();

      final nativeTargetsStart = project.indexOf(
        '/* Begin PBXNativeTarget section */',
      );
      expect(nativeTargetsStart, greaterThanOrEqualTo(0));
      final runnerTargetStart = project.indexOf(
        '/* Runner */ = {',
        nativeTargetsStart,
      );
      final runnerBuildPhasesEnd = project.indexOf(
        'buildRules = (',
        runnerTargetStart,
      );
      expect(runnerTargetStart, greaterThanOrEqualTo(0));
      expect(runnerBuildPhasesEnd, greaterThan(runnerTargetStart));

      final runnerBuildPhases = project.substring(
        runnerTargetStart,
        runnerBuildPhasesEnd,
      );
      final flutterEmbed = runnerBuildPhases.indexOf('/* ShellScript */');
      final prepareRuntime = runnerBuildPhases.indexOf(
        '/* Prepare LiteRT-LM Runtime */',
      );

      expect(flutterEmbed, greaterThanOrEqualTo(0));
      expect(prepareRuntime, greaterThan(flutterEmbed));
      expect(project, contains('macos_assemble.sh embed'));
      expect(project, isNot(contains('../../../tool/')));
      expect(
        _pbxprojShellScript(project, 'Prepare LiteRT-LM Runtime'),
        _documentedBuildPhase(_installationDocs.first),
      );
    });

    for (final docs in _installationDocs) {
      test('$docs build phase runs the resolved package script', () async {
        final script = _documentedBuildPhase(docs);
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_docs_',
        );
        addTearDown(() => root.delete(recursive: true));

        final workspace = Directory(path.join(root.path, 'my workspace'));
        final package = Directory(
          path.join(workspace.path, 'packages', 'llama dart'),
        );
        final prepare = File(
          path.join(package.path, 'tool', 'macos_litert_lm_prepare_app.sh'),
        );
        await prepare.parent.create(recursive: true);
        await prepare.writeAsString('echo "PREPARE \$1"\n');
        final config = File(
          path.join(workspace.path, '.dart_tool', 'package_config.json'),
        );
        await config.parent.create(recursive: true);
        final project = Directory(
          path.join(workspace.path, 'apps', 'my app', 'macos'),
        );
        await project.create(recursive: true);

        Future<ProcessResult> run() => Process.run(
          'bash',
          ['-c', script],
          environment: {
            'PROJECT_DIR': project.path,
            'TARGET_BUILD_DIR': path.join(root.path, 'Build'),
            'WRAPPER_NAME': 'My App.app',
          },
        );
        final appPath = path.join(root.path, 'Build', 'My App.app');

        for (final rootUri in [
          '../packages/llama%20dart/',
          Uri.directory(package.path).toString(),
        ]) {
          await config.writeAsString(
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'meta', 'rootUri': 'file:///unused/'},
                {'name': 'llamadart', 'rootUri': rootUri},
              ],
            }),
          );
          final result = await run();
          expect(result.exitCode, 0, reason: '$rootUri: ${result.stderr}');
          expect(result.stdout, contains('PREPARE $appPath'));
        }

        await config.writeAsString(
          jsonEncode({'configVersion': 2, 'packages': <Object>[]}),
        );
        final unresolved = await run();
        expect(unresolved.exitCode, 1);
        expect(unresolved.stderr, contains('llamadart is not resolved'));

        await config.delete();
        final missing = await run();
        expect(missing.exitCode, 1);
        expect(missing.stderr, contains('run flutter pub get'));
      }, skip: Platform.isMacOS ? false : 'requires macOS plutil');
    }

    test('rejects incomplete explicit arm64 runtime directories', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_partial_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = Directory(path.join(root.path, 'litert'))..createSync();
      await File(path.join(libDir.path, 'libLiteRtLm.dylib')).create();

      final appDir = Directory(path.join(root.path, 'Test.app'));
      final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

      expect(result.exitCode, 2);
      expect(result.stderr, contains('library directory is incomplete'));
      expect(result.stderr, contains('libCLiteRTLM_mac.dylib'));
      expect(
        Directory(
          path.join(appDir.path, 'Contents', 'Frameworks'),
        ).existsSync(),
        isFalse,
      );
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test('installs the full arm64 companion library set', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_full_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = Directory(path.join(root.path, 'litert'))..createSync();
      for (final library in _arm64Libraries) {
        await File(path.join(libDir.path, library)).create();
      }

      final appDir = Directory(path.join(root.path, 'Test.app'));
      final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Prepared LiteRT-LM macOS'));

      final frameworksDir = path.join(appDir.path, 'Contents', 'Frameworks');
      final runtimeDir = path.join(frameworksDir, 'LiteRtLmRuntime');
      for (final library in _arm64Libraries) {
        final libraryPath = path.join(runtimeDir, library);
        expect(File(libraryPath).existsSync(), isTrue, reason: library);
      }
      for (final framework in _oldFrameworks) {
        expect(
          Directory(
            path.join(frameworksDir, '$framework.framework'),
          ).existsSync(),
          isFalse,
          reason: framework,
        );
      }
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test(
      'does not treat unrelated Flutter frameworks as LiteRT-LM runtime',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_flutter_framework_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = Directory(path.join(root.path, 'litert'))..createSync();
        for (final library in _arm64Libraries) {
          await File(path.join(libDir.path, library)).create();
        }

        final appDir = Directory(path.join(root.path, 'Test.app'));
        Directory(
          path.join(
            appDir.path,
            'Contents',
            'Frameworks',
            'llamadart.framework',
          ),
        ).createSync(recursive: true);

        final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('Prepared LiteRT-LM macOS'));
        expect(
          File(
            path.join(
              appDir.path,
              'Contents',
              'Frameworks',
              'LiteRtLmRuntime',
              'libCLiteRTLM_mac.dylib',
            ),
          ).existsSync(),
          isTrue,
        );
      },
      skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false,
    );

    test('skips when a complete fallback runtime is already bundled', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_skip_bundled_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = Directory(path.join(root.path, 'litert'))..createSync();
      for (final library in _arm64Libraries) {
        await File(path.join(libDir.path, library)).create();
      }

      final appDir = Directory(path.join(root.path, 'Test.app'));
      final runtimeDir = Directory(
        path.join(appDir.path, 'Contents', 'Frameworks', 'LiteRtLmRuntime'),
      )..createSync(recursive: true);
      for (final library in _arm64Libraries) {
        await File(path.join(runtimeDir.path, library)).create();
      }

      final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Complete LiteRT-LM runtime detected'));
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test(
      'does not treat partial arm64 native SPM runtime as complete',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_partial_spm_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = Directory(path.join(root.path, 'litert'))..createSync();
        for (final library in _arm64Libraries) {
          await File(path.join(libDir.path, library)).create();
        }

        final appDir = Directory(path.join(root.path, 'Test.app'));
        final frameworksDir = Directory(
          path.join(appDir.path, 'Contents', 'Frameworks'),
        )..createSync(recursive: true);
        final liteRtLmDir = Directory(
          path.join(frameworksDir.path, 'LiteRtLm.framework', 'Versions', 'A'),
        )..createSync(recursive: true);
        await File(path.join(liteRtLmDir.path, 'LiteRtLm')).create();
        await File(
          path.join(frameworksDir.path, 'libCLiteRTLM_mac.dylib'),
        ).create();

        final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('Prepared LiteRT-LM macOS'));
        expect(
          File(
            path.join(
              frameworksDir.path,
              'LiteRtLmRuntime',
              'libCLiteRTLM_mac.dylib',
            ),
          ).existsSync(),
          isTrue,
        );
      },
      skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false,
    );

    test('installs the x64 runtime library set', () async {
      final root = await Directory.systemTemp.createTemp('litert_prepare_x64_');
      addTearDown(() => root.delete(recursive: true));

      final libDir = Directory(path.join(root.path, 'litert'))..createSync();
      for (final library in _x64Libraries) {
        await File(path.join(libDir.path, library)).create();
      }

      final appDir = Directory(path.join(root.path, 'Test.app'));
      final result = await _runPrepareApp(appDir, libDir, arch: 'x64');

      expect(result.exitCode, 0, reason: result.stderr.toString());

      final frameworksDir = path.join(appDir.path, 'Contents', 'Frameworks');
      final runtimeDir = path.join(frameworksDir, 'LiteRtLmRuntime');
      for (final library in _x64Libraries) {
        final libraryPath = path.join(runtimeDir, library);
        expect(File(libraryPath).existsSync(), isTrue, reason: library);
      }
      expect(
        File(
          path.join(
            frameworksDir,
            'LiteRtLmRuntime',
            'libLiteRtMetalAccelerator.dylib',
          ),
        ).existsSync(),
        isFalse,
      );
      for (final framework in _oldFrameworks) {
        expect(
          Directory(
            path.join(frameworksDir, '$framework.framework'),
          ).existsSync(),
          isFalse,
          reason: framework,
        );
      }
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);
  });
}

const _installationDocs = [
  'website/docs/getting-started/installation.md',
  'website/versioned_docs/version-0.12.0/getting-started/installation.md',
];

/// The `bash` block of the Flutter macOS LiteRT-LM build phase section.
String _documentedBuildPhase(String docsPath) {
  final docs = File(docsPath).readAsStringSync();
  final section = docs.indexOf('### Flutter macOS LiteRT-LM build phase');
  expect(section, greaterThanOrEqualTo(0), reason: docsPath);
  final start = docs.indexOf('```bash\n', section) + '```bash\n'.length;
  return docs.substring(start, docs.indexOf('```', start));
}

/// Decodes the `shellScript` of the named `PBXShellScriptBuildPhase`.
String _pbxprojShellScript(String project, String phaseName) {
  final phase = project.indexOf('name = "$phaseName";');
  expect(phase, greaterThanOrEqualTo(0), reason: phaseName);
  final match = RegExp(
    r'shellScript = "((?:[^"\\]|\\.)*)";',
  ).firstMatch(project.substring(phase))!;
  return match
      .group(1)!
      .replaceAllMapped(
        RegExp(r'\\(.)'),
        (escape) => escape[1] == 'n' ? '\n' : escape[1]!,
      );
}

Future<ProcessResult> _runPrepareApp(
  Directory appDir,
  Directory libDir, {
  required String arch,
}) {
  return Process.run(
    'bash',
    ['tool/macos_litert_lm_prepare_app.sh', appDir.path],
    environment: {
      'LLAMADART_LITERT_LM_ARCH': arch,
      'LLAMADART_LITERT_LM_LIB_DIR': libDir.path,
    },
  );
}

const List<String> _arm64Libraries = [
  'libCLiteRTLM_mac.dylib',
  'libGemmaModelConstraintProvider.dylib',
  'libLiteRt.dylib',
  'libLiteRtLm.dylib',
  'libLiteRtMetalAccelerator.dylib',
  'libLiteRtTopKMetalSampler.dylib',
  'libLiteRtTopKWebGpuSampler.dylib',
  'libLiteRtWebGpuAccelerator.dylib',
  'libwebgpu_dawn.dylib',
];

const List<String> _oldFrameworks = [
  'GemmaModelConstraintProvider',
  'LiteRt',
  'LiteRtLm',
  'LiteRtMetalAccelerator',
  'LiteRtTopKMetalSampler',
  'LiteRtTopKWebGpuSampler',
  'LiteRtWebGpuAccelerator',
];

const List<String> _x64Libraries = [
  'libCLiteRTLM_mac.dylib',
  'libLiteRtLm.dylib',
];
