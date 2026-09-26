extends Node
## Player accounts on top of the friend codes (Net). Optional: by default a player is just a code.
## Registering (nick, email, password) moves this device's code, nick and friends into the
## account — the same identity on every device, friends find you by nick, and the friend list
## lives in the cloud. Signing out brings the device's own code back.
##
## Database (under Net.ROOT), guarded by firebase/database.rules.json:
##   accounts/<uid>  {n: nick, c: code, f: {code: name}, t}  only its owner reads and writes it
##   names/<key>     {u: uid, c: code, n: nick}             nick -> player (key: the nick in lower case)
##   codes/<code>    uid                                    the code belongs to an account: only its
##                                                          owner may write presence as that code

## Signed in or out, the nick or the friend list changed.
signal changed
## A saved session is not accepted any more (password changed, account deleted elsewhere).
signal session_lost

const FbAuth = preload("res://scripts/core/fb_auth.gd")
const FbDb = preload("res://scripts/core/fb_db.gd")
const NICK_MIN := 3
const NICK_MAX := 16

var auth: FbAuth
var db: FbDb
## Called after GS.settings changed (Net._save: in the self-test nothing reaches the disk).
var save := Callable()
## The signed-in account's profile, cached in the settings so it works offline too.
var nick := ""
var code := ""
var friends: Array = []
## The last session ended on its own (shown once on the multiplayer tab).
var lost := false


func setup(api_key: String, database: FbDb, save_cb: Callable) -> void:
	db = database
	save = save_cb
	auth = FbAuth.new()
	auth.api_key = api_key
	add_child(auth)
	auth.session_lost.connect(func() -> void:
		lost = true
		_forget()
		session_lost.emit())
	# the refresh token may be replaced by a new one: keep the newest
	auth.token_changed.connect(func(_t: String) -> void:
		var s = GS.settings.get("account", {})
		if active() and s is Dictionary and String(s.get("refresh", "")) != auth.refresh_token:
			_store())
	var s = GS.settings.get("account", {})
	if auth.enabled() and s is Dictionary and String(s.get("uid", "")) != "" and String(s.get("refresh", "")) != "":
		nick = _clean(s.get("nick", ""))
		code = Net.parse_code(String(s.get("code", "")))
		friends = _clean_list(s.get("friends", []))
		auth.restore(String(s.uid), String(s.get("email", "")), String(s.refresh))


## Accounts are set up for this build (the Firebase Web API key is known).
func enabled() -> bool:
	return auth != null and auth.enabled()


## Signed in: code(), nick() and friends() come from the account.
func active() -> bool:
	return enabled() and auth.signed_in() and code != ""


func email() -> String:
	return auth.email if auth != null else ""


# --- Nicks ---------------------------------------------------------------------------------------
## "" when the nick can name an account, otherwise what is wrong with it.
static func check_nick(n: String) -> String:
	n = n.strip_edges()
	if n.length() < NICK_MIN or n.length() > NICK_MAX:
		return GS.t("Ник — от %d до %d символов") % [NICK_MIN, NICK_MAX]
	for ch in n:
		if not (ch.to_lower() != ch.to_upper() or "0123456789_-".contains(ch)):
			return GS.t("В нике можно только буквы, цифры, «_» и «-»")
	return ""


## Database key of a nick: nicks differing only in letter case are the same nick.
static func key(n: String) -> String:
	return n.strip_edges().to_lower()


## Finds a player by nick: cb(ok: bool, info) — info {c: code, n: nick}, null when nobody has it.
func lookup(n: String, cb: Callable) -> void:
	if check_nick(n) != "":
		cb.call_deferred(true, null)
		return
	db.get_value("names/" + key(n), func(ok: bool, d) -> void:
		var found = d if d is Dictionary and Net.parse_code(String(d.get("c", ""))) != "" else null
		cb.call(ok, found))


# --- Signing up and in ---------------------------------------------------------------------------
## Creates the account and moves this device's code and friends into it. cb(ok: bool, text: String).
func register(n: String, mail: String, password: String, dev_code: String, dev_friends: Array, cb: Callable) -> void:
	n = n.strip_edges()
	var bad := check_nick(n)
	if bad != "":
		cb.call_deferred(false, bad)
		return
	db.get_value("names/" + key(n), func(ok: bool, d) -> void:
		if not ok:
			cb.call(false, FbAuth.message("NETWORK"))
		elif d != null:
			cb.call(false, GS.t("Ник «%s» уже занят") % n)
		else:
			auth.sign_up(mail.strip_edges(), password, func(ok2: bool, err: String) -> void:
				if ok2:
					_claim(n, dev_code, dev_friends, true, cb)
				else:
					cb.call(false, FbAuth.message(err))))


