# Builds libtilawa_asr.so: whisper.cpp (pinned submodule) + the thin C API used by Dart FFI.
cmake_minimum_required(VERSION 3.18)
project(tilawa_asr CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)  # static whisper/ggml linked into a .so
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)      # no network code in the app
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
if (ANDROID)
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)     # portable across all phones of an ABI
endif()

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../whisper.cpp whisper_build)

add_library(tilawa_asr SHARED tilawa_asr.cpp)
target_link_libraries(tilawa_asr PRIVATE whisper)
if (ANDROID)
  target_link_options(tilawa_asr PRIVATE "-Wl,-z,max-page-size=16384")  # 16 KB page devices
endif()
