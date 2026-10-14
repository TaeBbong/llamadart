/// Arms, summary and receipt of the image settings comparison
/// (`image_settings_comparison_e2e_test.dart`). Pure Dart, so the validation
/// tool grades collected receipts with the same code that writes them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'image_evidence.dart';

const String imageSettingsDirectoryName = 'image_settings';
const String imageSettingsReceiptName = 'image_settings.json';
const String imageSettingsJournalName = 'journal.jsonl';
const String imageSettingsScenario = 'image-settings-comparison';

/// One set of `ImageModelParams` overrides; `null` keeps the automatic value.
typedef ImageSettingsArm = ({bool? flashAttention, bool? vaeDirectConvolution});

/// The compared settings. `auto` is what an app gets without overrides.
const Map<String, ImageSettingsArm> imageSettingsArms = {
  'auto': (flashAttention: null, vaeDirectConvolution: null),
  'both_off': (flashAttention: false, vaeDirectConvolution: false),
  'vae_direct_off': (flashAttention: null, vaeDirectConvolution: false),
};

/// Model variants and the arms each runs. A tiny autoencoder (SDXS's
/// embedded one, TAESD) keeps direct convolutions off automatically, so only
/// the full SD-Turbo VAE needs `vae_direct_off` to separate the two
/// defaults: it differs from `auto` in the VAE alone and from `both_off` in
/// flash attention alone.
const Map<String, List<String>> imageSettingsVariants = {
  'sdxs': ['auto', 'both_off'],
  'sd_turbo_taesd': ['auto', 'both_off'],
  'sd_turbo_vae': ['auto', 'both_off', 'vae_direct_off'],
};

/// What the load-time memory check's refusal names; a `refused` load whose
/// error does not name it is not a memory-check refusal.
const String imageSettingsMemoryRefusalMarker = 'ImageModelParams.checkMemory';

/// The evidence PNG of one arm: its first image.
String imageSettingsArtifactName(String variant, String arm) =>
    '${variant}__$arm.png';

