extends Node
## Multiplayer through the Firebase Realtime Database (autoload "Net").
##
## Every player has a friend code. The multiplayer tab lists the friends added by code (or by
## nick, when the friend has an account): online or not, and the world they have opened. A guest knocks with a join request, the host accepts or
## declines it in their game, and from then on everyone in the session sees each other — bases
## with name tags, where each camera is looking — and can watch through a friend's eyes — and
## defends the city against one shared raid.
##
## Database layout (under ROOT):
##   users/<code>             {n: nick, t: heartbeat, s: menu|game|host|guest, w: open world}
##   requests/<host>/<guest>  {n, t, p: protocol, st: wait|ok|no|full|version|timeout, w, s}
##   sessions/<host>/<code>   {n, s: slot, t, b: [x, z, loc], c: [px, py, pz, qx, qy, qz, qw],
##                             f: fov, v: view, p: ping, h: {enemy: damage dealt so far},
##                             m: [[seq, weapon, x, y, z, enemy], …] missiles launched lately}
##   sessions/<host>/raid     the host's raid, RAID_EVERY: phase and clock, every threat in the
##                             air, kills and impacts of the last seconds, each player's earnings
##   sessions/<host>/map      damaged / collapsed buildings and blackouts (when they change)
## One raid for everybody: the host simulates the threats, guests fly "puppets" that follow the
## snapshots (dead reckoning + smoothing) and report the damage they deal; the host applies it
## and credits the kill to whoever brought the target down.
## "t" is always the server's clock.
##
## Two ways to be somebody: by default a player is just the code kept on this device; an optional
## account (Account, Firebase Authentication: email + password) owns a code and a unique nick and
## keeps the friend list in the cloud, the same on every device. Requests then carry the account's
## ID token (?auth=) and the rules let nobody else write as that code — see
## firebase/database.rules.json.

const FbDb = preload("res://scripts/core/fb_db.gd")
const FbStream = preload("res://scripts/core/fb_stream.gd")
const FbConn = preload("res://scripts/core/fb_conn.gd")
const BuildInfo = preload("res://scripts/build_info.gd")
const Account = preload("res://scripts/core/account.gd")
## The Firebase Web API key (accounts) lives in this file, kept out of the public repository:
##   const FIREBASE_WEB_KEY := "AIza..."
## Without it the game runs on friend codes only.
const KEYS_PATH := "res://scripts/keys.gd"

## Friends' online state refreshed (friend_info).
signal friends_changed
## Host: somebody knocks. The HUD shows Accept / Decline.
signal join_requested(code: String, nick: String)
## Host: a request went away without an answer (timeout, the guest cancelled).
signal request_closed(code: String)
## Guest: the request reached the database and waits for the host.
signal request_sent
## Guest: the host answered. info is the world on accept, {"reason": code} otherwise.
signal join_answered(ok: bool, info: Dictionary)
## Guest: the request could not be sent at all.
signal connect_failed(reason: String)
signal player_joined(nick: String)
signal player_left(nick: String)
## Guest: the host closed the world or the connection was lost.
signal session_ended(reason: String)
## Guest: a new raid snapshot / buildings state from the host.
signal raid_received(raid: Dictionary)
signal map_received(state: Dictionary)
## Host: a guest's running totals of damage dealt, enemy id -> damage.
signal guest_hits(code: String, totals: Dictionary)
## Another player's recent missile launches (drawn, they do no damage here).
signal launches_received(code: String, list: Array)
## The newest published build arrived from the database (uad/release).
signal release_checked(info: Dictionary)
## Signed in or out of the account, or its nick / friends changed.
signal account_changed

const DB_URL := "https://dream-journal-93835-default-rtdb.firebaseio.com"
## Updates are only ever downloaded from here (see update_url).
const RELEASES_URL := "https://github.com/MikeLiashenko/UAD/releases/"
const SITE_URL := "https://mikeliashenko.github.io/UAD/"
const ROOT := "uad/v1"
const MAX_PLAYERS := 4
const PROTO := 1
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 8
## Presence writes: camera and base while playing, a heartbeat only while choosing a position.
const STATE_EVERY := 0.2
const IDLE_STATE_EVERY := 1.0
const USER_EVERY := 15.0
const HOST_USER_EVERY := 5.0
const FRIENDS_EVERY := 3.0
## A session entry older than this belongs to a player who crashed or lost the connection.
const STALE_MS := 12000
## A friend whose heartbeat is older than this is shown offline.
const ONLINE_MS := 40000
const REQUEST_TIMEOUT := 30.0
## A guest whose session stream stays down this long gives up.
const LOST_AFTER := 20.0
## Raid snapshots: 4 a second while threats are in the air (one kept-alive connection answers
## ~5.8 requests a second), one a second when the sky is empty.
const RAID_EVERY := 0.25
const IDLE_RAID_EVERY := 1.0
const MAP_EVERY := 1.0
const COLORS := [
	Color(0.2, 1.0, 0.65), Color(0.35, 0.8, 1.0), Color(1.0, 0.55, 0.9), Color(1.0, 0.78, 0.3),
]

