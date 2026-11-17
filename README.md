<div align="center">

# Iron Brigade, recompiled

**The Xbox 360 (XBLA) version of Iron Brigade, recompiled into a native Windows program.**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)
![Steam Deck](https://img.shields.io/badge/Steam%20Deck-30%20FPS%20(Proton)-1A9FFF?logo=steamdeck&logoColor=white)
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
  mission. It needs `render_target_path = "rov"` under `[gpu.d3d12]` (set in
  `config/ironbrigade.toml`): the game renders its scene in the 7e3 HDR format, which the
  default path approximates too bright.
- **Native renderer (ReXNative, with DLAA / DLSS / DLSS 5 and a settings menu): in progress.**
  It draws the warning, logo and title screens and opens its settings menu (**F1**), and the
  game goes on into its intro (the GPU hang the first 3D frames used to cause is fixed: this
  LTCG build passes its draw arguments in other registers). The intro video plays, with its
  subtitles and the stock renderer's brightness (since 2026-11-15: Scaleform draws its frames
  with DrawIndexedVerticesUP, which ReXNative now hooks, into a gamma render target it now
  writes in the console's gamma). It goes on into the first mission at 30 FPS with its
  static scenery (towers, the base), which the game draws from recorded command buffers that
  ReXNative replays since 2026-11-15 (before, it showed bright yellow). Its light and
  particles blend in linear color into the game's gamma targets, as on the console, and its
  half-resolution particles are hidden by the scenery's depth (before, the glows came out far
  too bright, with purple columns under the towers). Turn it on with `--rexnative=true`; off,
  the stock renderer draws everything.
- **Steam Deck: plays at the game's 30 FPS** with ReXNative, the Windows build under Proton
  (first mission tested 2026-11-15: GPU about a third busy, about 5 W). See
  [Steam Deck](#steam-deck).

Details, findings and next steps: [docs/NATIVE_RENDERER.md](docs/NATIVE_RENDERER.md) and
[docs/NOTES.md](docs/NOTES.md).

## What you need

- **Iron Brigade for Xbox 360 (XBLA)**, extracted from its package so that `game-data\` holds
  `default.xex` and the game's data (an STFS extractor such as
  [FromDustRecomp's](https://github.com/gtguerreiro-max/FromDustRecomp) `tools/stfs_extract.py`
  does it). The add-on, if you have it, goes in
  `dlc-data\0000000000000000\58410A95\00000002\<package name>\`.
- **A Windows 10/11 PC**: Visual Studio 2022 Build Tools (the C++ workload: Windows SDK and
  MSVC libraries), LLVM 20 (clang++ and lld; `REXNATIVE_LLVM` names its `bin` folder, or pass
  `-Llvm`), the Vulkan SDK, CMake 3.25+, Ninja, Python 3 and Git.
- For the native renderer: the [AMD FidelityFX SDK](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK)
  v2.4.0 (commit `7539ae8`: FSR 4.1.2, FSR 3.1.6, Frame Generation 4.0.2, whose signed DLLs ship
  beside the game) and NVIDIA's DLSS SDK headers. Their paths are CMake cache
  variables (`IB_FIDELITYFX_SDK`, default `build/fidelityfx-sdk`; `IB_DLSS_SDK`, `IB_DLSS_NR`).
  Build with `-DIRONBRIGADE_NATIVE=OFF` to leave it out.

## Build

```powershell
git clone --recurse-submodules https://github.com/gtguerreiro-max/IronBrigadeRecomp
cd IronBrigadeRecomp
# Put (or link) your extracted game in game-data\ so that game-data\default.xex exists.
scripts\build.ps1 -CopyGame
```

The port runs on ReXGlue v0.11. The first build makes the SDK with ReXNative's
`third_party\ReXNative\scripts\build-sdk.ps1` (ReXGlue v0.11.0 with ReXNative's
`sdk/patches/v0.11`: the host renderer's side of the Xenos driver, codegen, kernel and audio
fixes), generates the game's code (`tools/gen_manifest.py`, which adds a function hint for each
branch target codegen reports) and builds the game into `build\IronBrigade`. An SDK built
already (the same lock and patches) is reused with `-SdkInstall <its sdk-install> -SdkSrc <its
source tree>`. After a change to the port itself, `scripts\build.ps1 -Stage game,install` is
enough.

The native renderer comes from the `third_party/ReXNative` submodule (or a ReXNative checkout
beside this folder). Everything specific to Iron Brigade is in `src/rexnative/`: `game_layer.h`
and `d3d_surface.inc`, written by ReXNative's tool from this game's generated code, with
`src/rexnative/overrides.json` for what was decided by hand.

## Play

Run `build\IronBrigade\ironbrigade.exe`. Settings are in `ironbrigade.toml` beside it, and a
command-line flag (`--name=value`) overrides one for a session. A pad works; with
`--mnk_mode=true` the keyboard does (Return = Start, Space = A).

## Steam Deck

The Windows build runs under Proton with ReXNative (D3D12 through vkd3d-proton), as
[FromDustDeck](https://github.com/gtguerreiro-max/FromDustDeck) does:

1. Copy `build\IronBrigade` to the Deck without the NVIDIA DLLs (`nvngx_*.dll`) and the
   `live\`, `logs\` and `userdata\cache\` folders, for example to `~/Games/IronBrigade`, with
   `game\` (the game's data) and `userdata\` (the add-on and your save).
2. Put the files of `deck/` beside `ironbrigade.exe`: `play.sh` starts Proton (GE-Proton 11,
   else Valve's Proton 11.0) with a prefix of its own; `ironbrigade-deck.toml` becomes the
   game's settings (1280x800 full screen, the game's 16:9 picture, ReXNative on);
   `install.sh` installs them and adds "Iron Brigade" to Steam's library (Steam must be
   closed; artwork from an `art/` folder beside it: `portrait.png`, `grid.png`, `hero.png`,
   `logo.png`, `icon.png`).
3. Run `install.sh` in a terminal, then start the game from Steam. Do not give the shortcut a
   compatibility tool: `play.sh` runs Proton itself.

The pad works through Steam Input; **F1** or Back + Start opens ReXNative's settings menu.
Its upscaler (off by default) runs **FSR 4.1** on the Deck: `play.sh` sets
`PROTON_FSR4_UPGRADE=1`, with which GE-Proton puts AMD's `amdxcffx64.dll` in the prefix the first
time (tested 2026-11-16: "ReXNative upscaler: 4.1.2" in the game's log); under Valve's Proton,
or with `PROTON_FSR4_UPGRADE=0` in a `deck.env` beside `play.sh`, it is FSR 3.1.

## Credits

- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk): the recompiler and runtime, built on
  [Xenia](https://github.com/xenia-project/xenia) (BSD 3-Clause).
- [ReXNative](https://github.com/gtguerreiro-max/ReXNative): the native D3D12 renderer and its
  settings menu (MIT), built from the `third_party/ReXNative` submodule.
- [PGR4Native](https://github.com/shaunsingh/pgr4-native): where that renderer comes from, and
  the generic SDK patches (ported to v0.11 in ReXNative's `sdk/patches`).
- [FromDustDeck](https://github.com/gtguerreiro-max/FromDustDeck): the port this one follows
  (build scripts, SDK changes, the renderer's first adaptation).
- Xenia Canary's community patches for this game (xenia-canary/game-patches) and Xenia's
  compatibility reports, read while porting it.

This repository holds the port's own code, scripts and notes only; the game is not included.
Iron Brigade is a game by Double Fine Productions, published by Microsoft; this project is not
affiliated with or endorsed by either.
