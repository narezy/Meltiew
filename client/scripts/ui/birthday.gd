class_name BirthdayInput
extends HBoxContainer
## Day / month / year pickers. value() returns "YYYY-MM-DD" or "" if incomplete.

var _day: OptionButton
var _month: OptionButton
var _year: OptionButton


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_day = _picker(L.t("bd_day"))
	for d in range(1, 32):
		_day.add_item(str(d), d)
	_month = _picker(L.t("bd_month"))
	var months: PackedStringArray = L.t("bd_months").split(",")
	for m in 12:
		_month.add_item(months[m] if m < months.size() else str(m + 1), m + 1)
	_year = _picker(L.t("bd_year"))
	var now := Time.get_date_dict_from_system()
	for y in range(int(now.year) - 3, int(now.year) - 100, -1):
		_year.add_item(str(y), y)
	for p in [_day, _month, _year]:
		add_child(p)
	_month.size_flags_stretch_ratio = 1.6


func _picker(placeholder: String) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.y = 52
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 18)
	o.add_item(placeholder, 0)
	o.set_item_disabled(0, true)
	o.select(0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.BG_2
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = UI.LINE
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	for st in ["normal", "hover", "pressed", "focus"]:
		o.add_theme_stylebox_override(st, sb)
	o.add_theme_color_override("font_color", UI.TEXT)
	return o


func value() -> String:
	var d := _day.get_selected_id()
	var m := _month.get_selected_id()
	var y := _year.get_selected_id()
	if d <= 0 or m <= 0 or y <= 0:
		return ""
	return "%04d-%02d-%02d" % [y, m, d]


## Modal that asks for the date of birth and saves it. Returns true once saved.
## `changing` = the player already has a date and is using a change (different wording).
static func ask(parent: Node, changing := false) -> bool:
	var layer := CanvasLayer.new()
	layer.layer = 70
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var c := UI.card(26, UI.CARD, 26)
	c.custom_minimum_size.x = 520
	center.add_child(c)
	var v := UI.vbox(14)
	c.add_child(v)
	v.add_child(UI.label(L.t("bd_title"), 26, UI.TEXT, "black"))
	var why := UI.label(L.t("bd_change_why" if changing else "bd_why"), 17, UI.MUTED)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(why)
	var picker := BirthdayInput.new()
	v.add_child(picker)
	var err := UI.label("", 16, UI.DANGER)
	err.visible = false
	v.add_child(err)
	var row := UI.hbox(10)
	v.add_child(row)
	var later := UI.button(L.t("cancel" if changing else "bd_later"), "ghost")
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(later)
	var save := UI.button(L.t("save"))
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(save)
	var result := [false, false]  # done, saved
	later.pressed.connect(func(): result[0] = true)
	save.pressed.connect(func():
		var val := picker.value()
		if val == "":
			err.text = L.t("bd_incomplete")
			err.visible = true
			return
		save.disabled = true
		var r := await Api.request("PATCH", "/api/me", {"birthdate": val})
		save.disabled = false
		if r.ok:
			Session.set_user(r.data.user)
			result[1] = true
			result[0] = true
		else:
			err.text = r.message
			err.visible = true)
	while not result[0]:
		await parent.get_tree().process_frame
	layer.queue_free()
	return result[1]
