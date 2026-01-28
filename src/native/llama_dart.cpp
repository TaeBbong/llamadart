#include "ggml-backend.h"
#include "llama.h"
#include <stdio.h>
#include <string.h>

#ifdef __ANDROID__
#include <android/log.h>
#endif

#ifdef __GNUC__
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define EXPORT
#endif

extern "C" {

// Forward declarations to fix "undeclared identifier" and "no previous
// prototype"
EXPORT const char *llama_dart_get_backend_name();
EXPORT bool llama_dart_gpu_supported();
EXPORT void llama_dart_init();
EXPORT int llama_dart_get_device_count();
EXPORT const char *llama_dart_get_device_name(int index);
EXPORT const char *llama_dart_get_device_description(int index);
EXPORT void *llama_dart_get_device_pointer(int index);
void llama_dart_init_logging();
void llama_dart_log_callback(ggml_log_level level, const char *text,
                             void *user_data);

// Custom Logger to filter spam and avoid Dart callback crashes
void llama_dart_log_callback(ggml_log_level level, const char *text,
                             void *user_data) {
  (void)user_data; // Fix "unused parameter" warning
  if (text == NULL)
    return;

  // 1. Filter Tokenizer noise (Gemma 3)
  if (strstr(text, "is not marked as EOG"))
    return;
  if (strstr(text, "unused"))
    return;

  // 2. Filter verbose init info
  if (strncmp(text, "print_info:", 11) == 0)
    return;
  if (strncmp(text, "load_tensors:", 13) == 0)
    return;
  if (strncmp(text, "create_tensor:", 14) == 0)
    return;
  if (strncmp(text, "load:", 5) == 0)
    return;
  if (strstr(text, "compiling pipeline"))
    return;
  if (strstr(text, "loaded kernel"))
    return;

  // 3. Print based on level
  if (level == GGML_LOG_LEVEL_ERROR) {
    fprintf(stderr, "LLAMA_ERR: %s", text);
  } else if (level == GGML_LOG_LEVEL_WARN) {
    // Only print warnings
    fprintf(stdout, "LLAMA_WARN: %s", text);
  }
}

void llama_dart_init_logging() {
  llama_log_set(llama_dart_log_callback, nullptr);
}

EXPORT void llama_dart_init() {
  // Call some dummy functions to ensure the linker doesn't strip the library
  llama_backend_init();
  llama_dart_init_logging();

  // Force usage to prevent stripping (dlsym lookup issues on some platforms)
  const char *backend = llama_dart_get_backend_name();
  bool gpu = llama_dart_gpu_supported();

  fprintf(stderr, "llama_dart_debug: Initializing...\n");
#ifdef __ANDROID__
#define LOG_TAG "llama_dart_native"
  __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "Initializing...");
#ifdef GGML_USE_VULKAN
  __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "GGML_USE_VULKAN is DEFINED");
#else
  __android_log_print(ANDROID_LOG_ERROR, LOG_TAG,
                      "GGML_USE_VULKAN is NOT DEFINED");
#endif
  __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "Backend: %s, GPU: %d",
                      backend, (int)gpu);
#endif

#ifdef GGML_USE_VULKAN
  fprintf(stderr, "llama_dart_debug: GGML_USE_VULKAN is DEFINED\n");
#else
  fprintf(stderr, "llama_dart_debug: GGML_USE_VULKAN is NOT DEFINED\n");
#endif

  fprintf(
      stderr,
      "llama_dart: Initializing with backend %s (GPU support directly: %d)\n",
      backend, (int)gpu);
  fprintf(stdout,
          "llama_dart: Initializing with backend %s (GPU support: %s)\n",
          backend, gpu ? "YES" : "NO");
}

EXPORT const char *llama_dart_get_backend_name() {
#if defined(GGML_USE_CUDA)
  return "CUDA";
#elif defined(GGML_USE_METAL)
  return "Metal";
#elif defined(GGML_USE_VULKAN)
  return "Vulkan";
#else
  return "CPU";
#endif
}

EXPORT bool llama_dart_gpu_supported() { return llama_supports_gpu_offload(); }

EXPORT int llama_dart_get_device_count() { return ggml_backend_dev_count(); }

EXPORT const char *llama_dart_get_device_name(int index) {
  if (index < 0 || index >= ggml_backend_dev_count()) {
    return "";
  }
  ggml_backend_dev_t dev = ggml_backend_dev_get(index);
  return ggml_backend_dev_name(dev);
}

EXPORT const char *llama_dart_get_device_description(int index) {
  if (index < 0 || index >= ggml_backend_dev_count()) {
    return "";
  }
  ggml_backend_dev_t dev = ggml_backend_dev_get(index);
  return ggml_backend_dev_description(dev);
}

EXPORT void *llama_dart_get_device_pointer(int index) {
  if (index < 0 || index >= ggml_backend_dev_count()) {
    return nullptr;
  }
  return ggml_backend_dev_get(index);
}
}
