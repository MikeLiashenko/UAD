extends Node
## Firebase Authentication over its REST API, email + password: create an account, sign in, keep
## the ID token fresh (it lives an hour), send a password-reset mail, delete the account.
## The database gets the ID token as ?auth= (FbDb.auth, FbConn.auth) and its rules check
## auth.uid. Only the refresh token stays on the device — never the password.
## api_key "" = accounts are off; "mock" = an in-memory stand-in for the offline self-test.

## The ID token changed (signed in, refreshed) or went away ("").
signal token_changed(token: String)
## The server no longer takes this session (password changed or account deleted elsewhere).
signal session_lost

const ACCOUNTS := "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s"
const TOKEN := "https://securetoken.googleapis.com/v1/token?key=%s"
## Refresh this long before the hour runs out.
const EARLY := 300.0
## After a failed refresh (no internet), try again in:
const RETRY := 20.0
## Refresh errors that mean the session is over for good.
const LOST := ["TOKEN_EXPIRED", "USER_DISABLED", "USER_NOT_FOUND", "INVALID_REFRESH_TOKEN",
	"INVALID_GRANT_TYPE", "MISSING_REFRESH_TOKEN", "PROJECT_NUMBER_MISMATCH"]

var api_key := ""
var uid := ""
var email := ""
var id_token := ""
var refresh_token := ""
## Unix time when id_token stops working.
var expires_at := 0.0
var _refreshing := false
var _retry := 0.0
## mock: email -> {uid, password}
var _mock_users := {}


func enabled() -> bool:
	return api_key != ""


func signed_in() -> bool:
	return uid != "" and refresh_token != ""


## The ID token works right now (it may be refreshing in the background).
func has_token() -> bool:
	return id_token != "" and Time.get_unix_time_from_system() < expires_at


## cb(ok: bool, err: String) — err is a Firebase error code ("EMAIL_EXISTS", "NETWORK"…),
## see message().
func sign_up(mail: String, password: String, cb: Callable) -> void:
	_call("signUp", {"email": mail, "password": password, "returnSecureToken": true}, func(ok: bool, d, err: String) -> void:
		if ok:
			_take(d)
		cb.call(ok, err))


func sign_in(mail: String, password: String, cb: Callable) -> void:
	_call("signInWithPassword", {"email": mail, "password": password, "returnSecureToken": true}, func(ok: bool, d, err: String) -> void:
		if ok:
			_take(d)
		cb.call(ok, err))


## A mail with a link to set a new password.
func send_reset(mail: String, cb: Callable) -> void:
	_call("sendOobCode", {"requestType": "PASSWORD_RESET", "email": mail}, func(ok: bool, _d, err: String) -> void:
		cb.call(ok, err))


## Deletes the signed-in user (Firebase wants a fresh sign-in first: CREDENTIAL_TOO_OLD_LOGIN_AGAIN).
func delete_user(cb: Callable) -> void:
	_call("delete", {"idToken": id_token}, func(ok: bool, _d, err: String) -> void:
		if ok:
			sign_out()
		cb.call(ok, err))


## Picks up a session saved in the settings; a new ID token is fetched right away.
func restore(u: String, mail: String, refresh: String) -> void:
	uid = u
	email = mail
	refresh_token = refresh
	id_token = ""
	expires_at = 0.0
	refresh()


func sign_out() -> void:
	var had := id_token != "" or uid != ""
	uid = ""
	email = ""
	id_token = ""
	refresh_token = ""
	expires_at = 0.0
	_retry = 0.0
	_refreshing = false # an answer still on its way is dropped (refresh token changed)
	if had:
		token_changed.emit("")


## Trades the refresh token for a new ID token.
func refresh(cb := Callable()) -> void:
	if refresh_token == "" or _refreshing:
		if cb.is_valid():
			cb.call_deferred(false, "BUSY")
		return
	_refreshing = true
	var asked := refresh_token
	var done := func(ok: bool, d, err: String) -> void:
		_refreshing = false
		if refresh_token != asked:
			return # signed out (or in as someone else) while this was on its way
		if ok and d is Dictionary:
			id_token = String(d.get("id_token", ""))
			refresh_token = String(d.get("refresh_token", refresh_token))
			uid = String(d.get("user_id", uid))
			expires_at = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))
			_retry = 0.0
			token_changed.emit(id_token)
		elif LOST.has(err):
			sign_out()
			session_lost.emit()
		else:
			_retry = RETRY
		if cb.is_valid():
			cb.call(ok, err)
	if api_key == "mock":
		_mock_refresh(done)
		return
	var body := "grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode()
	_post(TOKEN % api_key, body, "application/x-www-form-urlencoded", done)


func _process(delta: float) -> void:
	if not signed_in() or _refreshing:
		return
	if _retry > 0.0:
		_retry -= delta
		if _retry <= 0.0:
			refresh()
		return
	if Time.get_unix_time_from_system() > expires_at - EARLY:
		refresh()


func _take(d) -> void:
	if not (d is Dictionary):
		return
	uid = String(d.get("localId", ""))
	email = String(d.get("email", email))
	id_token = String(d.get("idToken", ""))
	refresh_token = String(d.get("refreshToken", ""))
	expires_at = Time.get_unix_time_from_system() + float(d.get("expiresIn", 3600))
	_retry = 0.0
	token_changed.emit(id_token)


