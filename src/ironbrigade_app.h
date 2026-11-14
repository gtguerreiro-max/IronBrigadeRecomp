// ironbrigade - ReXGlue port of Iron Brigade (XBLA, title 58410A95)

#pragma once

#include <rex/rex_app.h>

#include "crash_report.h"
#if defined(IRONBRIGADE_NATIVE_RENDERER)
#include "hud/hud.h"  // ReXNative's settings HUD
#endif

void DumpImageIfAsked();  // image_dump.cpp
void InstallStackDump();  // stack_dump.cpp

class IronbrigadeApp : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  void OnPostInitLogging() override {
    InstallCrashReport();
    InstallStackDump();
  }
  void OnPostLoadXexImage() override { DumpImageIfAsked(); }

#if defined(IRONBRIGADE_NATIVE_RENDERER)
  // ReXNative's settings HUD (F1 or Back+Start) writes the configuration file.
  void OnConfigurePaths(rex::PathConfig& paths) override {
    rexnative::hud::SetConfigPath(paths.config_path);
  }
  void OnCreateDialogs(rex::ui::ImGuiDrawer*) override { rexnative::hud::Initialize(window()); }
  void OnShutdown() override { rexnative::hud::Shutdown(); }
#endif

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<IronbrigadeApp>(new IronbrigadeApp(ctx, "ironbrigade", PPCImageConfig));
  }
};