## "" (single player), "host", "joining" (request waiting for the answer) or "guest".
var role := ""
## Friend code of the session's host (our own while hosting).
var host := ""
## Everyone in the session, us included: code -> {nick, color, slot, base, has_base, loc, cam,
## fov, view, ping}.
var players := {}
## Host: requests waiting for an answer, code -> {nick, t}.
var pending := {}
## Guest: the world the host described when accepting.
var world := {}
## Friends as last seen in the database: code -> {online, nick, s, w, ping}.
var friend_info := {}
## The root node (main.gd): whether a game is running, day or night.
var main
## The newest published build: {build, version, date, exe, apk, site, notes}; {} until known.
var release := {}

var db: FbDb
## Optional player account (nick, cloud friends, one identity on every device).
var account: Account
## The code our presence was last written under (signing in or out switches it).
var _presence_code := ""
## The code of the friend added last (the list selects it).
var last_added := ""
## Kept-alive connections: our presence (both roles) and the raid + map (host).
var conn: FbConn
var conn_raid: FbConn
## Guest: the latest raid snapshot, how many arrive a second and how old they are on arrival.
var raid := {}
var map_state := {}
var raid_hz := 0.0
var raid_lag := 0.0
var _raid_rx := -1.0
var _raid_t := 0.0
var _map_t := 0.0
var _map_sig := ""
var _raid_seq := 0
## Extra fields sent with our presence (damage totals, launches) and what was last seen of others.
var _extra := {}
var _seen_obj := {}
var _session: FbStream
var _requests: FbStream
var _clock := 0.0
var _state_t := 0.0
var _user_t := 999.0
var _friends_t := 999.0
var _lost_t := 0.0
var _watch_friends := false
var _local := {}
## Host: requests already answered (the answer stays in the database until the guest reads it).
var _answered := {}
## Host: when each guest was let in (their session entry takes a moment to appear).
var _accepted_at := {}
## Guest: when the request was sent, and whether it has been seen waiting in the database.
var _join_t := 0.0
var _req_seen := false
var _host_seen := false
## --mpid=CODE test hook: a second copy of the game on the same computer plays as someone else.
var _code_override := ""
## Self-test: settings changed here stay in memory and are never written to disk.
var dry := false
## Leaving for good (the test quits): no more heartbeats that would bring our entry back.
var quiet := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	db = FbDb.new()
	db.base_url = "%s/%s" % [DB_URL, ROOT]
	add_child(db)
	conn = FbConn.new()
	conn.base_url = db.base_url
	add_child(conn)
	conn_raid = FbConn.new()
	conn_raid.base_url = db.base_url
	add_child(conn_raid)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--mpid="):
			_code_override = parse_code(String(a).substr(7))
	account = Account.new()
	add_child(account)
	account.setup(_web_key(), db, _save)
	account.auth.token_changed.connect(_on_token)
	account.changed.connect(_on_account)


func _web_key() -> String:
	if not ResourceLoader.exists(KEYS_PATH):
		return ""
	var s = load(KEYS_PATH)
	return String(s.get("FIREBASE_WEB_KEY")) if s != null and s.get("FIREBASE_WEB_KEY") != null else ""


## The account's ID token goes with every request from now on ("" once signed out).
func _on_token(token: String) -> void:
	db.auth = token
	conn.auth = token
	conn_raid.auth = token


func _on_account() -> void:
	# signing in or out changes who we are: the old code's presence goes, friends are read again
	var c := code()
	if _presence_code != "" and _presence_code != c:
		db.delete("users/" + _presence_code)
		_presence_code = ""
	friend_info.clear()
	_friends_t = FRIENDS_EVERY
	_user_t = 999.0
	account_changed.emit()
	friends_changed.emit()


