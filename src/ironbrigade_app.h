// ironbrigade - ReXGlue port of Iron Brigade (XBLA, title 58410A95)

#pragma once

#include <rex/app/title_app.h>

class IronbrigadeApp : public rex::app::TitleApp {
 public:
  IronbrigadeApp();

 protected:
  rex::Result<void> OnConfigure(rex::SettingsRegistry& settings) override;
  rex::Result<void> OnInit() override;
  rex::Result<void> OnTitleLaunch(rex::kernel::TitleRuntime& title) override;
  void OnShutdown() override;
};
