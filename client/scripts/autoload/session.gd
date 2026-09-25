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
## Emitted whenever a setting changes, so open screens can apply it right away.
signal settings_changed

var token := ""
var user: Dictionary = {}
var settings := {
	"camera_sensitivity": 1.0,
	"volume": 0.8,
	"music": 0.5,
	"quality": "high",
	"show_fps": false,
	# Empty until the first run picks the phone's language.
	"lang": "",
	# 0 = automatic (bigger on phones).
	"ui_scale": 0.0,
	# Bumped when the graphics presets change, to re-pick the default.
	"gfx_v": 2,
}
## Where the game scene should go when it opens: "auto", "new" or a server id.
var pending_server := "auto"
## Which place the game scene joins: "playground" or a studio place id.
var pending_game := "playground"
## Studio: the place being edited (id and its unsaved state), and the place being play-tested.
var studio_place_id := ""
var studio_melt: Dictionary = {}
var test_melt: Dictionary = {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_FILE) == OK:
		token = str(cfg.get_value("auth", "token", ""))
	if OS.has_feature("mobile"):
		settings.quality = "medium"
	var s := ConfigFile.new()
	if s.load(SETTINGS_FILE) == OK:
		var old_gfx := int(s.get_value("settings", "gfx_v", 1))
		for key in settings.keys():
			settings[key] = s.get_value("settings", key, settings[key])
		# 1.3 and older defaulted phones to "high"; start them on the lighter preset.
		if old_gfx < 2:
			settings.gfx_v = 2
			if OS.has_feature("mobile") and settings.quality == "high":
				settings.quality = "medium"
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
	settings_changed.emit()


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(settings.volume), 0.0001)))


## What someone wears: `accessories` from newer servers, else the single old `hat`.
static func worn_of(u: Dictionary) -> Array:
	var list: Variant = u.get("accessories")
	if list is Array:
		return list.map(func(x): return str(x))
	var hat := str(u.get("hat", "none"))
	return [] if hat == "none" or hat == "" else [hat]


## Stable fingerprint of how an avatar looks; used to cache/upload bust renders.
static func look_hash(u: Dictionary) -> String:
	var c := colors_of(u)
	var parts := []
	for part in BODY_PARTS:
		parts.append(str(c[part]))
	var worn := worn_of(u)
	worn.sort()
	parts.append("+".join(worn))
	parts.append(str(u.get("face", ":D")))
	parts.append("v4")
	return "|".join(parts).md5_text().substr(0, 16)


static func colors_of(u: Dictionary) -> Dictionary:
	var out := DEFAULT_COLORS.duplicate()
	var c: Variant = u.get("colors", {})
	if typeof(c) == TYPE_DICTIONARY:
		for part in BODY_PARTS:
			if c.has(part):
				out[part] = str(c[part])
	return out