## Self-test: nothing reaches the network (every request fails at once, streams stay idle).
func set_offline() -> void:
	db.base_url = ""
	conn.base_url = ""
	conn_raid.base_url = ""


## The database's clock (ms) as far as this machine can tell: the kept-alive connection learns
## the offset from every presence write.
func server_now() -> int:
	var off := conn.server_offset if conn.has_offset else db.server_offset
	return int(Time.get_unix_time_from_system() * 1000.0) + off


## Asks the database for the newest published build (build.ps1 -Publish writes uad/release).
func check_release() -> void:
	if db.base_url == "":
		return
	var r := HTTPRequest.new()
	r.timeout = 10.0
	add_child(r)
	r.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		r.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var d = JSON.parse_string(body.get_string_from_utf8())
		if d is Dictionary and (d as Dictionary).has("build"):
			release = d
			release_checked.emit(d))
	if r.request("%s/uad/release.json" % DB_URL) != OK:
		r.queue_free()


## A newer build than this one has been published.
func update_available() -> bool:
	return int(float(release.get("build", 0))) > BuildInfo.BUILD


## Where this platform gets the new build: the .apk on Android, the .exe on Windows. The record in
## the database only picks the file: a link that leads anywhere but this game's GitHub releases
## (or its site) is replaced by the site, so a forged record cannot hand players a strange .exe.
func update_url() -> String:
	var key := "site"
	if OS.get_name() == "Android":
		key = "apk"
	elif OS.get_name() == "Windows":
		key = "exe"
	var url := String(release.get(key, ""))
	return url if url.begins_with(RELEASES_URL) else SITE_URL


## The game's site; the link from the database only when it is that site.
func site_url() -> String:
	var url := String(release.get("site", ""))
	return url if url.begins_with(SITE_URL) else SITE_URL


## Connection quality for the player list: round trip to the database, raid snapshots a second
## and their age on arrival (guests).
func quality() -> Dictionary:
	return {"rtt": int(conn.rtt_avg), "hz": raid_hz, "lag": int(raid_lag)}


func _save() -> void:
	if not dry:
		GS.save_settings()


# --- Identity ---------------------------------------------------------------------------------
## This player's friend code: the account's while signed in, otherwise this device's.
func code() -> String:
	if _code_override != "":
		return _code_override
	if account != null and account.active():
		return account.code
	return device_code()


## The device's own code (8 characters, generated once and kept in the settings).
func device_code() -> String:
	var c := String(GS.settings.get("mp_code", ""))
	if parse_code(c) == "":
		c = new_code()
		GS.settings["mp_code"] = c
		_save()
	return c


static func new_code() -> String:
	var c := ""
	for i in CODE_LEN:
		c += CODE_CHARS[randi() % CODE_CHARS.length()]
	return c


## "ABCD-EFGH" for showing and dictating.
static func fmt_code(c: String) -> String:
	return c.substr(0, 4) + "-" + c.substr(4) if c.length() == CODE_LEN else c


