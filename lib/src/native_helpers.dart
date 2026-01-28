import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'loader.dart';

// Type definitions for direct ggml-backend access
/// Native signature for ggml_backend_dev_count.
typedef GgmlBackendDevCountNative = Size Function();

/// Dart signature for ggml_backend_dev_count.
typedef GgmlBackendDevCountDart = int Function();

/// Native signature for ggml_backend_dev_get.
typedef GgmlBackendDevGetNative = Pointer<Void> Function(Size index);

/// Dart signature for ggml_backend_dev_get.
typedef GgmlBackendDevGetDart = Pointer<Void> Function(int index);

/// Native signature for ggml_backend_dev_name.
typedef GgmlBackendDevNameNative = Pointer<Utf8> Function(Pointer<Void> dev);

/// Dart signature for ggml_backend_dev_name.
typedef GgmlBackendDevNameDart = Pointer<Utf8> Function(Pointer<Void> dev);

/// Native signature for ggml_backend_dev_description.
typedef GgmlBackendDevDescNative = Pointer<Utf8> Function(Pointer<Void> dev);

/// Dart signature for ggml_backend_dev_description.
typedef GgmlBackendDevDescDart = Pointer<Utf8> Function(Pointer<Void> dev);

/// Helper class to interact with native ggml backend functions.
class NativeHelpers {
  static DynamicLibrary get _lib {
    try {
      return llamaLib;
    } catch (_) {
      loadLlamaLib();
      return llamaLib;
    }
  }

  // ggml_backend_dev_count
  static final _getDevCount =
      _lib.lookupFunction<GgmlBackendDevCountNative, GgmlBackendDevCountDart>(
          'ggml_backend_dev_count');

  // ggml_backend_dev_get
  static final _getDevGet =
      _lib.lookupFunction<GgmlBackendDevGetNative, GgmlBackendDevGetDart>(
          'ggml_backend_dev_get');

  // ggml_backend_dev_name
  static final _getDevName =
      _lib.lookupFunction<GgmlBackendDevNameNative, GgmlBackendDevNameDart>(
          'ggml_backend_dev_name');

  // ggml_backend_dev_description
  static final _getDevDesc =
      _lib.lookupFunction<GgmlBackendDevDescNative, GgmlBackendDevDescDart>(
          'ggml_backend_dev_description');

  /// Returns the number of available compute devices.
  static int getDeviceCount() => _getDevCount();

  /// Returns a pointer to the device at the given [index].
  static Pointer<Void> getDevicePointer(int index) {
    return _getDevGet(index);
  }

  /// Returns the name of the device at the given [index].
  static String getDeviceName(int index) {
    final dev = getDevicePointer(index);
    if (dev == nullptr) return "";
    final ptr = _getDevName(dev);
    if (ptr == nullptr) return "";
    return ptr.toDartString();
  }

  /// Returns the description of the device at the given [index].
  static String getDeviceDescription(int index) {
    final dev = getDevicePointer(index);
    if (dev == nullptr) return "";
    final ptr = _getDevDesc(dev);
    if (ptr == nullptr) return "";
    return ptr.toDartString();
  }

  /// Returns a list of all available device names.
  static List<String> getAvailableDevices() {
    final count = getDeviceCount();
    final devices = <String>[];
    for (var i = 0; i < count; i++) {
      devices.add(getDeviceName(i));
    }
    return devices;
  }
}
