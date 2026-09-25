class_name RoundedImage
extends TextureRect
## TextureRect with anti-aliased rounded corners.

const SHADER := preload("res://assets/shaders/rounded.gdshader")

var radius := 22.0


func _init(tex: Texture2D = null, r := 22.0) -> void:
	texture = tex
	radius = r
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# UV must span the whole control for the corner mask, so no aspect modes.
	stretch_mode = TextureRect.STRETCH_SCALE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	material = m
	resized.connect(_sync)


func _ready() -> void:
	_sync()


func _sync() -> void:
	var m := material as ShaderMaterial
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("rect_size", size)
