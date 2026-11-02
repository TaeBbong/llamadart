import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'src/guard_controller.dart';
import 'src/model.dart';
import 'src/redaction.dart';
import 'src/scanner.dart';
import 'src/ui/guard_page.dart';

void main() => runApp(const PrivacyGuardApp());

/// Loads the model, then checks the photos the user picks.
class PrivacyGuardApp extends StatefulWidget {
  /// Creates the app.
  const PrivacyGuardApp({super.key});

  @override
  State<PrivacyGuardApp> createState() => _PrivacyGuardAppState();
}

class _PrivacyGuardAppState extends State<PrivacyGuardApp> {
  final GuardController _guard = GuardController(
    prepare: (bytes) => Isolate.run(() => preparePhoto(bytes)),
    redact: (bytes, boxes) => Isolate.run(() => redactPhoto(bytes, boxes)),
  );
  final AgentModel _model = pickModel(
    phone: Platform.isIOS || Platform.isAndroid,
  );
  late final AppLifecycleListener _lifecycle;
  LlamaEngine? _engine;
  PrivacyScanner? _scanner;
  ModelStatus _status = const ModelStatus('Starting');

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExit);
    unawaited(_loadModel());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _guard.dispose();
    unawaited(_engine?.dispose());
    super.dispose();
  }

  /// Frees the model before the app exits: llama.cpp's Metal backend aborts
  /// the process when it exits with GPU buffers still allocated.
  Future<AppExitResponse> _onExit() async {
    await _engine?.dispose();
    return AppExitResponse.exit;
  }

  Future<void> _loadModel() async {
    try {
      final engine = await loadAgentModel(
        _model.load(),
        label: _model.label,
        cpu: Platform.isAndroid,
        onStatus: (message, fraction) {
          if (mounted) {
            setState(() => _status = ModelStatus(message, fraction: fraction));
          }
        },
      );
      if (!mounted) {
        await engine.dispose();
        return;
      }
      final backend = await engine.getBackendName();
      setState(() {
        _engine = engine;
        _scanner = PrivacyScanner(engine);
        _status = ModelStatus('${_model.label} · $backend', ready: true);
      });
      unawaited(_guard.scanWaiting(_scanner!.scan));
    } catch (e) {
      if (mounted) setState(() => _status = ModelStatus('$e'));
    }
  }

  /// Picks photos with the system picker, which needs no photo library
  /// permission, and checks them once the model is ready.
  Future<void> _pick() async {
    final files = await ImagePicker().pickMultiImage(
      // Also turns HEIC into JPEG, which `package:image` can decode.
      maxWidth: shareEdge.toDouble(),
      maxHeight: shareEdge.toDouble(),
      imageQuality: 95,
    );
    await _guard.add([
      for (final file in files) (file.name, await file.readAsBytes()),
    ]);
    if (_scanner case final scanner?) {
      unawaited(_guard.scanWaiting(scanner.scan));
    }
  }

  Future<void> _share(Rect origin) async {
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    for (final (name, bytes) in await _guard.shareable()) {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes);
      files.add(XFile(file.path, mimeType: 'image/jpeg'));
    }
    await SharePlus.instance.share(
      ShareParams(files: files, sharePositionOrigin: origin),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Privacy Guard',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: GuardPage(
      controller: _guard,
      status: _status,
      onPick: _pick,
      onShare: _share,
    ),
  );
}
