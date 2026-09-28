# src/xenia/app/CMakeLists.txt - Main xenia_canary executable.

if(WIN32)
  add_executable(xenia-app WIN32)
elseif(APPLE)
  add_executable(xenia-app MACOSX_BUNDLE)
else()
  add_executable(xenia-app)
endif()

set_target_properties(xenia-app PROPERTIES OUTPUT_NAME "xenia_canary")

# Main source
target_sources(xenia-app PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/xenia_main.cc
)

# Other app sources (emulator_window, profile_dialogs, etc.)
xe_platform_sources(xenia-app ${CMAKE_CURRENT_SOURCE_DIR})

# Platform-specific entry points
if(WIN32)
  target_sources(xenia-app PRIVATE
    ${PROJECT_SOURCE_DIR}/src/xenia/base/main_init_win.cc
    ${PROJECT_SOURCE_DIR}/src/xenia/ui/windowed_app_main_win.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/main_resources.rc
    ${PROJECT_SOURCE_DIR}/src/xenia/base/app_win32.manifest
  )
  if(XE_TARGET_X86_64)
    # main_init_win.cc needs SSE2 only (not AVX)
    set_source_files_properties(
      ${PROJECT_SOURCE_DIR}/src/xenia/base/main_init_win.cc
      PROPERTIES COMPILE_OPTIONS "/arch:SSE2"
    )
  endif()
elseif(APPLE)
  target_sources(xenia-app PRIVATE
    ${PROJECT_SOURCE_DIR}/src/xenia/base/main_init_mac.cc
    ${PROJECT_SOURCE_DIR}/src/xenia/ui/windowed_app_main_mac.cc)
else()
  target_sources(xenia-app PRIVATE
    ${PROJECT_SOURCE_DIR}/src/xenia/base/main_init_posix.cc
    ${PROJECT_SOURCE_DIR}/src/xenia/ui/windowed_app_main_posix.cc
  )
  if(NOT MSVC AND XE_TARGET_X86_64)
    set_source_files_properties(
      ${PROJECT_SOURCE_DIR}/src/xenia/base/main_init_posix.cc
      PROPERTIES COMPILE_OPTIONS "-msse2;-mno-avx"
    )
  endif()
endif()

target_compile_definitions(xenia-app PRIVATE
  XBYAK_NO_OP_NAMES
  XBYAK_ENABLE_OMITTED_OPERAND
)

# Core libraries (all platforms)
target_link_libraries(xenia-app PRIVATE
  xenia-apu
  xenia-apu-nop
  xenia-base
  xenia-core
  xenia-cpu
  xenia-gpu
  xenia-gpu-null
  xenia-hid
  xenia-hid-nop
  xenia-kernel
  xenia-patcher
  xenia-ui
  xenia-vfs
  # Third-party
  aes_128
  capstone
  fmt
  dxbc
  discord-rpc
  imgui
  libavcodec
  libavutil
  mspack
  snappy
  xxhash
)

# Vulkan/SPIR-V backends (not macOS)
if(NOT APPLE)
  target_link_libraries(xenia-app PRIVATE
    xenia-gpu-vulkan
    xenia-ui-vulkan
    glslang-spirv
  )
endif()

# Native macOS graphics and application metadata.
if(APPLE)
  target_link_libraries(xenia-app PRIVATE xenia-gpu-metal xenia-ui-metal
    "-framework Cocoa" "-framework Metal" "-framework QuartzCore")
  # App icon (assets/icon/icon.icns, generated from the PNGs next to it).
  set(XE_APP_ICON "${PROJECT_SOURCE_DIR}/assets/icon/icon.icns")
  target_sources(xenia-app PRIVATE "${XE_APP_ICON}")
  set_source_files_properties("${XE_APP_ICON}" PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources")
  set_target_properties(xenia-app PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER "jp.xenia.canary.mac"
    MACOSX_BUNDLE_BUNDLE_NAME "Xenia Canary"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info-mac.plist"
    BUILD_RPATH "@executable_path/../Frameworks"
    INSTALL_RPATH "@executable_path/../Frameworks")
endif()

# Non-Android specific (always true for Windows/Linux)
target_link_libraries(xenia-app PRIVATE
  xenia-app-discord
  xenia-apu-sdl
  xenia-debug-ui
  xenia-helper-sdl
  xenia-hid-sdl
  xenia-hid-keyboard
)

# Architecture-specific backend
if(XE_TARGET_X86_64)
  target_link_libraries(xenia-app PRIVATE xenia-cpu-backend-x64)
elseif(XE_TARGET_AARCH64)
  target_link_libraries(xenia-app PRIVATE xenia-cpu-backend-a64)
endif()

# Platform-specific libraries
if(WIN32)
  target_link_libraries(xenia-app PRIVATE
    xenia-apu-xaudio2
    xenia-gpu-d3d12
    xenia-hid-xinput
    xenia-ui-d3d12
  )
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(xenia-app PRIVATE
    xenia-apu-alsa
    X11
    xcb
    X11-xcb
    SDL2
  )
endif()

xe_target_defaults(xenia-app)

if(APPLE)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  set(_mac_bundle_libraries)
  foreach(_library metalirconverter dxilconv)
    if(TARGET ${_library})
      list(APPEND _mac_bundle_libraries --library "$<TARGET_FILE:${_library}>")
    endif()
  endforeach()
  set(_mac_bundle_licenses --license "${PROJECT_SOURCE_DIR}/LICENSE" "Xenia.txt")
  if(TARGET metalirconverter)
    list(APPEND _mac_bundle_licenses
      --license "${PROJECT_SOURCE_DIR}/third_party/metal-shader-converter/include/LICENSE.txt" "MetalShaderConverter.txt"
      --license "${PROJECT_SOURCE_DIR}/third_party/metal-shader-converter/include/metal_irconverter/LICENSE.txt" "MetalIRConverter.txt"
      --license "${PROJECT_SOURCE_DIR}/third_party/metal-shader-converter/include/metal_irconverter_runtime/LICENSE.txt" "MetalIRConverterRuntime.txt")
  endif()
  if(TARGET dxilconv)
    list(APPEND _mac_bundle_licenses
      --license "${PROJECT_SOURCE_DIR}/third_party/DirectXShaderCompiler-mac/LICENSE.TXT" "DirectXShaderCompiler.txt"
      --license "${PROJECT_SOURCE_DIR}/third_party/DirectXShaderCompiler-mac/ThirdPartyNotices.txt" "DirectXShaderCompilerThirdPartyNotices.txt")
  endif()
  target_link_options(xenia-app PRIVATE "-Wl,-headerpad_max_install_names")
  add_custom_command(TARGET xenia-app POST_BUILD
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/package_macos.py"
      --app "$<TARGET_BUNDLE_DIR:xenia-app>"
      --executable "$<TARGET_FILE:xenia-app>"
      --entitlements "${PROJECT_SOURCE_DIR}/xenia.entitlements"
      ${_mac_bundle_libraries} ${_mac_bundle_licenses}
    VERBATIM)
endif()
