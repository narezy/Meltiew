class_name LocalNet
extends Node
## Studio play test: stands in for the Net autoload and runs the place's server
## scripts on this device, in their own sandboxed Luau VM. The game scene talks to
## it exactly like to the real server, so what you test is what players get.

signal connected
signal disconnected(reason: String)
signal message(msg: Dictionary)

const TIME_LIMIT := 0.25

var melt: Dictionary
var _vm: RefCounted
var _open := false
var _me := {}
var _pos := {}
var _events: Array = []
var _shared: Array = []
var _mine: Array = []


func _init(place: Dictionary) -> void:
	melt = place


func connect_to_game() -> void:
	_open = true
	_me = Session.user
	connected.emit.call_deferred()
	message.emit.call_deferred({"t": "hello", "you": _me})


func is_open() -> bool:
	return _open


func close() -> void:
	_open = false
	if _vm:
		_vm.close()
		_vm = null


func send(m: Dictionary) -> void:
	if not _open:
		return
	match str(m.get("t", "")):
		"join":
			_join()
		"state":
			_pos = {"e": "pos", "userId": int(_me.id), "p": {"$v3": m.p}}
		"remote":
			_events.append({"e": "fire", "userId": int(_me.id), "id": m.id, "args": m.get("args", [])})
		"invoke":
			_events.append({"e": "invoke", "userId": int(_me.id), "id": m.id, "rid": m.rid, "args": m.get("args", [])})
		"touch":
			_events.append({"e": "touch", "userId": int(_me.id), "id": m.id, "ended": m.get("ended", false)})
		"click":
			_events.append({"e": "click", "userId": int(_me.id), "id": m.id})
		"tool":
			_events.append({"e": "tool", "userId": int(_me.id), "id": m.get("id"), "ev": str(m.get("ev", "")), "p": m.get("p")})
		"dead":
			_events.append({"e": "died", "userId": int(_me.id)})
		"chat":
			message.emit({"t": "chat", "id": int(_me.id), "name": str(_me.display_name), "m": str(m.m)})
		"ping":
			message.emit({"t": "pong", "c": m.get("c", 0), "s": Time.get_ticks_msec()})


func _join() -> void:
	_vm = ClassDB.instantiate("LuauVM")
	_vm.open(64)
	var err: String = _vm.run("=runtime", FileAccess.get_file_as_string(PlaceHost.RUNTIME_PATH))
	if err != "":
		message.emit({"t": "error", "code": "not_found", "m": "runtime: " + err})
		return
	_vm.sandbox()
	_route(_call("__init", {"role": "server", "place": melt, "seed": randi(), "schema": StudioSchema.data()}))
	_route(_call("__start", ""))
	var snap: Variant = JSON.parse_string(_vm.call_function("__snapshot", "", TIME_LIMIT))
	var starter: Dictionary = {}
	for n in melt.tree.get("k", []):
		if n.get("c") == "StarterPlayer":
			starter = n.get("p", {})
	message.emit({
		"t": "welcome",
		"server": {"id": "test", "name": "Studio test", "name_ru": "Тест в студии", "players": 1, "max_players": 10},
		"you": int(_me.id),
		"chat": starter.get("ChatEnabled", true) != false,
		"emotes": starter.get("EmotesEnabled", true) != false,
		"place": {"id": "test", "strings": melt.get("strings", {}), "snapshot": snap if snap is Array else []},
		"spawn": [0, 5, 0],
		"players": [],
	})
	_route(_call("__dispatch", [{"e": "player_add", "userId": int(_me.id), "name": str(_me.username), "display": str(_me.display_name), "lang": L.lang}]))
	_flush()


func _process(delta: float) -> void:
	if not _vm:
		return
	var evs := _events
	_events = []
	if not _pos.is_empty():
		evs.append(_pos)
		_pos = {}
	if not evs.is_empty():
		_route(_call("__dispatch", evs))
	_route(_call("__step", {"dt": delta}))
	_flush()


func _call(fn: String, arg: Variant) -> Array:
	var out: String = _vm.call_function(fn, arg if arg is String else JSON.stringify(arg), TIME_LIMIT)
	var err: String = _vm.get_error()
	if err != "":
		_mine.append({"o": "print", "level": "error", "msg": err, "src": "server runtime", "server": true})
		return []
	var ops: Variant = JSON.parse_string(out) if out != "" else []
	return ops if ops is Array else []


## Same routing as the real server (server/src/game.js routeOps) for one player.
func _route(ops: Array) -> void:
	for op in ops:
		match str(op.get("o", "")):
			"new", "set", "del", "parent", "sound", "mesh", "meshv":
				_shared.append(op)
			"fire":
				_mine.append({"o": "fire", "id": op.id, "args": op.get("args", [])})
			"ret":
				_mine.append({"o": "ret", "rid": op.rid, "ok": op.ok, "values": op.get("values", [])})
			"spawn":
				_mine.append({"o": "spawn", "pos": op.pos})
			"print":
				var line: Dictionary = op.duplicate()
				line["server"] = true
				_mine.append(line)
			"kick":
				message.emit({"t": "kicked", "code": "place", "m": str(op.get("msg", ""))})
			"prompt_pass":
				_mine.append({"o": "prompt_pass", "id": op.id})
			"ds":
				# A play test keeps saved data in memory, for this test only.
				_events.append(_datastore(op))


var _ds := {}  # "store/key" -> value


func _datastore(op: Dictionary) -> Dictionary:
	var key := "%s/%s" % [str(op.get("store", "")), str(op.get("key", ""))]
	var out := {"e": "ds_ret", "rid": op.rid, "ok": true, "value": null, "err": ""}
	match str(op.get("op", "")):
		"get":
			out.value = _ds.get(key)
		"set":
			if op.get("value") == null:
				_ds.erase(key)
			else:
				_ds[key] = op.value
			out.value = op.get("value")
		"inc":
			var cur: Variant = _ds.get(key, 0)
			if not (cur is float or cur is int):
				out.ok = false
				out.err = "IncrementAsync needs a number stored at that key"
			else:
				_ds[key] = float(cur) + float(op.get("delta", 1))
				out.value = _ds[key]
		"remove":
			out.value = _ds.get(key)
			_ds.erase(key)
		"list":
			var prefix := str(op.get("store", "")) + "/"
			var keys: Array = []
			for k in _ds:
				if str(k).begins_with(prefix):
					keys.append(str(k).substr(prefix.length()))
			keys.sort()
			out.value = keys
	return out


func _flush() -> void:
	if _shared.is_empty() and _mine.is_empty():
		return
	var o := _shared + _mine
	_shared = []
	_mine = []
	message.emit({"t": "r", "o": o})