## Normalizes a typed code ("abcd efgh", "ABCD-EFGH"); "" when it is not a valid code.
static func parse_code(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if CODE_CHARS.contains(ch):
			out += ch
		elif ch != "-" and ch != " ":
			return "" # 0 / O / 1 / I are left out of codes on purpose: they are easy to mix up
	return out if out.length() == CODE_LEN else ""


func nick() -> String:
	if account != null and account.active() and account.nick != "":
		return account.nick
	var n := String(GS.settings.get("nick", "")).strip_edges()
	return n.substr(0, 16) if n != "" else GS.t("Игрок %s") % code().substr(0, 4)


static func _clean_nick(v) -> String:
	var n := String(v if v != null else "").strip_edges().substr(0, 16)
	return n if n != "" else GS.t("Игрок")


func is_online() -> bool:
	return role == "host" or role == "guest"


## Codes of the other players in the session.
func others() -> Array:
	var me := code()
	return players.keys().filter(func(c) -> bool: return String(c) != me)


## Multiplayer switched on: from now on the game keeps a heartbeat so friends see us online.
func _enable() -> void:
	if not bool(GS.settings.get("mp", false)):
		GS.settings["mp"] = true
		_save()


# --- Friends ------------------------------------------------------------------------------------
## Friends as [{code, name}]: the account's list while signed in, otherwise this device's.
func friends() -> Array:
	if account != null and account.active():
		return account.friends.duplicate()
	return device_friends()


func device_friends() -> Array:
	var out := []
	for f in GS.settings.get("friends", []):
		if f is Dictionary and parse_code(String(f.get("code", ""))) != "":
			out.append(f)
	return out


## Adds a friend by code — or by nick, when the friend has an account. cb(ok: bool, text: String)
## gets the friend's nick on success or the reason on failure; the code lands in last_added.
func add_friend(typed: String, cb: Callable) -> void:
	var text := typed.strip_edges()
	var c := parse_code(text)
	if c != "" and c == code():
		cb.call(false, GS.t("Это ваш собственный код"))
		return
	_enable()
	if c == "":
		if Account.check_nick(text) != "":
			cb.call(false, GS.t("Введите код друга (8 символов, например %s) или его ник") % fmt_code("K7MQ4XRT"))
		else:
			_add_by_nick(text, cb)
		return
	db.get_value("users/" + c, func(ok: bool, d) -> void:
		if not ok:
			cb.call(false, GS.t("Нет связи с сервером"))
		elif d is Dictionary:
			_added(c, _clean_nick(d.get("n")), cb)
		elif Account.check_nick(text) == "":
			_add_by_nick(text, cb) # eight letters that look like a code can still be a nick
		else:
			cb.call(false, GS.t("Игрок с таким кодом не найден")))


func _add_by_nick(n: String, cb: Callable) -> void:
	account.lookup(n, func(ok: bool, info) -> void:
		if not ok:
			cb.call(false, GS.t("Нет связи с сервером"))
		elif info == null:
			cb.call(false, GS.t("Игрока с ником «%s» нет. Ник есть только у игроков с аккаунтом — попросите код.") % n)
		elif String(info.c) == code():
			cb.call(false, GS.t("Это ваш собственный ник"))
		else:
			_added(String(info.c), _clean_nick(info.get("n", n)), cb))


func _added(c: String, n: String, cb: Callable) -> void:
	_remember_friend(c, n)
	last_added = c
	_friends_t = FRIENDS_EVERY
	cb.call(true, n)


func _remember_friend(c: String, n: String) -> void:
	if c == "" or c == code():
		return
	if account != null and account.active():
		account.add_friend(c, n)
		return
	var list := device_friends().filter(func(f) -> bool: return String(f.code) != c)
	list.append({"code": c, "name": n})
	GS.settings["friends"] = list
	_save()


func remove_friend(c: String) -> void:
	if account != null and account.active():
		account.remove_friend(c)
	else:
		GS.settings["friends"] = device_friends().filter(func(f) -> bool: return String(f.code) != c)
		_save()
	friend_info.erase(c)
	friends_changed.emit()


## The multiplayer tab asks for friends' state while it is open.
func watch_friends(on: bool) -> void:
	_watch_friends = on
	if on:
		_enable()
		_friends_t = FRIENDS_EVERY
		_user_t = 999.0
		account.sync()


# --- Account -------------------------------------------------------------------------------------
## Accounts work in this build (the Firebase key is in).
func accounts_enabled() -> bool:
	return account != null and account.enabled()


## cb(ok: bool, text: String) for all of these; text says why when it failed.
func register(n: String, mail: String, password: String, cb: Callable) -> void:
	account.register(n, mail, password, code(), device_friends(), cb)


func login(mail: String, password: String, cb: Callable) -> void:
	account.login(mail, password, code(), device_friends(), cb)


## Signs out: this device's own code, nick and friends come back.
func logout() -> void:
	close()
	if account.active():
		db.delete("users/" + account.code) # sent while the token is still on: only we may do it
	_presence_code = ""
	account.logout()


func rename(n: String, cb: Callable) -> void:
	account.rename(n, cb)


func reset_password(mail: String, cb: Callable) -> void:
	account.reset_password(mail, cb)


func delete_account(password: String, cb: Callable) -> void:
	close()
	account.delete_account(password, cb)


func _poll_friends() -> void:
	for f in friends():
		var c := String(f.code)
		db.get_value("users/" + c, func(ok: bool, d) -> void:
			if not ok or not friends().any(func(x) -> bool: return String(x.code) == c):
				return
			var info := {"online": false, "nick": String(f.name), "s": "", "w": {}, "ping": db.rtt}
			if d is Dictionary:
				info.nick = _clean_nick(d.get("n", f.name))
				info.online = db.server_now() - int(float(d.get("t", 0))) < ONLINE_MS
				info.s = String(d.get("s", ""))
				if info.online and info.s == "host" and d.get("w") is Dictionary:
					info.w = d.w
				if info.nick != String(f.name):
					_remember_friend(c, info.nick)
			friend_info[c] = info
			friends_changed.emit())


func _heartbeat() -> void:
	var s := "menu"
	if role == "host" or role == "guest":
		s = role
	elif main != null and main.game != null and is_instance_valid(main.game):
		s = "game"
	var d := {"n": nick(), "t": FbDb.now_placeholder(), "s": s}
	if role == "host":
		d["w"] = _world_info()
	_presence_code = code()
	db.put("users/" + _presence_code, d)


# --- Hosting -------------------------------------------------------------------------------------
## Opens the running world to friends.
func open_world() -> void:
	if role != "":
		return
	_enable()
	role = "host"
	host = code()
	players = {host: _player(nick(), 0)}
	pending.clear()
	_answered.clear()
	# a fresh session: whatever a crashed earlier one left behind is wiped
	db.put("sessions/" + host, {host: {"n": nick(), "s": 0, "t": FbDb.now_placeholder()}})
	db.delete("requests/" + host)
	_requests = _stream("requests/" + host)
	_requests.changed.connect(_on_requests)
	_session = _stream("sessions/" + host)
	_session.changed.connect(_on_session)
	_user_t = 999.0


func _world_info() -> Dictionary:
	var night := false
	if main != null and main.game != null and is_instance_valid(main.game) and main.game.director != null:
		night = main.game.director.is_night()
	return {"n": nick(), "world": GS.world_name, "city": GS.city_id, "day": GS.day, "night": night,
		"difficulty": GS.difficulty, "players": players.size(), "max": MAX_PLAYERS, "p": PROTO,
		"base": [snappedf(GS.base_pos.x, 0.1), snappedf(GS.base_pos.z, 0.1)]}


func _player(n: String, slot: int) -> Dictionary:
	return {"nick": n, "color": COLORS[slot % COLORS.size()], "slot": slot, "base": Vector3.ZERO,
		"has_base": false, "loc": 0, "cam": Transform3D.IDENTITY, "has_cam": false, "cam_t": 0,
		"cam_vel": Vector3.ZERO, "fov": 62.0, "view": "", "ping": 0}


func _free_slot() -> int:
	var used := {}
	for c in players:
		used[int(players[c].slot)] = true
	for s in MAX_PLAYERS:
		if not used.has(s):
			return s
	return -1


func _on_requests() -> void:
	if role != "host":
		return
	var d = _requests.data
	var reqs: Dictionary = d if d is Dictionary else {}
	for c in reqs:
		var r = reqs[c]
		if not (r is Dictionary) or String(r.get("st", "")) != "wait":
			continue
		if _answered.has(c) or pending.has(c) or parse_code(String(c)) == "":
			continue
		if int(r.get("p", 0)) != PROTO:
			_reply(c, "version")
		elif players.size() >= MAX_PLAYERS:
			_reply(c, "full")
		else:
			var n := _clean_nick(r.get("n"))
			pending[c] = {"nick": n, "t": _clock}
			join_requested.emit(c, n)
	# withdrawn by the guest
	for c in pending.keys():
		if not reqs.has(c) or not (reqs[c] is Dictionary) or String(reqs[c].get("st", "")) != "wait":
			pending.erase(c)
			request_closed.emit(c)


func _reply(c: String, st: String, extra := {}) -> void:
	_answered[c] = true
	var d := {"st": st}
	d.merge(extra)
	db.patch("requests/%s/%s" % [host, c], d)


func accept(c: String) -> void:
	if role != "host" or not pending.has(c):
		return
	var n := String(pending[c].nick)
	pending.erase(c)
	var slot := _free_slot()
	if slot < 0:
		_reply(c, "full")
		return
	players[c] = _player(n, slot)
	_accepted_at[c] = _clock
	_map_sig = "" # the newcomer gets the buildings as they are now
	db.put("sessions/%s/%s" % [host, c], {"n": n, "s": slot, "t": FbDb.now_placeholder()})
	_reply(c, "ok", {"w": _world_info(), "s": slot})
	_remember_friend(c, n)
	_user_t = 999.0
	player_joined.emit(n)


func decline(c: String) -> void:
	if pending.has(c):
		pending.erase(c)
		_reply(c, "no")


# --- Joining --------------------------------------------------------------------------------------
func request_join(host_code: String) -> void:
	close()
	_enable()
	role = "joining"
	host = host_code
	_join_t = _clock
	_req_seen = false
	_host_seen = false
	var path := "requests/%s/%s" % [host, code()]
	db.put(path, {"n": nick(), "t": FbDb.now_placeholder(), "p": PROTO, "st": "wait"}, func(ok: bool, _d) -> void:
		if role != "joining" or host != host_code:
			return
		if ok:
			request_sent.emit()
		else:
			_drop()
			connect_failed.emit(GS.t("Нет связи с сервером. Проверьте интернет.")))
	_requests = _stream(path)
	_requests.changed.connect(_on_my_request)


func _on_my_request() -> void:
	if role != "joining":
		return
	var r = _requests.data
	if not (r is Dictionary):
		if _req_seen:
			_give_up("closed") # the host closed the world and wiped the requests
		return
	_req_seen = true
	var st := String(r.get("st", "wait"))
	if st == "wait":
		return
	if st != "ok":
		_give_up(st)
		return
	world = r.get("w", {}) if r.get("w") is Dictionary else {}
	role = "guest"
	players = {code(): _player(nick(), int(r.get("s", 1)))}
	_close_stream(_requests)
	_requests = null
	db.delete("requests/%s/%s" % [host, code()])
	_session = _stream("sessions/" + host)
	_session.changed.connect(_on_session)
	_remember_friend(host, _clean_nick(world.get("n")))
	_user_t = 999.0
	join_answered.emit(true, world)


func _give_up(reason: String) -> void:
	db.delete("requests/%s/%s" % [host, code()])
	_drop()
	join_answered.emit(false, {"reason": reason})


# --- Session ----------------------------------------------------------------------------------------
func _on_session() -> void:
	if not is_online():
		return
	var d = _session.data
	var now := server_now()
	var me := code()
	var seen := {}
	if d is Dictionary:
		for c in d:
			var e = d[c]
			if not (e is Dictionary) or parse_code(String(c)) != String(c):
				continue # "raid" and "map" live next to the players
			if c != me and now - int(float(e.get("t", 0))) > STALE_MS:
				if role == "host":
					db.delete("sessions/%s/%s" % [host, c]) # crashed or lost: tidy up
				continue
			seen[c] = true
			var p = players.get(c)
			if p == null:
				p = _player(_clean_nick(e.get("n")), int(e.get("s", players.size())))
				players[c] = p
				if role == "guest" and _host_seen:
					player_joined.emit(String(p.nick))
			_read_entry(p, e, c == me)
			if c != me:
				# the mirror swaps in a new object whenever a player sends a field again
				var h = e.get("h")
				if role == "host" and h is Dictionary and _changed(c + "/h", h):
					guest_hits.emit(String(c), h)
				var m = e.get("m")
				if m is Array and _changed(c + "/m", m):
					launches_received.emit(String(c), m)
		if role == "guest":
			var r = d.get("raid")
			if r is Dictionary and _changed("raid", r):
				_on_raid(r)
			var ms = d.get("map")
			if ms is Dictionary and _changed("map", ms):
				map_state = ms
				map_received.emit(ms)
	for c in players.keys():
		# just accepted: their entry is still on its way to the database
		if role == "host" and _clock - float(_accepted_at.get(c, -99.0)) < 10.0:
			continue
		if not seen.has(c) and c != me:
			var n := String(players[c].nick)
			players.erase(c)
			if c != host:
				player_left.emit(n)
	if role == "guest":
		if seen.has(host):
			_host_seen = true
		elif _session.synced and (_host_seen or _clock - _join_t > 8.0):
			_end("closed")


## True (and remembered) when `obj` is not the object last seen under `key`.
func _changed(key: String, obj) -> bool:
	if _seen_obj.has(key) and is_same(_seen_obj[key], obj):
		return false
	_seen_obj[key] = obj
	return true


## A raid snapshot arrived: count the rate and the delay for the connection indicator.
func _on_raid(r: Dictionary) -> void:
	raid = r
	var now := _clock
	if _raid_rx >= 0.0:
		var dt := maxf(now - _raid_rx, 0.001)
		raid_hz = lerpf(raid_hz, 1.0 / dt, 0.2) if raid_hz > 0.0 else 1.0 / dt
	_raid_rx = now
	var age := float(server_now() - int(float(r.get("t", server_now()))))
	raid_lag = lerpf(raid_lag, clampf(age, 0.0, 5000.0), 0.2) if raid_lag > 0.0 else clampf(age, 0.0, 5000.0)
	raid_received.emit(r)


func _read_entry(p: Dictionary, e: Dictionary, mine: bool) -> void:
	if e.has("s"):
		p.slot = int(e.s)
		p.color = COLORS[p.slot % COLORS.size()]
	if mine:
		return # our own camera is fresher here than its echo from the server
	p.nick = _clean_nick(e.get("n", p.nick))
	var b = e.get("b")
	if b is Array and (b as Array).size() >= 3:
		p.base = Vector3(float(b[0]), 0.0, float(b[1]))
		p.loc = int(b[2])
		p.has_base = true
	var cv = e.get("c")
	var t := int(float(e.get("t", 0)))
	if cv is Array and (cv as Array).size() >= 7:
		var q := Quaternion(float(cv[3]), float(cv[4]), float(cv[5]), float(cv[6]))
		if q.length_squared() > 0.001:
			var origin := Vector3(float(cv[0]), float(cv[1]), float(cv[2]))
			# velocity between two samples lets the eye glide on between updates
			if bool(p.has_cam) and t > int(p.cam_t) and t - int(p.cam_t) < 2000:
				var dt := float(t - int(p.cam_t)) / 1000.0
				if dt > 0.04:
					var v: Vector3 = (origin - (p.cam as Transform3D).origin) / dt
					p.cam_vel = v if v.length() < 400.0 else Vector3.ZERO
			elif t != int(p.cam_t):
				p.cam_vel = Vector3.ZERO
			p.cam = Transform3D(Basis(q.normalized()), origin)
			p.cam_t = t
			p.has_cam = true
	p.fov = float(e.get("f", p.fov))
	p.view = String(e.get("v", p.view))
	p.ping = int(e.get("p", p.ping))


## Called every frame by the running game with this player's base and camera.
func set_local(base: Vector3, loc: int, cam: Transform3D, fov: float, view: String) -> void:
	_local = {"base": base, "loc": loc, "cam": cam, "fov": fov, "view": view}
	var p = players.get(code())
	if p != null:
		p.base = base
		p.has_base = true
		p.loc = loc
		p.cam = cam
		p.has_cam = true
		p.fov = fov
		p.view = view
		p.ping = conn.rtt


## Not in a game any more (back on the map screen): stop sending the camera.
func clear_local() -> void:
	_local.clear()
	_extra.clear()


## A field sent along with our presence from now on (damage totals "h", launches "m").
func set_extra(key: String, value) -> void:
	_extra[key] = value


## Host: the raid snapshot built by the game (see game_controller.net_snapshot).
func _publish_raid() -> void:
	var g = main.game if main != null else null
	if g == null or not is_instance_valid(g) or not g.has_method("net_snapshot"):
		return
	var snap: Dictionary = g.net_snapshot()
	_raid_seq += 1
	snap["n"] = _raid_seq
	snap["t"] = server_now()
	conn_raid.send(HTTPClient.METHOD_PUT, "sessions/%s/raid" % host, snap, Callable(), "raid")


## Host: buildings state, sent only when it changed.
func _publish_map() -> void:
	var g = main.game if main != null else null
	if g == null or not is_instance_valid(g) or not g.has_method("net_map_state"):
		return
	var m: Dictionary = g.net_map_state()
	var sig := JSON.stringify(m)
	if sig == _map_sig:
		return
	_map_sig = sig
	conn_raid.send(HTTPClient.METHOD_PUT, "sessions/%s/map" % host, m, Callable(), "map")


func _push_state() -> void:
	var d := {"n": nick(), "t": FbDb.now_placeholder(), "p": conn.rtt}
	d.merge(_extra, true)
	if not _local.is_empty():
		var b: Vector3 = _local.base
		var tr: Transform3D = _local.cam
		var q := tr.basis.get_rotation_quaternion()
		d["b"] = [snappedf(b.x, 0.1), snappedf(b.z, 0.1), int(_local.loc)]
		d["c"] = [snappedf(tr.origin.x, 0.01), snappedf(tr.origin.y, 0.01), snappedf(tr.origin.z, 0.01),
			snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)]
		d["f"] = snappedf(float(_local.fov), 0.1)
		d["v"] = String(_local.view)
	conn.send(HTTPClient.METHOD_PATCH, "sessions/%s/%s" % [host, code()], d, Callable(), "state")


