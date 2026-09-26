extends Node
## Minimal Firebase Realtime Database client over the REST API: one-shot reads and writes, with
## coalesced "latest wins" writes for data sent many times a second (camera positions).
## Paths are relative to base_url ("https://<db>.firebaseio.com/<root>").

var base_url := ""
## Round trip of the last successful request, ms (shown as the connection quality).
var rtt := 0
## Server clock minus local clock, ms — learnt from the timestamps the server writes for us.
var server_offset := 0
## ID token of a signed-in account (FbAuth): sent as ?auth= with every request, so the rules know
## who writes. "" for players without an account.
var auth := ""
## Self-test: an in-memory database (a Dictionary) instead of the network; null normally.
var mock = null
var _busy := {}
var _queued := {}


func url(path: String) -> String:
	return "%s/%s.json" % [base_url, path]


## Server-side timestamp placeholder: the database writes its own clock (ms) in its place.
static func now_placeholder() -> Dictionary:
	return {".sv": "timestamp"}


## Server clock in ms as far as this machine can tell.
func server_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + server_offset


## Calls cb(ok: bool, data) when the request finishes (at once with false when base_url is
## empty: the offline self-test). data is the parsed JSON reply (the
## written value for PUT / PATCH, with server timestamps resolved).
func request(method: int, path: String, body = null, cb := Callable()) -> void:
	if mock is Dictionary:
		_mock_request(method, path, body, cb)
		return
	if base_url == "":
		if cb.is_valid():
			cb.call_deferred(false, null)
		return
	var r := HTTPRequest.new()
	r.timeout = 10.0
	add_child(r)
	var t0 := Time.get_ticks_msec()
	var sent_at := Time.get_unix_time_from_system() * 1000.0
	r.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		r.queue_free()
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		var data = null
		if ok:
			rtt = Time.get_ticks_msec() - t0
			if raw.size() > 0:
				data = JSON.parse_string(raw.get_string_from_utf8())
			if method != HTTPClient.METHOD_GET:
				_learn_offset(data, sent_at + rtt * 0.5)
		if cb.is_valid():
			cb.call(ok, data))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := JSON.stringify(body) if body != null else ""
	var u := url(path)
	if auth != "":
		u += "?auth=" + auth
	if r.request(u, headers, method, payload) != OK:
		r.queue_free()
		if cb.is_valid():
			cb.call_deferred(false, null)


## A "t" we wrote as a server timestamp comes back resolved: how far the server clock is from
## ours. (Only for writes — a read returns somebody else's old timestamp.)
func _learn_offset(data, local_ms: float) -> void:
	if data is Dictionary and (data as Dictionary).has("t") and (data.t is float or data.t is int):
		server_offset = int(float(data.t) - local_ms)


func get_value(path: String, cb: Callable) -> void:
	request(HTTPClient.METHOD_GET, path, null, cb)


func put(path: String, value, cb := Callable()) -> void:
	request(HTTPClient.METHOD_PUT, path, value, cb)


func patch(path: String, value: Dictionary, cb := Callable()) -> void:
	request(HTTPClient.METHOD_PATCH, path, value, cb)


func delete(path: String, cb := Callable()) -> void:
	request(HTTPClient.METHOD_DELETE, path, null, cb)


## Like patch(), but while a write with the same key is still in flight only the newest value
## waits for it: a slow connection sends fewer updates instead of a growing backlog.
func patch_latest(key: String, path: String, value: Dictionary) -> void:
	if _busy.has(key):
		_queued[key] = [path, value]
		return
	_busy[key] = true
	patch(path, value, func(_ok: bool, _d) -> void:
		_busy.erase(key)
		if _queued.has(key):
			var q: Array = _queued[key]
			_queued.erase(key)
			patch_latest(key, q[0], q[1]))


## Drops a waiting coalesced write (the session it belonged to is over).
func cancel(key: String) -> void:
	_queued.erase(key)


# --- Offline stand-in (mock, the self-test) ------------------------------------------------------
## Same answers as the REST API, kept in `mock`: server timestamps resolved, empty nodes gone.
func _mock_request(method: int, path: String, body, cb: Callable) -> void:
	var keys := Array(path.split("/", false))
	var value = _mock_resolve(body)
	var data = null
	match method:
		HTTPClient.METHOD_GET:
			data = _mock_get(keys)
		HTTPClient.METHOD_PUT:
			_mock_set(keys, value)
			data = value
		HTTPClient.METHOD_PATCH:
			if value is Dictionary:
				for k in value:
					_mock_set(keys + Array(String(k).split("/", false)), value[k])
			data = value
		HTTPClient.METHOD_DELETE:
			_mock_set(keys, null)
	if cb.is_valid():
		cb.call_deferred(true, data.duplicate(true) if data is Dictionary or data is Array else data)


func _mock_resolve(v):
	if v is Dictionary:
		if v.size() == 1 and v.get(".sv") == "timestamp":
			return float(server_now())
		var out := {}
		for k in v:
			var r = _mock_resolve(v[k])
			if r != null:
				out[k] = r
		return out
	return v.duplicate(true) if v is Array else v


func _mock_get(keys: Array):
	var node = mock
	for k in keys:
		if not (node is Dictionary) or not (node as Dictionary).has(k):
			return null
		node = node[k]
	return null if node is Dictionary and (node as Dictionary).is_empty() else node


func _mock_set(keys: Array, value) -> void:
	if keys.is_empty():
		return
	var node: Dictionary = mock
	for i in keys.size() - 1:
		if not (node.get(keys[i]) is Dictionary):
			if value == null:
				return
			node[keys[i]] = {}
		node = node[keys[i]]
	if value == null or (value is Dictionary and (value as Dictionary).is_empty()):
		node.erase(keys[-1])
	else:
		node[keys[-1]] = value
