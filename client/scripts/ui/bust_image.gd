class_name BustImage
extends RoundedImage
## Circular avatar portrait that fills in once Busts finishes rendering it.

var _hash := ""


func _init(u: Dictionary = {}, r := 26.0) -> void:
	super(null, r)
	_hash = Session.look_hash(u)
	texture = Busts.get_bust(u)


func _enter_tree() -> void:
	if texture == null and not Busts.ready_for.is_connected(_on_ready):
		Busts.ready_for.connect(_on_ready)


func _exit_tree() -> void:
	if Busts.ready_for.is_connected(_on_ready):
		Busts.ready_for.disconnect(_on_ready)


func _on_ready(done_hash: String, tex: Texture2D) -> void:
	if done_hash == _hash:
		texture = tex
		Busts.ready_for.disconnect(_on_ready)
