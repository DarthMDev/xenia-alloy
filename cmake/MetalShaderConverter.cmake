# The macOS DXBC converter is isolated from Canary's Windows DXC dependency.
option(XENIA_METAL_SHADER_CONVERTER "Build the DXBC/DXIL Metal shader path" ON)
if(NOT XENIA_METAL_SHADER_CONVERTER)
  return()
endif()

set(_xe_dxc_source "${PROJECT_SOURCE_DIR}/third_party/DirectXShaderCompiler-mac")
set(_xe_dxc_binary "${PROJECT_BINARY_DIR}/third_party/dxilconv-build")
set(_xe_msc_source "${PROJECT_SOURCE_DIR}/third_party/metal-shader-converter")
if(NOT EXISTS "${_xe_dxc_source}/CMakeLists.txt" OR
   NOT EXISTS "${_xe_msc_source}/lib/libmetalirconverter.dylib")
  message(FATAL_ERROR "Initialize the DirectXShaderCompiler-mac and metal-shader-converter submodules before building Metal")
endif()

include(ExternalProject)
# LLVM in DXC builds its own host tools (tablegen) in a separate "NATIVE" CMake
# tree when cross-compiling (CMAKE_SYSTEM_NAME is passed below). Give that tree
# the host architecture, the SDK and the compilers explicitly - otherwise it may pick x86_64,
# which newer Command Line Tools (macOS 27+) can no longer build.
set(_xe_dxc_native_arch "${CMAKE_HOST_SYSTEM_PROCESSOR}")
if(NOT _xe_dxc_native_arch OR _xe_dxc_native_arch STREQUAL "aarch64")
  set(_xe_dxc_native_arch "arm64")
endif()
ExternalProject_Add(xenia-dxilconv-build
  LIST_SEPARATOR |
  SOURCE_DIR "${_xe_dxc_source}"
  BINARY_DIR "${_xe_dxc_binary}"
  DOWNLOAD_COMMAND ""
  UPDATE_COMMAND ""
  PATCH_COMMAND "${CMAKE_COMMAND}" -DGIT_EXECUTABLE=${GIT_EXECUTABLE}
    -DSOURCE_DIR=<SOURCE_DIR>
    -DPATCH_FILE=${PROJECT_SOURCE_DIR}/cmake/patches/dxilconv-macos.patch
    -P "${PROJECT_SOURCE_DIR}/cmake/ApplyDependencyPatch.cmake"
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
    -DCMAKE_SYSTEM_NAME=Darwin
    -DCMAKE_SYSTEM_PROCESSOR=${CMAKE_OSX_ARCHITECTURES}
    -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
    -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}
    "-DCROSS_TOOLCHAIN_FLAGS_NATIVE=-DCMAKE_OSX_ARCHITECTURES=${_xe_dxc_native_arch}|-DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}|-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}|-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}|-DCMAKE_APPLE_SILICON_PROCESSOR=${_xe_dxc_native_arch}|-DD3D12_INCLUDE_DIR=${PROJECT_SOURCE_DIR}/third_party/DirectX-Headers/include/directx|-DDXGI_INCLUDE_DIR=${PROJECT_SOURCE_DIR}/third_party/DirectX-Headers/include/directx|-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    -DCMAKE_CXX_STANDARD=17
    -DCMAKE_CXX_STANDARD_REQUIRED=ON
    -DCMAKE_CXX_EXTENSIONS=OFF
    "-DCMAKE_CXX_FLAGS=-stdlib=libc++ -Wno-deprecated-declarations -Wno-deprecated"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DD3D12_INCLUDE_DIR=${PROJECT_SOURCE_DIR}/third_party/DirectX-Headers/include/directx
    -DDXGI_INCLUDE_DIR=${PROJECT_SOURCE_DIR}/third_party/DirectX-Headers/include/directx
    -DLLVM_TARGETS_TO_BUILD=None
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=
    -DLLVM_DEFAULT_TARGET_TRIPLE=${CMAKE_OSX_ARCHITECTURES}-apple-darwin
    -DLLVM_TARGET_ARCH=${CMAKE_OSX_ARCHITECTURES}
    -DLLVM_ENABLE_THREADS=ON
    -DLLVM_ENABLE_PIC=ON
    -DLLVM_BUILD_32_BITS=OFF
    -DBUILD_SHARED_LIBS=OFF
    -DLLVM_OPTIMIZED_TABLEGEN=OFF
    -DLLVM_USE_INTEL_JITEVENTS=OFF
    -DLLVM_ENABLE_ZLIB=ON
    -DLLVM_ENABLE_LIBXML2=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DCLANG_BUILD_EXAMPLES=OFF
    -DCLANG_INCLUDE_TESTS=OFF
    -DHLSL_INCLUDE_TESTS=OFF
    -DENABLE_SPIRV_CODEGEN=OFF
    -DSPIRV_BUILD_TESTS=OFF
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF
    -DCLANG_ENABLE_ARCMT=OFF
    -DLLVM_ENABLE_BINDINGS=OFF
    -DLLVM_ENABLE_EH=ON
    -DLLVM_ENABLE_RTTI=ON
    -DLLVM_REQUIRES_EH=ON
    -DLLVM_REQUIRES_RTTI=ON
  BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR>
    --target dxilconv LLVMDxcSupport --parallel 4
  INSTALL_COMMAND ""
  BUILD_BYPRODUCTS "${_xe_dxc_binary}/lib/libdxilconv.dylib"
    "${_xe_dxc_binary}/lib/libLLVMDxcSupport.a")

add_library(dxilconv SHARED IMPORTED GLOBAL)
set_target_properties(dxilconv PROPERTIES
  IMPORTED_LOCATION "${_xe_dxc_binary}/lib/libdxilconv.dylib"
  INTERFACE_INCLUDE_DIRECTORIES "${_xe_dxc_source}/include;${_xe_dxc_source}/projects/dxilconv/include"
  INTERFACE_LINK_LIBRARIES "${_xe_dxc_binary}/lib/libLLVMDxcSupport.a")
add_dependencies(dxilconv xenia-dxilconv-build)

add_library(metalirconverter SHARED IMPORTED GLOBAL)
set_target_properties(metalirconverter PROPERTIES
  IMPORTED_LOCATION "${_xe_msc_source}/lib/libmetalirconverter.dylib"
  INTERFACE_INCLUDE_DIRECTORIES "${_xe_msc_source}/include")
message(STATUS "Metal: building DXBC/DXIL shader converter for ${CMAKE_OSX_ARCHITECTURES}")