# --- Leaving ------------------------------------------------------------------------------------------
## Leaves the session; a host closes the world for everyone.
func close() -> void:
	if role == "":
		return
	var paths := []
	match role:
		"host":
			paths = ["sessions/" + host, "requests/" + host]
		"guest":
			paths = ["sessions/%s/%s" % [host, code()]]
		"joining":
			paths = ["requests/%s/%s" % [host, code()]]
	_drop()
	_wipe(paths)
	# a presence write already on its way can land after the delete: wipe once more after it
	if not paths.is_empty():
		get_tree().create_timer(1.5, true).timeout.connect(_wipe.bind(paths))
	_user_t = 999.0


func _wipe(paths: Array) -> void:
	if role != "" and host != "" and paths.any(func(p) -> bool: return String(p).contains(host)):
		return # a new session with the same host started in the meantime
	for p in paths:
		db.delete(String(p))


func _end(reason: String) -> void:
	db.delete("sessions/%s/%s" % [host, code()])
	_drop()
	session_ended.emit(reason_text(reason))


func _drop() -> void:
	_close_stream(_session)
	_close_stream(_requests)
	_session = null
	_requests = null
	conn.cancel("state")
	conn_raid.cancel("raid")
	conn_raid.cancel("map")
	role = ""
	raid = {}
	map_state = {}
	raid_hz = 0.0
	raid_lag = 0.0
	_raid_rx = -1.0
	_map_sig = ""
	_extra.clear()
	_seen_obj.clear()
	host = ""
	players.clear()
	pending.clear()
	world = {}
	_local.clear()
	_answered.clear()
	_lost_t = 0.0
	_accepted_at.clear()


