extends Node
## Draws the clothing template (assets/clothing_template.png, also served by the site at
## /img/clothing_template.png) from ClothingLayout, and with --demo a filled-in test
## shirt next to it (for checking the body shader). Needs a window (it renders):
##   godot --path . res://tools/clothing_template.tscn [-- --demo=/tmp/demo.png]

const FACE_NAMES := {"front": ["FRONT", "ПЕРЕД"], "back": ["BACK", "СПИНА"], "right": ["R", "ПРАВ"],
	"left": ["L", "ЛЕВ"], "top": ["TOP", "ВЕРХ"], "bottom": ["BOTTOM", "НИЗ"]}

var demo := false


class Sheet extends Control:
	var filled := false

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for part in ClothingLayout.DRESSED:
			var faces: Dictionary = ClothingLayout.faces(part)
			var i := 0
			for key in faces:
				var r: Rect2 = faces[key]
				if filled:
					var hue := fmod(part * 0.19 + i * 0.07, 1.0)
					draw_rect(r, Color.from_hsv(hue, 0.55, 0.95))
					# A stripe along the top edge of each face shows which way is up.
					draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), Color.BLACK)
				else:
					draw_rect(r, Color(1, 1, 1, 0.06))
				draw_rect(r, Color(0.1, 0.09, 0.14, 0.75), false, 2.0)
				var names: Array = FACE_NAMES[key]
				var t := "%s\n%s" % [names[1], names[0]]
				draw_multiline_string(font, r.position + Vector2(4, 16), t, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 12, -1, Color(0.1, 0.09, 0.14, 0.8))
				i += 1
			var front: Rect2 = faces.front
			var title: Array = ClothingLayout.PART_NAMES[part]
			draw_string(font, Vector2(ClothingLayout.ORIGIN[part].x, front.end.y + faces.bottom.size.y + 16), "%s / %s" % [title[1], title[0]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.09, 0.14, 0.9))


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			out = a.trim_prefix("--demo=")
	var vp := SubViewport.new()
	vp.size = Vector2i(ClothingLayout.W, ClothingLayout.H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var sheet := Sheet.new()
	sheet.filled = out != ""
	sheet.size = Vector2(vp.size)
	vp.add_child(sheet)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if out != "":
		img.save_png(out)
	else:
		img.save_png("res://assets/clothing_template.png")
		img.save_png(ProjectSettings.globalize_path("res://").path_join("../server/public/img/clothing_template.png"))
	print("template saved ", img.get_size())
	get_tree().quit()
