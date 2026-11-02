import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';

import 'src/copilot.dart';
import 'src/ledger.dart';
import 'src/model.dart';
import 'src/ui/budget_page.dart';

void main() => runApp(const InAppCopilotApp());

/// A budget app whose copilot reads and changes its data through tools.
class InAppCopilotApp extends StatefulWidget {
  /// Creates the app.
  const InAppCopilotApp({super.key});

  @override
  State<InAppCopilotApp> createState() => _InAppCopilotAppState();
}

class _InAppCopilotAppState extends State<InAppCopilotApp> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey();
  final DateTime _today = DateTime.now();
  late final Ledger _ledger = Ledger.sample(_today);
  // Phones use 4B too: in testing, 2B answered a budget change by trying to
  // delete unrelated expenses.
  final AgentModel _model = pickModel(phone: false);
  late final AppLifecycleListener _lifecycle;
  LlamaEngine? _engine;
  Copilot? _copilot;
  String _status = 'Starting';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExit);
    unawaited(_loadModel());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_engine?.dispose());
    unawaited(_ledger.close());
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
        _model.load(vision: false),
        label: _model.label,
        cpu: Platform.isAndroid,
        onStatus: (message, fraction) {
          if (!mounted) return;
          setState(
            () => _status = fraction == null
                ? message
                : '$message (${(fraction * 100).round()}%)',
          );
        },
      );
      if (!mounted) {
        await engine.dispose();
        return;
      }
      final backend = await engine.getBackendName();
      setState(() {
        _engine = engine;
        _copilot = Copilot(engine, _ledger, confirm: _confirm);
        _status = '${_model.label} · $backend · on this device';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  Future<bool> _confirm(String question) async {
    final context = _navigator.currentContext;
    if (context == null) return false;
    final lines = question.split('\n');
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lines.first),
        content: Text(lines.skip(1).join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'In-app Copilot',
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.green),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.green,
      brightness: Brightness.dark,
    ),
    home: BudgetPage(
      ledger: _ledger,
      today: _today,
      status: _status,
      ask: _copilot?.ask,
      onStop: _engine?.cancelGeneration,
    ),
  );
}
