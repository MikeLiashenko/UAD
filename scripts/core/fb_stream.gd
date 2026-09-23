extends Node
## A live Firebase Realtime Database path over server-sent events. `data` mirrors the value at
## the path and `changed` fires after every update from the server. Follows Firebase's redirects
## to the database shard and reconnects on its own when the line drops.

signal changed
## The line dropped; the stream keeps retrying. `synced` is false until the next snapshot.
signal lost

const RETRY := 2.0

## The mirrored value: null (nothing there), a Dictionary or a plain value.
var data = null
## True once the first full snapshot has arrived (and again after each reconnect).
var synced := false

var _url := ""
var _http := HTTPClient.new()
var _path := ""
var _requested := false
var _buf := PackedByteArray()
var _retry := 0.0
var _redirects := 0


func open(full_url: String) -> void:
	_url = full_url
	_redirects = 0
	_connect(full_url)


func close() -> void:
	_http.close()
	set_process(false)


func _connect(u: String) -> void:
	_http.close()
	_requested = false
	_buf = PackedByteArray()
	var rest := u.trim_prefix("https://")
	var i := rest.find("/")
	var host := rest.substr(0, i) if i >= 0 else rest
	_path = rest.substr(i) if i >= 0 else "/"
	if host == "":
		set_process(false) # offline (self-test): nothing to connect to
		return
	if _http.connect_to_host("https://" + host, 443, TLSOptions.client()) != OK:
		_fail()


func _fail() -> void:
	_http.close()
	if synced:
		synced = false
		lost.emit()
	_retry = RETRY


func _process(delta: float) -> void:
	if _retry > 0.0:
		_retry -= delta
		if _retry <= 0.0:
			_redirects = 0
			_connect(_url)
		return
	_http.poll()
	var st := _http.get_status()
	match st:
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				_http.request(HTTPClient.METHOD_GET, _path, PackedStringArray(["Accept: text/event-stream"]))
			elif _http.has_response():
				_on_response()
				# the reply is over: an event stream never ends while it is healthy
				if _http.get_status() == HTTPClient.STATUS_CONNECTED:
					_fail()
		HTTPClient.STATUS_BODY:
			_on_response()
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_fail()
		HTTPClient.STATUS_DISCONNECTED:
			if _requested:
				_fail()


func _on_response() -> void:
	var code := _http.get_response_code()
	if code == 307 or code == 302 or code == 301:
		var loc := ""
		var hd := _http.get_response_headers_as_dictionary()
		for k in hd:
			if String(k).to_lower() == "location":
				loc = String(hd[k])
		_redirects += 1
		if loc != "" and _redirects < 5:
			_connect(loc)
		else:
			_fail()
		return
	if code != 200:
		_fail()
		return
	while _http.get_status() == HTTPClient.STATUS_BODY:
		var chunk := _http.read_response_body_chunk()
		if chunk.is_empty():
			break
		_buf.append_array(chunk)
	_parse()


## Splits complete events off the buffer (blank line between events). Bytes are only decoded
## once an event is whole, so a Cyrillic letter cut in two by a chunk boundary survives.
func _parse() -> void:
	while true:
		var cut := -1
		var skip := 0
		var i := _buf.find(10)
		while i >= 0 and i + 1 < _buf.size():
			if _buf[i + 1] == 10:
				cut = i
				skip = 2
				break
			if _buf[i + 1] == 13 and i + 2 < _buf.size() and _buf[i + 2] == 10:
				cut = i
				skip = 3
				break
			i = _buf.find(10, i + 1)
		if cut < 0:
			return
		var text := _buf.slice(0, cut).get_string_from_utf8()
		_buf = _buf.slice(cut + skip)
		handle_event(text)


## One server-sent event: "event: put|patch|keep-alive|cancel|auth_revoked" + "data: {...}".
func handle_event(text: String) -> void:
	var kind := ""
	var payload := ""
	for line in text.split("\n"):
		line = line.strip_edges(false, true)
		if line.begins_with("event:"):
			kind = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			payload += line.substr(5).strip_edges()
	match kind:
		"put", "patch":
			var ev = JSON.parse_string(payload)
			if not (ev is Dictionary):
				return
			var path := String(ev.get("path", "/"))
			if kind == "put" and path == "/":
				synced = true
			data = apply(data, path, ev.get("data"), kind == "patch")
			changed.emit()
		"cancel", "auth_revoked":
			_fail()


## Applies a put (replace) or patch (merge children) at a slash path to a mirrored value;
## null values delete. Returns the new root.
static func apply(root, path: String, value, is_patch: bool):
	var keys := path.split("/", false)
	if keys.is_empty():
		if not is_patch:
			return value
		if not (root is Dictionary):
			root = {}
		_merge(root, value)
		return root
	if not (root is Dictionary):
		root = {}
	var node: Dictionary = root
	for i in keys.size() - 1:
		var k := keys[i]
		if not (node.get(k) is Dictionary):
			node[k] = {}
		node = node[k]
	var last := keys[keys.size() - 1]
	if is_patch:
		if not (node.get(last) is Dictionary):
			node[last] = {}
		_merge(node[last], value)
	elif value == null:
		node.erase(last)
	else:
		node[last] = value
	return root


static func _merge(node: Dictionary, value) -> void:
	if not (value is Dictionary):
		return
	for k in value:
		if value[k] == null:
			node.erase(k)
		else:
			node[k] = value[k]
