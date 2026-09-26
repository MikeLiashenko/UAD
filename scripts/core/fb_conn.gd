extends Node
## One kept-alive HTTPS connection to the database for frequent writes. A fresh HTTPRequest
## pays a TLS handshake every time (~380 ms to the database); one open connection answers in
## ~175 ms (measured with tools_scripts/fb_probe.js), so presence and raid snapshots go here.
## Requests run one after another; a keyed request replaces the waiting one with the same key,
## so a slow line sends fewer updates instead of a growing backlog ("latest wins").

## The request that timed out or failed was retried; reported for the connection indicator.
signal trouble

const TIMEOUT := 8.0
const RETRY := 0.6

## "https://<db>.firebaseio.com/<root>"; empty = offline (self-test): requests fail at once.
var base_url := ""
## Round trip of the last request, ms, and a smoothed average for the HUD.
var rtt := 0
var rtt_avg := 0.0
## Requests answered since the start (the probe divides it by time).
var answered := 0
## Server clock minus local clock (ms), learnt from server timestamps coming back resolved.
var server_offset := 0
var has_offset := false
## ID token of a signed-in account, sent as ?auth= (see FbDb.auth).
var auth := ""

var _http := HTTPClient.new()
var _host := ""
var _prefix := ""
var _queue: Array = []
var _cur: Dictionary = {}
var _body := PackedByteArray()
var _t0 := 0
var _sent_local := 0.0
var _retry := 0.0


func _ready() -> void:
	var rest := base_url.trim_prefix("https://")
	var i := rest.find("/")
	_host = rest.substr(0, i) if i >= 0 else rest
	_prefix = rest.substr(i) if i >= 0 else ""


## Queues a request. `key` != "" coalesces with a waiting request of the same key.
## cb(ok: bool, data) gets the parsed reply.
func send(method: int, path: String, body = null, cb := Callable(), key := "") -> void:
	if base_url == "":
		if cb.is_valid():
			cb.call_deferred(false, null)
		return
	if key != "":
		for q in _queue:
			if String(q.key) == key:
				q.path = path
				q.body = body
				q.cb = cb
				q.method = method
				return
	_queue.append({"method": method, "path": path, "body": body, "cb": cb, "key": key})


## Drops waiting requests with this key (the session they belonged to is over).
func cancel(key: String) -> void:
	_queue = _queue.filter(func(q) -> bool: return String(q.key) != key)


func busy() -> bool:
	return not _cur.is_empty() or not _queue.is_empty()


func close() -> void:
	_queue.clear()
	_cur = {}
	_http.close()


func _process(delta: float) -> void:
	if _retry > 0.0:
		_retry -= delta
		return
	if _cur.is_empty() and _queue.is_empty():
		_http.poll()
		return
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_DISCONNECTED:
			if not _cur.is_empty():
				_fail()
			elif _http.connect_to_host("https://" + _host, 443, TLSOptions.client()) != OK:
				_fail()
		HTTPClient.STATUS_CONNECTED:
			if _cur.is_empty():
				_start_next()
			elif _http.has_response():
				_finish()
			elif Time.get_ticks_msec() - _t0 > TIMEOUT * 1000.0:
				_fail()
		HTTPClient.STATUS_BODY:
			while _http.get_status() == HTTPClient.STATUS_BODY:
				var chunk := _http.read_response_body_chunk()
				if chunk.is_empty():
					break
				_body.append_array(chunk)
			if _http.get_status() == HTTPClient.STATUS_CONNECTED:
				_finish()
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_fail()
		_:
			# resolving / connecting / requesting: wait, but not forever
			if not _cur.is_empty() and Time.get_ticks_msec() - _t0 > TIMEOUT * 1000.0:
				_fail()


func _start_next() -> void:
	_cur = _queue.pop_front()
	_body = PackedByteArray()
	_t0 = Time.get_ticks_msec()
	_sent_local = Time.get_unix_time_from_system() * 1000.0
	var payload := JSON.stringify(_cur.body) if _cur.body != null else ""
	var headers := PackedStringArray(["Content-Type: application/json", "Connection: keep-alive"])
	var q := "?auth=" + auth if auth != "" else ""
	if _http.request(int(_cur.method), "%s/%s.json%s" % [_prefix, _cur.path, q], headers, payload) != OK:
		_fail()


func _finish() -> void:
	var code := _http.get_response_code()
	var done := _cur
	_cur = {}
	var ok := code >= 200 and code < 300
	var data = null
	if ok:
		rtt = Time.get_ticks_msec() - _t0
		rtt_avg = float(rtt) if rtt_avg <= 0.0 else lerpf(rtt_avg, float(rtt), 0.15)
		answered += 1
		if _body.size() > 0:
			data = JSON.parse_string(_body.get_string_from_utf8())
		if data is Dictionary and (data as Dictionary).has("t") and (data.t is float or data.t is int):
			# the server wrote its clock while answering: half a round trip after we sent
			server_offset = int(float(data.t) - (_sent_local + rtt * 0.5))
			has_offset = true
	var cb: Callable = done.get("cb", Callable())
	if cb.is_valid():
		cb.call(ok, data)


## The line broke or the answer never came: reconnect and send the same request again (unless a
## newer one with its key is already waiting).
func _fail() -> void:
	_http.close()
	if not _cur.is_empty():
		var k := String(_cur.key)
		if k == "" or not _queue.any(func(q) -> bool: return String(q.key) == k):
			_queue.push_front(_cur)
		_cur = {}
	_retry = RETRY
	trouble.emit()
