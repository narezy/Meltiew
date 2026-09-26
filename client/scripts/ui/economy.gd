class_name Economy
extends RefCounted
## Pieces (bought) and orbs (earned): balances, price tags, buying items, the
## "buy pieces" sheet, daily quests and gamepass purchases.

const PIECE_COLOR := Color("#ffb86b")
const ORB_COLOR := Color("#9d7bff")


static func wallet() -> Dictionary:
	return Session.user.get("wallet", {"pieces": 0, "orbs": 0})


static func pieces_text() -> String:
	var w := wallet()
	return "∞" if w.get("infinite", false) else str(int(w.get("pieces", 0)))


static func owned(kind: String) -> Array:
	var o: Dictionary = Session.user.get("owned", {})
	if kind == "face":
		return o.get("faces", [":D", ":)"])
	return o.get("accessories", [])


static func set_wallet(w: Dictionary, owned_items: Variant = null) -> void:
	var u := Session.user.duplicate()
	u.wallet = w
	if owned_items is Dictionary:
		u.owned = owned_items
	Session.set_user(u)


## A small "icon + number" label for a price ({pieces} or {orbs}).
static func price_tag(price: Variant, size := 16) -> Control:
	var row := UI.hbox(4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not (price is Dictionary) or price.is_empty():
		return row
	var is_pieces: bool = price.has("pieces")
	row.add_child(Icon.make("piece" if is_pieces else "orb", size + 2, PIECE_COLOR if is_pieces else ORB_COLOR))
	row.add_child(UI.label(str(int(price.pieces if is_pieces else price.orbs)), size, UI.TEXT, "black"))
	return row


## Balance chips; tapping pieces opens the shop of packs, tapping orbs the quests.
static func chips(parent: Node) -> HBoxContainer:
	var row := UI.hbox(8)
	var fill := func():
		for c in row.get_children():
			c.queue_free()
		row.add_child(_chip("piece", PIECE_COLOR, pieces_text(), func(): open_buy_pieces(parent)))
		row.add_child(_chip("orb", ORB_COLOR, str(int(wallet().get("orbs", 0))), func(): open_quests(parent)))
	fill.call()
	Session.user_changed.connect(func():
		if is_instance_valid(row):
			fill.call())
	return row


static func _chip(icon: String, tint: Color, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 44
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.9)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var row := UI.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -14
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(Icon.make(icon, 22, tint))
	var l := UI.label(text, 18, UI.TEXT, "black")
	row.add_child(l)
	b.add_child(row)
	b.custom_minimum_size.x = 52 + text.length() * 11
	b.pressed.connect(func():
		Sfx.click()
		on_press.call())
	return b


## Buys one item (accessory or face). Returns true when it's yours.
static func buy(kind: String, id: String) -> bool:
	var r := await Api.request("POST", "/api/shop/buy", {"kind": kind, "id": id})
	if not r.ok:
		UI.toast(r.message, "error")
		return false
	set_wallet(r.data.wallet, r.data.owned)
	Sfx.play("coin")
	return true


# --- sheets --------------------------------------------------------------------------

## A centered card over a dim layer; returns [layer, content vbox].
static func _sheet(parent: Node, title: String, width := 560.0) -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 70
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.theme = UI.theme
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	var vp := parent.get_viewport().get_visible_rect().size
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var card := UI.card(22, UI.CARD, 22)
	card.custom_minimum_size = Vector2(minf(width, vp.x - 32.0), 0)
	center.add_child(card)
	var outer := UI.vbox(12)
	card.add_child(outer)
	var head := UI.hbox(8)
	var tl := UI.label(title, 24, UI.TEXT, "black")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var close := UI.button("✕", "ghost", 44)
	close.custom_minimum_size.x = 48
	close.pressed.connect(layer.queue_free)
	head.add_child(close)
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = minf(460.0, vp.y - 170.0)
	outer.add_child(scroll)
	var v := UI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return [layer, v]


## Packs of pieces: paying opens the payment page in the browser.
static func open_buy_pieces(parent: Node) -> void:
	var s := _sheet(parent, L.t("eco_pieces"))
	var v: VBoxContainer = s[1]
	var note := UI.label(L.t("eco_pieces_about"), 15, UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	v.add_child(Loading.spinner(30))
	var r := await Api.request("GET", "/api/pay/packs")
	if not is_instance_valid(v):
		return
	v.get_child(1).queue_free()
	if not r.ok:
		v.add_child(UI.label(r.message, 16, UI.DANGER))
		return
	if not r.data.payments:
		var soon := UI.label(L.t("eco_pay_soon"), 17, UI.TEXT, "bold")
		soon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(soon)
	for p in r.data.packs:
		var row := UI.card(14, UI.BG_2, 18)
		var h := UI.hbox(12)
		row.add_child(h)
		h.add_child(Icon.make("piece", 34, PIECE_COLOR))
		var n := UI.label(str(int(p.pieces)), 26, UI.TEXT, "black")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var b := UI.button(L.t("eco_buy_for", [int(p.rub)]), "primary", 48)
		b.disabled = not r.data.payments
		var pack_id := str(p.id)
		b.pressed.connect(func():
			b.disabled = true
			var pay := await Api.request("POST", "/api/pay", {"pack": pack_id})
			if not pay.ok:
				UI.toast(pay.message, "error")
				b.disabled = false
				return
			Session.set_meta("pending_pay", str(pay.data.id))
			OS.shell_open(str(pay.data.pay_url))
			UI.toast(L.t("eco_pay_opened"), "ok"))
		h.add_child(b)
		v.add_child(row)
	var legal := UI.label(L.t("eco_pay_note"), 13, UI.MUTED)
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(legal)
	var links := UI.hbox(10)
	for l in [["eco_terms", "/terms"], ["eco_privacy", "/privacy"], ["eco_support", "/support"]]:
		var lb := UI.button(L.t(l[0]), "ghost", 36)
		lb.add_theme_font_size_override("font_size", 14)
		var path: String = l[1]
		lb.pressed.connect(func(): OS.shell_open(Api.BASE_URL + path))
		links.add_child(lb)
	v.add_child(links)


## After coming back from the browser: did the payment go through?
static func check_pending_payment() -> void:
	var id := str(Session.get_meta("pending_pay", ""))
	if id == "":
		return
	for i in 20:
		var r := await Api.request("GET", "/api/pay/" + id)
		if not r.ok:
			break
		if str(r.data.status) == "paid":
			Session.remove_meta("pending_pay")
			set_wallet(r.data.wallet)
			Sfx.play("coin")
			UI.toast(L.t("eco_paid", [int(r.data.pieces)]), "ok")
			return
		if str(r.data.status) in ["canceled", "expired", "failed"]:
			Session.remove_meta("pending_pay")
			return
		await (Engine.get_main_loop() as SceneTree).create_timer(3.0).timeout


## Today's quests: progress, claim, and a button to go do it.
static func open_quests(parent: Node) -> void:
	var s := _sheet(parent, L.t("eco_quests"))
	var v: VBoxContainer = s[1]
	var layer: CanvasLayer = s[0]
	var draw := func(data: Dictionary, redraw: Callable) -> void:
		for c in v.get_children():
			c.queue_free()
		var note := UI.label(L.t("eco_daily_note", [int(data.get("daily_orbs", 15))]), 15, UI.MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)
		for q in data.get("quests", []):
			var card := UI.card(14, UI.BG_2, 18)
			var h := UI.hbox(12)
			card.add_child(h)
			h.add_child(Icon.make("orb", 30, ORB_COLOR))
			var col := UI.vbox(6)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var title := UI.label(L.t("q_" + str(q.id)), 17, UI.TEXT, "bold")
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(title)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size.y = 10
			bar.max_value = float(q.target)
			bar.value = float(q.progress)
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0, 0, 0, 0.35)
			bg.set_corner_radius_all(5)
			var fg := StyleBoxFlat.new()
			fg.bg_color = ORB_COLOR
			fg.set_corner_radius_all(5)
			bar.add_theme_stylebox_override("background", bg)
			bar.add_theme_stylebox_override("fill", fg)
			col.add_child(bar)
			h.add_child(col)
			var done: bool = float(q.progress) >= float(q.target)
			if q.claimed:
				h.add_child(UI.label(L.t("eco_claimed"), 15, UI.MUTED, "bold"))
			elif done:
				var b := UI.button(L.t("eco_claim", [int(q.reward)]), "primary", 44)
				var qid := str(q.id)
				b.pressed.connect(func():
					b.disabled = true
					var r := await Api.request("POST", "/api/quests/%s/claim" % qid)
					if r.ok:
						set_wallet(r.data.wallet)
						Sfx.play("coin")
						redraw.call(r.data, redraw)
					else:
						UI.toast(r.message, "error")
						b.disabled = false)
				h.add_child(b)
			else:
				var b := UI.button(L.t("eco_go", [int(q.reward)]), "ghost", 44)
				var go: Dictionary = q.go
				b.pressed.connect(func():
					layer.queue_free()
					_go(parent, go))
				h.add_child(b)
			v.add_child(card)
	v.add_child(Loading.spinner(30))
	var r := await Api.request("GET", "/api/quests")
	if not is_instance_valid(v):
		return
	if r.ok:
		set_wallet(r.data.wallet)
		draw.call(r.data, draw)
	else:
		UI.toast(r.message, "error")


static func _go(from: Node, go: Dictionary) -> void:
	var menu := from.get_tree().current_scene
	match str(go.get("type", "")):
		"place":
			if menu.has_method("open_place"):
				menu.open_place(str(go.id))
		"friends":
			if menu.has_method("open_page"):
				menu.open_page("friends")
		_:
			if menu.has_method("open_page"):
				menu.open_page("home")


## "Buy this gamepass?" Returns true if it was bought (or already owned).
static func gamepass_prompt(parent: Node, place_id: String, pass_id: int) -> bool:
	var r := await Api.request("GET", "/api/places/%s/passes" % place_id)
	var gp: Dictionary = {}
	for p in (r.data.get("passes", []) if r.ok else []):
		if int(p.id) == pass_id:
			gp = p
	if gp.is_empty():
		return false
	if gp.get("owned", false):
		return true
	var s := _sheet(parent, str(gp.name), 440.0)
	var layer: CanvasLayer = s[0]
	var v: VBoxContainer = s[1]
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(180, 180)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	if str(gp.get("image", "")) != "":
		AssetCache.fetch(str(gp.image), func(t: Texture2D):
			if is_instance_valid(pic) and t:
				pic.texture = t)
	else:
		pic.custom_minimum_size = Vector2(0, 0)
	if str(gp.get("description", "")) != "":
		var d := UI.label(str(gp.description), 16, UI.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	var bal := UI.hbox(6)
	bal.add_child(UI.label(L.t("eco_you_have"), 15, UI.MUTED))
	bal.add_child(Icon.make("piece", 18, PIECE_COLOR))
	bal.add_child(UI.label(pieces_text(), 15, UI.TEXT, "bold"))
	v.add_child(bal)
	var buy := UI.button(L.t("eco_buy_pass", [int(gp.price)]), "primary", 56)
	v.add_child(buy)
	var result := [null]
	buy.pressed.connect(func():
		buy.disabled = true
		var br := await Api.request("POST", "/api/passes/%d/buy" % pass_id)
		if br.ok:
			set_wallet(br.data.wallet)
			Sfx.play("coin")
			result[0] = true
		else:
			UI.toast(br.message, "error")
			buy.disabled = false)
	layer.tree_exiting.connect(func():
		if result[0] == null:
			result[0] = false)
	while result[0] == null:
		await parent.get_tree().process_frame
	if is_instance_valid(layer):
		layer.queue_free()
	return result[0]
