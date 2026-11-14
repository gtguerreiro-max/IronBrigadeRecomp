# Iron Brigade (XBLA) static recompilation: working notes

## The game

- Iron Brigade (World) (XBLA), Double Fine / Microsoft Studios. **Title ID `58410A95`**
  (XA-2709), package `878AB257730B01956E00D0668E4DB846EF53039458` (content type `000D0000`, LIVE).
  Media ID `4836A4E6`. Base version (no title update in the package; the Canary patch file's base
  `default.xex` hash is `3DD6AB3FBD285A9B`, TU6 is `CF37AF559A37B77C`).
- One executable, `default.xex`, no other XEX modules. Image `0x82000000-0x82C50000`, code
  `0x82100000-0x82B1DEAC`.
- Add-on "Rise of the Martian Bear" (`8034235E5F61DAE91A26B257296E540FA192EED058`, content type
  `00000002`, marketplace): data only (`DLC1.dlc`, `DLC1.~p/~h`, audio, Bink videos), no code.
- Extracted with `F:\FromDustRecomp\tools\stfs_extract.py`:
  - `game-pkg\` the 7z's contents, `game-data\` the game's files (`default.xex`, `Data\`, `360\`).
  - `dlc-pkg\` the add-on's 7z, `dlc-data\0000000000000000\58410A95\00000002\<package>\` its
    files, in the layout ReXGlue's `ContentManager` reads (`content_root/xuid/title/type/name`,
    xuid 0 for marketplace content). `scripts\build.ps1 -CopyGame` copies it to
    `build\IronBrigade\content\`.

## Existing work found (search first)

- No recompilation of Iron Brigade exists (GitHub, web).
- Xenia: [xenia-project/game-compatibility#1238](https://github.com/xenia-project/game-compatibility/issues/1238),
  "state-gameplay", uses Havok. Black shading on NVIDIA fixed by forcing anisotropic filtering;
  audio needed Canary's newer XMA decoder (cut dialogue blocked scripted events).
- Canary patches (`ref\58410A95 - Iron Brigade*.patch.toml`, from xenia-canary/game-patches,
  author Sowa_95): 60 FPS (base: `0x82077dfc`, `0x82b517f8`, `0x82646a83`; subtitles in
  prerendered cutscenes end early), disable AA (`0x8236c8fc` nop), and the render resolution
  (native **1280x646**, at `0x823dbd22`/`0x823dbd26`). Addresses for the base version match
  ours (the patch file names hash `3DD6AB3FBD285A9B`; to be checked against our xex).

## Build

Same scheme as FromDustDeck: `scripts\build.ps1` (ReXGlue at `patches\rexglue.lock`, plus
`patches\deck` and `patches\shared` = FromDustDeck's SDK patch). The SDK FromDustDeck already
built is the same tree, so it is reused:

```powershell
scripts\build.ps1 -Stage game,install -SdkInstall F:\FromDustDeck\build\sdk-install -CopyGame
```

`tools\gen_manifest.py` writes `ironbrigade_manifest.toml` from `tools\hints\default.txt` and
loops codegen, adding a hint per unresolved branch target.

### Function discovery

ReXGlue's codegen finds functions from `.pdata`, calls and vtables. Functions reached only by a
pointer built in code (e.g. qsort comparators: `0x825E1F88`, the first crash, "Call to invalid
or unregistered function") are missed. `tools\find_functions.py` finds them: it needs the loaded
image, which `ironbrigade.exe --ironbrigade_dump_image=build\default.bin` writes
(`src\image_dump.cpp`), and adds every uncovered code address that follows non-falling-through
code and is pointed to (a data word or `lis`+`addi/ori`). First pass: 150 starts.

### Codegen warnings

`Unexpected float16_4 pack instruction` (vpkd3d128 type 5, pack 3, shift 0; ~90 sites): Xenia's
emitter treats pack 3 / shift 0 exactly like pack 2 / shift 0, which is what codegen emits, so it
is harmless.

The prologue criterion (`mflr r12` / `stwu r1`) found nothing more; the `lis`+`addi` window is 32
instructions (the second crash, `0x82858E60`, was built 10 instructions before its `addi`).
After two passes (156 hints) the game runs to the first mission without an unregistered call.

## Status with the stock renderer (2026-11-14)

- Builds with clang-cl in ~10 min (codegen ~40 s). Boots: Microsoft Game Studios / Double Fine
  logos, title, new game, the intro movie (Bink, subtitles), main menu with its 3D scene, pilot
  selection, and the first mission ("The Fighting Trenches") playable, with the tutorial prompts.
- **Picture too bright with the default render-target path**: the scene is rendered in the 7e3
  HDR format (k_2_10_10_10_FLOAT) and the "rtv" path's float16 approximation washed the first
  mission out to white. `render_target_path_d3d12 = "rov"` (Xenia's exact EDRAM emulation) gives
  the console's picture; it is the default in `config/ironbrigade.toml`. Some banding in the smoke.
- Input: keyboard with `--mnk_mode=true` (Enter = Start, Space = A) or an Xbox pad (SDL).
- The add-on is installed to `userdata\0000000000000000\58410A95\00000002\<package>\` (ReXGlue's
  content root is `userdata\`); whether the game lists it was not checked yet (it is unlocked
  later in the campaign).
- Log noise, not fatal: `UPDATE:\` has no device (no title update), `D:\360\Packs\Patch.~h`
  missing (a patch pack the base game probes), `save:\*.sav` missing on the first run,
  `XmaContext: There are no bits to copy!` now and then.

## Native renderer

See `docs/NATIVE_RENDERER.md`: builds and draws the first screens; hangs at the first loading
screen (a GPU fence that never arrives once the renderer is live). Next steps there.

## Not done / ideas

- 60 FPS: the Canary patch's presentation interval byte (`0x82646A83`, 2 -> 1) plus its two
  timing constants; subtitles of prerendered cutscenes end early with it.
- Resolution: native 1280x646 (`li r11,1280` / `li r10,646` at `0x823DBD20`).
