# Native D3D12 renderer (PGR4Native + DLSS 5) on Iron Brigade: status and next steps

State on 2026-11-14. The stock ReXGlue renderer (Xenos plugin) plays the game; the native
renderer builds, starts and draws the first screens, then the game hangs at its first loading
screen. Nothing was verified for DLAA / DLSS 5 yet (no 3D scene reaches the native renderer).

## Now: ReXNative's renderer (since 2026-11-14 evening)

The renderer is no longer copied into this port. It is ReXNative's
(https://github.com/gtguerreiro-max/ReXNative, checked out at `F:\ReXNative`): its
`renderer/src/native` (the same renderer, game-neutral), `renderer/src/rexnative_d3d_hooks.cpp`
(the guest D3D hooks, was `src/ib_d3d_trace.cpp`), `renderer/src/hud` (the settings HUD, was
`src/fromdust_settings.*`; `src/ironbrigade_app.h` calls `rexnative::hud::`) and its default
game-side functions (`renderer/src/glue_defaults.cpp`, was `src/native_glue.cpp`, identical).
`CMakeLists.txt` includes `${IRONBRIGADE_REXNATIVE_DIR}/renderer/rexnative.cmake` (default
`../ReXNative`) and calls `rexnative_add(ironbrigade ...)`. Built with `IRONBRIGADE_NATIVE`
(default ON on Windows); off at run time unless `--rexnative=true` (presenter) or
`--rexnative_beside_xenos=true` (debug window beside the Xenos plugin).

Everything specific to Iron Brigade is in `src/rexnative/`: `game_layer.h` (addresses, device
offsets, Resolve arguments and default clear colour, devices, scene) and `d3d_surface.inc` (the
hooked functions), written by ReXNative's tool with `src/rexnative/overrides.json`, plus its
`report.md` and `layer.json`. Regenerate, from `F:\ReXNative`:

    python -m rexnative adapt --generated F:/IronBrigadeRecomp/generated/default --xex F:/IronBrigadeRecomp/game-data/default.xex --name ironbrigade --title "Iron Brigade" --out F:/IronBrigadeRecomp/src/rexnative

The overrides keep what this port ran with before ReXNative:

- `follow_swap_device_only: true`: the game drives a second device while a level loads (below);
  only Swap's reaches the renderer.
- `CreateDevice: null`, `configure_at_first_device: true`: the tool finds CreateDevice at
  `8263E748`, but it is not hooked yet (its second caller `8260DDF8` makes a 640x480 device, a
  likely source of the second device); the device is adopted from the first Swap.
- `RunCommandBuffer: null`: found at `8264EF50` through the PGR4 reference, not hooked yet (next
  step 2 below).
- `scene` and `defaults`: the old values (PGR4's 1280-wide 2x MSAA scene, which happens to match
  Iron Brigade's 1280x646 2x MSAA; frame height 720; occlusion off).

The generated layer's values equal the hand-made layer's (with the `slice` fix); its
`d3d_surface.inc` hooks 124 functions against 83: 42 more pass-through ones (tracing only;
`InsertFence` is the only new push-buffer one) and it leaves out the false
`SetField_10888 -> 82619EB0` entry. The files the port had before are in
`attic/before-rexnative/` (`src/native/`, `src/ib_d3d_trace.cpp`, `src/fromdust_settings.*`,
`src/d3d_surface*.inc`, `src/native_glue.cpp`, the old `CMakeLists.txt` and
`src/ironbrigade_app.h`).

### Result (2026-11-14, PC): the first 3D frames hang the GPU

With ReXNative the warning, logo and "PRESS START" screens are drawn as before, and the HUD opens
(F1, titled "Iron Brigade settings"). The route Enter at 10 and 18 s, Space at 26 s, Enter at
32 s, Space at 38 s (`--rexnative=true --rexnative_replace_draws=false`, windowed)
now passes the title and reaches the first 3D frames: resolves of 320x161, 256x128 and 128x64
images at frame ~356. About 5 s later the GPU hangs: D3D12 `DEVICE_HUNG` (TDR, `887A0006`),
"frame 359 failed; native path off", and the Xenos plugin aborts (its D3D12 device is removed
too; `crash.txt` is its stack). The same happens with r9 = slice and with slice forced to 0
(`resolve_args` override), and, checked by an A/B rebuild of the old files from
`attic/before-rexnative/`, with the old hand-made renderer too. Earlier runs never got past the
loading screen, so this is a pre-existing native-renderer problem newly reached, not a ReXNative
regression. It is the next blocker, before the WAIT_REG_MEM item below.

**Fixed the same evening.** The hang came from the draw arguments. Iron Brigade's LTCG
DrawIndexedVertices (`8264DF88`) has no BaseVertexIndex: `(dev, primitive, start index r5, index
count r6)`, base vertex a constant 0 (`li r17,0` where From Dust has `mr r17,r5`); its
DrawVertices (`8264DB70`) takes only the vertex count, in r5 (start 0). Read in the public
registers (count from r7 / r6), the counts were garbage and the draws long enough for a TDR.
ReXNative's tool now derives every hooked draw's argument registers (`kArgsDrawIndexedVertices =
{3, 4, 0, 5, 6, ...}`, `kArgsDrawVertices = {3, 4, 0, 5, ...}` in `src/rexnative/game_layer.h`)
and the hooks put them in the public order (`PublicRegs`). With that, on the same route the game
plays its intro at a steady 30 FPS for minutes (no TDR, no WAIT_REG_MEM hang): the subtitles are
drawn, the video itself is black. The log said `memexport unsupported (draw skipped)` once, so
the video was first put down to a memexport draw; ReXNative runs those now (its roadmap item 8)
and reads k_DXT5A as BC4, and the video stayed black.

### The intro video (fixed 2026-11-15)

Debugged with ReXNative's draw log (`--rexnative_draw_log_from`), per-draw snapshots
(`draw-debug.txt`, mask 256) and a push-buffer trace (`--rexnative_d3d_control`, `tap on` /
`trace`):

- Bink decodes on the CPU into three k_8 planes (Y 1280x720 at `088A6000`, chroma 640x360) that
  the texture cache re-uploads every frame. The YUV-to-RGB draw (DrawVertices) does produce the
  picture: once into a 1280x720 target, resolved to `08A68000`, and once into the scene target.
- Scaleform's subtitle movie then draws an opaque black rectangle over the whole screen
  (DrawVerticesUP, twips 25600x14400), then the resolved frame `08A68000` as a bitmap: a
  30-index mesh with inline vertices and indices, from **DrawIndexedVerticesUP** (`8264DAD0`,
  which calls **BeginIndexedVertices** `8264D590`). The trace showed that draw with no hooked
  call behind it: ReXNative never drew it, so only the black rectangle and the text were left.
- ReXNative now hooks both (the layer's `kFnBeginIndexedVertices` / `kFnDrawIndexedVerticesUP`,
  found by their place between DrawVerticesUP and DrawVertices) and reads the inline indices.
- The picture was then half as bright as with the stock renderer: the scene target is
  `k_8_8_8_8_GAMMA`, which ReXNative wrote with linear values. It now writes the console's
  piecewise-linear gamma (`--rexnative_gamma_targets`); the frames' average colour matches the
  stock renderer's within 1 %.

## What was done before (hand-made port)

`src/native/` was FromDustDeck's copy of PGR4Native's renderer (branch `dlss`: `dlss.cpp`,
`neural.cpp`, `neural_scene.cpp` are byte-identical to `F:\PGR4Native\src\native`), with FSR 1,
the overlay and the settings menu. `src/ib_d3d_trace.cpp` was FromDustDeck's
`fromdust_d3d_trace.cpp` (the guest D3D hooks). Both are now in `attic/before-rexnative/`.

### Retargeting (tools/, superseded by ReXNative's tool)

Iron Brigade links the same XDK as From Dust (2.0.20353), but the **LTCG** D3D library
(`D3D9LTCG`): functions were inlined, specialised and had arguments reordered.

- `tools/match_d3d_fd.py`: From Dust's hooked functions -> Iron Brigade's, by instruction listing
  (exact, masked, then fuzzy). 66 of 107 matched exactly or masked, 30 fuzzy. Output
  `build/d3dmap_fd.txt`. (`tools/match_d3d.py` does the same from PGR4: 42 of 199.)
- `tools/device_offsets.py`: the device layout is **From Dust's** (vertex stride 12136, index
  buffer 12684, shaders 12940/12944, fences 11036/11024...), so `d3d_state.h` needed no change.
- `tools/retarget_fd.py`: rewrites the addresses in the copied sources and writes
  `src/d3d_surface.inc` (83 functions kept, 21 without a copy dropped).

| Hook | From Dust | Iron Brigade | How |
|---|---|---|---|
| Swap | 820E0AC8 | 82646ED8 | fuzzy 0.84 / 0.28; calls VdSwap |
| DrawIndexedVertices / DrawVertices / DrawVerticesUP | 8250DDA0 / 8250D988 / 8250D940 | 8264DF88 / 8264DB70 / 8264D548 | fuzzy 1.00, 0.99; masked |
| BeginVertices / RestorePush | 8250D480 / 8250D470 | 8264D078 / 8264D538 | masked / exact |
| DrawIndx2Inline / Split | 820EEAD8 / 820E9558 | 82647830 / 82658708 | masked / fuzzy 0.97 |
| Clear / ClearF | 820EFD40 / 820EFC18 | 82648960 / 82648A20 | masked |
| ShaderLoad / immediate VS | 820EB9F0 / 820EB618 | 82651708 / 82651328 | masked / fuzzy 0.97 |
| MakeSpace, Start/SwitchSegment | 820D7D88, 820D70D8, 820D7C00 | 826403C8, 8263F5A0, 8263FF30 | fuzzy 0.96, 0.80, 0.99 |
| Resolve | 820EE9D0 (wrapper) -> 820ED880 | **82649280** (inner, no wrapper) | fuzzy 0.89 / 0.00 |
| CreateDevice, RestoreSegment, Begin/EndTiling, QueryIssue/GetData | ... | **not found** | ids set to `kFnCount` |

- **Resolve**: the game calls the inner function from 8 sites. LTCG dropped the inner
  function's two constant 0 arguments (From Dust's wrapper passes 0 in r6 and r7), which leaves
  exactly the public signature in the same registers: `(dev, flags, src_rect, dest_texture,
  dest_point, level, slice, clear_color; clear_z f1, clear_stencil sp+92, params sp+100)`. r9 is
  `slice` (an earlier version of this note called it "a mask" and passed slice = 0): it is used
  as From Dust's inner Resolve uses its slice (sp+84), null-checked then `andc r4,slice,mask`
  before the same call. Found by matching every argument's uses in the two listings
  (ReXNative, F:\ReXNative: `python -m rexnative validate ironbrigade`). `EntryArgs`
  (ib_d3d_trace.cpp) leaves them as they are. Default clear colour: `0x8202EED0` (16-byte
  vector). A first guess (r7 = level) gave "destination level 1885336848" and heap corruption.
