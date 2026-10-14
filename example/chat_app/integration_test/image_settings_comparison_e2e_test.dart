@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 40))
/// Local-only device comparison of the automatic image attention and VAE
/// settings against explicit overrides
/// (https://github.com/leehack/llamadart/issues/805).
///
/// In one process, through the public API, it loads SDXS-512, SD-Turbo with
/// TAESD and SD-Turbo with its full VAE once per arm of
/// `imageSettingsVariants` and generates the same seeded 512x512 image:
/// `ImageGenerationEngine.warmUp` (a one-step generation on a GPU, nothing
/// on the CPU), then `IMAGE_SETTINGS_MEASURED` timed images per load. Arms
/// are `auto` (no overrides), `both_off` (`flashAttention: false,
/// vaeDirectConvolution: false`) and, for the full VAE, which is the only
/// variant whose automatic settings turn both on, `vae_direct_off`.
/// `IMAGE_SETTINGS_ROUNDS` rounds load every arm again, alternating the arm
/// order so that warming or throttling does not favour one arm.
///
/// Each load records wall time per image (and the sampling and decode parts,
/// split at the first decoding progress event), the image hash, the backend
/// and the peak memory from load to dispose: the kernel peak reset at the
/// load where the platform allows it (Android `VmHWM`, Apple
/// `ri_interval_max_phys_footprint`), otherwise a 20 ms sampled peak. A
/// model the load-time memory check refuses is recorded as refused.
///
/// Every record is logged as an `IMAGE_SETTINGS {json}` line and appended to
/// `image_settings/run-*/journal.jsonl` (app external files on Android, the
/// temporary directory elsewhere); the end writes `image_settings.json` with
/// the summary and one PNG per arm, verified by
/// `verifyImageSettingsEvidence`. The test fails when an arm fails, is not
/// deterministic, or does not run within `IMAGE_SETTINGS_BUDGET_MINUTES`.
///
/// ```bash
/// cd example/chat_app
/// flutter test --run-skipped -t local-only \
///   integration_test/image_settings_comparison_e2e_test.dart -d <device> \
///   --dart-define=IMAGE_SETTINGS_DEVICE=cpu
/// ```
///
/// `IMAGE_SETTINGS_DEVICE` is `auto` (default) or `cpu`;
/// `IMAGE_SETTINGS_VARIANTS` is a comma-separated subset of the variants.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:llamadart_chat_example/models/downloadable_model.dart';
import 'package:llamadart_chat_example/models/image_model_profile.dart';
import 'package:llamadart_chat_example/services/image_model_service.dart';

import 'support/image_settings_evidence.dart';
import 'support/process_peak_memory.dart';

const _logTag = 'IMAGE_SETTINGS';
const _prompt = 'a lighthouse on a cliff at sunset';
const _seed = 42;
const _size = 512;
const _rounds = int.fromEnvironment('IMAGE_SETTINGS_ROUNDS', defaultValue: 2);
const _measuredDefine = int.fromEnvironment('IMAGE_SETTINGS_MEASURED');
const _budgetMinutes = int.fromEnvironment(
  'IMAGE_SETTINGS_BUDGET_MINUTES',
  defaultValue: 16,
);
const _deviceDefine = String.fromEnvironment(
  'IMAGE_SETTINGS_DEVICE',
  defaultValue: 'auto',
);
const _variantsDefine = String.fromEnvironment('IMAGE_SETTINGS_VARIANTS');
const _downloadAttempts = 3;

/// Phone CPUs take 5 to 50 s per image, so they time one image per load to
/// stay inside a 20-minute Test Lab run; elsewhere two.
int get _measured =>
    _measuredDefine > 0 ? _measuredDefine : (Platform.isAndroid ? 1 : 2);

ImageModelProfile _profileOf(String variant) =>
    variant == 'sdxs' ? ImageModelProfile.sdxs : ImageModelProfile.sdTurbo;