func login(mail: String, password: String, dev_code: String, dev_friends: Array, cb: Callable) -> void:
	auth.sign_in(mail.strip_edges(), password, func(ok: bool, err: String) -> void:
		if not ok:
			cb.call(false, FbAuth.message(err))
			return
		db.get_value("accounts/" + auth.uid, func(ok2: bool, p) -> void:
			if not ok2:
				auth.sign_out()
				cb.call(false, FbAuth.message("NETWORK"))
			elif p is Dictionary and Net.parse_code(String(p.get("c", ""))) != "":
				# friends added on this device before signing in join the account
				var list := _from_map(p.get("f"))
				var added := {}
				for f in dev_friends:
					var c := String(f.code)
					if c != String(p.c) and not list.any(func(x) -> bool: return String(x.code) == c):
						list.append({"code": c, "name": String(f.name)})
						added[c] = String(f.name)
				if not added.is_empty():
					db.patch("accounts/%s/f" % auth.uid, added)
				lost = false
				_apply_profile(_clean(p.get("n")), String(p.c), list)
				cb.call(true, "")
			else:
				# signed up, but the connection dropped before the profile was written: finish it
				_recover_nick(dev_code, func(n: String) -> void:
					_claim(n, dev_code, dev_friends, false, cb))))


## A nick for a profile that has to be made at sign-in: the device's nick when it is free,
## otherwise one built from the code (codes are unique, so is the nick).
func _recover_nick(dev_code: String, cb: Callable) -> void:
	var fallback := (GS.t("Игрок") + "_" + dev_code).substr(0, NICK_MAX)
	var mine := String(GS.settings.get("nick", "")).strip_edges()
	if check_nick(mine) != "":
		cb.call(fallback)
		return
	db.get_value("names/" + key(mine), func(ok: bool, d) -> void:
		var free := ok and (d == null or (d is Dictionary and String(d.get("u", "")) == auth.uid))
		cb.call(mine if free else fallback))


## Writes a new profile: the nick first (the scarce part), then the code, then the account.
## A fresh sign-up that cannot finish is deleted again, so the email can be used once more.
func _claim(n: String, want_code: String, list: Array, fresh: bool, cb: Callable) -> void:
	var k := key(n)
	var fail := func(text: String, written: Array) -> void:
		if fresh:
			for p in written:
				db.delete(String(p))
			auth.delete_user(func(_ok: bool, _e: String) -> void: pass)
		else:
			auth.sign_out()
		cb.call(false, text)
	db.get_value("codes/" + want_code, func(ok: bool, owner) -> void:
		if not ok:
			fail.call(FbAuth.message("NETWORK"), [])
			return
		# this device's code already belongs to another account (a second account made here)
		var c := want_code if owner == null or String(owner) == auth.uid else Net.new_code()
		db.put("names/" + k, {"u": auth.uid, "c": c, "n": n}, func(ok2: bool, _d) -> void:
			if not ok2:
				fail.call(GS.t("Ник «%s» уже занят") % n, [])
				return
			db.put("codes/" + c, auth.uid, func(ok3: bool, _d3) -> void:
				var f := {}
				for e in list:
					if String(e.code) != c:
						f[String(e.code)] = String(e.name)
				db.put("accounts/" + auth.uid, {"n": n, "c": c, "f": f, "t": FbDb.now_placeholder()}, func(ok4: bool, _d4) -> void:
					if not (ok3 and ok4):
						fail.call(FbAuth.message("NETWORK"), ["names/" + k, "codes/" + c])
						return
					lost = false
					_apply_profile(n, c, list.filter(func(e) -> bool: return String(e.code) != c))
					cb.call(true, "")))))


func logout() -> void:
	auth.sign_out()
	_forget()


## A mail with a link to choose a new password.
func reset_password(mail: String, cb: Callable) -> void:
	auth.send_reset(mail.strip_edges(), func(ok: bool, err: String) -> void:
		cb.call(ok, "" if ok else FbAuth.message(err)))


