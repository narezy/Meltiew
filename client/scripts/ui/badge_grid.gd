class_name BadgeGrid
extends RefCounted
## Badge tiles: picture, name, and (on profiles) which place it's from. Badges
## you don't have yet are dimmed.


static func make(badges: Array, show_place: bool) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	for b in badges:
		flow.add_child(tile(b, show_place))
	return flow


static func tile(b: Dictionary, show_place: bool) -> Control:
	var card := UI.card(10, UI.CARD, 18)
	card.custom_minimum_size.x = 150
	card.tooltip_text = str(b.get("description", ""))
	var v := UI.vbox(6)
	card.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(96, 96)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(pic)
	if str(b.get("image", "")) != "":
		var wr: WeakRef = weakref(pic)
		AssetCache.fetch(str(b.image), func(t: Texture2D):
			var p: TextureRect = wr.get_ref()
			if p and t:
				p.texture = t)
	else:
		var star := Icon.make("star", 64, UI.ACCENT)
		star.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.add_child(star)
		star.position = Vector2(16, 16)
	var name := UI.label(str(b.get("name", "")), 15, UI.TEXT, "bold")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size.x = 130
	v.add_child(name)
	if show_place and str(b.get("place_name", "")) != "":
		var pl := UI.label(str(b.place_name), 13, UI.MUTED)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.clip_text = true
		pl.custom_minimum_size.x = 130
		v.add_child(pl)
	if not b.get("owned", false):
		card.modulate = Color(1, 1, 1, 0.45)
	return card
