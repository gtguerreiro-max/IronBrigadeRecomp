// --ironbrigade_dump_image=<path>: writes default.xex's loaded image (0x82000000, the size the
// codegen's function table names) to a file right after it is loaded, before any guest code runs.
// tools/find_functions.py reads it to find function starts codegen did not discover.

#include <cstdio>
#include <string>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xmemory.h>

REXCVAR_DEFINE_STRING(ironbrigade_dump_image, "", "IronBrigade",
                      "Write the loaded default.xex image (0x82000000-0x82C50000) to this file");

void DumpImageIfAsked() {
  const std::string path = REXCVAR_GET(ironbrigade_dump_image);
  if (path.empty()) return;
  constexpr uint32_t kBase = 0x82000000, kSize = 0xC50000;
  const auto* data = rex::system::kernel_memory()->TranslateVirtual<const uint8_t*>(kBase);
  if (FILE* f = std::fopen(path.c_str(), "wb")) {
    std::fwrite(data, 1, kSize, f);
    std::fclose(f);
    REXLOG_INFO("image dump: {:08X}+{:X} -> {}", kBase, kSize, path);
  }
}
