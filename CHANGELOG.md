## 0.3.0+b7883

*   **Version Alignment**: Aligned package versioning and binary distribution with `llama.cpp` release tags (starting with `b7883`).
*   **Pure Native Assets**: Migrated to the modern Dart Native Assets mechanism (`hook/build.dart`).
*   **Zero Setup**: Native binaries are now automatically downloaded and bundled at runtime based on the target platform.
*   **Logging Control**: Implemented comprehensive logging interception for both `llama` and `ggml` backends. Added `LlamaLogLevel` configuration to `ModelParams` to suppress verbose engine output.
*   **Performance Optimization**: Added token caching to message processing, significantly reducing latency when building prompts from long conversation histories.
*   **Architecture Overhaul**: 
    *   Refactored the Flutter Chat Example into a clean, layered architecture (Models, Services, Providers, Widgets).
    *   Rebuilt the CLI Basic Example into a robust conversation tool with interactive and single-response modes.
*   **Streamlined Bindings**: Switched to `@Native` top-level FFI bindings for better performance and simpler code.
*   **Stable Submodule**: Pinned `llama.cpp` to a stable release tag (`b7883`).
*   **Consolidated Build Infra**: Moved all native source, submodules, and build scripts into a unified `third_party/` directory.
*   **Clean Repository**: Removed obsolete platform folders (`macos/`, `android/`, `ios/`) and legacy build scripts.

## 0.2.0