## cb(ok: bool, data, err: String)
func _call(method: String, body: Dictionary, cb: Callable) -> void:
	if api_key == "":
		cb.call_deferred(false, null, "DISABLED")
		return
	if api_key == "mock":
		_mock_call(method, body, cb)
		return
	_post(ACCOUNTS % [method, api_key], JSON.stringify(body), "application/json", cb)


func _post(url: String, body: String, type: String, cb: Callable) -> void:
	var r := HTTPRequest.new()
	r.timeout = 15.0
	add_child(r)
	r.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		r.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			cb.call(false, null, "NETWORK")
			return
		var d = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
		if code >= 200 and code < 300:
			cb.call(true, d, "")
		else:
			cb.call(false, d, _error_code(d)))
	if r.request(url, PackedStringArray(["Content-Type: " + type]), HTTPClient.METHOD_POST, body) != OK:
		r.queue_free()
		cb.call_deferred(false, null, "NETWORK")


## "WEAK_PASSWORD : Password should be at least 6 characters" -> "WEAK_PASSWORD"
static func _error_code(d) -> String:
	if d is Dictionary and d.get("error") is Dictionary:
		var m := String(d.error.get("message", "UNKNOWN"))
		for sep in [" : ", " "]:
			var i := m.find(sep)
			if i > 0:
				m = m.substr(0, i)
		return m
	return "UNKNOWN"


## A Firebase error code as a sentence for the player.
static func message(err: String) -> String:
	match err:
		"NETWORK":
			return GS.t("Нет связи с сервером. Проверьте интернет.")
		"EMAIL_EXISTS":
			return GS.t("Эта почта уже зарегистрирована — войдите")
		"EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
			return GS.t("Неверная почта или пароль")
		"INVALID_EMAIL", "MISSING_EMAIL":
			return GS.t("Проверьте адрес почты")
		"WEAK_PASSWORD", "MISSING_PASSWORD":
			return GS.t("Пароль слишком простой — минимум 6 символов")
		"TOO_MANY_ATTEMPTS_TRY_LATER":
			return GS.t("Слишком много попыток. Попробуйте через несколько минут.")
		"USER_DISABLED":
			return GS.t("Аккаунт заблокирован")
		"CREDENTIAL_TOO_OLD_LOGIN_AGAIN", "TOKEN_EXPIRED", "INVALID_ID_TOKEN", "USER_NOT_FOUND":
			return GS.t("Войдите в аккаунт заново")
		"OPERATION_NOT_ALLOWED", "DISABLED", "PASSWORD_LOGIN_DISABLED", "CONFIGURATION_NOT_FOUND":
			return GS.t("Вход по почте на сервере выключен")
	return GS.t("Ошибка сервера: %s") % err


# --- Offline stand-in (api_key "mock", the self-test) ---------------------------------------------
func _mock_call(method: String, body: Dictionary, cb: Callable) -> void:
	var mail := String(body.get("email", "")).strip_edges().to_lower()
	var pw := String(body.get("password", ""))
	var reply := func(d) -> Dictionary:
		return {"localId": d.uid, "email": mail, "idToken": "mock-id-" + String(d.uid) + "-" + str(randi()),
			"refreshToken": "mock-rt-" + String(d.uid), "expiresIn": "3600"}
	match method:
		"signUp":
			if not mail.contains("@") or not mail.contains("."):
				cb.call_deferred(false, null, "INVALID_EMAIL")
			elif pw.length() < 6:
				cb.call_deferred(false, null, "WEAK_PASSWORD")
			elif _mock_users.has(mail):
				cb.call_deferred(false, null, "EMAIL_EXISTS")
			else:
				_mock_users[mail] = {"uid": "u%08d" % (randi() % 100000000), "password": pw}
				cb.call_deferred(true, reply.call(_mock_users[mail]), "")
		"signInWithPassword":
			if not _mock_users.has(mail) or String(_mock_users[mail].password) != pw:
				cb.call_deferred(false, null, "INVALID_LOGIN_CREDENTIALS")
			else:
				cb.call_deferred(true, reply.call(_mock_users[mail]), "")
		"sendOobCode":
			cb.call_deferred(true, {}, "")
		"delete":
			for m in _mock_users.keys():
				if String(_mock_users[m].uid) == uid:
					_mock_users.erase(m)
			cb.call_deferred(true, {}, "")
		_:
			cb.call_deferred(false, null, "UNKNOWN")


## Answers a frame later, like the real server: the users are looked up then.
func _mock_refresh(done: Callable) -> void:
	(func() -> void:
		for m in _mock_users:
			if "mock-rt-" + String(_mock_users[m].uid) == refresh_token:
				done.call(true, {"id_token": "mock-id-" + String(_mock_users[m].uid) + "-" + str(randi()),
					"refresh_token": refresh_token, "user_id": _mock_users[m].uid, "expires_in": "3600"}, "")
				return
		done.call(false, null, "USER_NOT_FOUND")).call_deferred()
