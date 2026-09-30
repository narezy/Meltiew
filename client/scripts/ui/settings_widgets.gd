class_name SettingsWidgets
extends RefCounted
## Settings controls shared by the menu Settings page and the in-game menu.



static func slider(parent: Control, title: String, key: String, lo: float, hi: float, step: float, percent := false) -> HSlider:
	var row := UI.hbox(8)
	row.add_child(UI.label(title, 19, UI.TEXT))
	row.add_child(UI.spacer())
	var val := UI.label("", 17, UI.MUTED, "bold")
	row.add_child(val)
	parent.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Session.settings[key])
	s.custom_minimum_size.y = 36
	s.focus_mode = Control.FOCUS_NONE
	var fmt := func(x: float) -> String:
		return "%d%%" % roundi(x * 100.0) if percent else "%.2fx" % x
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(x):
		val.text = fmt.call(x)
		Session.settings[key] = x
		Session.apply_settings()
		Session.settings_changed.emit())
	s.drag_ended.connect(func(_c): Session.save_settings())
	parent.add_child(s)
	return s


static func chips(parent: Control, title: String, key: String, options: Array, on_change := Callable()) -> void:
	var q := UI.hbox(8)
	q.add_child(UI.label(title, 19, UI.TEXT))
	q.add_child(UI.spacer())
	for opt in options:
		var b := UI.button(opt[1], "flat", 44)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_pressed = str(Session.settings.get(key, "")) == opt[0]
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			for c in q.get_children():
				if c is Button:
					c.button_pressed = c == b
			if on_change.is_valid():
				on_change.call(opt[0])
			else:
				Session.settings[key] = opt[0]
				Session.save_settings())
		q.add_child(b)
	parent.add_child(q)


static func toggle(parent: Control, title: String, key: String) -> CheckButton:
	var t := CheckButton.new()
	t.text = title
	t.button_pressed = bool(Session.settings.get(key, false))
	t.add_theme_font_size_override("font_size", 19)
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.toggled.connect(func(on):
		Session.settings[key] = on
		Session.save_settings())
	parent.add_child(t)
	return t


static func game_block(parent: Control) -> void:
	slider(parent, L.t("camera_sensitivity"), "camera_sensitivity", 0.3, 2.5, 0.05)
	slider(parent, L.t("volume"), "volume", 0.0, 1.0, 0.05, true)
	chips(parent, L.t("graphics"), "quality", [["low", L.t("quality_low")], ["medium", L.t("quality_medium")], ["high", L.t("quality_high")]])
	# Frame limit: "auto" is the screen's full rate on phones, none on computers; a lower
	# one keeps a phone cooler, if someone wants that.
	var fps_options := [["auto", L.t("fps_auto")], ["30", "30"], ["60", "60"], ["90", "90"], ["120", "120"]] if OS.has_feature("mobile") \
		else [["auto", L.t("fps_auto")], ["60", "60"], ["144", "144"], ["240", "240"], ["display", L.t("fps_display")], ["0", "∞"]]
	chips(parent, L.t("fps_limit"), "fps", fps_options)
	toggle(parent, L.t("show_fps"), "show_fps")
	toggle(parent, L.t("voice_hear"), "voice_hear")
	# Which microphone voice chat listens to.
	var mic_row := UI.hbox(8)
	mic_row.add_child(UI.label(L.t("mic_device"), 19, UI.TEXT))
	mic_row.add_child(UI.spacer())
	var pick := OptionButton.new()
	pick.custom_minimum_size.x = 240
	pick.clip_text = true
	var devices := AudioServer.get_input_device_list()
	for i in devices.size():
		pick.add_item(L.t("mic_default") if devices[i] == "Default" else devices[i], i)
		if devices[i] == str(Session.settings.get("mic_device", "Default")):
			pick.select(i)
	pick.item_selected.connect(func(i: int):
		Session.settings["mic_device"] = devices[i]
		AudioServer.input_device = devices[i]
		Session.save_settings())
	mic_row.add_child(pick)
	parent.add_child(mic_row)
	if not DisplayServer.is_touchscreen_available():
		toggle(parent, L.t("shift_lock"), "shift_lock")
