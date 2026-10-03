class_name Vehicle
extends Node
## A VehicleSeat's vehicle as this app draws it: every part of its Model keeps its place
## around the seat, so moving the seat moves the car. Parts with "Wheel" in their name
## turn as it rolls, and the front ones steer. Driven here by VehicleDrive, or following
## the driver's reports for everyone else (game.gd).

const STEER_ANGLE := 0.5  # radians the front wheels turn at full steer
const TREE_EVERY := 0.25  # seconds between quietly writing the parts' places to the tree

var scene: PlaceScene
var seat := ""
var parts: Array[String] = []
var offsets := {}  # part id -> Transform3D from the seat
var box := AABB()  # all of it, in the seat's space
var wheels: Array[Dictionary] = []  # { id, axle (part space), up (part space), radius, front }
var pose := Transform3D()  # where the seat is
var _spin := {}  # wheel id -> radians rolled
var _tree_wait := 0.0


## Reads the vehicle from the tree, where scripts last put it.
func setup(p_scene: PlaceScene, p_seat: String) -> void:
	scene = p_scene
	seat = p_seat
	pose = scene.part_transform(seat)
	var inv := pose.affine_inverse()
	var first := true
	var center := Vector3.ZERO
	for id in scene.vehicle_parts(seat):
		var t := scene.part_transform(id)
		var off := inv * t
		parts.append(id)
		offsets[id] = off
		var size: Vector3 = scene.tree.prop(id, "Size")
		var b := off * AABB(-size / 2.0, size)
		box = b if first else box.merge(b)
		first = false
	center = box.get_center()
	for id in parts:
		if not scene.tree.name_of(id).to_lower().contains("wheel"):
			continue
		var off: Transform3D = offsets[id]
		var size: Vector3 = scene.tree.prop(id, "Size")
		# Its own axis closest to the seat's sideways: the round part is across it.
		var axle := Vector3.RIGHT
		var best := -1.0
		for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var d := absf((off.basis * ax).normalized().dot(Vector3.RIGHT))
			if d > best:
				best = d
				axle = ax
		var across := (Vector3.ONE - axle.abs()) * size
		# It rolls about the seat's sideways (in the part's own space), whichever way it faces.
		wheels.append({"id": id, "axle": (off.basis.inverse() * Vector3.RIGHT).normalized(), "up": (off.basis.inverse() * Vector3.UP).normalized(),
			"radius": maxf(0.1, maxf(across.x, maxf(across.y, across.z)) / 2.0), "front": off.origin.z < center.z})


## Puts the whole vehicle where the seat is now; wheels roll by `speed` (studs a second,
## forward) and the front ones turn by `steer` (-1..1).
func place(t: Transform3D, speed: float, steer: float, delta: float) -> void:
	pose = t
	for id in parts:
		scene.pose_part(id, t * (offsets[id] as Transform3D))
	for w in wheels:
		var mesh := scene.part_mesh(w.id)
		if mesh == null:
			continue
		_spin[w.id] = fmod(float(_spin.get(w.id, 0.0)) + speed / float(w.radius) * delta, TAU)
		var turn := Basis(w.up, -steer * STEER_ANGLE) if w.front else Basis()
		mesh.transform = Transform3D(turn * Basis(w.axle, -float(_spin[w.id])), Vector3.ZERO)
	_tree_wait -= delta
	if _tree_wait <= 0.0:
		_tree_wait = TREE_EVERY
		write_tree()


## The parts' places into the tree without telling anyone (so scripts moving a door of a
## moving car start from where it really is).
func write_tree() -> void:
	for id in parts:
		var t := pose * (offsets[id] as Transform3D)
		var r := t.basis.orthonormalized().get_euler() * (180.0 / PI)
		scene.tree.set_quiet(id, "Position", t.origin)
		scene.tree.set_quiet(id, "Rotation", r)


## Rotation as a part's Rotation (degrees, Y then X then Z).
static func degrees_of(b: Basis) -> Vector3:
	return b.orthonormalized().get_euler() * (180.0 / PI)


static func basis_of(deg: Vector3) -> Basis:
	return Basis.from_euler(deg * (PI / 180.0))
