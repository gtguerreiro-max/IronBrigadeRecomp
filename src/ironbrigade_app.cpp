// ironbrigade - ReXGlue port of Iron Brigade (XBLA, title 58410A95)

#include "ironbrigade_app.h"

#include <cstdio>
#include <filesystem>
#include <string>

#include <rex/kernel/guest_memory.h>
#include <rex/kernel/title_runtime.h>
#include <rex/logging/log_category.h>
#include <rex/setting.h>
#include <rex/settings_registry.h>

#include "generated/default/ironbrigade_init.h"
#if defined(IRONBRIGADE_NATIVE_RENDERER)
#include "host.h"     // ReXNative's connection to the app
#include "hud/hud.h"  // ReXNative's settings HUD
#endif

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace {

// The folder of the executable: the game's files (game\), and the player's data and the add-on
// (userdata\) are beside it.
std::filesystem::path ExeDir() {
  wchar_t path[MAX_PATH];
  const DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
  return std::filesystem::path(std::wstring(path, n)).parent_path();
}

// --ironbrigade.dump_image=<path>: default.xex's loaded image (0x82000000, the size the codegen's
// function table names), written right after it is loaded, before any guest code runs.
// tools/find_functions.py reads it to find function starts codegen did not discover.
class IronbrigadeSettings final : public rex::SettingOwner {
 public:
  IronbrigadeSettings() : SettingOwner("ironbrigade") {}
  REX_SETTING(std::string, dump_image, "",
              "Write the loaded default.xex image (0x82000000-0x82C50000) to this file");
};
IronbrigadeSettings& Settings() {
  static IronbrigadeSettings* settings = new IronbrigadeSettings;
  return *settings;
}

}  // namespace

IronbrigadeApp::IronbrigadeApp() : TitleApp("ironbrigade", kPPCImageConfig) {}

rex::Result<void> IronbrigadeApp::OnConfigure(rex::SettingsRegistry& settings) {
  if (auto r = settings.Register(Settings()); !r) return r;
  settings.AddAlias("ironbrigade_dump_image", "ironbrigade.dump_image");
#if defined(IRONBRIGADE_NATIVE_RENDERER)
  rexnative::host::Configure();
#endif
  const std::filesystem::path dir = ExeDir();
  std::error_code ec;
  if (std::filesystem::is_directory(dir / "game", ec))
    (void)settings.SetText(rex::SettingLayer::kTitle, "title.game_root", (dir / "game").string());
  (void)settings.SetText(rex::SettingLayer::kTitle, "app.user_root", (dir / "userdata").string());
  return TitleApp::OnConfigure(settings);
}

rex::Result<void> IronbrigadeApp::OnInit() {
  if (auto r = TitleApp::OnInit(); !r) return r;
#if defined(IRONBRIGADE_NATIVE_RENDERER)
  rexnative::host::Attach(*this);
  rexnative::hud::Initialize();
#endif
  return {};
}

rex::Result<void> IronbrigadeApp::OnTitleLaunch(rex::kernel::TitleRuntime& title) {
  if (const std::string path = Settings().dump_image.Get(); !path.empty()) {
    constexpr uint32_t kBase = 0x82000000, kSize = 0xC50000;
    auto image = title.GetGuestMemory().GetReadOnlySpan(kBase, kSize);
    if (std::FILE* f = image ? std::fopen(path.c_str(), "wb") : nullptr) {
      std::fwrite(image->data(), 1, image->size(), f);
      std::fclose(f);
      REXLOG_INFO("image dump: {:08X}+{:X} -> {}", kBase, kSize, path);
    }
  }
  return TitleApp::OnTitleLaunch(title);
}

void IronbrigadeApp::OnShutdown() {
#if defined(IRONBRIGADE_NATIVE_RENDERER)
  rexnative::hud::Shutdown();
  rexnative::host::Detach();
#endif
  TitleApp::OnShutdown();
}
