class_name ShopPage
extends HBoxContainer
## The shop: try things on the 3D Melly, buy them for pieces (or orbs, where the
## item allows it), then wear them. What you own lives in the avatar editor.

var _stage: AvatarStage
var _items := {"accessory": [], "face": [], "clothing": []}  # accessories/faces from /api/shop; clothing from /api/clothing
var _tab := "accessory"
var _look_acc: Array = []
var _look_face := ":D"
var _look_clothes: Array = []  # clothing ids being tried on, bottom to top
var _grid: GridContainer
var _tab_buttons := {}
var _wear: Button
var _cols := 2
var _grid_empty := false  # a message instead of cards: one full-width column


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var compact := UI.is_compact()
	add_theme_constant_override("separation", 16 if compact else 24)
	_look_acc = Session.worn_of(Session.user).duplicate()
	_look_face = str(Session.user.get("face", ":D"))
	_look_clothes = _my_clothes()

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
		_look_clothes = _my_clothes()
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
	for t in [["accessory", L.t("accessories")], ["face", L.t("faces")], ["clothing", L.t("clothing")]]:
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
	sc.resized.connect(func():
		_cols = maxi(2, int((sc.size.x - 14.0) / 150.0))
		_grid.columns = 1 if _grid_empty else _cols)

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
	var c := await Api.request("GET", "/api/clothing?sort=popular")
	if c.ok and is_inside_tree():
		_items.clothing = c.data.get("items", [])
	_draw()


func _my_clothes() -> Array:
	var c: Variant = Session.user.get("clothes", [])
	return (c as Array).map(func(x): return int(x)) if c is Array else []


func _owns(kind: String, it: Dictionary) -> bool:
	if kind == "clothing":
		return bool(it.get("owned", false))
	return it.get("owned", false) or not (it.get("price") is Dictionary) or Economy.owned(kind).has(str(it.id))


func _trying(kind: String, id: String) -> bool:
	if kind == "clothing":
		return int(id) in _look_clothes
	return id in _look_acc if kind == "accessory" else id == _look_face


