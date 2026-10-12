#!/usr/bin/env bash
# The pictures of the site (docs/img), all taken in the game at UltraMax on the hidden desktop
# (tools_scripts/shots.sh). Takes about three quarters of an hour for everything.
#   tools_scripts/site_shots.sh ui [lang ...] [-- scene ...]   interface scenes, once per language
#                                                              -> docs/img/<lang>/<scene>.webp
#   tools_scripts/site_shots.sh cities                         the four cities without the interface
#   tools_scripts/site_shots.sh battle                         the night raid on the battery
# "cities" and "battle" write candidates into build/site_shots/: look through them and copy the
# good ones into docs/img under the names the page uses (hero, battle-N, kyiv-N, gfx-N …).
set -u
cd "$(dirname "$0")/.."
ROOT="$(cygpath -m "$PWD")"
export SHOTS_RENDERER=forward_plus

ui() {
	local langs=() only=" "
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do langs+=("$1"); shift; done
	[ $# -gt 0 ] && shift
	[ $# -gt 0 ] && only=" $* "
	[ ${#langs[@]} -eq 0 ] && langs=(uk ru en)
	export SHOTS_WINDOW=1920x1080 SHOTS_TIMEOUT=240
	local RL="--autotest --realism --city=kyiv --loc=river --weapons=mg,gepard,osa,patriot --day=8"
	for L in "${langs[@]}"; do
		mkdir -p "docs/img/$L"
		shot() { # name second args...
			local name="$1" at="$2"; shift 2
			if [ "$only" != " " ] && [[ "$only" != *" $name "* ]]; then return; fi
			bash tools_scripts/shots.sh --quality=4 --lang=$L --shot-ui --shot-quality=0.86 \
				--shot="$ROOT/docs/img/$L/$name.webp" --shot-at=$at --quit-at=$((at + 1)) "$@" 2>&1 \
				| grep "screenshot saved\|SCRIPT ERROR\|aborting" | sed "s/^/[$L $name] /" | cut -c1-160
		}
		shot raid 10 --autotest --city=kyiv --loc=river --weapons=mg,zu23,gepard,drone,iris,nasams,patriot --day=8 --fxstage --lockfirst
		shot gunner 6 --autotest --city=kyiv --loc=river --weapons=mg,gepard,iris --weapon=gepard --view=base --aimbot --fxstage
		shot fpv 11 --autotest --city=kyiv --loc=river --weapons=mg,drone --view=fpv --aimbot --fxstage=day
		shot f16 17 --autotest --city=odesa --loc=river --money=90000 --weapons=mg,gepard --f16 --view=fighter --aimbot --fxstage=day
		shot pickup 10 --autotest --city=kharkiv --weapons=mg,gepard --view=mfg --aimbot --fxstage
		shot shop 4 --autotest --city=kyiv --weapons=mg,gepard,drone --money=185000 --day=6 --open=shop
		shot strikes 4 --autotest --city=kyiv --open=strikes --strikedemo
		shot morning 4 --autotest --city=kyiv --open=morning
		shot alarm 8 --autotest --city=dnipro --loc=river --weapons=mg,gepard,iris,patriot --day=7 --fxstage=day --press=L
		shot menu 5 --screen=menu --city=kyiv
		shot map 5 --screen=map --city=odesa
		shot rl_foot 9 $RL --fxstage=day
		shot rl_post 12 $RL --rl-sit=post --fxstage
		shot rl_console 13 $RL --rl-sit=patriot --rl-bot --fxstage
		shot rl_gun 11 $RL --rl-sit=gepard --aimbot --fxstage
		shot rl_supply 5 $RL --rl-sit=post --open=shop
		shot rl_training 6 --screen=training --city=kyiv
		shot touch 6 --autotest --city=kyiv --loc=river --touch --weapons=mg,gepard,iris --weapon=gepard --view=base --aimbot --fxstage
	done
}

# One shot list: lines of name|lat,lon,height|lat,lon,height|night|fov (camera, then what it looks at).
list() {
	local out="$1"; shift
	local first=1
	echo "[" > "$out"
	for e in "$@"; do
		IFS='|' read -r f p l n v <<< "$e"
		[ $first = 1 ] || echo "," >> "$out"
		first=0
		echo "{\"file\":\"$ROOT/build/site_shots/$f.webp\",\"quality\":0.88,\"ll\":true,\"pos\":[$p],\"look\":[$l],\"night\":$n,\"fov\":$v}" >> "$out"
	done
	echo "]" >> "$out"
}

cities() {
	mkdir -p build/site_shots
	export SHOTS_TIMEOUT=600
	local T="$ROOT/build/site_shots"
	list "$T/kyiv.json" \
		"kyiv-lavra|50.4300,30.5660,170|50.4346,30.5571,45|0|50" "kyiv-maidan-night|50.4462,30.5300,230|50.4505,30.5225,25|1|55" \
		"kyiv-aerial|50.395,30.605,2600|50.452,30.530,0|0|50" "kyiv-motherland|50.4228,30.5712,150|50.4266,30.5630,75|0|50" \
		"kyiv-bridges|50.4350,30.5720,200|50.4440,30.5600,15|0|55" "kyiv-podil-night|50.4680,30.5080,150|50.4660,30.5170,25|1|55"
	list "$T/kharkiv.json" \
		"kharkiv-centre|49.9960,36.2420,220|50.0040,36.2310,30|0|55" "kharkiv-night|49.9850,36.2130,180|49.9905,36.2218,30|1|55" \
		"kharkiv-opera|49.9990,36.2430,90|50.0000,36.2360,25|0|55"
	list "$T/dnipro.json" \
		"dnipro-river|48.4700,35.0800,120|48.4640,35.0560,20|0|55" "dnipro-arena-night|48.4570,35.0250,180|48.4603,35.0325,20|1|55" \
		"dnipro-city|48.4560,35.0700,260|48.4700,35.0450,10|0|55" "dnipro-aerial|48.42,35.10,2400|48.47,35.04,0|0|50"
	list "$T/odesa.json" \
		"odesa-centre|46.4832,30.7372,110|46.4853,30.7411,22|0|50" "odesa-night|46.4800,30.7520,160|46.4860,30.7430,20|1|55" \
		"odesa-port|46.4930,30.7480,60|46.4878,30.7462,15|0|60" "odesa-sea|46.4920,30.7560,200|46.4855,30.7420,15|0|55"
	for c in kyiv kharkiv dnipro odesa; do
		bash tools_scripts/shots.sh --quality=4 --screen=menu --city=$c --shotlist="$T/$c.json" 2>&1 | grep "UAD SHOT\|SCRIPT ERROR" | cut -c1-140
	done
}

# Camera and target are offsets from the battery; "hold" waits for the staged raid (--fxstage).
battle() {
	mkdir -p build/site_shots
	export SHOTS_TIMEOUT=500
	local T="$ROOT/build/site_shots" first=1
	echo "[" > "$T/battle.json"
	for e in "-90,12,60|200,180,-100|70|5" "-160,60,120|150,220,-80|65|2" "-40,5,35|30,40,-15|60|2.5" "-400,220,350|100,200,-50|60|3" \
		"-120,30,0|300,250,0|65|2.5" "-600,700,600|0,100,0|55|3" "-30,3,50|10,14,0|60|2.5" "-250,90,200|200,300,-100|65|3" \
		"-90,12,60|200,180,-100|70|4" "-160,60,120|150,220,-80|65|3"; do
		IFS='|' read -r p l v h <<< "$e"
		[ $first = 1 ] || echo "," >> "$T/battle.json"
		echo "{\"file\":\"$T/battle-$first.webp\",\"quality\":0.88,\"base\":true,\"pos\":[$p],\"look\":[$l],\"fov\":$v,\"hold\":$h}" >> "$T/battle.json"
		first=$((first + 1))
	done
	echo "]" >> "$T/battle.json"
	bash tools_scripts/shots.sh --quality=4 --autotest --city=kyiv --loc=river --fxstage --nomarkers \
		--weapons=mg,zu23,gepard,shilka,drone,osa,iris,nasams,patriot --shotlist="$T/battle.json" 2>&1 | grep "UAD SHOT\|SCRIPT ERROR" | cut -c1-140
}

what="${1:-}"
[ $# -gt 0 ] && shift
case "$what" in
	ui) ui "$@" ;;
	cities) cities ;;
	battle) battle ;;
	*) sed -n 2,9p "$0" ;;
esac
