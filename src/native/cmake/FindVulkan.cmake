# Custom FindVulkan.cmake to shim Android NDK discovery for llama.cpp

if(ANDROID)
  # In Android NDK, Vulkan is available but find_package(Vulkan) often fails to find glslc
  # or sets properties incompatibly for cross-compilation in some versions.
  # We manually force it to be FOUND to satisfy `find_package(Vulkan REQUIRED)` in subprojects.

  if(NOT Vulkan_FOUND)
    message(STATUS "llama_dart: Shim FindVulkan.cmake - Forcing Vulkan_FOUND=TRUE for Android")
    set(Vulkan_FOUND TRUE CACHE BOOL "Vulkan found" FORCE)
    
    # Map the NDK's libvulkan.so to the library variable if not already set
    if(NOT Vulkan_LIBRARY)
      set(Vulkan_LIBRARY "vulkan" CACHE STRING "Vulkan library" FORCE)
    endif()

    if(NOT TARGET Vulkan::Vulkan)
      add_library(Vulkan::Vulkan INTERFACE IMPORTED)
      set_target_properties(Vulkan::Vulkan PROPERTIES INTERFACE_LINK_LIBRARIES "${Vulkan_LIBRARY}")
    endif()

    # GLSL Compiler (glslc) is part of NDK but might not be in PATH or CMAKE_PREFIX_PATH
    # llama.cpp uses ${Vulkan_GLSLC_EXECUTABLE}
    if(NOT Vulkan_GLSLC_EXECUTABLE)
       find_program(Vulkan_GLSLC_EXECUTABLE NAMES glslc
          HINTS
          "${ANDROID_NDK}/shader-tools/darwin-x86_64"
          "${ANDROID_NDK}/shader-tools/linux-x86_64"
          "${ANDROID_NDK}/shader-tools/windows-x86_64"
          NO_CMAKE_FIND_ROOT_PATH
       )
       if(Vulkan_GLSLC_EXECUTABLE)
           message(STATUS "llama_dart: Shim FindVulkan.cmake - Found glslc at ${Vulkan_GLSLC_EXECUTABLE}")
       else()
           message(WARNING "llama_dart: Shim FindVulkan.cmake - Could NOT find glslc. Shader compilation may fail.")
       endif()
    endif()

  endif()
else()
  # Fallback to standard standard discovery on non-Android
  include(${CMAKE_ROOT}/Modules/FindVulkan.cmake)
endif()
