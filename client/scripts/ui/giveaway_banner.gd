class_name GiveawayBanner
extends PanelContainer
## The owner's giveaway on top of the menu: what's up for grabs, time left, and
## "take part". A day after it ends it shows the winner, then goes away.

var _g: Dictionary = {}
var _title: Label
var _info: Label
var _left: Label
var _btn: Button
var _poll := 0.0
## Shown only where the menu allows it (the home page).
var allowed := true:
	set(v):
		allowed = v
		if is_node_ready():
			_paint()
var _tick := 0.0


func _ready() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.CARD
	sb.border_color = UI.ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var row := UI.hbox(14)
	add_child(row)
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UI.label(L.t("gw_title").to_upper(), 13, UI.ACCENT, "black"))
	_title = UI.label("", 20, UI.TEXT, "black")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_info = UI.label("", 15, UI.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)
	_left = UI.label("", 15, UI.MINT, "bold")
	col.add_child(_left)
	_btn = UI.button(L.t("gw_enter"), "primary", 44)
	_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn.pressed.connect(_enter)
	row.add_child(_btn)
	_load()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 30.0
		_load()
	_tick -= delta
	if _tick <= 0.0 and not _g.is_empty():
		_tick = 1.0
		_show_left()


func _load() -> void:
	var r := await Api.request("GET", "/api/giveaway")
	if not is_inside_tree():
		return
	_g = r.data.get("giveaway", {}) if r.ok and r.data.get("giveaway") is Dictionary else {}
	_paint()


func _paint() -> void:
	visible = allowed and not _g.is_empty()
	if not visible:
		return
	var prize := "%s %s" % [int(_g.amount), L.t("gw_pieces" if _g.currency == "pieces" else "gw_orbs")]
	_title.text = str(_g.title)
	_info.text = "%s: %s · %d %s" % [L.t("gw_prize"), prize, int(_g.entries), L.t("gw_people")]
	if _g.done:
		var w: Variant = _g.get("winner")
		_left.text = ("%s: %s" % [L.t("gw_won"), w.display_name]) if w is Dictionary else L.t("gw_nobody")
		_btn.visible = false
		return
	_btn.visible = true
	_btn.disabled = bool(_g.entered)
	_btn.text = ("✓ " + L.t("gw_in")) if _g.entered else L.t("gw_enter")
	_show_left()


func _show_left() -> void:
	if _g.get("done", true):
		return
	var s := maxi(0, int((float(_g.ends_at) - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	var d := s / 86400
	var h := (s % 86400) / 3600
	var m := (s % 3600) / 60
	var t := ("%d%s %d%s" % [d, L.t("u_d"), h, L.t("u_h")]) if d > 0 else (("%d%s %d%s" % [h, L.t("u_h"), m, L.t("u_m")]) if h > 0 else "%d%s %d%s" % [m, L.t("u_m"), s % 60, L.t("u_s")])
	_left.text = "%s: %s" % [L.t("gw_left"), t]
	if s == 0:
		_poll = minf(_poll, 6.0)


func _enter() -> void:
	_btn.disabled = true
	var r := await Api.request("POST", "/api/giveaway/enter")
	if not is_inside_tree():
		return
	if not r.ok:
		_btn.disabled = false
		UI.toast(r.message, "error")
		return
	_g = r.data.giveaway
	Sfx.play("join")
	_paint()