func _draw() -> void:
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == _tab
	for c in _grid.get_children():
		c.queue_free()
	for it in _items[_tab]:
		_grid.add_child(_cloth_card(it) if _tab == "clothing" else _card(_tab, it))
	_grid_empty = _tab == "clothing" and _items.clothing.is_empty()
	_grid.columns = 1 if _grid_empty else _cols
	if _grid_empty:
		var empty := UI.label(L.t("clothing_empty"), 16, UI.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(empty)
	_update_wear()


## A piece of clothing: the front of its shirt over your body colour (tap to try it on),
## its name and maker, and "get" / "buy" / "wear".
func _cloth_card(it: Dictionary) -> Control:
	var id := int(it.id)
	var card := UI.card(8, UI.BG_2 if not _trying("clothing", str(id)) else Color(UI.ACCENT, 0.22), 18)
	card.custom_minimum_size = Vector2(136, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	card.add_child(v)
	var pic_btn := Button.new()
	pic_btn.flat = true
	pic_btn.focus_mode = Control.FOCUS_NONE
	pic_btn.custom_minimum_size = Vector2(0, 110)
	var tile := Panel.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(str(Session.colors_of(Session.user).get("torso", "#8a7cf0")))
	sb.set_corner_radius_all(12)
	tile.add_theme_stylebox_override("panel", sb)
	var front := ClothingLayout.torso_front()
	tile.custom_minimum_size = front.size * 0.52
	tile.set_anchors_preset(Control.PRESET_CENTER)
	tile.offset_left = -front.size.x * 0.26
	tile.offset_right = front.size.x * 0.26
	tile.offset_top = -front.size.y * 0.26
	tile.offset_bottom = front.size.y * 0.26
	pic_btn.add_child(tile)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(pic)
	var wr: WeakRef = weakref(pic)
	AssetCache.fetch(str(it.image), func(t: Texture2D):
		var p: TextureRect = wr.get_ref()
		if p and t:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = front
			p.texture = at)
	pic_btn.pressed.connect(func():
		Sfx.click()
		if id in _look_clothes:
			_look_clothes.erase(id)
		else:
			_look_clothes.append(id)
			_look_clothes = _look_clothes.slice(maxi(0, _look_clothes.size() - 5))
		_preview()
		_draw())
	v.add_child(pic_btn)
	v.add_child(_card_name(str(it.name)))
	var by: Variant = it.get("community") if it.get("community") is Dictionary else it.get("creator")
	if by is Dictionary:
		var who := UI.label(str(by.get("name", by.get("display_name", ""))), 12, UI.MUTED)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(who)
	if it.get("owned", false):
		var worn := id in _my_clothes()
		var b := UI.button(L.t("shop_worn") if worn else L.t("shop_wear"), "ghost", 40)
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = worn
		b.pressed.connect(func():
			var mine := _my_clothes()
			mine.append(id)
			_save_clothes(mine.slice(maxi(0, mine.size() - 5))))
		v.add_child(b)
	else:
		var price := int(it.get("price", 0))
		var b := UI.button(L.t("clothing_get") if price == 0 else "", "primary", 40)
		if price > 0:
			var row := Economy.price_tag({"pieces": price}, 15, "pieces")
			row.set_anchors_preset(Control.PRESET_FULL_RECT)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			b.add_child(row)
		b.pressed.connect(func(): _buy_cloth(it))
		v.add_child(b)
	return card


## An item's name under its picture: up to two lines, then "…" (a long name never
## widens the card).
static func _card_name(text: String) -> Label:
	var l := UI.label(text, 15, UI.TEXT, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 60
	return l


func _buy_cloth(it: Dictionary) -> void:
	var price := int(it.get("price", 0))
	if price > 0:
		var price_text := "%d %s" % [price, L.t("eco_pieces")]
		if not await UI.confirm(self, L.t("shop_buy_q", [it.name]), L.t("shop_buy_text", [it.name, price_text]), L.t("buy")):
			return
	var r := await Api.request("POST", "/api/clothing/%d/buy" % int(it.id))
	if not is_inside_tree():
		return
	if not r.ok:
		UI.toast(r.message, "error")
		return
	if r.data.get("wallet") is Dictionary:
		Economy.set_wallet(r.data.wallet)
	UI.toast(L.t("shop_bought", [it.name]), "ok")
	if not int(it.id) in _look_clothes:
		_look_clothes.append(int(it.id))
		_preview()
	_load()


## Wearing clothes: the list goes to the server, bottom to top (at most 5).
func _save_clothes(worn: Array) -> bool:
	var r := await Api.request("PUT", "/api/me/clothing", {"worn": worn})
	if not is_inside_tree():
		return false
	if not r.ok:
		UI.toast(r.message, "error")
		return false
	var u := Session.user.duplicate()
	u["clothes"] = r.data.get("worn", worn)
	Session.set_user(u)
	Busts.sync_my_render()
	_look_clothes = _my_clothes()
	_preview()
	_draw()
	return true


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
	v.add_child(_card_name(Accessories.name_of(id) if kind == "accessory" else id))
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
	_stage.avatar.set_clothes(_look_clothes)
	_update_wear()


## "Wear this look" only makes sense when what you try on is all yours and differs from now.
func _update_wear() -> void:
	if not _wear:
		return
	var mine_acc := Economy.owned("accessory")
	var all_mine := _look_acc.all(func(a): return mine_acc.has(a)) and (Economy.owned("face").has(_look_face) or _look_face == str(Session.user.get("face", "")))
	var same: bool = _look_acc == Session.worn_of(Session.user) and _look_face == str(Session.user.get("face", "")) and _look_clothes == _my_clothes()
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
	if _look_clothes != _my_clothes():
		# Only what's yours goes on; the rest stays a try-on.
		var owned := {}
		for it in _items.clothing:
			if it.get("owned", false):
				owned[int(it.id)] = true
		for id in _my_clothes():
			owned[id] = true
		if not await _save_clothes(_look_clothes.filter(func(x): return owned.has(x))):
			return
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
