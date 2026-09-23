#!/usr/bin/env bash
# Pictures of the game without a window on anybody's screen. The game runs on a separate hidden
# Windows desktop (tools_scripts/hidden_run.ps1): its window cannot show up, reach the taskbar or
# take the keyboard focus. It is also borderless and far off-screen (override.cfg), and has no
# sound; the 3D frame is rendered into an off-screen 1920x1080 buffer (main.gd, --offscreen) that
# --shot / --shotlist save. For pictures with the interface pass --shot-ui and give the window a
# real size: SHOTS_WINDOW=1920x1080. The game's output is printed when it is done.
#   tools_scripts/shots.sh --screen=menu --shotlist=C:/path/list.json
#   tools_scripts/shots.sh --autotest --shot=C:/path/a.png --shot-at=4 --quit-at=5
#   SHOTS_WINDOW=1920x1080 tools_scripts/shots.sh --screen=worlds --shot-ui --shot=C:/p/ui.png
set -u
cd "$(dirname "$0")/.."
SIZE="${SHOTS_WINDOW:-64x64}"
printf '%s\n' "[display]" "" \
	"window/size/window_width_override=${SIZE%x*}" \
	"window/size/window_height_override=${SIZE#*x}" \
	"window/size/borderless=true" \
	"window/size/no_focus=true" \
	"window/size/initial_position_type=0" \
	"window/size/initial_position=Vector2i(-32000, -32000)" > override.cfg
LOG="$(mktemp -t uadshots.XXXXXX)"
trap 'rm -f override.cfg "$LOG"' EXIT
GODOT="$(cygpath -w "$PWD/tools/Godot_v4.7.2-stable_win64_console.exe")"
powershell -NoProfile -ExecutionPolicy Bypass -File tools_scripts/hidden_run.ps1 \
	-Command "\"$GODOT\" --path . --audio-driver Dummy --position -32000,-32000 -- --offscreen $*" \
	-Log "$(cygpath -w "$LOG")" -Dir "$(cygpath -w "$PWD")" -TimeoutSec "${SHOTS_TIMEOUT:-300}"
code=$?
cat "$LOG"
exit $code
