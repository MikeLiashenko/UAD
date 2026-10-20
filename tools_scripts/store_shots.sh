#!/usr/bin/env bash
# Google Play screenshots: what a tablet or phone really shows — the Compatibility renderer at the
# best Android graphics level (--quality=2) with the touch controls — once per language, on the
# hidden desktop (tools_scripts/shots.sh). 1920x1080 JPEG, no alpha: Play takes the same files
# for phones and for 7" and 10" tablets. About 40 s a scene.
#   tools_scripts/store_shots.sh [lang ...] [-- scene ...]   -> store/graphics/<lang>/NN_<scene>.jpg
set -u
cd "$(dirname "$0")/.."
ROOT="$(cygpath -m "$PWD")"
export SHOTS_WINDOW=1920x1080 SHOTS_TIMEOUT=240
langs=() only=" "
while [ $# -gt 0 ] && [ "$1" != "--" ]; do langs+=("$1"); shift; done
[ $# -gt 0 ] && shift
[ $# -gt 0 ] && only=" $* "
[ ${#langs[@]} -eq 0 ] && langs=(uk ru en)
RL="--autotest --realism --city=kyiv --loc=river --weapons=mg,gepard,osa,patriot --day=8"
for L in "${langs[@]}"; do
	mkdir -p "store/graphics/$L"
	shot() { # name second args...
		local name="$1" at="$2"; shift 2
		if [ "$only" != " " ] && [[ "$only" != *" ${name#*_} "* ]]; then return; fi
		bash tools_scripts/shots.sh --quality=2 --lang=$L --touch --shot-ui --shot-quality=0.92 \
			--shot="$ROOT/store/graphics/$L/$name.jpg" --shot-at=$at --quit-at=$((at + 1)) "$@" 2>&1 \
			| grep "screenshot saved\|SCRIPT ERROR\|aborting" | sed "s/^/[$L $name] /" | cut -c1-160
	}
	shot 01_raid 10 --autotest --city=kyiv --loc=river --weapons=mg,zu23,gepard,drone,iris,nasams,patriot --day=8 --fxstage --lockfirst
	shot 02_gunner 6 --autotest --city=kyiv --loc=river --weapons=mg,gepard,iris --weapon=gepard --view=base --aimbot --fxstage
	shot 03_fpv 11 --autotest --city=kyiv --loc=river --weapons=mg,drone --view=fpv --aimbot --fxstage=day
	shot 04_f16 17 --autotest --city=odesa --loc=river --money=90000 --weapons=mg,gepard --f16 --view=fighter --aimbot --fxstage=day
	shot 05_pickup 10 --autotest --city=kharkiv --weapons=mg,gepard --view=mfg --aimbot --fxstage
	shot 06_alarm 8 --autotest --city=dnipro --loc=river --weapons=mg,gepard,iris,patriot --day=7 --fxstage=day --press=L
	shot 07_realism 13 $RL --rl-sit=patriot --rl-bot --fxstage
	shot 08_shop 4 --autotest --city=kyiv --weapons=mg,gepard,drone --money=185000 --day=6 --open=shop
done
