class_name PlaceWorld
extends Node3D
## Stands in for the Playground when the game joins a studio place: the actual
## world is a PlaceScene created once the server sends it.

var spawn_point := Vector3(0, 3, 0)
var _scene: PlaceScene
var _quality := "high"


func attach_player(p: LocalPlayer) -> void:
	p.spawn_point = spawn_point


func set_scene(s: PlaceScene) -> void:
	_scene = s
	s.apply_quality(_quality)


func apply_quality(q: String) -> void:
	_quality = q
	if _scene:
		_scene.apply_quality(q)
