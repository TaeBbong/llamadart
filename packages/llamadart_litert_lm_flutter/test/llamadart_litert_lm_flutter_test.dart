import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_litert_lm_flutter/llamadart_litert_lm_flutter.dart';

void main() {
  test('declares LiteRT-LM runtime family', () {
    expect(llamadartLiteRtLmFlutterRuntime, 'litert_lm');
  });

  test('declares Flutter SwiftPM product name', () {
    final manifest = File(
      'darwin/llamadart_litert_lm_flutter/Package.swift',
    ).readAsStringSync();

    expect(manifest, contains('name: "llamadart-litert-lm-flutter"'));
    expect(manifest, isNot(contains('GemmaModelConstraintProvider')));
    expect(manifest, contains('name: "LiteRtMetalAccelerator"'));
    expect(manifest, contains('name: "LiteRtTopKMetalSampler"'));
    expect(
      manifest,
      isNot(
        contains(
          'checksum: "0000000000000000000000000000000000000000000000000000000000000000"',
        ),
      ),
    );
    expect(
      manifest,
      contains(
        'name: "LiteRtLm", condition: '
        '.when(platforms: [.iOS, .macOS])',
      ),
    );
    expect(
      manifest,
      contains('name: "CLiteRTLMMac", condition: .when(platforms: [.macOS])'),
    );
    expect(
      manifest,
      contains('name: "CLiteRTLM", condition: .when(platforms: [.iOS])'),
    );
    // The v0.18.0 macOS slices of these two carry an invalid signature, and
    // the macOS GPU path uses the WebGPU accelerator instead.
    for (final target in ['LiteRtMetalAccelerator', 'LiteRtTopKMetalSampler']) {
      expect(
        manifest,
        contains('name: "$target", condition: .when(platforms: [.iOS])'),
      );
    }
  });

  test('links the complete macOS arm64 runtime', () {
    final manifest = File(
      'darwin/llamadart_litert_lm_flutter/Package.swift',
    ).readAsStringSync();

    for (final target in [
      'LiteRt',
      'LiteRtTopKWebGpuSampler',
      'LiteRtWebGpuAccelerator',
      'WebgpuDawn',
    ]) {
      expect(
        manifest,
        contains(
          'artifactName: "litert-lm-native-apple-$target-xcframework-'
          r'\(liteRtLmTag).zip"',
        ),
      );
      expect(
        manifest,
        contains('name: "$target", condition: .when(platforms: [.macOS])'),
      );
    }
  });

  test('macOS plugin source does not import the runtime modules', () {
    final pluginSource = File(
      'darwin/llamadart_litert_lm_flutter/Sources/'
      'llamadart_litert_lm_flutter/LlamadartLiteRtLmPlugin.swift',
    ).readAsStringSync();

    final macosBlock = RegExp(
      r'#elseif os\(macOS\)([\s\S]*?)#endif',
    ).firstMatch(pluginSource);
    expect(macosBlock, isNotNull);
    expect(macosBlock!.group(1), isNot(contains('import LiteRtLm')));
  });
}
