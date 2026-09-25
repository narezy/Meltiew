class_name Backdrop
extends Control
## Soft animated background: vertical gradient with slowly drifting glow blobs.

var _t := 0.0
var _blobs := [
	{"c": Color("#8f6ff0"), "r": 0.42, "x": 0.12, "y": 0.2, "sx": 0.07, "sy": 0.05, "sp": 0.11},
	{"c": Color("#ff8fb1"), "r": 0.3, "x": 0.85, "y": 0.85, "sx": 0.05, "sy": 0.06, "sp": 0.09},
	{"c": Color("#4cc9f0"), "r": 0.26, "x": 0.9, "y": 0.1, "sx": 0.04, "sy": 0.04, "sp": 0.13},
]
var _glow: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.22))
	g.set_color(1, Color(1, 1, 1, 0.0))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 256
	_glow.height = 256


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.BG)
	var m := maxf(size.x, size.y)
	for b in _blobs:
		var center := Vector2(
			(b.x + sin(_t * b.sp * TAU) * b.sx) * size.x,
			(b.y + cos(_t * b.sp * 0.8 * TAU) * b.sy) * size.y)
		var r: float = b.r * m
		draw_texture_rect(_glow, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, b.c)
