# ironbrigade - ReXGlue port of Iron Brigade (XBLA, title 58410A95), on ReXGlue v0.11.

cmake_minimum_required(VERSION 3.25)
project(ironbrigade LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(rexglue 0.11.0 REQUIRED CONFIG)
rexglue_project(ironbrigade OUTPUT_DIR generated/default)

# Host code: the app, and ReXNative below. OBJECT, not STATIC: an archive drops the hooks.
add_library(ironbrigade_common OBJECT src/ironbrigade_app.cpp)
rexglue_setup_host_library(ironbrigade_common)

if(WIN32)
    add_executable(ironbrigade WIN32 src/main.cpp)
else()
    add_executable(ironbrigade src/main.cpp)
endif()

# ReXGlue's Xenos GPU drivers (Xenia's D3D12 and Vulkan backends): the stock renderer.
rexglue_setup_target(ironbrigade)
target_link_libraries(ironbrigade PRIVATE ironbrigade_common)

# The native D3D12 renderer: ReXNative (https://github.com/gtguerreiro-max/ReXNative), the
# universal version of PGR4Native's renderer (DLAA / DLSS / DLSS 5, FSR, the settings HUD). It
# hooks the guest D3D draw, clear, resolve and Swap calls; the Xenos driver stays for the GPU's
# fences and interrupts (gpu.xenos.skip_draws) and as the comparison renderer. Everything specific
# to Iron Brigade is in src/rexnative/ (game_layer.h, d3d_surface.inc, written by ReXNative's tool
# with src/rexnative/overrides.json; docs/NATIVE_RENDERER.md). The renderer's game-side
# functions are ReXNative's defaults (renderer/src/glue_defaults.cpp).
option(IRONBRIGADE_NATIVE "Build the native D3D12 renderer (ReXNative)" ${WIN32})
if(WIN32 AND IRONBRIGADE_NATIVE)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ReXNative/renderer/rexnative.cmake")
        set(_ironbrigade_rexnative "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ReXNative")
    else()
        set(_ironbrigade_rexnative "${CMAKE_CURRENT_SOURCE_DIR}/../ReXNative")
    endif()
    set(IRONBRIGADE_REXNATIVE_DIR "${_ironbrigade_rexnative}" CACHE PATH
        "ReXNative (the third_party/ReXNative submodule, or a checkout beside this one)")
    # The SDK's source tree and FidelityFX: where scripts\build.ps1's sdk stage puts them
    # (ReXNative's scripts\build-sdk.ps1).
    set(IB_REXGLUE_SDK_SRC "${CMAKE_CURRENT_SOURCE_DIR}/build/rexglue-sdk" CACHE PATH
        "The source tree the ReXGlue SDK was built from")
    set(IB_FIDELITYFX_SDK "${CMAKE_CURRENT_SOURCE_DIR}/build/fidelityfx-sdk" CACHE PATH
        "AMD FSR (FidelityFX) SDK v2.4.0 (7539ae8, ReXNative's sdk/fidelityfx.lock)")
    set(IB_DLSS_SDK "F:/PGR4Native/third_party/dlss_sdk" CACHE PATH "NVIDIA DLSS SDK")
    set(IB_DLSS_NR "F:/PGR4Native/third_party/dlss_nr" CACHE PATH "NVIDIA DLSS 5 headers")
    include("${IRONBRIGADE_REXNATIVE_DIR}/renderer/rexnative.cmake")
    rexnative_add(ironbrigade_common
        EXECUTABLE      ironbrigade
        LAYER_DIR       "${CMAKE_CURRENT_SOURCE_DIR}/src/rexnative"
        REXGLUE_SDK_SRC "${IB_REXGLUE_SDK_SRC}"
        FIDELITYFX_SDK  "${IB_FIDELITYFX_SDK}"
        DLSS_SDK        "${IB_DLSS_SDK}"
        DLSS_NR         "${IB_DLSS_NR}")
    target_compile_definitions(ironbrigade_common PRIVATE IRONBRIGADE_NATIVE_RENDERER=1)
endif()

# The link map (build\game\ironbrigade.map) names the recompiled guest functions of a crash's
# offsets.
target_link_options(ironbrigade PRIVATE "LINKER:/MAP")
