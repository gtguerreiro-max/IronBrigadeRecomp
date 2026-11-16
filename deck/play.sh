#!/usr/bin/env bash
# Plays Iron Brigade (the Windows build, with ReXNative's native D3D12 renderer) under Proton on
# the Steam Deck. Add this script to Steam as a non-Steam game with NO compatibility tool
# (deck/install.sh does): it starts Proton itself, with a prefix of its own in this folder.
#   play.sh [game flags...]
# IB_PROTON picks another Proton (default: GE-Proton 11, else Valve's Proton 11.0).
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# deck.env beside this script, if present: this Deck's own environment for Proton, one
# VAR=value a line (not in the repository), e.g. PROTON_LOG=1.
if [[ -f $here/deck.env ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$here/deck.env"
  set +a
fi
# FSR 4 on the Deck: GE-Proton fetches AMD's amdxcffx64.dll into the prefix (once), with which the
# FSR SDK 2.4 upscaler runs FSR 4.1 (its RDNA 2 model) instead of FSR 3.1. Used when the upscaler
# is on (F1); PROTON_FSR4_UPGRADE=0 in deck.env leaves FSR 3.1. Valve's Proton ignores it.
export PROTON_FSR4_UPGRADE=${PROTON_FSR4_UPGRADE:-1}
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
# waitforexitandrun, as Steam starts Proton: GE-Proton runs its protonfixes and upscaler setup
# (deck.env's PROTON_FSR4_UPGRADE) only then.
exec "$proton/proton" waitforexitandrun "$here/ironbrigade.exe" "--log_file=$log" "$@"
