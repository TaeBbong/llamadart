# Agent Guide: Native Layer

This document guides AI agents and developers on maintaining the native layer of `llama_dart`, specifically the vendoring of `llama.cpp`.

## Vendoring Strategy: "Zero-Overwrite" / "Zero-Patch"

We vendor `llama.cpp` to `src/native/llama_cpp`. Our strategy prioritizes minimal maintenance and maximum compatibility with Android/Vulkan builds.

### Key Principles

1.  **Pin Version**: We depend on a specific Git tag (e.g., `b78xx`) rather than `master` to ensure stability.
2.  **No Source Modifications**: We do NOT patch the C++ source code of `llama.cpp`.
    - Patches are fragile and break on every update.
    - We rely on external configuration instead.
3.  **Upstream `CMakeLists.txt`**: We use the native `CMakeLists.txt` provided by `llama.cpp` without modification.
4.  **External Shims**: Platform-specific build fixes are handled via checking for local CMake modules in `src/native/cmake/`.
    - **Example**: `FindVulkan.cmake` in `src/native/cmake/` intercepts the Android NDK's broken Vulkan discovery, forcing `Vulkan_FOUND=TRUE` without touching `ggml` code.

## How to Update llama.cpp

The update process is fully automated.

1.  **Identify New Version**: Find the latest stable release tag from [llama.cpp resources](https://github.com/ggerganov/llama.cpp/tags).
2.  **Modify Script**: Open `tool/update_llama_cpp.dart` and update the `targetVersion` variable.
    ```dart
    final targetVersion = args.isNotEmpty ? args[0] : 'b7845'; // Update this tag
    ```
3.  **Run Automation**:
    ```bash
    dart tool/update_llama_cpp.dart
    ```
    This will:
    - Clean `src/native/llama_cpp`.
    - Sparse-checkout the new tag.
    - Copy source files including `common` and `vendor`.
    - Prune bloated directories (tests, docs, etc.).
    - **NOT** apply any patches.
4.  **Verify Build**:
    ```bash
    cd example/chat_app/android
    ./gradlew clean assembleDebug
    ```
    Ensure the build log shows `llama_dart: Vulkan backend ENABLED`.

## Files to Watch

- **`src/native/CMakeLists.txt`**: The parent CMake file. It sets build flags (`LLAMA_BUILD_TESTS=OFF`) and includes the `src/native/cmake` module path.
- **`src/native/cmake/FindVulkan.cmake`**: The shim for Android Vulkan discovery. Edit this if Vulkan linking fails on future NDK versions.
- **`tool/update_llama_cpp.dart`**: The vendoring logic.

## Common Issues

- **Missing Directories**: If `llama.cpp` adds a new required top-level directory (like `common` or `vendor`), the sparse-checkout list in `tool/update_llama_cpp.dart` must be updated to include it.
- **CMake Errors**: If downstream `CMakeLists.txt` changes significantly, we might need to adjust the flags in `src/native/CMakeLists.txt`.
