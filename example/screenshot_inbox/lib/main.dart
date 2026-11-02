import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';
import 'package:photo_manager/photo_manager.dart';

import 'src/actions.dart';
import 'src/inbox_controller.dart';
import 'src/library.dart';
import 'src/model.dart';
import 'src/triage.dart';
import 'src/ui/inbox_page.dart';

void main() => runApp(const ScreenshotInboxApp());

/// Loads the model and the newest screenshots, then shows the inbox.
class ScreenshotInboxApp extends StatefulWidget {
  /// Creates the app.
  const ScreenshotInboxApp({super.key});

  @override
  State<ScreenshotInboxApp> createState() => _ScreenshotInboxAppState();
}

class _ScreenshotInboxAppState extends State<ScreenshotInboxApp> {
  final InboxController _inbox = InboxController(PhotoLibrary());
  final AgentModel _model = pickModel(
    phone: Platform.isIOS || Platform.isAndroid,
  );
  late final AppLifecycleListener _lifecycle;
  LlamaEngine? _engine;
  ScreenshotTriager? _triager;
  ModelStatus _status = const ModelStatus('Starting');

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExit);
    unawaited(_inbox.load());
    unawaited(_loadModel());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _inbox.dispose();
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
        _triager = ScreenshotTriager(
          engine,
          language: PlatformDispatcher.instance.locale.toLanguageTag(),
        );
        _status = ModelStatus('${_model.label} · $backend', ready: true);
      });
    } catch (e) {
      if (mounted) setState(() => _status = ModelStatus('$e'));
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Screenshot Inbox',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    ),
    home: InboxPage(
      controller: _inbox,
      status: _status,
      onSort: () {
        if (_triager case final triager?) {
          unawaited(_inbox.sortAll(triager.triage));
        }
      },
      onRun: runAction,
      onOpenSettings: PhotoManager.openSetting,
    ),
  );
}
