class_name StudioScriptEditor
extends VBoxContainer
## Luau script editor: syntax colors, auto-indent, completion of the Meltiew API,
## one tab per open script. Edits go into the script's Source (undoable per edit burst).

signal closed(id: String)

const KEYWORDS := ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue", "export", "type", "typeof"]
const GLOBALS := ["game", "workspace", "script", "Instance", "Vector3", "Vector2", "Color3", "UDim", "UDim2", "TweenInfo", "Enum", "task", "wait", "print", "warn", "require", "tick", "time", "Strings", "math", "string", "table", "coroutine", "pairs", "ipairs", "next", "select", "tostring", "tonumber", "pcall", "error", "assert", "setmetatable", "getmetatable", "os", "utf8", "bit32", "buffer"]
const MEMBERS := [
	"Parent", "Name", "ClassName", "FindFirstChild", "FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestor", "WaitForChild", "GetChildren", "GetDescendants",
	"IsA", "IsDescendantOf", "Destroy", "Clone", "ClearAllChildren", "GetPropertyChangedSignal", "GetFullName", "SetAttribute", "GetAttribute",
	"Connect", "Once", "Wait", "Disconnect", "Changed", "ChildAdded", "ChildRemoved", "Destroying",
	"GetService", "Players", "LocalPlayer", "PlayerAdded", "PlayerRemoving", "GetPlayers", "GetPlayerFromCharacter", "GetPlayerByUserId", "Character", "CharacterAdded", "Kick", "LoadCharacter", "Teleport",
	"Humanoid", "Health", "MaxHealth", "WalkSpeed", "JumpPower", "TakeDamage", "Died", "HealthChanged",
	"Touched", "TouchEnded", "Position", "Rotation", "Size", "Color", "Transparency", "Anchored", "CanCollide", "Material", "Shape",
	"FireServer", "FireClient", "FireAllClients", "OnServerEvent", "OnClientEvent", "InvokeServer", "OnServerInvoke", "Fire", "Event",
	"Activated", "MouseButton1Click", "Text", "TextColor", "BackgroundColor", "Visible", "FocusLost", "Value",
	"new", "fromRGB", "fromHex", "fromHSV", "fromScale", "fromOffset", "Magnitude", "Unit", "Lerp", "Dot", "Cross",
	"spawn", "defer", "delay", "cancel", "Heartbeat", "Create", "Play", "Completed", "MouseClick", "Play", "Stop", "MoveTo",
]

var doc: EditDoc
var _tabs: TabBar
var _code: CodeEdit
var _open: Array = []  # script ids
var _current := ""
var _pending_commit := 0.0
var _loading := false


