class_name Launcher
extends RefCounted
## "Play" on the website: the Android app stores the meltiew://play?server=..&game=..
## link it was opened with in user://launch_intent.txt (see GodotApp.java).

const FILE := "user://launch_intent.txt"


## The pending launch as {server, game}, or {} if there is none. Reading it clears it.
static func take() -> Dictionary:
	if not FileAccess.file_exists(FILE):
		return {}
	var uri := FileAccess.get_file_as_string(FILE).strip_edges()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var out := {"server": "auto", "game": "playground"}
	var q := uri.get_slice("?", 1) if "?" in uri else ""
	for pair in q.split("&", false):
		var kv := pair.split("=")
		if kv.size() == 2 and kv[0] in ["server", "game"]:
			var v := kv[1].uri_decode()
			if v.length() <= 40 and (v.is_valid_identifier() or v.is_valid_int()):
				out[kv[0]] = v
	return out