- **CreateDevice** not hooked: the tap adopts the first Swap's device instead. [ReXNative found it at
  `8263E748` (writes 0 to *ppDevice in r8, allocates the 0x6000-byte device, returns
  E_OUTOFMEMORY); its second caller `8260DDF8` creates a 640x480 device when no global one
  exists, a likely source of the second device. Not hooked yet.]
- **Occlusion queries**: hooks not found; `rexnative_occlusion` is off by default anyway.
- **Two devices**: while a level loads, a second device object (main device + 0x6000) is driven
  from another thread [INFERENCE: XDK command buffer recording, replayed by RunCommandBuffer,
  Iron Brigade 0x8264EF50 by the PGR4 match]. The renderer follows one device, and alternating
  between the two corrupted the heap (0xC0000374). Now only Swap's device reaches the renderer;
  calls on another device run the guest function only (`g_main_device`, ib_d3d_trace.cpp).

## Results

- `--rexnative=true --rexnative_replace_draws=false`: D3D12 on the RTX 5060 Ti, HDR10
  swapchain, the warning / logo screens and "PRESS START" are drawn by the native renderer.
- **Blocker: hang at the first loading screen** (the stock renderer goes on to the intro movie).
  Same hang with `--rexnative_beside_xenos=true` (Xenos still draws everything). Host stacks
  (`--ironbrigade_dump_stacks_at=70`, `src/stack_dump.cpp`, symbolised with
  `tools/map_symbolize.py build/game/ironbrigade.map`):
  - render thread: `Swap sub_82646ED8 -> sub_826404C8 -> sub_8263E308`, spinning: the D3D's wait
    for a GPU fence (compares the fence it wants with `*(device+11024)`, the value the GPU
    writes, against the counter at device+11036).
  - the Xenos command processor thread is asleep in a wait inside `rexgpu-xenos.dll`, most likely
    `ExecutePacketType3_WAIT_REG_MEM` on a memory word nobody writes.
  - main thread: waiting in `sub_82371370 -> sub_828E6588`.
  So the GPU stream stops at a WAIT_REG_MEM once the renderer is live. The renderer writes guest
  memory almost nowhere (MarkAllDirty only), so the suspects are its texture write-watches on
  guest physical memory (`TextureCache::ArmWatches`; a CPU or DMA write the game uses as the
  WAIT_REG_MEM's flag landing on a watched page) or the second device's recorded commands.
- Other gaps logged: `memexport unsupported (draw skipped)`, `unsupported format k_DXT5A`
  (both handled since), the title screen's background (a movie / dynamic texture) not drawn,
  the loading screen's background white.

## Next steps, in order

1. Find the WAIT_REG_MEM: add a log line to the SDK's `ExecutePacketType3_WAIT_REG_MEM` (address,
   reference, mask, current value) when it has waited over ~1 s. That needs an SDK build of this
   project's own (`scripts\build.ps1 -Stage sdk`, into `build\`, not FromDustDeck's tree). Then
   find who should write that address (the guest code, `generated/`) and why it does not with
   the renderer live. Try first with the texture cache's watches disabled.
