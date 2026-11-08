# Builds libtilawa_asr.so: whisper.cpp (pinned submodule) + the thin C API used by Dart FFI.
cmake_minimum_required(VERSION 3.18)
project(tilawa_asr CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if (NOT CMAKE_BUILD_TYPE OR CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)  # never ship an unoptimised engine
endif()

set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)      # no network code in the app
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)       # never tuned to the build machine

# Runtime CPU dispatch: ggml builds one CPU backend per ARM / x86 generation (dotprod, fp16,
# i8mm, SVE...) as separate .so files and loads the best one the phone supports. Not
# available for 32-bit ARM, which gets one portable build.
if (TILAWA_CPU_VARIANTS OR (ANDROID AND ANDROID_ABI MATCHES "arm64-v8a|x86_64"))
  set(GGML_BACKEND_DL ON CACHE BOOL "" FORCE)
  set(GGML_CPU_ALL_VARIANTS ON CACHE BOOL "" FORCE)
  set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
else()
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
endif()

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../whisper.cpp whisper_build)

add_library(tilawa_asr SHARED tilawa_asr.cpp)
target_link_libraries(tilawa_asr PRIVATE whisper ggml)
if (ANDROID)
  target_link_options(tilawa_asr PRIVATE "-Wl,-z,max-page-size=16384")  # 16 KB page devices
endif()
