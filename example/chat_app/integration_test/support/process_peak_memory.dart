/// Per-phase peak memory of this process: a kernel peak counter that can be
/// reset between phases where the platform has one, plus a sampled peak of
/// the current figure, which every platform with a counter supports.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// A peak-memory reading over one phase, in bytes.
class PeakMemoryReading {
  /// What the figures count.
  final String source;

  /// The current figure when the phase started.
  final int? baselineBytes;

  /// The kernel's peak since the phase started, when [kernelPeakKind] says it
  /// was reset for this phase; otherwise the process lifetime peak.
  final int? kernelPeakBytes;

  /// `interval` (reset for this phase) or `lifetime` (could not be reset).
  final String? kernelPeakKind;

  /// The largest current figure sampled during the phase.
  final int? sampledPeakBytes;

  /// How many samples [sampledPeakBytes] is the largest of.
  final int samples;

  /// The current figure when the phase ended.
  final int? endBytes;

  /// Creates a reading.
  const PeakMemoryReading({
    required this.source,
    required this.baselineBytes,
    required this.kernelPeakBytes,
    required this.kernelPeakKind,
    required this.sampledPeakBytes,
    required this.samples,
    required this.endBytes,
  });

  /// The phase's peak: the reset kernel peak, else the sampled peak.
  int? get peakBytes =>
      kernelPeakKind == 'interval' ? kernelPeakBytes : sampledPeakBytes;

  /// JSON for receipts.
  Map<String, Object?> toJson() => {
    'source': source,
    'baseline_bytes': baselineBytes,
    'kernel_peak_bytes': kernelPeakBytes,
    'kernel_peak_kind': kernelPeakKind,
    'sampled_peak_bytes': sampledPeakBytes,
    'samples': samples,
    'end_bytes': endBytes,
    'peak_bytes': peakBytes,
  };
}

/// The `kB` value of [field] in `/proc/<pid>/status` [text], in bytes.
int? procStatusBytes(String text, String field) {
  final match = RegExp(
    '^$field:\\s*(\\d+) kB\$',
    multiLine: true,
  ).firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!) * 1024;
}

abstract class _Counter {
  String get source;
  int? current();
  int? kernelPeak();

  /// Resets the kernel peak to the current figure; false when it cannot.
  bool resetPeak();
}

/// Linux and Android: `VmRSS` and `VmHWM`. Writing `5` to
/// `/proc/self/clear_refs` resets `VmHWM` to the current `VmRSS` (Linux 4.0).
class _ProcCounter implements _Counter {
  @override
  String get source =>
      '/proc/self/status VmRSS (sampled) and VmHWM (reset through '
      '/proc/self/clear_refs)';

  String? _status() {
    try {
      return File('/proc/self/status').readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  @override
  int? current() {
    final status = _status();
    return status == null ? null : procStatusBytes(status, 'VmRSS');
  }

  @override
  int? kernelPeak() {
    final status = _status();
    return status == null ? null : procStatusBytes(status, 'VmHWM');
  }

  @override
  bool resetPeak() {
    try {
      File('/proc/self/clear_refs').writeAsStringSync('5', flush: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// macOS and iOS: `phys_footprint` from `proc_pid_rusage(RUSAGE_INFO_V4)`,
/// whose `ri_interval_max_phys_footprint` `proc_reset_footprint_interval`
/// resets. The footprint includes Metal buffers, which RSS under-counts.
class _DarwinCounter implements _Counter {
  _DarwinCounter() {
    final process = DynamicLibrary.process();
    _rusage = process
        .lookupFunction<
          Int32 Function(Int32, Int32, Pointer<Uint64>),
          int Function(int, int, Pointer<Uint64>)
        >('proc_pid_rusage');
    _reset = process.providesSymbol('proc_reset_footprint_interval')
        ? process.lookupFunction<Int32 Function(Int32), int Function(int)>(
            'proc_reset_footprint_interval',
          )
        : null;
  }

  // Word offsets in `struct rusage_info_v4` (`<sys/resource.h>`), after the
  // 16-byte UUID.
  static const _physFootprint = 9;
  static const _lifetimeMax = 30;
  static const _intervalMax = 35;
  static const _words = 37;
  static const _flavorV4 = 4;

  late final int Function(int, int, Pointer<Uint64>) _rusage;
  late final int Function(int)? _reset;
  bool _intervalReset = false;

  @override
  String get source =>
      'proc_pid_rusage(RUSAGE_INFO_V4) ri_phys_footprint (sampled) and '
      'ri_interval_max_phys_footprint (reset through '
      'proc_reset_footprint_interval)';

  int? _word(int index) {
    final info = calloc<Uint64>(_words);
    try {
      return _rusage(pid, _flavorV4, info) == 0 ? info[index] : null;
    } finally {
      calloc.free(info);
    }
  }

  @override
  int? current() => _word(_physFootprint);

  @override
  int? kernelPeak() => _word(_intervalReset ? _intervalMax : _lifetimeMax);

  @override
  bool resetPeak() {
    final reset = _reset;
    _intervalReset = reset != null && reset(pid) == 0;
    return _intervalReset;
  }
}

_Counter? _counterFor(String operatingSystem) => switch (operatingSystem) {
  'android' || 'linux' => _ProcCounter(),
  'ios' || 'macos' => _DarwinCounter(),
  _ => null,
};

/// Measures one phase at a time: [start] resets the kernel peak and starts
/// sampling, [stop] returns the reading.
class PeakMemoryProbe {
  /// Creates a probe for this platform, sampling every [interval].
  PeakMemoryProbe({this.interval = const Duration(milliseconds: 20)})
    : _counter = _counterFor(Platform.operatingSystem);

  /// How often the current figure is sampled.
  final Duration interval;

  final _Counter? _counter;
  Timer? _timer;
  int? _baseline;
  int? _sampledPeak;
  int _samples = 0;
  bool _reset = false;

  /// What this platform's figures count, or why there are none.
  String get source =>
      _counter?.source ?? 'unavailable on ${Platform.operatingSystem}';

  /// The current figure, or null without a counter.
  int? current() => _counter?.current();

  void _sample() {
    final value = _counter?.current();
    if (value == null) return;
    _samples++;
    if (_sampledPeak == null || value > _sampledPeak!) _sampledPeak = value;
  }

  /// Starts a phase.
  void start() {
    _timer?.cancel();
    _sampledPeak = null;
    _samples = 0;
    _reset = _counter?.resetPeak() ?? false;
    _baseline = _counter?.current();
    _sample();
    _timer = Timer.periodic(interval, (_) => _sample());
  }

  /// Ends the phase started by [start].
  PeakMemoryReading stop() {
    _timer?.cancel();
    _timer = null;
    _sample();
    final kernelPeak = _counter?.kernelPeak();
    return PeakMemoryReading(
      source: source,
      baselineBytes: _baseline,
      kernelPeakBytes: kernelPeak,
      kernelPeakKind: kernelPeak == null
          ? null
          : (_reset ? 'interval' : 'lifetime'),
      sampledPeakBytes: _sampledPeak,
      samples: _samples,
      endBytes: _counter?.current(),
    );
  }
}
