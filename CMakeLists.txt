# ironbrigade - ReXGlue port of Iron Brigade (XBLA, title 58410A95)
#
# SDK boilerplate lives in generated/rexglue.cmake (written by rexglue codegen).

cmake_minimum_required(VERSION 3.25)
project(ironbrigade LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

set(IRONBRIGADE_SOURCES
    src/main.cpp
    src/crash_report.cpp
    src/image_dump.cpp
    src/stack_dump.cpp
)

if(WIN32)
    add_executable(ironbrigade WIN32 ${IRONBRIGADE_SOURCES})
else()
    add_executable(ironbrigade ${IRONBRIGADE_SOURCES})
endif()

# The Xenos GPU plugin: ReXGlue's stock renderer (Xenia's D3D12 backend).
rexglue_setup_target(ironbrigade GPU_PLUGINS xenos)

# The native D3D12 renderer: ReXNative (https://github.com/gtguerreiro-max/ReXNative), the
# universal version of PGR4Native's renderer (DLAA / DLSS / DLSS 5, FSR, the settings HUD). It
# hooks the guest D3D draw, clear, resolve and Swap calls; the Xenos plugin stays for the GPU's
# fences and interrupts (--gpu_skip_draws) and as the comparison renderer. Everything specific to
# Iron Brigade is in src/rexnative/ (game_layer.h, d3d_surface.inc, written by ReXNative's tool
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
    # The SDK's source tree and FidelityFX: where scripts\build.ps1's sdk stage puts them (or
    # ReXNative's scripts\build-sdk.ps1, or FromDustDeck's build, which is the same SDK).
    set(IB_REXGLUE_SDK_SRC "${CMAKE_CURRENT_SOURCE_DIR}/build/rexglue-sdk" CACHE PATH
        "The source tree the ReXGlue SDK was built from")
    set(IB_FIDELITYFX_SDK "${CMAKE_CURRENT_SOURCE_DIR}/build/fidelityfx-sdk2" CACHE PATH
        "AMD FSR (FidelityFX) SDK v2.4.0 (7539ae8, ReXNative's sdk/fidelityfx.lock)")
    set(IB_DLSS_SDK "F:/PGR4Native/third_party/dlss_sdk" CACHE PATH "NVIDIA DLSS SDK")
    set(IB_DLSS_NR "F:/PGR4Native/third_party/dlss_nr" CACHE PATH "NVIDIA DLSS 5 headers")
    include("${IRONBRIGADE_REXNATIVE_DIR}/renderer/rexnative.cmake")
    rexnative_add(ironbrigade
        LAYER_DIR       "${CMAKE_CURRENT_SOURCE_DIR}/src/rexnative"
        REXGLUE_SDK_SRC "${IB_REXGLUE_SDK_SRC}"
        FIDELITYFX_SDK  "${IB_FIDELITYFX_SDK}"
        DLSS_SDK        "${IB_DLSS_SDK}"
        DLSS_NR         "${IB_DLSS_NR}")
    target_compile_definitions(ironbrigade PRIVATE FROMDUST_NATIVE_RENDERER=1 IRONBRIGADE_NATIVE_RENDERER=1)
endif()

# Link map for crash.txt's module+offset frames.
if(MSVC)
    target_link_options(ironbrigade PRIVATE /MAP)
endif()
