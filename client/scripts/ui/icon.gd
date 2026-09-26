class_name Icon
extends Control
## Small vector icon set drawn with canvas primitives (no image assets).

var kind := "home"
var color := UI.TEXT:
	set(v):
		color = v
		queue_redraw()
var stroke := 2.6


static func make(icon_kind: String, px := 26, tint := UI.TEXT) -> Icon:
	var i := Icon.new()
	i.kind = icon_kind
	i.color = tint
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon_kind in ["piece", "orb"]:
		i.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return i


const PIECE_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="#ffb86b" stroke="#c9772a" stroke-width="1.2" stroke-linejoin="round" d="M4 7.5h4.2c-.6-2.9 1-4.5 2.8-4.5s3.4 1.6 2.8 4.5H18v4.2c2.9-.6 4.5 1 4.5 2.8s-1.6 3.4-4.5 2.8V21H13.8c.6-2.9-1-4.5-2.8-4.5S7.6 18.1 8.2 21H4v-4.2c2.9.6 4.5-1 4.5-2.8S6.9 10.6 4 11.2z"/></svg>'
const ORB_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><defs><radialGradient id="og" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#e6dcff"/><stop offset=".6" stop-color="#9d7bff"/><stop offset="1" stop-color="#6c4bd8"/></radialGradient></defs><circle cx="12" cy="12" r="10" fill="url(#og)"/><circle cx="12" cy="12" r="3.6" fill="#fff" fill-opacity=".9"/></svg>'
static var _currency_tex := {}


## The piece or orb picture, rendered once at a large size (mipmaps keep it smooth when small).
static func currency_texture(which: String) -> Texture2D:
	if not _currency_tex.has(which):
		var img := Image.new()
		img.load_svg_from_string(PIECE_SVG if which == "piece" else ORB_SVG, 8.0)
		img.generate_mipmaps()
		_currency_tex[which] = ImageTexture.create_from_image(img)
	return _currency_tex[which]


func _line(pts: Array, w := -1.0) -> void:
	var s := size.x / 24.0
	var packed := PackedVector2Array()
	for p in pts:
		packed.append(p * s)
	draw_polyline(packed, color, (stroke if w < 0 else w) * s, true)
	for p in [pts[0], pts[pts.size() - 1]]:
		draw_circle(p * s, (stroke if w < 0 else w) * s * 0.5, color)


func _circle(c: Vector2, r: float, filled := false) -> void:
	var s := size.x / 24.0
	if filled:
		draw_circle(c * s, r * s, color)
	else:
		draw_arc(c * s, r * s, 0, TAU, 40, color, stroke * s, true)


func _arc(c: Vector2, r: float, a0: float, a1: float) -> void:
	var s := size.x / 24.0
	draw_arc(c * s, r * s, a0, a1, 24, color, stroke * s, true)


func _poly(pts: Array) -> void:
	var s := size.x / 24.0
	var packed := PackedVector2Array()
	for p in pts:
		packed.append(p * s)
	draw_colored_polygon(packed, color)


