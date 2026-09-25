extends Node
## Holds the signed-in user, the auth token and local settings.

const SESSION_FILE := "user://session.cfg"
const SETTINGS_FILE := "user://settings.cfg"
const BODY_PARTS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
const DEFAULT_COLORS := {
	"torso": "#baa4e2", "head": "#f5f1ec", "arm_l": "#f5f1ec",
	"arm_r": "#f5f1ec", "leg_l": "#302d38", "leg_r": "#302d38",
}

signal user_changed

var token := ""
var user: Dictionary = {}
var settings := {
	"camera_sensitivity": 1.0,
	"volume": 0.8,
	"music": 0.5,
	"quality": "high",
	"show_fps": false,
	"lang": "en",
}
## Where the game scene should go when it opens: "auto", "new" or a server id.
var pending_server := "auto"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_FILE) == OK:
		token = str(cfg.get_value("auth", "token", ""))
	var s := ConfigFile.new()
	if s.load(SETTINGS_FILE) == OK:
		for key in settings.keys():
			settings[key] = s.get_value("settings", key, settings[key])
	apply_settings()


func set_auth(new_token: String, new_user: Dictionary) -> void:
	token = new_token
	set_user(new_user)
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token)
	cfg.save(SESSION_FILE)


func set_user(new_user: Dictionary) -> void:
	user = new_user
	user_changed.emit()


func clear() -> void:
	token = ""
	user = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))


func save_settings() -> void:
	var s := ConfigFile.new()
	for key in settings.keys():
		s.set_value("settings", key, settings[key])
	s.save(SETTINGS_FILE)
	apply_settings()


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(settings.volume), 0.0001)))


## Stable fingerprint of how an avatar looks; used to cache/upload bust renders.
static func look_hash(u: Dictionary) -> String:
	var c := colors_of(u)
	var parts := []
	for part in BODY_PARTS:
		parts.append(str(c[part]))
	parts.append(str(u.get("hat", "none")))
	parts.append("v1")
	return "|".join(parts).md5_text().substr(0, 16)


static func colors_of(u: Dictionary) -> Dictionary:
	var out := DEFAULT_COLORS.duplicate()
	var c: Variant = u.get("colors", {})
	if typeof(c) == TYPE_DICTIONARY:
		for part in BODY_PARTS:
			if c.has(part):
				out[part] = str(c[part])
	return out