void _log(Map<String, Object?> record) =>
    debugPrint('$_logTag ${jsonEncode(record)}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compares automatic image settings with overrides', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Running image settings comparison')),
      ),
    );
    final budget = Stopwatch()..start();
    final device = switch (_deviceDefine) {
      'auto' => ComputeDevice.auto,
      'cpu' => ComputeDevice.cpu,
      _ => throw ArgumentError.value(_deviceDefine, 'IMAGE_SETTINGS_DEVICE'),
    };
    final variants = _variantsDefine.isEmpty
        ? imageSettingsVariants.keys.toList()
        : _variantsDefine.split(',').map((value) => value.trim()).toList();
    for (final variant in variants) {
      if (!imageSettingsVariants.containsKey(variant)) {
        throw ArgumentError.value(variant, 'IMAGE_SETTINGS_VARIANTS');
      }
    }
    const commit = String.fromEnvironment(
      'VALIDATION_COMMIT',
      defaultValue: 'unknown',
    );
    const dirty = bool.fromEnvironment(
      'VALIDATION_SOURCE_DIRTY',
      defaultValue: true,
    );
    final base = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getTemporaryDirectory();
    if (base == null) throw StateError('No pullable evidence directory');
    final directory = Directory(
      p.join(
        base.path,
        imageSettingsDirectoryName,
        'run-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    final journal = File(p.join(directory.path, imageSettingsJournalName));
    void record(Map<String, Object?> value) {
      _log(value);
      journal.writeAsStringSync(
        '${jsonEncode(value)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    final runtime = await ImageGenerationEngine.checkRuntime();
    expect(runtime.isSupported, isTrue, reason: runtime.unsupportedReason);
    final memory = PeakMemoryProbe();
    final config = <String, Object?>{
      'type': 'config',
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'source_commit': commit,
      'source_dirty': dirty,
      'runtime_tag': stableDiffusionReleaseTag,
      'runtime_version': runtime.runtimeVersion,
      'runtime_devices': runtime.deviceNames,
      'runtime_backend': runtime.backendName,
      'device': _deviceDefine,
      'variants': variants,
      'rounds': _rounds,
      'measured_per_load': _measured,
      'budget_minutes': _budgetMinutes,
      'memory_source': memory.source,
    };
    record(config);

    final service = ImageModelService();
    final installed = <String, InstalledImageModel>{};
    Future<ImageGenerationModel> modelOf(String variant) async {
      final profile = _profileOf(variant);
      var files = installed[profile.id];
      if (files == null) {
        final watch = Stopwatch()..start();
        final cached = await service.resolve(profile);
        files = cached;
        // Test Lab devices fetch about 2 GB from Hugging Face at a few MB/s,
        // and the CDN can drop the connection for longer than the service's
        // own retries (0.5 to 2 s); install resumes the partial file.
        for (var attempt = 1; files == null; attempt++) {
          try {
            files = await service.install(
              profile,
              cancelToken: CancelToken(),
              onProgress: (_) {},
              onVerifying: () {},
            );
          } on IOException catch (error) {
            if (attempt == _downloadAttempts) rethrow;
            record({
              'type': 'download_retry',
              'profile': profile.id,
              'attempt': attempt,
              'error_type': '${error.runtimeType}',
            });
            await Future<void>.delayed(const Duration(seconds: 15));
          }
        }
        installed[profile.id] = files;
        record({
          'type': 'model',
          'profile': profile.id,
          'cache_hit': cached != null,
          'prepare_ms': watch.elapsedMilliseconds,
        });
      }
      return profile.buildModel(
        modelPath: files.modelPath,
        taesdPath: variant == 'sd_turbo_taesd' ? files.taesdPath : null,
      );
    }

    final loads = <Map<String, dynamic>>[];
    final pngs = <String, Uint8List>{};
    final pixels = <String, Uint8List>{};
    for (final variant in variants) {
      final profile = _profileOf(variant);
      final request = ImageGenerationRequest(
        prompt: _prompt,
        width: _size,
        height: _size,
        steps: profile.steps,
        guidanceScale: profile.guidanceScale,
        seed: _seed,
      );
      final model = await modelOf(variant);
      var refused = false;
      for (var round = 0; round < _rounds && !refused; round++) {
        final arms = round.isEven
            ? imageSettingsVariants[variant]!
            : imageSettingsVariants[variant]!.reversed.toList();
        for (final arm in arms) {
          final settings = imageSettingsArms[arm]!;
          final load = <String, dynamic>{
            'type': 'load',
            'variant': variant,
            'arm': arm,
            'round': round,
            'flash_attention': settings.flashAttention,
            'vae_direct_convolution': settings.vaeDirectConvolution,
          };
          if (budget.elapsed > const Duration(minutes: _budgetMinutes)) {
            load['status'] = 'skipped';
            load['error_message'] = 'time budget of $_budgetMinutes min spent';
            loads.add(load);
            record(load);
            continue;
          }
          record({'type': 'load_started', 'variant': variant, 'arm': arm});
          ImageGenerationEngine? engine;
          memory.start();
          try {
            final loadWatch = Stopwatch()..start();
            engine = await ImageGenerationEngine.load(
              model,
              params: ImageModelParams(
                device: device,
                flashAttention: settings.flashAttention,
                vaeDirectConvolution: settings.vaeDirectConvolution,
              ),
            );
            load['load_ms'] = loadWatch.elapsedMilliseconds;
            final capabilities = await engine.capabilities;
            load['backend'] = capabilities.backendName;
            load['model_version'] = capabilities.modelVersion;
            final warmupWatch = Stopwatch()..start();
            await engine.warmUp(
              width: _size,
              height: _size,
              guidanceScale: profile.guidanceScale,
            );
            load['warmup'] = {'wall_ms': warmupWatch.elapsedMilliseconds};
            final images = [
              for (var i = 0; i < _measured; i++)
                await _generate(engine, request),
            ];
            load['generations'] = [for (final image in images) image.timing];
            load['status'] = 'ok';
            final key = imageSettingsArtifactName(variant, arm);
            pngs.putIfAbsent(key, () => images.first.png);
            pixels.putIfAbsent('${variant}__$arm', () => images.first.pixels);
          } on LlamaModelException catch (error) {
            final memoryRefusal = error.message.contains('checkMemory');
            load['status'] = memoryRefusal ? 'refused' : 'failed';
            load['error_type'] = '${error.runtimeType}';
            load['error_message'] = error.message;
            refused = memoryRefusal;
          } on LlamaException catch (error) {
            load['status'] = 'failed';
            load['error_type'] = '${error.runtimeType}';
            load['error_message'] = error.message;
          } finally {
            await engine?.dispose();
            load['memory'] = memory.stop().toJson();
          }
          loads.add(load);
          record(load);
          if (refused) break;
        }
      }
    }

    final pixelDiffs = <String, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in pixels.entries) {
      final variant = key.split('__').first;
      final auto = pixels['${variant}__auto'];
      if (auto == null || key.endsWith('__auto')) continue;
      pixelDiffs[key] = _pixelDiff(auto, value);
    }
    final Map<String, dynamic> manifest;
    try {
      manifest = await writeImageSettingsEvidence(
        directory: directory,
        pngs: pngs,
        pixelDiffs: pixelDiffs,
        receipt: {
          ...config..remove('type'),
          'model_locks': [
            for (final profile in [
              ImageModelProfile.sdxs,
              ImageModelProfile.sdTurbo,
            ])
              for (final source in profile.sources) _lockOf(source),
          ],
          'request': {
            'prompt': _prompt,
            'seed': _seed,
            'width': _size,
            'height': _size,
          },
          'loads': loads,
        },
      );
    } on FormatException catch (error) {
      record({'type': 'evidence_rejected', 'error': error.message});
      rethrow;
    }
    for (final row in manifest['summary'] as List) {
      record({'type': 'summary', ...row as Map<String, dynamic>});
    }
    record({'type': 'evidence', 'directory': directory.path});
  });
}

