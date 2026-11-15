#!/usr/bin/env bash
# Plays Iron Brigade (the Windows build, with ReXNative's native D3D12 renderer) under Proton on
# the Steam Deck. Add this script to Steam as a non-Steam game with NO compatibility tool
# (deck/install.sh does): it starts Proton itself, with a prefix of its own in this folder.
#   play.sh [game flags...]
# IB_PROTON picks another Proton (default: GE-Proton 11, else Valve's Proton 11.0).
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
steam=$HOME/.local/share/Steam
proton=${IB_PROTON:-}
if [[ -z $proton ]]; then
  for p in "$steam"/compatibilitytools.d/GE-Proton11-*/ "$steam/steamapps/common/Proton 11.0/"; do
    [[ -x $p/proton ]] && { proton=${p%/}; break; }
  done
fi
export STEAM_COMPAT_DATA_PATH=$here/prefix STEAM_COMPAT_CLIENT_INSTALL_PATH=$steam
export PROTON_USE_XALIA=0
mkdir -p "$STEAM_COMPAT_DATA_PATH" "$here/logs"
cd "$here"
log=logs/ironbrigade-$(date +%Y%m%d-%H%M%S).log
ls -1t logs/ironbrigade-*.log 2>/dev/null | tail -n +10 | xargs -r rm -f || true
exec "$proton/proton" run "$here/ironbrigade.exe" "--log_file=$log" "$@"
