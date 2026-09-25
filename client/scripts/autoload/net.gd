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
		disconnected.emit("Не удалось подключиться к игровому серверу")


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
		while _ws.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				message.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		if _closing:
			return
		var reason := "Соединение с сервером потеряно"
		if not _was_open:
			reason = "Игровой сервер недоступен"
		if code == 4000:
			reason = "Ты зашёл(ла) в игру с другого устройства"
		_was_open = false
		disconnected.emit(reason)
