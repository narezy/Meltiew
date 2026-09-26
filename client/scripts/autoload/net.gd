extends Node
## Realtime game connection (WebSocket, JSON messages).

signal connected
signal disconnected(reason: String)
signal message(msg: Dictionary)

var _ws: WebSocketPeer
var _was_open := false
var _closing := false


func connect_to_game() -> void:
	close()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 16
	_was_open = false
	_closing = false
	var err := _ws.connect_to_url(Api.ws_url())
	if err != OK:
		_ws = null
		disconnected.emit(L.t("err_ws_connect"))


func close() -> void:
	if _ws:
		_closing = true
		_ws.close(1000, "bye")
		_ws = null
	_was_open = false


func is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		_ws.send_text(JSON.stringify(msg))


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			connected.emit()
		while _ws != null and _ws.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				message.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		# Whatever arrived right before the close (a "please update", a kick) still counts.
		var kicked := false
		while _ws != null and _ws.get_available_packet_count() > 0:
			var last: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if typeof(last) == TYPE_DICTIONARY and not _closing:
				kicked = kicked or str(last.get("t", "")) == "kicked"
				message.emit(last)
		if _ws == null or kicked:
			_ws = null
			return
		_ws = null
		if _closing:
			return
		if code == 4003:
			# Turned away for an old app version.
			_was_open = false
			message.emit({"t": "kicked", "code": "update", "m": ""})
			return
		var reason := L.t("err_ws_lost")
		if not _was_open:
			reason = L.t("err_ws_unavailable")
		if code == 4000:
			reason = L.t("err_duplicate")
		_was_open = false
		disconnected.emit(reason)