2. Hook RunCommandBuffer (0x8264EF50, check by listing) so the second device's recorded draws
   reach the renderer when they are replayed on the main device (PGR4 had this hook).
3. Find Begin/EndTiling in Iron Brigade (the scene is 1280x646 with 2x MSAA: 13 MB, more than the
   10 MB EDRAM, so it is tiled; LTCG may have inlined them into the Swap/Resolve path).
4. ~~memexport draws, k_DXT5A textures.~~ Done in ReXNative (2026-11-15); the intro video
   needed DrawIndexedVerticesUP and gamma targets instead (above).
5. Then DLAA (`rexnative_upscaler=true`, `rexnative_dlss_mode=dlaa`) and DLSS 5
   (`rexnative_dlss5=true`). DLSS 5 must run on the HDR scene **before** the game's tone mapping
   / colour grading (`rexnative_dlss5_stage = "scene"`); Iron Brigade renders its scene in the
   7e3 (k_2_10_10_10_FLOAT) HDR format, which is that stage. The pass that tone-maps it has to be
   identified (RenderDoc 1.47 is in `F:\FromDustRecomp\third_party\renderdoc_dl`; FromDustDeck's
   `tools/rdoc_*.py` list draws, render targets and shaders).

## Debug aids added here

- `--ironbrigade_dump_image=<file>` (src/image_dump.cpp): the loaded default.xex image.
- `--ironbrigade_dump_stacks_at=<s>` (src/stack_dump.cpp): every thread's host stack to
  `stacks.txt`, six rounds 10 s apart.
- `tools/drive.ps1` (FromDustDeck's): keys and window captures. With no save: Enter at 10 and
  18 s, Space at 26 s (new game, intro movie ~60 s), Space every 10 s from 95 s reaches the first
  mission at ~200 s (stock renderer).
