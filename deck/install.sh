#!/usr/bin/env bash
# Finishes an Iron Brigade install on the Steam Deck (run on the Deck, as the deck user), in the
# folder that holds this script, ironbrigade.exe and its DLLs, and the game's data in game/:
#   install.sh
# Puts deck/ironbrigade.toml beside the game as its settings (keeping an existing one), makes
# play.sh runnable and adds "Iron Brigade" to Steam's library as a non-Steam game that runs
# play.sh with no compatibility tool, with the artwork in art/ if there is one. Steam must not be
# running: it rewrites its shortcuts file when it exits (in Game Mode, close it from a desktop
# session or over SSH with `steam -shutdown`; Game Mode starts it again).
set -euo pipefail
dest=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ -e $dest/ironbrigade.exe ]] || { echo "no ironbrigade.exe in $dest" >&2; exit 1; }
[[ -e $dest/game/default.xex ]] || { echo "no game data: put the game's files in $dest/game" >&2; exit 1; }
[[ -e $dest/ironbrigade.toml ]] || cp "$dest/ironbrigade-deck.toml" "$dest/ironbrigade.toml"
chmod +x "$dest/play.sh"
echo "installed in $dest"
if pgrep -x steam >/dev/null; then
  echo "Steam is running: not adding the shortcut (run again with Steam closed)"
  exit 0
fi
art=()
[[ -d $dest/art ]] && art=(--art-dir "$dest/art")
python3 "$dest/steam_shortcuts.py" add "Iron Brigade" "$dest/play.sh" --start-dir "$dest" "${art[@]}"
