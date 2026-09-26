class_name ShopPage
extends HBoxContainer
## The shop: try things on the 3D Melly, buy them for pieces (or orbs, where the
## item allows it), then wear them. What you own lives in the avatar editor.

var _stage: AvatarStage
var _items := {"accessory": [], "face": []}  # from /api/shop: {id, price, owned}
var _tab := "accessory"
var _look_acc: Array = []
var _look_face := ":D"
var _grid: GridContainer
var _tab_buttons := {}
var _wear: Button


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var compact := UI.is_compact()
	add_theme_constant_override("separation", 16 if compact else 24)
	_look_acc = Session.worn_of(Session.user).duplicate()
	_look_face = str(Session.user.get("face", ":D"))

	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.62 if compact else 0.8
	add_child(left)
	var title_row := UI.hbox(10)
	var title := UI.label(L.t("nav_shop"), 34, UI.TEXT, "black")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(Economy.chips(self))
	left.add_child(title_row)
	var stage_card := UI.card(0, Color(UI.CARD, 0.55), 26)
	stage_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(stage_card)
	_stage = AvatarStage.new()
	_stage.zoom = 1.15
	stage_card.add_child(_stage)
	var tools := UI.hbox(10)
	var reset := UI.button(L.t("shop_reset_look"), "ghost", 44 if compact else 48)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		_look_acc = Session.worn_of(Session.user).duplicate()
		_look_face = str(Session.user.get("face", ":D"))
		_preview())
	tools.add_child(reset)
	_wear = UI.button(L.t("shop_wear_all"), "primary", 44 if compact else 48)
	_wear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wear.pressed.connect(_wear_look)
	tools.add_child(_wear)
	if compact:
		for b in tools.get_children():
			b.add_theme_font_size_override("font_size", 15)
	left.add_child(tools)

	var right := UI.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var tabs := UI.hbox(8)
	for t in [["accessory", L.t("accessories")], ["face", L.t("faces")]]:
		var b := UI.button(t[1], "flat", 46)
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_tab = t[0]
			_draw())
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	right.add_child(tabs)
	var body := UI.card(16, UI.CARD, 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(_grid)
	# As many columns as fit; the cards stretch to fill the row.
	sc.resized.connect(func(): _grid.columns = maxi(2, int((sc.size.x - 14.0) / 150.0)))

	_preview()
	_load()


func refresh() -> void:
	_load()


func _load() -> void:
	var r := await Api.request("GET", "/api/shop")
	if not r.ok or not is_inside_tree():
		if not r.ok:
			UI.toast(r.message, "error")
		return
	_items.accessory = r.data.get("accessories", [])
	_items.face = r.data.get("faces", [])
	if r.data.get("wallet") is Dictionary:
		Economy.set_wallet(r.data.wallet, Session.user.get("owned", null))
	_draw()


func _owns(kind: String, it: Dictionary) -> bool:
	return it.get("owned", false) or not (it.get("price") is Dictionary) or Economy.owned(kind).has(str(it.id))


func _trying(kind: String, id: String) -> bool:
	return id in _look_acc if kind == "accessory" else id == _look_face


func _draw() -> void:
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == _tab
	for c in _grid.get_children():
		c.queue_free()
	for it in _items[_tab]:
		_grid.add_child(_card(_tab, it))
	_update_wear()


## One item: its picture (tap to try on), name, and either buy buttons or "wear".
func _card(kind: String, it: Dictionary) -> Control:
	var id := str(it.id)
	var card := UI.card(8, UI.BG_2 if not _trying(kind, id) else Color(UI.ACCENT, 0.22), 18)
	card.custom_minimum_size = Vector2(136, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	card.add_child(v)
	var pic_btn := Button.new()
	pic_btn.flat = true
	pic_btn.focus_mode = Control.FOCUS_NONE
	pic_btn.custom_minimum_size = Vector2(0, 100)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic_btn.add_child(pic)
	if kind == "accessory":
		# Weak: the grid is redrawn often and the picture may be gone when the thumbnail comes.
		var wr: WeakRef = weakref(pic)
		AccessoryThumbs.fetch(id, func(t: Texture2D):
			var p: TextureRect = wr.get_ref()
			if p:
				p.texture = t)
	else:
		# The face on a skin-colored tile, the way it sits on Melly's head.
		var tile := Panel.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(str(Session.colors_of(Session.user).get("head", "#f5f1ec")))
		sb.set_corner_radius_all(16)
		tile.add_theme_stylebox_override("panel", sb)
		tile.custom_minimum_size = Vector2(84, 84)
		tile.set_anchors_preset(Control.PRESET_CENTER)
		tile.offset_left = -42
		tile.offset_right = 42
		tile.offset_top = -42
		tile.offset_bottom = 42
		pic_btn.add_child(tile)
		pic.reparent(tile)
		pic.texture = Faces.texture(id)
	pic_btn.pressed.connect(func():
		Sfx.click()
		_try(kind, id))
	v.add_child(pic_btn)
	var name := UI.label(Accessories.name_of(id) if kind == "accessory" else id, 15, UI.TEXT, "bold")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.custom_minimum_size.x = 100
	v.add_child(name)
	if _owns(kind, it):
		var worn: bool = id in Session.worn_of(Session.user) if kind == "accessory" else id == str(Session.user.get("face", ""))
		var b := UI.button(L.t("shop_worn") if worn else L.t("shop_wear"), "ghost", 40)
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = worn
		b.pressed.connect(func(): _wear_one(kind, id))
		v.add_child(b)
	else:
		var price: Dictionary = it.price
		for cur in ["pieces", "orbs"]:
			if not price.has(cur):
				continue
			var b := UI.button("", "primary" if cur == "pieces" else "ghost", 40)
			var row := Economy.price_tag(price, 15, cur)
			row.set_anchors_preset(Control.PRESET_FULL_RECT)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			if cur == "pieces":
				var buy := UI.label(L.t("buy"), 15, UI.BG, "black")
				buy.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(buy)
				row.move_child(buy, 0)
				(row.get_child(2) as Label).add_theme_color_override("font_color", UI.BG)
			b.add_child(row)
			b.pressed.connect(func(): _buy(kind, id, cur, int(price[cur])))
			v.add_child(b)
	return card


func _try(kind: String, id: String) -> void:
	if kind == "accessory":
		if id in _look_acc:
			_look_acc.erase(id)
		else:
			_look_acc = Accessories.wear(_look_acc, id)
	else:
		_look_face = str(Session.user.get("face", ":D")) if _look_face == id else id
	_preview()
	_draw()


func _preview() -> void:
	_stage.avatar.set_colors(Session.colors_of(Session.user))
	_stage.avatar.set_accessories(_look_acc)
	_stage.avatar.set_face(_look_face)
	_update_wear()


## "Wear this look" only makes sense when what you try on is all yours and differs from now.
func _update_wear() -> void:
	if not _wear:
		return
	var mine_acc := Economy.owned("accessory")
	var all_mine := _look_acc.all(func(a): return mine_acc.has(a)) and (Economy.owned("face").has(_look_face) or _look_face == str(Session.user.get("face", "")))
	var same: bool = _look_acc == Session.worn_of(Session.user) and _look_face == str(Session.user.get("face", ""))
	_wear.disabled = same or not all_mine
	_wear.tooltip_text = "" if all_mine else L.t("shop_buy_first")


func _buy(kind: String, id: String, cur: String, amount: int) -> void:
	var what := Accessories.name_of(id) if kind == "accessory" else id
	var price_text := "%d %s" % [amount, L.t("eco_pieces") if cur == "pieces" else L.t("eco_orbs")]
	if not await UI.confirm(self, L.t("shop_buy_q", [what]), L.t("shop_buy_text", [what, price_text]), L.t("buy")):
		return
	if not await Economy.buy(kind, id, cur):
		return
	UI.toast(L.t("shop_bought", [what]), "ok")
	if not _trying(kind, id):
		_try(kind, id)
	_load()


func _wear_one(kind: String, id: String) -> void:
	if kind == "accessory":
		await _save_look(Accessories.wear(Session.worn_of(Session.user), id), str(Session.user.get("face", ":D")))
	else:
		await _save_look(Session.worn_of(Session.user), id)


func _wear_look() -> void:
	await _save_look(_look_acc, _look_face)


func _save_look(acc: Array, face: String) -> void:
	var r := await Api.request("PATCH", "/api/me", {"accessories": acc, "face": face})
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		return
	Session.set_user(r.data.user)
	Busts.sync_my_render()
	UI.toast(L.t("look_saved"), "ok")
	_stage.avatar.play("wave")
	_draw()