typedef _Generation = ({
  Map<String, Object?> timing,
  Uint8List png,
  Uint8List pixels,
});

Future<_Generation> _generate(
  ImageGenerationEngine engine,
  ImageGenerationRequest request,
) async {
  final watch = Stopwatch()..start();
  final task = await engine.generate(request);
  int? decodingAt;
  final events = task.events.listen((event) {
    if (event is ImageGenerationProgressEvent &&
        event.phase == ImageGenerationPhase.decoding) {
      decodingAt ??= watch.elapsedMilliseconds;
    }
  });
  try {
    final result = await task.result;
    final wall = watch.elapsedMilliseconds;
    final image = result.images.single;
    final png = image.toPng();
    expect(result.seed, request.seed);
    expect((image.width, image.height), (_size, _size));
    return (
      timing: {
        'wall_ms': wall,
        'elapsed_ms': result.elapsed.inMilliseconds,
        'sampling_ms': decodingAt,
        'decode_ms': decodingAt == null ? null : wall - decodingAt!,
        'sha256': sha256.convert(png).toString(),
      },
      png: png,
      pixels: image.pixels,
    );
  } finally {
    await events.cancel();
  }
}

/// Largest and mean absolute channel difference, and the share of differing
/// channel values, between two images of the same size.
Map<String, Object?> _pixelDiff(Uint8List a, Uint8List b) {
  if (a.length != b.length) return {'comparable': false};
  var max = 0;
  var total = 0;
  var differing = 0;
  for (var i = 0; i < a.length; i++) {
    final delta = (a[i] - b[i]).abs();
    if (delta > max) max = delta;
    if (delta != 0) differing++;
    total += delta;
  }
  return {
    'max_abs': max,
    'mean_abs': (total / a.length * 1000).round() / 1000,
    'differing_share': (differing / a.length * 10000).round() / 10000,
  };
}

Map<String, Object?> _lockOf(RemoteModelAssetSource source) {
  final uri = Uri.parse(source.url);
  return {
    'filename': source.filename,
    'sha256': source.sha256,
    'bytes': source.sizeBytes,
    'revision': uri.pathSegments[uri.pathSegments.indexOf('resolve') + 1],
  };
}