func setup(d: EditDoc) -> void:
	doc = d
	add_theme_constant_override("separation", 0)
	_tabs = TabBar.new()
	_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	_tabs.tab_changed.connect(func(i):
		if i >= 0 and i < _open.size():
			_show(_open[i]))
	_tabs.tab_close_pressed.connect(func(i): close_script(_open[i]))
	# The studio's center tab bar shows the open scripts; this one only tracks them.
	_tabs.visible = false
	add_child(_tabs)
	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.indent_automatic = true
	_code.indent_use_spaces = false
	_code.auto_brace_completion_enabled = true
	_code.code_completion_enabled = true
	_code.minimap_draw = false
	_code.draw_tabs = false
	_code.caret_blink = true
	_code.highlight_current_line = true
	_code.add_theme_font_size_override("font_size", 16)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["JetBrains Mono", "Fira Code", "DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
	_code.add_theme_font_override("font", mono)
	_code.add_theme_color_override("background_color", Color("#15131c"))
	_code.add_theme_color_override("current_line_color", Color("#1f1b2a"))
	_code.add_theme_color_override("font_color", Color("#e8e4f2"))
	_code.add_theme_color_override("line_number_color", Color("#5d5775"))
	_code.syntax_highlighter = _highlighter()
	_code.delimiter_comments = PackedStringArray(["--"])
	_code.delimiter_strings = PackedStringArray(["\" \"", "' '"])
	_code.indent_automatic_prefixes = PackedStringArray(["then", "do", "function", "(", "{", "repeat", "else"])
	_code.text_changed.connect(func():
		if not _loading:
			_pending_commit = 0.6
		_code.request_code_completion())
	_code.code_completion_requested.connect(_complete)
	add_child(_code)
	rebind()


func rebind() -> void:
	doc.tree.removed.connect(func(id, _p):
		if id in _open:
			close_script(id))


func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("#ffb86b")
	h.symbol_color = Color("#b8b0d0")
	h.function_color = Color("#7ee0c3")
	h.member_variable_color = Color("#e8e4f2")
	for k in KEYWORDS:
		h.add_keyword_color(k, Color("#ff8fb1"))
	for g in GLOBALS:
		h.add_keyword_color(g, Color("#b89cff"))
	h.add_color_region("--", "", Color("#6f6a85"), true)
	h.add_color_region("\"", "\"", Color("#ffd166"))
	h.add_color_region("'", "'", Color("#ffd166"))
	h.add_color_region("`", "`", Color("#ffd166"))
	return h


func open_script(id: String) -> void:
	if not id in _open:
		_open.append(id)
		_tabs.add_tab(doc.tree.name_of(id))
	_tabs.current_tab = _open.find(id)
	_show(id)


func close_script(id: String) -> void:
	_commit()
	var i := _open.find(id)
	if i < 0:
		return
	_open.remove_at(i)
	_tabs.remove_tab(i)
	if _current == id:
		_current = ""
		if not _open.is_empty():
			_show(_open[mini(i, _open.size() - 1)])
	closed.emit(id)


func has_open() -> bool:
	return not _open.is_empty()


func current() -> String:
	return _current


func _show(id: String) -> void:
	_commit()
	_current = id
	_loading = true
	_code.text = str(doc.tree.prop(id, "Source"))
	_code.clear_undo_history()
	_loading = false
	_code.grab_focus()


func _process(delta: float) -> void:
	if _pending_commit > 0.0:
		_pending_commit -= delta
		if _pending_commit <= 0.0:
			_commit()


## Saves the editor text into the script (one undo step per typing burst).
func _commit() -> void:
	_pending_commit = 0.0
	if _current != "" and doc.tree.has(_current) and str(doc.tree.prop(_current, "Source")) != _code.text:
		doc.set_prop(_current, "Source", _code.text)


func goto_line(line: int) -> void:
	_code.set_caret_line(maxi(line - 1, 0))
	_code.center_viewport_to_caret()


func _complete() -> void:
	var line := _code.get_line(_code.get_caret_line()).substr(0, _code.get_caret_column())
	var word := ""
	var i := line.length() - 1
	while i >= 0 and (line[i].is_valid_identifier() or line[i].is_valid_int() or line[i] == "_"):
		word = line[i] + word
		i -= 1
	if word.length() < 2:
		return
	var after_dot := i >= 0 and (line[i] == "." or line[i] == ":")
	var pool: Array = MEMBERS if after_dot else KEYWORDS + GLOBALS
	if not after_dot and line.ends_with("\"" + word):
		pool = StudioSchema.data().classes.keys()
	for w in pool:
		if str(w).begins_with(word) and str(w) != word:
			_code.add_code_completion_option(CodeEdit.KIND_MEMBER if after_dot else CodeEdit.KIND_PLAIN_TEXT, w, w)
	# Class names inside Instance.new("...").
	if line.contains("Instance.new(\""):
		for c in StudioSchema.data().classes.keys():
			if str(c).begins_with(word) and StudioSchema.raw(c).get("creatable", false):
				_code.add_code_completion_option(CodeEdit.KIND_CLASS, c, c)
	_code.update_code_completion_options(false)
