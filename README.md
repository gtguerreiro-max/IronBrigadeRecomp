<div align="center">

# Iron Brigade, recompiled

**The Xbox 360 (XBLA) version of Iron Brigade, recompiled into a native Windows program.**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/status-work%20in%20progress-orange)
![Game files](https://img.shields.io/badge/game%20files-not%20included-lightgrey)

</div>

This is **not an emulator**. The game's PowerPC code is translated ahead of time into C++ with
the [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk) and built into a normal Windows
program. It draws through ReXGlue's emulated Xbox 360 GPU (Xenia's Direct3D 12 backend), and a
native Direct3D 12 renderer, [ReXNative](https://github.com/gtguerreiro-max/ReXNative), is being
brought up for it.

> [!IMPORTANT]
> **You need your own copy of the game.** Nothing from the game is in this repository: no
> executables, data, saves or artwork. The recompiled code is generated on your computer, from
> your copy of Iron Brigade for Xbox 360 Live Arcade (title ID `58410A95`), and optionally its
> "Rise of the Martian Bear" add-on.

> [!NOTE]
> **Made with AI.** Most of the code and the investigation were done by Claude (Anthropic's AI),
> directed and tested by the repository's owner.

## Status

- **Stock renderer (ReXGlue's Xenos plugin): plays**, from the title screen into the first
  mission. It needs `render_target_path_d3d12 = "rov"` (set in `config/ironbrigade.toml`): the
  game renders its scene in the 7e3 HDR format, which the default path approximates too bright.
- **Native renderer (ReXNative, with DLAA / DLSS / DLSS 5 and a settings menu): in progress.**
  It draws the warning, logo and title screens and opens its settings menu (**F1**). The game's
  first 3D frames then hang the GPU (a D3D12 TDR); the earlier hand-made copy of the renderer did
  the same, so this is being investigated in ReXNative. Turn it on with
  `--pgr4_native_primary=true`; off, the stock renderer draws everything.

Details, findings and next steps: [docs/NATIVE_RENDERER.md](docs/NATIVE_RENDERER.md) and
[docs/NOTES.md](docs/NOTES.md).

## What you need

- **Iron Brigade for Xbox 360 (XBLA)**, extracted from its package so that `game-data\` holds
  `default.xex` and the game's data (an STFS extractor such as
  [FromDustRecomp's](https://github.com/gtguerreiro-max/FromDustRecomp) `tools/stfs_extract.py`
  does it). The add-on, if you have it, goes in
  `dlc-data\0000000000000000\58410A95\00000002\<package name>\`.
- **A Windows 10/11 PC**: Visual Studio 2022 Build Tools (clang-cl, lld, Windows SDK), CMake
  3.25+, Ninja, Python 3 and Git.
- For the native renderer: the [AMD FidelityFX SDK](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK)
  2.x headers (commit `60f4ea8`) and NVIDIA's DLSS SDK headers. Their paths are CMake cache
  variables (`IB_FIDELITYFX_SDK`, default `build/fidelityfx-sdk2`; `IB_DLSS_SDK`, `IB_DLSS_NR`).
  Build with `-DIRONBRIGADE_NATIVE=OFF` to leave it out.

## Build

```powershell
git clone --recurse-submodules https://github.com/gtguerreiro-max/IronBrigadeRecomp
cd IronBrigadeRecomp
# Put (or link) your extracted game in game-data\ so that game-data\default.xex exists.
scripts\build.ps1 -CopyGame
```

The first build fetches the ReXGlue SDK at the commit in `patches/rexglue.lock`, applies
`patches/deck` (PGR4Native's generic patches) and `patches/shared` (the renderer support from
From Dust's port), builds it, generates the game's code (`tools/gen_manifest.py`, which adds a
function hint for each branch target codegen reports) and builds the game into
`build\IronBrigade`. The same SDK can be built with ReXNative's
`third_party\ReXNative\scripts\build-sdk.ps1`, or reused from another port with
`-SdkInstall <its sdk-install>`. After a change to the port itself,
`scripts\build.ps1 -Stage game,install` is enough.

The native renderer comes from the `third_party/ReXNative` submodule (or a ReXNative checkout
beside this folder). Everything specific to Iron Brigade is in `src/rexnative/`: `game_layer.h`
and `d3d_surface.inc`, written by ReXNative's tool from this game's generated code, with
`src/rexnative/overrides.json` for what was decided by hand.

## Play

Run `build\IronBrigade\ironbrigade.exe`. Settings are in `ironbrigade.toml` beside it, and a
command-line flag (`--name=value`) overrides one for a session. A pad works; with
`--mnk_mode=true` the keyboard does (Return = Start, Space = A).

## Credits

- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk): the recompiler and runtime, built on
  [Xenia](https://github.com/xenia-project/xenia) (BSD 3-Clause).
- [ReXNative](https://github.com/gtguerreiro-max/ReXNative): the native D3D12 renderer and its
  settings menu (MIT), built from the `third_party/ReXNative` submodule.
- [PGR4Native](https://github.com/shaunsingh/pgr4-native): where that renderer comes from, and
  the generic SDK patches.
- [FromDustDeck](https://github.com/gtguerreiro-max/FromDustDeck): the port this one follows
  (build scripts, SDK changes, the renderer's first adaptation).
- Xenia Canary's community patches for this game (xenia-canary/game-patches) and Xenia's
  compatibility reports, read while porting it.

This repository holds the port's own code, scripts and notes only; the game is not included.
Iron Brigade is a game by Double Fine Productions, published by Microsoft; this project is not
affiliated with or endorsed by either.
