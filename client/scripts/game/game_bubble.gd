class_name GameBubble
extends RefCounted
## Sticker-style chat bubble shown above a player's head.


static func make() -> Label3D:
	var b := Label3D.new()
	b.position.y = 2.75
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.font = UI.font_bold
	b.font_size = 38
	# A thick white outline doubles as the bubble.
	b.outline_size = 30
	b.outline_modulate = Color(1, 1, 1, 0.96)
	b.modulate = UI.INK
	b.pixel_size = 0.0042
	b.width = 900
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.visible = false
	return b


static func show(b: Label3D, text: String) -> void:
	b.text = text
	b.visible = true
	b.scale = Vector3.ONE * 0.6
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
