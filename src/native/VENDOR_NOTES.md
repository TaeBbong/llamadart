# Vendor Notes: llama.cpp

This directory contains a vendored copy of [llama.cpp](https://github.com/ggerganov/llama.cpp) (tag: `b7839`).
Modifications have been made to support Android compilation with Vulkan on NDK 29.

## Modifications

### Automation Strategy (Zero-Patch)

The `tool/update_llama_cpp.dart` script is now configured to use a "Zero-Patch" strategy:

1.  **Pinned Version**: The script defaults to the **`b7845`** release tag (latest stable as of Jan 2026), ensuring a predictable and stable build baseline.
2.  **External Shim**: Instead of patching `llama.cpp` sources, we use a custom `src/native/cmake/FindVulkan.cmake` shim.
    *   This shim intercepts `find_package(Vulkan)` calls.
    *   It manually forces `Vulkan_FOUND=TRUE` for Android NDK builds.
    *   It locates `glslc` and sets the necessary variables without modifying the vendored code.
3.  **No Source Modifications (Zero-Patch / Zero-Overwrite)**: 
    *   The `src/native/llama_cpp` directory contains unmodified upstream code (except for standard cleanup).
    *   We use the upstream `CMakeLists.txt` directly.
    *   Build options (e.g., `LLAMA_BUILD_TESTS=OFF`) are set in `src/native/CMakeLists.txt`.

### Important Notes

*   **Maintenance**: To update the `llama.cpp` version, simply change the default tag in `tool/update_llama_cpp.dart` and re-run. No patch rebasing is required.
  ```cmake
  # find_package(Vulkan COMPONENTS glslc REQUIRED)
  if (NOT Vulkan_FOUND)
      set(Vulkan_FOUND TRUE)
  endif()
  ```

### 2. Pruned Directories
The following directories were removed to reduce size and build complexity:
- `benches/`
- `ci/`
- `docs/`
- `examples/`
- `grammars/`
- `media/`
- `pocs/`
- `tests/`
- `tools/`
- `gguf-py/`
- `requirements/`
- `scripts/`
- `ggml/src/ggml-cann/`
- `ggml/src/ggml-hexagon/`
- `ggml/src/ggml-musa/`
- `ggml/src/ggml-opencl/`
- `ggml/src/ggml-rpc/`
- `ggml/src/ggml-sycl/`
- `ggml/src/ggml-webgpu/`
- `ggml/src/ggml-zdnn/`
- `ggml/src/ggml-zendnn/`
- Root-level Python conversion scripts (`convert_*.py`)



## Maintenance
To update `llama.cpp`:
1.  Open `tool/update_llama_cpp.dart`.
2.  Update the `targetVersion` variable to the desired release tag (e.g., `b78xx`).
3.  Run `dart tool/update_llama_cpp.dart`.
4.  Re-build Android project to verify.