func _stream(path: String) -> FbStream:
	var s := FbStream.new()
	add_child(s)
	s.open(db.url(path))
	return s


func _close_stream(s: FbStream) -> void:
	if s != null and is_instance_valid(s):
		s.close()
		s.queue_free()


## A host's answer or goodbye code as a sentence for the guest.
static func reason_text(reason: String, host_nick := "") -> String:
	match reason:
		"no":
			return GS.t("%s отклонил запрос") % host_nick if host_nick != "" else GS.t("Хост отклонил запрос")
		"timeout":
			return GS.t("Хост не ответил на запрос")
		"full":
			return GS.t("Мир заполнен")
		"version":
			return GS.t("У хоста другая версия игры")
		"closed":
			return GS.t("Хост закрыл мир")
		"lost":
			return GS.t("Соединение с хостом потеряно")
	return reason


# --- Frame -----------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_clock += delta
	if quiet:
		return
	if not bool(GS.settings.get("mp", false)) and role == "":
		return
	_user_t += delta
	if _user_t >= (HOST_USER_EVERY if role == "host" else USER_EVERY):
		_user_t = 0.0
		_heartbeat()
	if _watch_friends:
		_friends_t += delta
		if _friends_t >= FRIENDS_EVERY:
			_friends_t = 0.0
			_poll_friends()
	match role:
		"joining":
			if _clock - _join_t > REQUEST_TIMEOUT + 5.0:
				_give_up("timeout")
			return
		"host":
			for c in pending.keys():
				if _clock - float(pending[c].t) > REQUEST_TIMEOUT:
					pending.erase(c)
					_reply(c, "timeout")
					request_closed.emit(c)
			if players.size() > 1:
				var g = main.game if main != null else null
				var busy: bool = g != null and is_instance_valid(g) and not g.enemies.is_empty()
				_raid_t += delta
				if _raid_t >= (RAID_EVERY if busy else IDLE_RAID_EVERY):
					_raid_t = 0.0
					_publish_raid()
				_map_t += delta
				if _map_t >= MAP_EVERY:
					_map_t = 0.0
					_publish_map()
		"guest":
			if _session != null and not _session.synced:
				_lost_t += delta
				if _lost_t > LOST_AFTER:
					_end("lost")
					return
			else:
				_lost_t = 0.0
		_:
			return
	_state_t += delta
	if _state_t >= (STATE_EVERY if not _local.is_empty() else IDLE_STATE_EVERY):
		_state_t = 0.0
		_push_state()