func _draw() -> void:
	match kind:
		"home":
			_line([Vector2(3, 11), Vector2(12, 3.5), Vector2(21, 11)])
			_line([Vector2(5.5, 9.5), Vector2(5.5, 20), Vector2(18.5, 20), Vector2(18.5, 9.5)])
			_line([Vector2(10, 20), Vector2(10, 14.5), Vector2(14, 14.5), Vector2(14, 20)])
		"friends":
			_circle(Vector2(9, 8), 3.6)
			_arc(Vector2(9, 20.5), 6.5, PI, TAU)
			_circle(Vector2(17, 9), 2.8)
			_arc(Vector2(17, 19.5), 5.0, PI * 1.25, TAU)
		"avatar":
			_line([Vector2(8, 3.5), Vector2(3, 7), Vector2(5, 11), Vector2(7.5, 10), Vector2(7.5, 20.5),
				Vector2(16.5, 20.5), Vector2(16.5, 10), Vector2(19, 11), Vector2(21, 7), Vector2(16, 3.5)])
			_arc(Vector2(12, 3.5), 4.0, 0, PI)
		"settings":
			_circle(Vector2(12, 12), 3.2)
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				_line([Vector2(12, 12) + d * 7.0, Vector2(12, 12) + d * 9.5], 3.2)
			_circle(Vector2(12, 12), 7.0)
		"play":
			_poly([Vector2(7, 4), Vector2(20, 12), Vector2(7, 20)])
		"refresh":
			_arc(Vector2(12, 12), 7.5, -PI * 0.35, PI * 1.35)
			_poly([Vector2(17.5, 2.5), Vector2(19.5, 8.5), Vector2(13.5, 8)])
		"plus":
			_line([Vector2(12, 4.5), Vector2(12, 19.5)])
			_line([Vector2(4.5, 12), Vector2(19.5, 12)])
		"search":
			_circle(Vector2(10.5, 10.5), 6.0)
			_line([Vector2(15, 15), Vector2(20, 20)])
		"close":
			_line([Vector2(6, 6), Vector2(18, 18)])
			_line([Vector2(18, 6), Vector2(6, 18)])
		"check":
			_line([Vector2(5, 12.5), Vector2(10, 17.5), Vector2(19, 7)])
		"chat":
			_line([Vector2(4, 5), Vector2(20, 5), Vector2(20, 16), Vector2(11, 16), Vector2(6, 20), Vector2(6, 16),
				Vector2(4, 16), Vector2(4, 5)])
		"exit":
			_line([Vector2(10, 4), Vector2(4, 4), Vector2(4, 20), Vector2(10, 20)])
			_line([Vector2(9, 12), Vector2(20, 12)])
			_line([Vector2(16, 8), Vector2(20, 12), Vector2(16, 16)])
		"users":
			_circle(Vector2(12, 8), 4.0)
			_arc(Vector2(12, 21), 7.5, PI, TAU)
		"group":
			# Three heads: a community.
			_circle(Vector2(12, 7.5), 3.4)
			_arc(Vector2(12, 19), 6.2, PI, TAU)
			_circle(Vector2(5, 10), 2.6)
			_arc(Vector2(5, 20), 4.4, PI * 1.05, PI * 1.6)
			_circle(Vector2(19, 10), 2.6)
			_arc(Vector2(19, 20), 4.4, PI * 1.4, PI * 1.95)
		"user_add":
			_circle(Vector2(9, 8), 3.8)
			_arc(Vector2(9, 21), 7.0, PI, TAU)
			_line([Vector2(18.5, 6), Vector2(18.5, 13)])
			_line([Vector2(15, 9.5), Vector2(22, 9.5)])
		"hand":
			_line([Vector2(8, 13), Vector2(8, 5.5)])
			_line([Vector2(11.5, 11), Vector2(11.5, 3.5)])
			_line([Vector2(15, 11), Vector2(15, 4.5)])
			_line([Vector2(18.5, 12), Vector2(18.5, 7)])
			_line([Vector2(8, 13), Vector2(5, 10.5), Vector2(4, 13), Vector2(8.5, 19.5), Vector2(15, 21),
				Vector2(18.5, 17), Vector2(18.5, 12)])
		"heart":
			_poly([Vector2(12, 20), Vector2(4, 12), Vector2(3.5, 7.5), Vector2(6, 4.5), Vector2(9.5, 4.5),
				Vector2(12, 7.5), Vector2(14.5, 4.5), Vector2(18, 4.5), Vector2(20.5, 7.5), Vector2(20, 12)])
		"menu":
			for y in [6.5, 12.0, 17.5]:
				_line([Vector2(4.5, y), Vector2(19.5, y)])
		"code":
			_line([Vector2(8, 7), Vector2(3, 12), Vector2(8, 17)])
			_line([Vector2(16, 7), Vector2(21, 12), Vector2(16, 17)])
			_line([Vector2(13.5, 5), Vector2(10.5, 19)])
		"send":
			_poly([Vector2(3, 4), Vector2(21, 12), Vector2(3, 20), Vector2(6, 12)])
		"jump":
			_line([Vector2(12, 20), Vector2(12, 5)])
			_line([Vector2(5.5, 11), Vector2(12, 4.5), Vector2(18.5, 11)])
		"star":
			var pts := []
			for k in 10:
				var a := -PI / 2.0 + TAU * k / 10.0
				var r := 9.5 if k % 2 == 0 else 4.2
				pts.append(Vector2(12, 12.5) + Vector2(cos(a), sin(a)) * r)
			_poly(pts)
		"music":
			_line([Vector2(9, 18), Vector2(9, 5), Vector2(19, 3), Vector2(19, 16)])
			_circle(Vector2(6.5, 18), 2.8, true)
			_circle(Vector2(16.5, 16), 2.8, true)
		"chair":
			_line([Vector2(7, 3), Vector2(7, 21)])
			_line([Vector2(7, 13), Vector2(18, 13), Vector2(18, 21)])
			_line([Vector2(7, 13), Vector2(7, 13)])
		"smile":
			_circle(Vector2(12, 12), 9.0)
			_circle(Vector2(9, 10), 1.3, true)
			_circle(Vector2(15, 10), 1.3, true)
			_arc(Vector2(12, 12.5), 4.5, 0.2, PI - 0.2)
		"clap":
			_line([Vector2(6, 20), Vector2(9, 9), Vector2(12, 6)])
			_line([Vector2(18, 20), Vector2(15, 9), Vector2(12, 6)])
			_line([Vector2(4, 5), Vector2(6, 7)])
			_line([Vector2(20, 5), Vector2(18, 7)])
			_line([Vector2(12, 1.5), Vector2(12, 3)])
		"camera":
			_line([Vector2(3, 8), Vector2(21, 8), Vector2(21, 19), Vector2(3, 19), Vector2(3, 8)])
			_line([Vector2(8, 8), Vector2(10, 5), Vector2(14, 5), Vector2(16, 8)])
			_circle(Vector2(12, 13.5), 3.2)
		"reset":
			_arc(Vector2(12, 12), 7.5, PI * 0.65, PI * 2.35)
			_poly([Vector2(3.5, 6.5), Vector2(9, 5), Vector2(5.5, 11)])
		"shield":
			_line([Vector2(12, 3), Vector2(20, 6), Vector2(19, 13), Vector2(12, 21), Vector2(5, 13), Vector2(4, 6), Vector2(12, 3)])
			_line([Vector2(7, 7), Vector2(17, 17)])
		"like":
			_line([Vector2(3, 11), Vector2(7, 11), Vector2(7, 21), Vector2(3, 21), Vector2(3, 11)])
			_line([Vector2(7, 11), Vector2(11, 3.5), Vector2(13, 4), Vector2(13.5, 9), Vector2(20, 9),
				Vector2(21, 11), Vector2(19, 20), Vector2(17.5, 21), Vector2(7, 21)])
		"dislike":
			_line([Vector2(3, 13), Vector2(7, 13), Vector2(7, 3), Vector2(3, 3), Vector2(3, 13)])
			_line([Vector2(7, 13), Vector2(11, 20.5), Vector2(13, 20), Vector2(13.5, 15), Vector2(20, 15),
				Vector2(21, 13), Vector2(19, 4), Vector2(17.5, 3), Vector2(7, 3)])
		"eye":
			_arc(Vector2(12, 19), 11.0, PI * 1.2, PI * 1.8)
			_arc(Vector2(12, 5), 11.0, PI * 0.2, PI * 0.8)
			_circle(Vector2(12, 12), 3.0, true)
		"back":
			_line([Vector2(15, 4), Vector2(7, 12), Vector2(15, 20)])
		"down":
			_line([Vector2(5, 9), Vector2(12, 16), Vector2(19, 9)])
		"piece", "orb":
			# The currencies are drawn from the same SVGs as the website, smooth at any size.
			draw_texture_rect(currency_texture(kind), Rect2(Vector2.ZERO, size), false)
		"lock":
			# A padlock: shift lock.
			_line([Vector2(5, 11), Vector2(19, 11), Vector2(19, 21), Vector2(5, 21), Vector2(5, 11)])
			_arc(Vector2(12, 8), 4.5, PI, TAU)
			_line([Vector2(7.5, 8), Vector2(7.5, 11)])
			_line([Vector2(16.5, 8), Vector2(16.5, 11)])
			_circle(Vector2(12, 16), 1.4, true)
		"run":
			# A lightning bolt: go fast.
			_poly([Vector2(13.5, 2.5), Vector2(5, 13.5), Vector2(11, 13.5), Vector2(9.5, 21.5), Vector2(19, 9.5), Vector2(13, 9.5)])
		"shop":
			_line([Vector2(4.5, 8), Vector2(19.5, 8), Vector2(18.5, 20.5), Vector2(5.5, 20.5), Vector2(4.5, 8)])
			_line([Vector2(8.5, 10.5), Vector2(8.5, 6.5)])
			_arc(Vector2(12, 6.5), 3.5, PI, TAU)
			_line([Vector2(15.5, 6.5), Vector2(15.5, 10.5)])
		"backpack":
			_line([Vector2(9, 6), Vector2(9, 4), Vector2(15, 4), Vector2(15, 6)])
			_line([Vector2(6, 21), Vector2(4.5, 19.5), Vector2(4.5, 9.5), Vector2(7, 6.5), Vector2(17, 6.5),
				Vector2(19.5, 9.5), Vector2(19.5, 19.5), Vector2(18, 21), Vector2(6, 21)])
			_line([Vector2(8, 13), Vector2(16, 13), Vector2(16, 17), Vector2(8, 17), Vector2(8, 13)])
