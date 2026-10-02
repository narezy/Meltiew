class_name VRKeyboard
extends PanelContainer
## The keyboard VR puts in front of you while a text field of the app has the focus (the
## chat, a search box): point at its keys and pull the trigger, or poke them with a hand.
## English or Russian letters, Shift, Backspace, Enter (sends the chat) and a close key.

signal closed

## The app's text field the keys type into (LineEdit or TextEdit).
var target: Control

const ROWS := {
	"en": ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm.,?"],
	"ru": ["1234567890", "йцукенгшщзхъ", "фывапролджэ", "ячсмитьбю.,"],
}

var _lang := "ru" if L.lang == "ru" else "en"
var _shift := false
var _rows: VBoxContainer


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.96)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	_rows = UI.vbox(8)
	add_child(_rows)
	_build()


func _build() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for line: String in ROWS[_lang]:
		var row := UI.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for ch in line:
			var shown := ch.to_upper() if _shift else ch
			row.add_child(_key(shown, _type.bind(shown)))
		_rows.add_child(row)
	var last := UI.hbox(8)
	last.add_child(_key("⇧", _toggle_shift, 90, _shift))
	last.add_child(_key("RU" if _lang == "en" else "EN", _toggle_lang, 90))
	var space := _key(" ", _type.bind(" "), 0)
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last.add_child(space)
	last.add_child(_key("⌫", _backspace, 110))
	last.add_child(_key("⏎", _enter, 110))
	last.add_child(_key("✕", _close, 90))
	_rows.add_child(last)


func _key(text: String, on_press: Callable, width := 64, lit := false) -> Button:
	var b := UI.button(text, "primary" if lit else "ghost", 64)
	b.custom_minimum_size.x = width
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _type(ch: String) -> void:
	if target is LineEdit or target is TextEdit:
		target.call("insert_text_at_caret", ch)
	if _shift:
		_shift = false
		_build()


func _backspace() -> void:
	if target is LineEdit:
		var le := target as LineEdit
		if le.caret_column > 0:
			le.delete_text(le.caret_column - 1, le.caret_column)
	elif target is TextEdit:
		(target as TextEdit).backspace()


func _enter() -> void:
	if target is LineEdit:
		(target as LineEdit).text_submitted.emit((target as LineEdit).text)
	elif target is TextEdit:
		(target as TextEdit).insert_text_at_caret("\n")


func _toggle_shift() -> void:
	_shift = not _shift
	_build()


func _toggle_lang() -> void:
	_lang = "en" if _lang == "ru" else "ru"
	_build()


func _close() -> void:
	closed.emit()
