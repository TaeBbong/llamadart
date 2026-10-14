import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/src/core/image/png_encoder.dart';
import 'package:path/path.dart' as p;

import '../integration_test/support/image_settings_evidence.dart';
import '../integration_test/support/process_peak_memory.dart';

const _commit = 'dfc58e7998bd751a9084bfa36d9ab9a90ba6d963';

Uint8List _png(int value, {int size = 512}) => encodePng(
  width: size,
  height: size,
  channels: 3,
  pixels: Uint8List.fromList(List.filled(size * size * 3, value)),
);

String _hash(Uint8List bytes) => sha256.convert(bytes).toString();

Map<String, dynamic> _load(
  String variant,
  String arm, {
  int round = 0,
  List<int> ms = const [100],
  String? hash,
  int peak = 1000,
  String status = 'ok',
  String backend = 'CPU',
}) => {
  'type': 'load',
  'variant': variant,
  'arm': arm,
  'round': round,
  'status': status,
  if (status == 'ok') ...{
    'backend': backend,
    'load_ms': 10,
    'warmup': {'wall_ms': 150, 'sha256': hash},
    'generations': [
      for (final value in ms)
        {
          'wall_ms': value,
          'sampling_ms': value ~/ 2,
          'decode_ms': value - value ~/ 2,
          'sha256': hash,
        },
    ],
    'memory': {'peak_bytes': peak},
  } else
    'error_message': 'The image model needs about 2.6 GiB',
};

Matcher _rejects(String detail) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(detail)),
);