func rename(n: String, cb: Callable) -> void:
	n = n.strip_edges()
	var bad := check_nick(n)
	if bad != "":
		cb.call_deferred(false, bad)
		return
	var old := key(nick)
	var k := key(n)
	var write := func() -> void:
		db.put("names/" + k, {"u": auth.uid, "c": code, "n": n}, func(ok: bool, _d) -> void:
			if not ok:
				cb.call(false, FbAuth.message("NETWORK"))
				return
			db.patch("accounts/" + auth.uid, {"n": n}, func(ok2: bool, _d2) -> void:
				if not ok2:
					cb.call(false, FbAuth.message("NETWORK"))
					return
				if old != k:
					db.delete("names/" + old)
				nick = n
				_store()
				changed.emit()
				cb.call(true, "")))
	if k == old:
		write.call() # only the letter case changes
		return
	db.get_value("names/" + k, func(ok: bool, d) -> void:
		if not ok:
			cb.call(false, FbAuth.message("NETWORK"))
		elif d != null:
			cb.call(false, GS.t("Ник «%s» уже занят") % n)
		else:
			write.call())


## Deletes the account for good — its nick, the code's binding, the friend list and the login
## itself. Firebase asks for the password once more before a deletion.
func delete_account(password: String, cb: Callable) -> void:
	var old_nick := nick
	var old_code := code
	auth.sign_in(auth.email, password, func(ok: bool, err: String) -> void:
		if not ok:
			cb.call(false, FbAuth.message(err))
			return
		var u := auth.uid
		db.delete("names/" + key(old_nick), func(ok1: bool, _a) -> void:
			db.delete("users/" + old_code)
			db.delete("codes/" + old_code, func(ok2: bool, _b) -> void:
				db.delete("accounts/" + u, func(ok3: bool, _c) -> void:
					if not (ok1 and ok2 and ok3):
						cb.call(false, FbAuth.message("NETWORK"))
						return
					auth.delete_user(func(ok4: bool, err4: String) -> void:
						if not ok4:
							cb.call(false, FbAuth.message(err4))
							return
						_forget()
						cb.call(true, ""))))))


# --- Friends -------------------------------------------------------------------------------------
func add_friend(c: String, n: String) -> void:
	var had := friends.any(func(f) -> bool: return String(f.code) == c and String(f.name) == n)
	friends = friends.filter(func(f) -> bool: return String(f.code) != c)
	friends.append({"code": c, "name": n})
	_store()
	if not had:
		db.patch("accounts/%s/f" % auth.uid, {c: n})


func remove_friend(c: String) -> void:
	friends = friends.filter(func(f) -> bool: return String(f.code) != c)
	_store()
	db.delete("accounts/%s/f/%s" % [auth.uid, c])


## Pulls the profile from the cloud: friends added and nick changed on another device.
func sync() -> void:
	if not active() or not auth.has_token():
		return
	db.get_value("accounts/" + auth.uid, func(ok: bool, p) -> void:
		if not ok or not active() or not (p is Dictionary):
			return
		var list := _from_map(p.get("f"))
		var n := _clean(p.get("n", nick))
		if JSON.stringify(list) != JSON.stringify(friends) or n != nick:
			friends = list
			nick = n
			_store()
			changed.emit())


# --- Local state ---------------------------------------------------------------------------------
func _apply_profile(n: String, c: String, list: Array) -> void:
	nick = n
	code = c
	friends = list
	_store()
	changed.emit()


func _forget() -> void:
	nick = ""
	code = ""
	friends = []
	GS.settings["account"] = {}
	if save.is_valid():
		save.call()
	changed.emit()


func _store() -> void:
	GS.settings["account"] = {"uid": auth.uid, "email": auth.email, "refresh": auth.refresh_token,
		"nick": nick, "code": code, "friends": friends.duplicate(true)}
	if save.is_valid():
		save.call()


static func _clean(v) -> String:
	return String(v if v != null else "").strip_edges().substr(0, NICK_MAX)


## {code: name} from the cloud -> [{code, name}], sorted by name.
static func _from_map(m) -> Array:
	var out := []
	if m is Dictionary:
		for c in m:
			if Net.parse_code(String(c)) == String(c):
				out.append({"code": String(c), "name": _clean(m[c])})
	out.sort_custom(func(a, b) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


static func _clean_list(a) -> Array:
	var out := []
	if a is Array:
		for f in a:
			if f is Dictionary and Net.parse_code(String(f.get("code", ""))) != "":
				out.append({"code": String(f.code), "name": _clean(f.get("name", ""))})
	return out