num? _median(List<num> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

num? _round(num? value) =>
    value == null ? null : (value * 10).roundToDouble() / 10;

/// One row per arm of each of [variants], in [imageSettingsVariants] order,
/// from the per-load records [loads]. Time is the median of every measured image of
/// the arm; peak memory is the smallest and largest per-load peak, so memory
/// an earlier load left with the allocator shows as a spread. `vs_auto`
/// compares a row with its variant's `auto` row.
List<Map<String, Object?>> summarizeImageSettingsLoads(
  List<Map<String, dynamic>> loads,
  List<String> variants,
) {
  final rows = <Map<String, Object?>>[];
  for (final MapEntry(key: variant, value: arms)
      in imageSettingsVariants.entries) {
    if (!variants.contains(variant)) continue;
    Map<String, Object?>? auto;
    // The load-time memory check estimates from file sizes alone, so one
    // refused arm stands for every arm of its variant.
    final refusal = loads
        .where(
          (load) => load['variant'] == variant && load['status'] == 'refused',
        )
        .firstOrNull;
    for (final arm in arms) {
      final own = [
        for (final load in loads)
          if (load['variant'] == variant && load['arm'] == arm) load,
      ];
      final ok = own.where((load) => load['status'] == 'ok').toList();
      final images = [
        for (final load in ok)
          for (final generation in load['generations'] as List)
            generation as Map,
      ];
      final hashes = {for (final image in images) image['sha256']};
      final peaks = [
        for (final load in ok)
          if ((load['memory'] as Map?)?['peak_bytes'] case final int peak) peak,
      ];
      final statuses = own.map((load) => load['status']).toSet();
      final status = own.isEmpty
          ? (refusal == null ? 'not_run' : 'refused')
          : statuses.length == 1
          ? statuses.single as String
          : 'mixed';
      final settings = imageSettingsArms[arm]!;
      final backends = {for (final load in ok) load['backend']};
      final row = <String, Object?>{
        'variant': variant,
        'arm': arm,
        'flash_attention': settings.flashAttention,
        'vae_direct_convolution': settings.vaeDirectConvolution,
        'status': status,
        'backend': backends.length == 1 ? backends.single : null,
        'loads': own.length,
        'images': images.length,
        'ms_per_image_median': _round(
          _median([for (final image in images) image['wall_ms'] as num]),
        ),
        'ms_per_image_min': images.isEmpty
            ? null
            : images
                  .map((image) => image['wall_ms'] as num)
                  .reduce((a, b) => a < b ? a : b),
        'ms_per_image_max': images.isEmpty
            ? null
            : images
                  .map((image) => image['wall_ms'] as num)
                  .reduce((a, b) => a > b ? a : b),
        'sampling_ms_median': _round(
          _median([
            for (final image in images)
              if (image['sampling_ms'] case final num value) value,
          ]),
        ),
        'decode_ms_median': _round(
          _median([
            for (final image in images)
              if (image['decode_ms'] case final num value) value,
          ]),
        ),
        'load_ms_median': _round(
          _median([for (final load in ok) load['load_ms'] as num]),
        ),
        'warmup_ms_median': _round(
          _median([
            for (final load in ok) (load['warmup'] as Map)['wall_ms'] as num,
          ]),
        ),
        'peak_bytes_min': peaks.isEmpty
            ? null
            : peaks.reduce((a, b) => a < b ? a : b),
        'peak_bytes_max': peaks.isEmpty
            ? null
            : peaks.reduce((a, b) => a > b ? a : b),
        'deterministic': ok.isEmpty ? null : hashes.length == 1,
        'sha256': hashes.length == 1 ? hashes.single : null,
        'error': [
          ...own,
          ?refusal,
        ].map((load) => load['error_message']).whereType<String>().firstOrNull,
      };
      if (arm == 'auto') {
        auto = row;
      } else if (auto != null) {
        final autoMs = auto['ms_per_image_median'] as num?;
        final ms = row['ms_per_image_median'] as num?;
        final autoPeak = auto['peak_bytes_min'] as int?;
        final peak = row['peak_bytes_min'] as int?;
        row['vs_auto'] = {
          'auto_ms_ratio': autoMs == null || ms == null || ms == 0
              ? null
              : (autoMs / ms * 1000).round() / 1000,
          'auto_peak_delta_bytes': autoPeak == null || peak == null
              ? null
              : autoPeak - peak,
          'same_image': auto['sha256'] == null || row['sha256'] == null
              ? null
              : auto['sha256'] == row['sha256'],
        };
      }
      rows.add(row);
    }
  }
  return rows;
}

/// Writes each arm's PNG and the final receipt, then verifies the saved
/// bytes. [receipt] holds `loads`; the summary is derived here.
Future<Map<String, dynamic>> writeImageSettingsEvidence({
  required Directory directory,
  required Map<String, Object?> receipt,
  required Map<String, Uint8List> pngs,
  Map<String, Map<String, Object?>> pixelDiffs = const {},
}) async {
  await directory.create(recursive: true);
  final artifacts = <String, Object?>{};
  for (final MapEntry(key: name, value: bytes) in pngs.entries) {
    final dimensions = inspectEvidencePng(bytes);
    await File(p.join(directory.path, name)).writeAsBytes(bytes, flush: true);
    artifacts[name] = {
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      ...dimensions,
    };
  }
  final summary = summarizeImageSettingsLoads(
    [for (final load in receipt['loads'] as List) load as Map<String, dynamic>],
    [for (final variant in receipt['variants'] as List) variant as String],
  );
  final manifest = {
    ...receipt,
    'schema_version': 1,
    'scenario': imageSettingsScenario,
    'summary': [
      for (final row in summary)
        {
          ...row,
          'pixel_diff_vs_auto': ?pixelDiffs['${row['variant']}__${row['arm']}'],
        },
    ],
    'artifacts': artifacts,
  };
  await File(
    p.join(directory.path, imageSettingsReceiptName),
  ).writeAsString('${jsonEncode(manifest)}\n', flush: true);
  return verifyImageSettingsEvidence(directory);
}

/// Verifies a receipt in [directory]: the summary must be the one its loads
/// give, every variant must have loaded each arm once per round with
/// `measured_per_load` images per completed load, or been refused once by
/// the load-time memory check when [expectedRefusals] (the receipt's
/// `expected_refusals` when omitted) allows that variant, at least one arm
/// must have measured, and every generating arm's PNG must be present with
/// the recorded bytes, the arm's image hash, and the requested size. The
/// optional expectations qualify it against a build: clean source
/// [expectedCommit], the backend every load reported, the runtime pin, the
/// model locks and the variants the build runs. PNG checks are structural;
/// they do not judge quality.
Map<String, dynamic> verifyImageSettingsEvidence(
  Directory directory, {
  String? expectedCommit,
  String? expectedBackend,
  String? expectedRuntimeTag,
  List<Map<String, dynamic>>? expectedModelLocks,
  List<String>? expectedVariants,
  List<String>? expectedRefusals,
}) {
  final manifest =
      jsonDecode(
            File(
              p.join(directory.path, imageSettingsReceiptName),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  if (manifest['schema_version'] != 1 ||
      manifest['scenario'] != imageSettingsScenario) {
    throw const FormatException('Invalid image settings receipt');
  }
  if (expectedCommit != null &&
      (!RegExp(r'^[0-9a-f]{40}$').hasMatch(expectedCommit) ||
          manifest['source_commit'] != expectedCommit ||
          manifest['source_dirty'] != false)) {
    throw const FormatException(
      'Image settings receipt source does not match clean build',
    );
  }
  if (expectedRuntimeTag != null &&
      manifest['runtime_tag'] != expectedRuntimeTag) {
    throw const FormatException('Image settings runtime pin mismatch');
  }
  if (expectedModelLocks != null &&
      jsonEncode(manifest['model_locks']) != jsonEncode(expectedModelLocks)) {
    throw const FormatException('Image settings model lock mismatch');
  }
  final request = manifest['request'];
  if (request is! Map ||
      request['seed'] != 42 ||
      request['width'] != 512 ||
      request['height'] != 512) {
    throw const FormatException('Image settings seed/dimensions mismatch');
  }
  final loads = [
    for (final load in manifest['loads'] as List) load as Map<String, dynamic>,
  ];
  if (expectedBackend != null &&
      loads.any(
        (load) => load['status'] == 'ok' && load['backend'] != expectedBackend,
      )) {
    throw const FormatException('Image settings backend mismatch');
  }
  final variants = manifest['variants'];
  if (variants is! List ||
      variants.isEmpty ||
      variants.toSet().length != variants.length ||
      !variants.every(imageSettingsVariants.containsKey) ||
      (expectedVariants != null &&
          jsonEncode(variants) != jsonEncode(expectedVariants))) {
    throw const FormatException('Image settings variants mismatch');
  }
  final allowedRefusals = expectedRefusals ?? manifest['expected_refusals'];
  if (allowedRefusals != null &&
      (allowedRefusals is! List || !allowedRefusals.every(variants.contains))) {
    throw const FormatException('Image settings expected refusals mismatch');
  }
  final rounds = manifest['rounds'];
  final measured = manifest['measured_per_load'];
  if (rounds is! int || rounds < 1 || measured is! int || measured < 1) {
    throw const FormatException('Image settings run size missing');
  }
  final refusals = <String>{};
  for (final variant in variants) {
    final own = loads.where((load) => load['variant'] == variant).toList();
    final refused = own.where((load) => load['status'] == 'refused').toList();
    if (refused.isNotEmpty) {
      // A refusal stops its variant: the test loads none of its other arms.
      if (own.length != 1 ||
          own.single['error_type'] != 'LlamaModelException' ||
          !'${own.single['error_message']}'.contains(
            imageSettingsMemoryRefusalMarker,
          )) {
        throw FormatException(
          'Image settings variant $variant was refused by something other '
          'than the load-time memory check',
        );
      }
      refusals.add(variant as String);
      continue;
    }
    final arms = imageSettingsVariants[variant]!;
    final slots = {for (final load in own) '${load['arm']}@${load['round']}'};
    final expectedSlots = {
      for (var round = 0; round < rounds; round++)
        for (final arm in arms) '$arm@$round',
    };
    if (own.length != expectedSlots.length ||
        slots.length != own.length ||
        !slots.containsAll(expectedSlots) ||
        own.any(
          (load) =>
              load['status'] == 'ok' &&
              (load['generations'] as List).length != measured,
        )) {
      throw FormatException(
        'Image settings run size mismatch: $variant needs ${arms.length} '
        'arms x $rounds rounds with $measured images per load',
      );
    }
  }
  if (loads.any((load) => !variants.contains(load['variant']))) {
    throw const FormatException(
      'Image settings receipt holds loads of other variants',
    );
  }
  final summary = summarizeImageSettingsLoads(loads, [
    for (final variant in variants) variant as String,
  ]);
  final recorded = [
    for (final row in manifest['summary'] as List)
      {...row as Map<String, dynamic>}..remove('pixel_diff_vs_auto'),
  ];
  if (jsonEncode(recorded) != jsonEncode(summary)) {
    throw const FormatException('Image settings summary does not match loads');
  }
  if (!summary.any((row) => row['status'] == 'ok')) {
    throw const FormatException('Image settings run has no measured arm');
  }
  final undeclared = refusals.difference({...?(allowedRefusals as List?)});
  if (undeclared.isNotEmpty) {
    throw FormatException(
      'Image settings undeclared refusal: ${undeclared.join(', ')} '
      '(a profile lists variants its device may refuse in expected_refusals)',
    );
  }
  final artifacts = manifest['artifacts'] as Map<String, dynamic>;
  final expectedArtifacts = <String>{};
  for (final row in summary) {
    final status = row['status'];
    if (status == 'refused') continue;
    if (status != 'ok' || row['deterministic'] != true) {
      throw FormatException(
        'Image settings arm ${row['variant']}/${row['arm']} did not complete '
        'deterministically ($status)',
      );
    }
    final name = imageSettingsArtifactName(
      row['variant'] as String,
      row['arm'] as String,
    );
    expectedArtifacts.add(name);
    final expected = artifacts[name];
    final file = File(p.join(directory.path, name));
    if (expected is! Map ||
        FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw FormatException('Image settings artifact missing: $name');
    }
    final bytes = file.readAsBytesSync();
    final dimensions = inspectEvidencePng(bytes);
    final digest = sha256.convert(bytes).toString();
    if (expected['bytes'] != bytes.length ||
        expected['sha256'] != digest ||
        digest != row['sha256'] ||
        dimensions['width'] != 512 ||
        dimensions['height'] != 512) {
      throw FormatException('Image settings PNG identity mismatch: $name');
    }
  }
  if (artifacts.length != expectedArtifacts.length) {
    throw const FormatException('Image settings receipt lists extra artifacts');
  }
  return manifest;
}