void main() {
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync(
      'image-settings-evidence-test-',
    ),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  group('summarizeImageSettingsLoads', () {
    test('takes medians and per-load peak spread against auto', () {
      final a = _hash(_png(1));
      final b = _hash(_png(2));
      final rows = summarizeImageSettingsLoads([
        _load('sdxs', 'auto', ms: [100], hash: a, peak: 900),
        _load('sdxs', 'both_off', ms: [200], hash: b, peak: 1200),
        _load('sdxs', 'both_off', round: 1, ms: [300], hash: b, peak: 1100),
        _load('sdxs', 'auto', round: 1, ms: [120], hash: a, peak: 950),
      ]);
      final auto = rows.firstWhere((row) => row['arm'] == 'auto');
      final off = rows.firstWhere((row) => row['arm'] == 'both_off');
      expect(auto['ms_per_image_median'], 110);
      expect(auto['peak_bytes_min'], 900);
      expect(auto['peak_bytes_max'], 950);
      expect(auto['deterministic'], isTrue);
      expect(off['ms_per_image_median'], 250);
      expect(off['decode_ms_median'], 125);
      expect(off['vs_auto'], {
        'auto_ms_ratio': 0.44,
        'auto_peak_delta_bytes': -200,
        'same_image': false,
      });
      expect(
        rows.where((row) => row['variant'] == 'sd_turbo_vae'),
        hasLength(4),
      );
      expect(
        rows.where((row) => row['variant'] != 'sdxs').map((r) => r['status']),
        everyElement('not_run'),
      );
    });

    test('marks a changing hash as not deterministic', () {
      final rows = summarizeImageSettingsLoads([
        _load('sdxs', 'auto', hash: _hash(_png(1))),
        _load('sdxs', 'auto', round: 1, hash: _hash(_png(2))),
      ]);
      expect(rows.first['deterministic'], isFalse);
      expect(rows.first['sha256'], isNull);
    });
  });

  group('image settings receipts', () {
    Future<Map<String, dynamic>> write({
      List<Map<String, dynamic>>? loads,
      Map<String, Uint8List>? pngs,
    }) {
      final png = _png(7);
      final hash = _hash(png);
      return writeImageSettingsEvidence(
        directory: directory,
        pngs:
            pngs ??
            {
              for (final arm in imageSettingsVariants['sdxs']!)
                imageSettingsArtifactName('sdxs', arm): png,
            },
        receipt: {
          'source_commit': _commit,
          'source_dirty': false,
          'runtime_tag': 'v0.2.0-3',
          'model_locks': [
            {'filename': 'a.gguf'},
          ],
          'request': {'seed': 42, 'width': 512, 'height': 512},
          'loads':
              loads ??
              [
                for (final arm in imageSettingsVariants['sdxs']!)
                  _load('sdxs', arm, hash: hash),
                for (final variant in ['sd_turbo_taesd', 'sd_turbo_vae'])
                  _load(variant, 'auto', status: 'refused'),
              ],
        },
      );
    }

    test('verify completed and memory-refused arms', () async {
      final manifest = await write();
      expect(manifest['artifacts'], hasLength(2));
      final verified = verifyImageSettingsEvidence(
        directory,
        expectedCommit: _commit,
        expectedBackend: 'CPU',
        expectedRuntimeTag: 'v0.2.0-3',
        expectedModelLocks: [
          {'filename': 'a.gguf'},
        ],
      );
      expect(
        (verified['summary'] as List).map((row) => (row as Map)['status']),
        containsAll(['ok', 'refused']),
      );
    });

    test('reject arms that failed, were skipped or did not run', () async {
      final hash = _hash(_png(7));
      for (final status in ['failed', 'skipped']) {
        await expectLater(
          write(
            loads: [
              _load('sdxs', 'auto', hash: hash),
              _load('sdxs', 'both_off', status: status),
            ],
          ),
          _rejects('did not complete'),
          reason: status,
        );
      }
      await expectLater(
        write(loads: [_load('sdxs', 'auto', hash: hash)]),
        _rejects('did not complete'),
      );
    });

    test('reject a missing, altered or unexpected PNG', () async {
      await write();
      File(
        p.join(directory.path, imageSettingsArtifactName('sdxs', 'auto')),
      ).writeAsBytesSync(_png(8));
      expect(
        () => verifyImageSettingsEvidence(directory),
        _rejects('PNG identity mismatch'),
      );
      await expectLater(
        write(pngs: {imageSettingsArtifactName('sdxs', 'auto'): _png(7)}),
        _rejects('artifact missing'),
      );
      await expectLater(
        write(
          pngs: {
            for (final arm in ['auto', 'both_off', 'fa_off'])
              imageSettingsArtifactName('sdxs', arm): _png(7),
          },
        ),
        _rejects('extra artifacts'),
      );
    });

    test('reject a summary that its loads do not give', () async {
      await write();
      final file = File(p.join(directory.path, imageSettingsReceiptName));
      final manifest = jsonDecode(file.readAsStringSync()) as Map;
      ((manifest['summary'] as List).first as Map)['ms_per_image_median'] = 1;
      file.writeAsStringSync(jsonEncode(manifest));
      expect(
        () => verifyImageSettingsEvidence(directory),
        _rejects('summary does not match'),
      );
    });

    test('reject another build, backend, pin or model lock', () async {
      await write();
      for (final (detail, verify) in [
        (
          'source does not match',
          () =>
              verifyImageSettingsEvidence(directory, expectedCommit: 'a' * 40),
        ),
        (
          'backend mismatch',
          () => verifyImageSettingsEvidence(directory, expectedBackend: 'MTL0'),
        ),
        (
          'runtime pin mismatch',
          () =>
              verifyImageSettingsEvidence(directory, expectedRuntimeTag: 'v1'),
        ),
        (
          'model lock mismatch',
          () => verifyImageSettingsEvidence(
            directory,
            expectedModelLocks: [
              {'filename': 'b.gguf'},
            ],
          ),
        ),
      ]) {
        expect(verify, _rejects(detail));
      }
    });
  });

  test('procStatusBytes reads kB fields of /proc/<pid>/status', () {
    const status = 'VmHWM:\t  2048 kB\nVmRSS:\t  1024 kB\n';
    expect(procStatusBytes(status, 'VmRSS'), 1024 * 1024);
    expect(procStatusBytes(status, 'VmHWM'), 2048 * 1024);
    expect(procStatusBytes(status, 'VmSwap'), isNull);
  });
}
