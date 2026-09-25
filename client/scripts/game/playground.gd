class_name Playground
extends Node3D
## The playground map, built procedurally. Static props are merged into a few
## vertex-colored meshes (cheap on phones) and every prop you can bump into has
## collision. Animated bits (carousel, swings, see-saw, fountain, balloons,
## ducks, clouds) are separate nodes.

signal bounced(strength: float)
signal reached_island
signal maze_solved

const HALF := 70.0
const TOON := preload("res://assets/shaders/toon.gdshader")
const WATER := preload("res://assets/shaders/water.gdshader")
const GRASS := preload("res://assets/shaders/grass.gdshader")

# Palette
const C_WOOD := Color("#e0a36b")
const C_WOOD_DARK := Color("#a8714a")
const C_RED := Color("#ff6b6b")
const C_ORANGE := Color("#ffa552")
const C_YELLOW := Color("#ffd166")
const C_MINT := Color("#7ee0c3")
const C_BLUE := Color("#4cc9f0")
const C_INDIGO := Color("#6c8cff")
const C_LILAC := Color("#b89cff")
const C_PINK := Color("#ff8fb1")
const C_WHITE := Color("#fbf8f3")
const C_STONE := Color("#c9c3d6")
const C_DARK := Color("#3a3450")
const C_PATH := Color("#efe1c4")
const C_LEAF := [Color("#5dbb63"), Color("#4caa5a"), Color("#79cf73"), Color("#ffb3c7")]

const POND_CENTER := Vector3(-6, 0, 44)
const POND_SIZE := Vector2(22, 14)
const MAZE_ORIGIN := Vector3(-54, 0, -52)
const MAZE_CELLS := 9
const MAZE_CELL := 3.4
const SPIRAL_CENTER := Vector3(42, 0, -36)

var spawn_point := Vector3(0, 0.6, 10)
var _batch := MeshBatch.new()
var _batch_mat: ShaderMaterial
var _static: StaticBody3D
var _sun: DirectionalLight3D
var _env: Environment
var _swings: Array = []
var _carousel: AnimatableBody3D
var _seesaw: AnimatableBody3D
var _slides: Array[Area3D] = []
var _seats: Array = []
var _clouds: Array[Node3D] = []
var _balloons: Array[Node3D] = []
var _ducks: Array[Node3D] = []
var _star: Node3D
var _prize: Node3D
var _fountain_jets: Array[MeshInstance3D] = []
var _player: LocalPlayer
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260925
	_batch_mat = ShaderMaterial.new()
	_batch_mat.shader = TOON
	_static = StaticBody3D.new()
	_static.name = "WorldCollision"
	add_child(_static)
	_build_environment()
	_build_ground()
	_build_paths()
	_build_spawn_plaza()
	_build_play_structure(Vector3(0, 0, -16))
	_build_swings(Vector3(20, 0, -6))
	_build_carousel(Vector3(-20, 0, -6))
	_build_trampolines(Vector3(22, 0, 20))
	_build_sandbox(Vector3(-22, 0, 20))
	_build_seesaws(Vector3(8, 0, 28))
	_build_pond()
	_build_maze()
	_build_parkour()
	_build_kiosk(Vector3(12, 0, 6))
	_build_picnic(Vector3(-36, 0, 36))
	_build_nature()
	_build_fence_and_backdrop()
	_build_clouds()
	_build_balloons()
	_batch.build(self, _batch_mat)
	_simplify_meshes(self)


func _simplify_meshes(n: Node) -> void:
	if n is MeshInstance3D and n.mesh is PrimitiveMesh:
		MeshBatch.simplify(n.mesh)
	for c in n.get_children():
		_simplify_meshes(c)


func attach_player(p: LocalPlayer) -> void:
	_player = p
	p.spawn_point = spawn_point


func apply_quality(q: String) -> void:
	if _sun:
		_sun.shadow_enabled = q != "low"
		_sun.directional_shadow_max_distance = 35.0 if q == "medium" else 70.0
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == "medium" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if _env:
		_env.glow_enabled = q == "high"
		_env.fog_enabled = q != "low"
		_env.adjustment_enabled = q != "low"
	for c in _clouds:
		c.visible = q != "low"
	for b in _balloons:
		b.visible = q != "low"


# --- builder helpers --------------------------------------------------------

func _xf(pos: Vector3, rot_deg := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)


func _collide(shape: Shape3D, xform: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	_static.add_child(cs)


func box(pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, collide := true) -> void:
	var m := BoxMesh.new()
	m.size = size
	var xf := _xf(pos, rot)
	_batch.add(m, xf, color)
	if collide:
		var s := BoxShape3D.new()
		s.size = size
		_collide(s, xf)


func cyl(pos: Vector3, radius: float, height: float, color: Color, collide := true, top := -1.0, segments := 20, rot := Vector3.ZERO) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	var xf := _xf(pos, rot)
	_batch.add(m, xf, color)
	if collide:
		var s := CylinderShape3D.new()
		s.radius = maxf(radius, m.top_radius)
		s.height = height
		_collide(s, xf)


func ball(pos: Vector3, radius: float, color: Color, collide := false, squash := 1.0) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = 14
	m.rings = 8
	_batch.add(m, _xf(pos), color)
	if collide:
		var s := SphereShape3D.new()
		s.radius = radius * minf(squash, 1.0)
		_collide(s, _xf(pos))


func prism(pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, collide := false) -> void:
	var m := PrismMesh.new()
	m.size = size
	var xf := _xf(pos, rot)
	_batch.add(m, xf, color)
	if collide:
		var s := ConvexPolygonShape3D.new()
		s.points = m.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
		_collide(s, xf)


func torus(pos: Vector3, inner: float, outer: float, color: Color, rot := Vector3.ZERO) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 10
	_batch.add(m, _xf(pos, rot), color)


## Invisible walkable ramp from `a` (bottom) to `b` (top), `width` wide.
func ramp(a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var len := d.length()
	var s := BoxShape3D.new()
	s.size = Vector3(width, 0.2, len)
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	_collide(s, Transform3D(basis, (a + b) * 0.5 - basis.y * 0.1))


func toon_mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("use_vertex_color", false)
	m.set_shader_parameter("tint", color)
	return m


func node_mesh(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = toon_mat(color)
	mi.transform = _xf(pos, rot)
	parent.add_child(mi)
	return mi


func sign_text(text: String, pos: Vector3, px := 96, color := UI.TEXT, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font_black
	l.font_size = px
	l.outline_size = int(px * 0.2)
	l.outline_modulate = Color("#2e2940")
	l.modulate = color
	l.position = pos
	l.rotation_degrees.y = rot_y
	l.pixel_size = 0.01
	l.double_sided = false
	add_child(l)
	# A second copy facing the other way keeps the text readable from behind.
	var back := l.duplicate() as Label3D
	back.rotation_degrees.y = rot_y + 180.0
	add_child(back)
	return l


# --- environment ------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#4f8fff")
	sky_mat.sky_horizon_color = Color("#cfe6ff")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color("#cfe6ff")
	sky_mat.ground_bottom_color = Color("#86b877")
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.85
	_env.ambient_light_energy = 0.75
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.35
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 1.1
	_env.fog_enabled = true
	_env.fog_light_color = Color("#d6e8ff")
	_env.fog_density = 0.0018
	_env.fog_sky_affect = 0.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.22
	_env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -35, 0)
	_sun.light_energy = 1.35
	_sun.light_color = Color("#fff1dc")
	_sun.shadow_enabled = true
	_sun.shadow_opacity = 0.75
	_sun.shadow_blur = 1.4
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)


func _build_ground() -> void:
	# The ground is four slabs around the pond so the pond can be a real dip.
	var big := HALF * 2.0 + 60.0
	var h := big * 0.5
	var px0 := POND_CENTER.x - POND_SIZE.x * 0.5
	var px1 := POND_CENTER.x + POND_SIZE.x * 0.5
	var pz0 := POND_CENTER.z - POND_SIZE.y * 0.5
	var pz1 := POND_CENTER.z + POND_SIZE.y * 0.5
	var slabs := [
		Rect2(-h, -h, big, pz0 + h),  # north of pond
		Rect2(-h, pz1, big, h - pz1),  # south
		Rect2(-h, pz0, px0 + h, pz1 - pz0),  # west
		Rect2(px1, pz0, h - px1, pz1 - pz0),  # east
	]
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS
	for r in slabs:
		var plane := PlaneMesh.new()
		plane.size = r.size
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = grass_mat
		mi.position = Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var s := BoxShape3D.new()
		s.size = Vector3(r.size.x, 2.0, r.size.y)
		_collide(s, Transform3D(Basis(), mi.position - Vector3(0, 1.0, 0)))


func _build_paths() -> void:
	# Soft beige paths from the plaza to each zone, each a chain of flat slabs.
	var routes := [
		[Vector3(0, 0, 4), Vector3(0, 0, -8)],
		[Vector3(4, 0, 8), Vector3(16, 0, -2)],
		[Vector3(-4, 0, 8), Vector3(-16, 0, -2)],
		[Vector3(5, 0, 14), Vector3(18, 0, 17)],
		[Vector3(-5, 0, 14), Vector3(-18, 0, 17)],
		[Vector3(0, 0, 16), Vector3(0, 0, 33)],
		[Vector3(18, 0, -10), Vector3(33, 0, -28)],
		[Vector3(-18, 0, -10), Vector3(-38.7, 0, -19)],
		[Vector3(-18, 0, 24), Vector3(-32, 0, 34)],
	]
	for r in routes:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var d := b - a
		var yaw := rad_to_deg(atan2(d.x, d.z))
		box((a + b) * 0.5 + Vector3(0, 0.015, 0), Vector3(2.6, 0.03, d.length() + 2.6), C_PATH, Vector3(0, yaw, 0), false)


func _build_spawn_plaza() -> void:
	var c := Vector3(0, 0, 10)
	cyl(c + Vector3(0, 0.04, 0), 7.5, 0.08, C_PATH, false, -1, 40)
	cyl(c + Vector3(0, 0.07, 0), 7.0, 0.06, Color("#e8dcff"), false, -1, 40)
	# Fountain in the middle.
	cyl(c + Vector3(0, 0.35, 0), 2.4, 0.7, C_STONE, true, -1, 28)
	cyl(c + Vector3(0, 0.62, 0), 2.0, 0.1, C_BLUE, false, -1, 28)
	cyl(c + Vector3(0, 1.3, 0), 0.35, 1.4, C_STONE, true)
	cyl(c + Vector3(0, 2.0, 0), 0.9, 0.2, C_STONE, true, 0.6)
	var water := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 2.05
	disk.bottom_radius = 2.05
	disk.height = 0.05
	water.mesh = disk
	var wm := ShaderMaterial.new()
	wm.shader = WATER
	water.material_override = wm
	water.position = c + Vector3(0, 0.66, 0)
	add_child(water)
	for i in 6:
		var a := TAU * i / 6.0
		var jet := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius = 0.02
		jm.bottom_radius = 0.09
		jm.height = 1.0
		jet.mesh = jm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.95, 1.0, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		jet.material_override = mat
		jet.position = c + Vector3(cos(a) * 1.1, 1.2, sin(a) * 1.1)
		jet.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
		jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(jet)
		_fountain_jets.append(jet)
	spawn_point = c + Vector3(0, 0.6, 5.0)
	# Benches and lamps around the plaza.
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var p := c + Vector3(cos(a), 0, sin(a)) * 6.2
		_bench(p, rad_to_deg(-a) + 90.0)
	for i in 6:
		var a := TAU * i / 6.0
		_lamp(c + Vector3(cos(a), 0, sin(a)) * 7.6)
	# Floating brand sign.
	var logo := sign_text("meltiew", c + Vector3(0, 6.8, -12.5), 280, UI.TEXT)
	logo.outline_size = 48
	sign_text(L.t("playground").to_lower(), c + Vector3(0, 5.2, -12.5), 110, C_YELLOW)


func _bench(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	# Standing on the seat sits you down; the backrest is on local -Z, so you face +Z.
	var area := Area3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 0.7, 0.62)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	area.add_child(cs)
	area.transform = Transform3D(b, p + b * Vector3(0, 0.9, 0))
	add_child(area)
	_seats.append({"area": area, "top": 0.54 + p.y, "basis": b, "center": p + b * Vector3(0, 0.54, 0.02)})
	box(p + b * Vector3(0, 0.48, 0), Vector3(2.2, 0.12, 0.62), C_WOOD, Vector3(0, yaw, 0))
	box(p + b * Vector3(0, 0.9, -0.3), Vector3(2.2, 0.48, 0.1), C_WOOD, Vector3(-8, yaw, 0))
	for x in [-0.9, 0.9]:
		box(p + b * Vector3(x, 0.22, 0), Vector3(0.12, 0.44, 0.55), C_DARK, Vector3(0, yaw, 0), false)


func _lamp(p: Vector3) -> void:
	cyl(p + Vector3(0, 0.15, 0), 0.22, 0.3, C_DARK, true)
	cyl(p + Vector3(0, 1.75, 0), 0.08, 3.2, C_DARK, true)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	bulb.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#fff4c2")
	m.emission_enabled = true
	m.emission = Color("#ffe29a")
	m.emission_energy_multiplier = 1.6
	bulb.material_override = m
	bulb.position = p + Vector3(0, 3.45, 0)
	add_child(bulb)
	cyl(p + Vector3(0, 3.78, 0), 0.38, 0.12, C_DARK, false, 0.1)


# --- play structure ---------------------------------------------------------

func _build_play_structure(at: Vector3) -> void:
	# Tower A (left, 3.6 m) and tower B (right, 5.6 m) joined by a bridge.
	_tower(at + Vector3(-6, 0, 0), 3.6, C_RED, C_INDIGO, true)
	_tower(at + Vector3(6, 0, 0), 5.6, C_ORANGE, C_LILAC, false)
	# Bridge between them: planks + rails (with collision so nobody falls through).
	var a := at + Vector3(-3.3, 3.6, 0)
	var b := at + Vector3(3.3, 5.6, 0)
	var steps := 11
	for i in steps:
		var t := (i + 0.5) / steps
		var p := a.lerp(b, t)
		box(p, Vector3(6.6 / steps - 0.05, 0.12, 1.8), C_WOOD if i % 2 == 0 else C_WOOD_DARK)
	ramp(a + Vector3(0, 0.06, 0), b + Vector3(0, 0.06, 0), 1.8)
	for z in [-0.95, 0.95]:
		var r0 := a + Vector3(0, 1.0, z)
		var r1 := b + Vector3(0, 1.0, z)
		var d := r1 - r0
		box((r0 + r1) * 0.5, Vector3(d.length(), 0.08, 0.08), C_YELLOW, Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))))
		box((r0 + r1) * 0.5 - Vector3(0, 0.45, 0), Vector3(d.length(), 0.9, 0.05), Color(1, 1, 1, 1), Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))), true)

	# Stairs up to tower A from the front (+Z).
	var ta := at + Vector3(-6, 0, 0)
	var st_n := 9
	for i in st_n:
		var y := (i + 1) * 3.6 / st_n
		var z := 2.0 + 5.0 - (i + 0.5) * 5.0 / st_n
		box(ta + Vector3(0, y * 0.5, z), Vector3(2.2, y, 5.0 / st_n + 0.01), C_YELLOW if i % 2 == 0 else Color("#ffc34d"), Vector3.ZERO, false)
	ramp(ta + Vector3(0, 0, 7.0), ta + Vector3(0, 3.6, 2.0), 2.2)
	for x in [-1.15, 1.15]:
		box(ta + Vector3(x, 2.5, 4.5), Vector3(0.1, 0.1, 5.4), C_RED, Vector3(rad_to_deg(atan2(3.6, 5.0)), 0, 0), false)

	# Climbing ramp with handholds up to tower B from the back (-Z).
	var tb := at + Vector3(6, 0, 0)
	box(tb + Vector3(0, 2.8, -5.0), Vector3(2.4, 0.25, 6.6), C_MINT, Vector3(-rad_to_deg(atan2(5.6, 5.8)), 0, 0))
	for i in 8:
		var t := (i + 0.5) / 8.0
		var hold := tb + Vector3(randf_range(-0.8, 0.8), 5.6 * t, -2.2 - 5.8 * (1.0 - t))
		ball(hold + Vector3(0, 0.18, 0), 0.16, [C_RED, C_YELLOW, C_INDIGO, C_PINK][i % 4])

	# Slide 1: straight, from tower A to the left.
	_slide(ta + Vector3(-2.2, 3.6, 0), ta + Vector3(-10.5, 0.2, 0), C_BLUE)
	# Slide 2: long wavy slide from tower B to the right, in two drops.
	var mid := tb + Vector3(7.5, 2.8, 0)
	_slide(tb + Vector3(2.2, 5.6, 0), mid, C_PINK)
	box(mid + Vector3(1.0, -0.05, 0), Vector3(2.0, 0.2, 2.2), C_PINK)
	_slide(mid + Vector3(2.0, 0, 0), tb + Vector3(16.0, 0.2, 0), C_PINK)
	# Slide 3: steep one from tower B toward the front.
	_slide(tb + Vector3(0, 5.6, 2.2), tb + Vector3(0, 0.2, 9.5), C_YELLOW)

	# Monkey bars behind the bridge.
	for side in [-1.0, 1.0]:
		box(at + Vector3(side * 3.0, 1.2, -3.6), Vector3(0.14, 2.4, 0.14), C_INDIGO)
	box(at + Vector3(0, 2.4, -3.3), Vector3(6.2, 0.1, 0.1), C_INDIGO, Vector3.ZERO, false)
	box(at + Vector3(0, 2.4, -3.9), Vector3(6.2, 0.1, 0.1), C_INDIGO, Vector3.ZERO, false)
	for i in 9:
		box(at + Vector3(-2.6 + i * 0.65, 2.4, -3.6), Vector3(0.07, 0.07, 0.7), C_YELLOW, Vector3.ZERO, false)
	# Sandy safety floor under the structure.
	box(at + Vector3(0, 0.02, 0), Vector3(30, 0.04, 12), Color("#ffe9b8"), Vector3.ZERO, false)


func _tower(p: Vector3, h: float, post: Color, roof: Color, back_wall: bool) -> void:
	# Roof sits 2.4 m above the deck so a standing Melly (1.8 m) fits inside.
	for x in [-1.9, 1.9]:
		for z in [-1.9, 1.9]:
			box(p + Vector3(x, (h + 2.5) * 0.5, z), Vector3(0.32, h + 2.5, 0.32), post)
	box(p + Vector3(0, h - 0.1, 0), Vector3(4.2, 0.25, 4.2), C_WOOD)
	if back_wall:
		box(p + Vector3(0, h + 0.5, -1.95), Vector3(4.0, 0.9, 0.12), C_WHITE)
	var roof_mesh_pos := p + Vector3(0, h + 3.25, 0)
	prism(roof_mesh_pos, Vector3(4.8, 1.6, 4.8), roof, Vector3.ZERO, true)
	box(p + Vector3(0, h + 2.4, 0), Vector3(4.6, 0.12, 4.6), roof.darkened(0.15))
	# Little flag on top.
	cyl(p + Vector3(0, h + 4.65, 0), 0.04, 1.4, C_DARK, false)
	prism(p + Vector3(0.35, h + 5.05, 0), Vector3(0.7, 0.5, 0.04), C_YELLOW, Vector3(0, 0, -90))


func _slide(top: Vector3, bottom: Vector3, color: Color) -> void:
	var d := bottom - top
	var flat := Vector3(d.x, 0, d.z)
	var len := d.length()
	var yaw := rad_to_deg(atan2(flat.x, flat.z))
	var pitch := rad_to_deg(atan2(-d.y, flat.length()))
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	var center := (top + bottom) * 0.5
	box(center, Vector3(1.9, 0.18, len), color, Vector3(pitch, yaw, 0))
	for sx in [-1.0, 1.0]:
		box(center + basis * Vector3(sx * 1.0, 0.35, 0), Vector3(0.14, 0.6, len), color.darkened(0.15), Vector3(pitch, yaw, 0))
	# Area that pushes players down the slide.
	var area := Area3D.new()
	area.transform = Transform3D(basis, center + basis * Vector3(0, 0.6, 0))
	var s := BoxShape3D.new()
	s.size = Vector3(1.8, 1.2, len)
	var cs := CollisionShape3D.new()
	cs.shape = s
	area.add_child(cs)
	area.set_meta("dir", flat.normalized() * 10.0)
	add_child(area)
	_slides.append(area)


# --- attractions ------------------------------------------------------------

func _build_swings(at: Vector3) -> void:
	var top_h := 4.4
	for x in [-4.4, 4.4]:
		for z in [-1.1, 1.1]:
			box(at + Vector3(x, top_h * 0.5, z * 0.55), Vector3(0.24, top_h + 0.2, 0.24), C_INDIGO, Vector3(z * 9.0, 0, 0))
	box(at + Vector3(0, top_h, 0), Vector3(9.2, 0.28, 0.28), C_INDIGO)
	cyl(at + Vector3(0, 0.02, 0), 5.0, 0.04, Color("#ffe9b8"), false, -1, 24)
	var colors := [C_RED, C_YELLOW, C_MINT]
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = at + Vector3(-2.9 + i * 2.9, top_h, 0)
		add_child(pivot)
		for side in [-0.55, 0.55]:
			var rope := BoxMesh.new()
			rope.size = Vector3(0.05, 3.1, 0.05)
			node_mesh(pivot, rope, C_DARK, Vector3(side, -1.55, 0))
		var seat := AnimatableBody3D.new()
		seat.position = Vector3(0, -3.15, 0)
		pivot.add_child(seat)
		var sm := BoxMesh.new()
		sm.size = Vector3(1.3, 0.14, 0.6)
		node_mesh(seat, sm, colors[i])
		var shape := BoxShape3D.new()
		shape.size = sm.size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		seat.add_child(cs)
		_swings.append({"pivot": pivot, "phase": i * 1.3, "amp": 0.5 + 0.1 * i})


func _build_carousel(at: Vector3) -> void:
	cyl(at + Vector3(0, 0.05, 0), 5.4, 0.1, C_PATH, false, -1, 32)
	_carousel = AnimatableBody3D.new()
	_carousel.position = at + Vector3(0, 0.3, 0)
	add_child(_carousel)
	var disk := CylinderMesh.new()
	disk.top_radius = 4.2
	disk.bottom_radius = 4.2
	disk.height = 0.3
	disk.radial_segments = 36
	node_mesh(_carousel, disk, C_PINK)
	var shape := CylinderShape3D.new()
	shape.radius = 4.2
	shape.height = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_carousel.add_child(cs)
	var seg_colors := [C_YELLOW, C_MINT, C_LILAC, C_BLUE, C_ORANGE, C_RED]
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 3.3
		var bar := CylinderMesh.new()
		bar.top_radius = 0.07
		bar.bottom_radius = 0.07
		bar.height = 2.2
		node_mesh(_carousel, bar, seg_colors[i], p + Vector3(0, 1.25, 0))
		var bshape := CylinderShape3D.new()
		bshape.radius = 0.1
		bshape.height = 2.2
		var bcs := CollisionShape3D.new()
		bcs.shape = bshape
		bcs.position = p + Vector3(0, 1.25, 0)
		_carousel.add_child(bcs)
		var horse := BoxMesh.new()
		horse.size = Vector3(0.35, 0.4, 0.9)
		var hm := node_mesh(_carousel, horse, seg_colors[i], p + Vector3(0, 0.9, 0))
		hm.rotation.y = -a
	var pole := CylinderMesh.new()
	pole.top_radius = 0.3
	pole.bottom_radius = 0.3
	pole.height = 2.6
	node_mesh(_carousel, pole, C_WHITE, Vector3(0, 1.3, 0))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.1
	roof.bottom_radius = 4.4
	roof.height = 1.2
	roof.radial_segments = 36
	node_mesh(_carousel, roof, C_RED, Vector3(0, 2.95, 0))
	var pole_shape := CylinderShape3D.new()
	pole_shape.radius = 0.35
	pole_shape.height = 2.6
	var pcs := CollisionShape3D.new()
	pcs.shape = pole_shape
	pcs.position.y = 1.3
	_carousel.add_child(pcs)


func _build_trampolines(at: Vector3) -> void:
	cyl(at + Vector3(0, 0.02, 0), 8.5, 0.04, Color("#ffe9b8"), false, -1, 28)
	var colors := [C_RED, C_YELLOW, C_MINT, C_LILAC, C_BLUE]
	var offsets := [Vector3(-4.5, 0, 0), Vector3(-1.5, 0, -3.5), Vector3(3.0, 0, -2.5), Vector3(4.5, 0, 2.5), Vector3(0, 0, 3.0)]
	var strengths := [14.0, 17.0, 17.0, 14.0, 26.0]
	for i in 5:
		var p: Vector3 = at + offsets[i]
		var big: bool = i == 4
		var r := 2.0 if big else 1.5
		cyl(p + Vector3(0, 0.3, 0), r, 0.6, C_DARK)
		cyl(p + Vector3(0, 0.62, 0), r - 0.2, 0.05, colors[i], false, -1, 24)
		torus(p + Vector3(0, 0.6, 0), r - 0.2, r + 0.05, colors[i].lightened(0.3))
		var area := Area3D.new()
		area.position = p + Vector3(0, 0.95, 0)
		var shape := CylinderShape3D.new()
		shape.radius = r - 0.2
		shape.height = 0.7
		var cs := CollisionShape3D.new()
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		var strength: float = strengths[i]
		area.body_entered.connect(func(b):
			if b is LocalPlayer:
				b.velocity.y = strength
				bounced.emit(strength))
	# A floating treat platform only the mega trampoline can reach.
	var sky := at + Vector3(4.5, 11.5, 7.5)
	cyl(sky, 2.2, 0.4, C_WHITE)
	for k in 6:
		var a := TAU * k / 6.0
		ball(sky + Vector3(cos(a) * 2.1, -0.2, sin(a) * 2.1), 0.9, Color("#f4f6ff"))
	cyl(sky + Vector3(0, 0.9, 0), 0.5, 1.4, C_PINK, true, 0.9)
	ball(sky + Vector3(0, 2.0, 0), 0.7, C_WHITE, true)
	sign_text(L.t("sign_trampolines"), at + Vector3(0, 3.4, -7.0), 90, C_YELLOW)


func _build_sandbox(at: Vector3) -> void:
	for s in [
		[Vector3(0, 0.25, -4.5), Vector3(9.4, 0.5, 0.4)],
		[Vector3(0, 0.25, 4.5), Vector3(9.4, 0.5, 0.4)],
		[Vector3(-4.5, 0.25, 0), Vector3(0.4, 0.5, 9.4)],
		[Vector3(4.5, 0.25, 0), Vector3(0.4, 0.5, 9.4)],
	]:
		box(at + s[0], s[1], C_PINK)
	box(at + Vector3(0, 0.1, 0), Vector3(8.6, 0.2, 8.6), Color("#f6dd9b"))
	# Sand castle with towers.
	var cc := at + Vector3(1.5, 0.2, -1.2)
	box(cc + Vector3(0, 0.4, 0), Vector3(2.0, 0.8, 2.0), Color("#e9c877"))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			cyl(cc + Vector3(x, 0.7, z), 0.35, 1.4, Color("#e9c877"))
			prism(cc + Vector3(x, 1.65, z), Vector3(0.7, 0.5, 0.7), C_RED)
	# Bucket, spade and a toy digger.
	cyl(at + Vector3(-2.5, 0.5, -2.5), 0.35, 0.6, C_BLUE, true, 0.45)
	box(at + Vector3(2.8, 0.25, 2.5), Vector3(0.14, 0.08, 1.2), C_RED, Vector3(0, 30, 0), false)
	var dg := at + Vector3(-2.0, 0.2, 2.2)
	box(dg + Vector3(0, 0.45, 0), Vector3(1.6, 0.6, 1.0), C_YELLOW)
	box(dg + Vector3(-0.3, 0.95, 0), Vector3(0.8, 0.5, 0.9), C_YELLOW.darkened(0.1))
	for x in [-0.55, 0.55]:
		for z in [-0.55, 0.55]:
			cyl(dg + Vector3(x, 0.2, z), 0.22, 0.14, C_DARK, false, -1, 12, Vector3(90, 0, 0))
	box(dg + Vector3(1.2, 0.6, 0), Vector3(1.0, 0.12, 0.3), C_YELLOW.darkened(0.2), Vector3(0, 0, -25), false)


func _build_seesaws(at: Vector3) -> void:
	box(at + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.9), C_INDIGO)
	_seesaw = AnimatableBody3D.new()
	_seesaw.position = at + Vector3(0, 1.0, 0)
	add_child(_seesaw)
	var plank := BoxMesh.new()
	plank.size = Vector3(7.0, 0.18, 0.9)
	node_mesh(_seesaw, plank, C_YELLOW)
	var shape := BoxShape3D.new()
	shape.size = plank.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_seesaw.add_child(cs)
	for x in [-2.6, 2.6]:
		var h := BoxMesh.new()
		h.size = Vector3(0.1, 0.6, 0.7)
		node_mesh(_seesaw, h, C_RED, Vector3(x, 0.35, 0))
	# Spring riders next to it.
	for i in 3:
		var p := at + Vector3(-6 + i * 2.2, 0, 4.5)
		cyl(p + Vector3(0, 0.3, 0), 0.12, 0.6, C_DARK, true)
		box(p + Vector3(0, 0.85, 0), Vector3(0.45, 0.5, 1.0), [C_MINT, C_PINK, C_BLUE][i])
		ball(p + Vector3(0, 1.2, 0.45), 0.28, [C_MINT, C_PINK, C_BLUE][i])


func _build_pond() -> void:
	var c := POND_CENTER
	var sx := POND_SIZE.x
	var sz := POND_SIZE.y
	# Basin floor and banks.
	box(c + Vector3(0, -0.9, 0), Vector3(sx, 0.2, sz), Color("#8fb7a8"))
	box(c + Vector3(0, -0.45, -sz * 0.5 + 0.2), Vector3(sx, 0.9, 0.4), C_STONE)
	box(c + Vector3(0, -0.45, sz * 0.5 - 0.2), Vector3(sx, 0.9, 0.4), C_STONE)
	box(c + Vector3(-sx * 0.5 + 0.2, -0.45, 0), Vector3(0.4, 0.9, sz), C_STONE)
	box(c + Vector3(sx * 0.5 - 0.2, -0.45, 0), Vector3(0.4, 0.9, sz), C_STONE)
	# Ramps so you can walk out of the water.
	ramp(c + Vector3(-sx * 0.5 + 2.0, -0.8, 0), c + Vector3(-sx * 0.5 - 0.5, 0.0, 0), 2.0)
	ramp(c + Vector3(sx * 0.5 - 2.0, -0.8, 0), c + Vector3(sx * 0.5 + 0.5, 0.0, 0), 2.0)
	# Rounded stones along the edge.
	for i in 26:
		var t := float(i) / 26.0
		var edge: Vector3
		if t < 0.25:
			edge = Vector3(lerpf(-sx, sx, t * 4.0) * 0.5, 0, -sz * 0.5)
		elif t < 0.5:
			edge = Vector3(sx * 0.5, 0, lerpf(-sz, sz, (t - 0.25) * 4.0) * 0.5)
		elif t < 0.75:
			edge = Vector3(lerpf(sx, -sx, (t - 0.5) * 4.0) * 0.5, 0, sz * 0.5)
		else:
			edge = Vector3(-sx * 0.5, 0, lerpf(sz, -sz, (t - 0.75) * 4.0) * 0.5)
		ball(c + edge + Vector3(0, 0.05, 0), _rng.randf_range(0.35, 0.6), C_STONE.darkened(_rng.randf_range(0.0, 0.12)), false, 0.6)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(sx - 0.6, sz - 0.6)
	plane.subdivide_width = 16
	plane.subdivide_depth = 10
	water.mesh = plane
	var wm := ShaderMaterial.new()
	wm.shader = WATER
	water.material_override = wm
	water.position = c + Vector3(0, -0.2, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# Wooden bridge across the middle.
	var b0 := c + Vector3(0, 0.0, -sz * 0.5 - 1.0)
	var b1 := c + Vector3(0, 0.0, sz * 0.5 + 1.0)
	var n := 16
	for i in n:
		var t := (i + 0.5) / n
		var p := b0.lerp(b1, t) + Vector3(0, sin(t * PI) * 1.0, 0)
		box(p, Vector3(2.4, 0.14, (sz + 2.0) / n - 0.05), C_WOOD if i % 2 == 0 else C_WOOD_DARK, Vector3(-cos(t * PI) * 14.0, 0, 0))
	# Smooth walkable arc under the planks (planks alone would be little steps).
	var segs := 6
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		ramp(b0.lerp(b1, t0) + Vector3(0, sin(t0 * PI) * 1.0 + 0.07, 0), b0.lerp(b1, t1) + Vector3(0, sin(t1 * PI) * 1.0 + 0.07, 0), 2.4)
	for sxd in [-1.25, 1.25]:
		for i in 8:
			var t := (i + 0.5) / 8.0
			var p := b0.lerp(b1, t) + Vector3(sxd, sin(t * PI) * 1.0 + 0.55, 0)
			box(p, Vector3(0.12, 1.0, 0.12), C_WOOD_DARK)
	# Lily pads to hop on.
	for i in 7:
		var p := c + Vector3(-7.5 + i * 1.6 + _rng.randf_range(-0.3, 0.3), -0.12, 3.5 + sin(i * 1.3) * 1.5)
		cyl(p, 0.75, 0.08, Color("#5dbb63"), true, -1, 16)
		if i % 2 == 0:
			ball(p + Vector3(0.2, 0.15, 0.1), 0.14, C_PINK)
	# Ducks.
	for i in 3:
		var duck := Node3D.new()
		duck.position = c + Vector3(-4 + i * 4, -0.1, -3.5)
		add_child(duck)
		var body := SphereMesh.new()
		body.radius = 0.28
		body.height = 0.42
		node_mesh(duck, body, C_YELLOW)
		var head := SphereMesh.new()
		head.radius = 0.16
		head.height = 0.32
		node_mesh(duck, head, C_YELLOW, Vector3(0, 0.25, 0.2))
		var beak := BoxMesh.new()
		beak.size = Vector3(0.12, 0.05, 0.14)
		node_mesh(duck, beak, C_ORANGE, Vector3(0, 0.22, 0.38))
		duck.set_meta("phase", i * 2.1)
		_ducks.append(duck)
	sign_text(L.t("sign_pond"), c + Vector3(-sx * 0.5 - 1.5, 2.4, -sz * 0.5 - 1.0), 70, C_BLUE, -35)


func _build_maze() -> void:
	# Hedge maze from a seeded depth-first carve; the prize waits in the center.
	var n := MAZE_CELLS
	var s := MAZE_CELL
	var o := MAZE_ORIGIN
	var hedge := Color("#4f9e57")
	var hedge_top := Color("#63b86a")
	var visited := {}
	var walls_h := {}  # "x,y" -> wall on north side of cell (y is row)
	var walls_v := {}  # wall on west side of cell
	for x in n + 1:
		for y in n + 1:
			walls_h[Vector2i(x, y)] = true
			walls_v[Vector2i(x, y)] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var stack: Array[Vector2i] = [Vector2i(n / 2, n - 1)]
	visited[stack[0]] = true
	while stack.size() > 0:
		var cur: Vector2i = stack[-1]
		var opts := []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if nb.x >= 0 and nb.y >= 0 and nb.x < n and nb.y < n and not visited.has(nb):
				opts.append(nb)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = opts[rng.randi() % opts.size()]
		var d := nxt - cur
		if d.x == 1:
			walls_v[nxt] = false
		elif d.x == -1:
			walls_v[cur] = false
		elif d.y == 1:
			walls_h[nxt] = false
		else:
			walls_h[cur] = false
		visited[nxt] = true
		stack.append(nxt)
	# Entrance at the south middle, open center room.
	walls_h[Vector2i(n / 2, n)] = false
	var mid := n / 2
	for cx in [mid - 1, mid, mid + 1]:
		for cy in [mid - 1, mid, mid + 1]:
			if cx > mid - 1:
				walls_v[Vector2i(cx, cy)] = false
			if cy > mid - 1:
				walls_h[Vector2i(cx, cy)] = false
	var hh := 2.6
	for key in walls_h:
		if walls_h[key] and key.x < n:
			var p := o + Vector3((key.x + 0.5) * s, hh * 0.5, key.y * s)
			box(p, Vector3(s + 0.5, hh, 0.5), hedge)
			box(p + Vector3(0, hh * 0.5 + 0.05, 0), Vector3(s + 0.5, 0.1, 0.5), hedge_top, Vector3.ZERO, false)
	for key in walls_v:
		if walls_v[key] and key.y < n:
			var p := o + Vector3(key.x * s, hh * 0.5, (key.y + 0.5) * s)
			box(p, Vector3(0.5, hh, s + 0.5), hedge)
			box(p + Vector3(0, hh * 0.5 + 0.05, 0), Vector3(0.5, 0.1, s + 0.5), hedge_top, Vector3.ZERO, false)
	box(o + Vector3(n * s * 0.5, 0.02, n * s * 0.5), Vector3(n * s, 0.04, n * s), Color("#d9cfb3"), Vector3.ZERO, false)
	var center := o + Vector3((mid + 0.5) * s, 0, (mid + 0.5) * s)
	cyl(center + Vector3(0, 0.3, 0), 1.2, 0.6, C_STONE)
	_prize = Node3D.new()
	_prize.position = center + Vector3(0, 1.4, 0)
	add_child(_prize)
	for i in 6:
		var a := TAU * i / 6.0
		var petal := SphereMesh.new()
		petal.radius = 0.28
		petal.height = 0.2
		node_mesh(_prize, petal, C_YELLOW, Vector3(cos(a) * 0.34, 0, sin(a) * 0.34))
	var core := SphereMesh.new()
	core.radius = 0.22
	core.height = 0.3
	var core_mi := node_mesh(_prize, core, C_ORANGE)
	core_mi.material_override = StandardMaterial3D.new()
	(core_mi.material_override as StandardMaterial3D).albedo_color = C_ORANGE
	(core_mi.material_override as StandardMaterial3D).emission_enabled = true
	(core_mi.material_override as StandardMaterial3D).emission = C_YELLOW
	var area := Area3D.new()
	area.position = center + Vector3(0, 1.0, 0)
	var sh := SphereShape3D.new()
	sh.radius = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = sh
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(func(b):
		if b is LocalPlayer:
			maze_solved.emit())
	sign_text(L.t("sign_maze"), o + Vector3(n * s * 0.5, 3.8, n * s + 1.5), 90, C_MINT)


func _build_parkour() -> void:
	var colors := [C_RED, C_ORANGE, C_YELLOW, C_MINT, C_BLUE, C_INDIGO, C_LILAC, C_PINK]
	var center := SPIRAL_CENTER
	var radius := 8.5
	sign_text(L.t("sign_parkour"), center + Vector3(radius + 1.0, 3.2, 3.5), 80, UI.TEXT, 90)
	cyl(center + Vector3(radius, 0.1, 0), 1.6, 0.2, C_LILAC, false)
	var top_y := 0.0
	for i in 18:
		var a := i * 0.43
		var pos := center + Vector3(cos(a) * radius, 1.0 + i * 1.05, sin(a) * radius)
		top_y = pos.y
		var size := Vector3(2.4, 0.5, 2.4) if i % 4 != 3 else Vector3(1.7, 0.5, 1.7)
		box(pos, size, colors[i % colors.size()])
		box(pos - Vector3(0, 0.3, 0), size * Vector3(0.9, 0.2, 0.9), colors[i % colors.size()].darkened(0.25), Vector3.ZERO, false)
	# Cloud island in the middle of the spiral.
	var island := center + Vector3(0, top_y + 0.6, 0)
	cyl(island, 5.5, 1.2, C_WHITE, true, -1, 32)
	for k in 10:
		var a := TAU * k / 10.0
		ball(island + Vector3(cos(a) * 5.0, -0.4, sin(a) * 5.0), 1.5, Color("#f4f6ff"))
	for k in 5:
		ball(island + Vector3(_rng.randf_range(-3, 3), -1.2, _rng.randf_range(-3, 3)), 2.0, Color("#eef1ff"))
	_star = Node3D.new()
	_star.position = island + Vector3(0, 2.4, 0)
	add_child(_star)
	var star_mesh := PrismMesh.new()
	star_mesh.size = Vector3(1.2, 1.2, 0.35)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = C_YELLOW
	gold.metallic = 0.6
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color("#ffb84d")
	gold.emission_energy_multiplier = 0.9
	for r in [0.0, 180.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = star_mesh
		mi.material_override = gold
		mi.rotation_degrees.z = r
		mi.position.y = -0.2 if r > 0.0 else 0.2
		_star.add_child(mi)
	var island_area := Area3D.new()
	island_area.position = island + Vector3(0, 1.6, 0)
	var sh := CylinderShape3D.new()
	sh.radius = 4.8
	sh.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = sh
	island_area.add_child(cs)
	add_child(island_area)
	island_area.body_entered.connect(func(b):
		if b is LocalPlayer:
			reached_island.emit())


func _build_kiosk(at: Vector3) -> void:
	box(at + Vector3(0, 1.0, 0), Vector3(3.2, 2.0, 2.2), C_WHITE)
	box(at + Vector3(0, 1.05, 1.12), Vector3(3.2, 0.12, 0.3), C_PINK)
	for i in 5:
		box(at + Vector3(-1.3 + i * 0.65, 2.75, 1.1), Vector3(0.62, 0.1, 1.2), C_PINK if i % 2 == 0 else C_WHITE, Vector3(-18, 0, 0), false)
	box(at + Vector3(0, 2.6, 0), Vector3(3.4, 0.14, 2.4), C_PINK)
	# Giant ice cream on the roof.
	cyl(at + Vector3(0, 3.35, 0), 0.05, 1.3, C_WOOD, false, 0.45)
	ball(at + Vector3(0, 4.2, 0), 0.55, C_PINK)
	ball(at + Vector3(0, 4.7, 0), 0.45, C_MINT)
	ball(at + Vector3(0, 5.1, 0), 0.12, C_RED)
	sign_text(L.t("sign_icecream"), at + Vector3(0, 1.75, 1.3), 40, C_PINK)


func _build_picnic(at: Vector3) -> void:
	for i in 3:
		var p := at + Vector3(i * 5.0 - 5.0, 0, (i % 2) * 3.0)
		box(p + Vector3(0, 0.75, 0), Vector3(2.4, 0.1, 1.2), C_WOOD)
		box(p + Vector3(0, 0.45, 0.9), Vector3(2.4, 0.08, 0.4), C_WOOD)
		box(p + Vector3(0, 0.45, -0.9), Vector3(2.4, 0.08, 0.4), C_WOOD)
		for x in [-1.0, 1.0]:
			box(p + Vector3(x, 0.37, 0), Vector3(0.1, 0.74, 2.0), C_WOOD_DARK)
		box(p + Vector3(0, 0.81, 0), Vector3(1.4, 0.02, 0.9), [C_RED, C_BLUE, C_MINT][i], Vector3.ZERO, false)
	# Umbrella.
	cyl(at + Vector3(0, 1.4, 0), 0.05, 2.8, C_WHITE, true)
	cyl(at + Vector3(0, 2.9, 0), 1.9, 0.5, C_RED, false, 0.1)


func _build_nature() -> void:
	# Trees: round ones and pines, kept away from attractions.
	var keep_out := [
		[Vector3(0, 0, 0), 30.0], [SPIRAL_CENTER, 15.0], [POND_CENTER, 15.0],
		[MAZE_ORIGIN + Vector3(15, 0, 15), 20.0], [Vector3(-36, 0, 36), 8.0],
	]
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 900:
		tries += 1
		var p := Vector3(_rng.randf_range(-HALF + 4, HALF - 4), 0, _rng.randf_range(-HALF + 4, HALF - 4))
		var bad := false
		for k in keep_out:
			if p.distance_to(k[0]) < k[1]:
				bad = true
				break
		if bad:
			continue
		var sc := _rng.randf_range(0.85, 1.5)
		if _rng.randf() < 0.35:
			cyl(p + Vector3(0, 0.8 * sc, 0), 0.25 * sc, 1.6 * sc, C_WOOD_DARK)
			var pine := Color("#3f9a5a").lerp(Color("#2f7f4f"), _rng.randf())
			for k in 3:
				cyl(p + Vector3(0, (1.6 + k * 1.1) * sc, 0), (1.7 - k * 0.45) * sc, 1.6 * sc, pine.lightened(k * 0.05), k == 0, 0.0, 12)
		else:
			cyl(p + Vector3(0, 1.2 * sc, 0), 0.3 * sc, 2.4 * sc, C_WOOD_DARK)
			var leaf: Color = C_LEAF[_rng.randi() % C_LEAF.size()]
			ball(p + Vector3(0, 3.0 * sc, 0), 1.5 * sc, leaf, true)
			ball(p + Vector3(0.8, 2.6, 0.3) * sc, 1.0 * sc, leaf.darkened(0.06))
			ball(p + Vector3(-0.7, 2.8, -0.4) * sc, 1.1 * sc, leaf.lightened(0.05))
		placed += 1
	# Bushes, rocks and flower patches.
	for i in 60:
		var p := Vector3(_rng.randf_range(-HALF + 3, HALF - 3), 0, _rng.randf_range(-HALF + 3, HALF - 3))
		if p.distance_to(Vector3(0, 0, 8)) < 12.0 or p.distance_to(POND_CENTER) < 13.0 or p.distance_to(SPIRAL_CENTER) < 11.0:
			continue
		var r := _rng.randf()
		if r < 0.4:
			ball(p + Vector3(0, 0.35, 0), _rng.randf_range(0.6, 1.0), Color("#56b060"), true, 0.75)
		elif r < 0.6:
			ball(p + Vector3(0, 0.15, 0), _rng.randf_range(0.4, 0.9), C_STONE.darkened(_rng.randf_range(0, 0.15)), true, 0.6)
		else:
			var fc: Color = [C_PINK, C_YELLOW, C_WHITE, C_LILAC, C_RED][_rng.randi() % 5]
			for k in 6:
				var fp := p + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))
				cyl(fp + Vector3(0, 0.15, 0), 0.02, 0.3, Color("#4caa5a"), false, -1, 4)
				ball(fp + Vector3(0, 0.33, 0), 0.09, fc)


func _build_fence_and_backdrop() -> void:
	var c := C_WHITE
	for side in 4:
		var horizontal := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var n := 36
		for i in n:
			var t := -HALF + (HALF * 2.0) * (i + 0.5) / n
			var p := Vector3(t, 0.6, sgn * HALF) if horizontal else Vector3(sgn * HALF, 0.6, t)
			box(p, Vector3(0.18, 1.2, 0.18), c, Vector3.ZERO, false)
			prism(p + Vector3(0, 0.7, 0), Vector3(0.18, 0.2, 0.18), c)
		for y in [0.45, 0.95]:
			var rail_pos := Vector3(0, y, sgn * HALF) if horizontal else Vector3(sgn * HALF, y, 0)
			var rail_size := Vector3(HALF * 2.0, 0.1, 0.07) if horizontal else Vector3(0.07, 0.1, HALF * 2.0)
			box(rail_pos, rail_size, c, Vector3.ZERO, false)
		var wall_pos := Vector3(0, 20.0, sgn * (HALF + 0.4)) if horizontal else Vector3(sgn * (HALF + 0.4), 20.0, 0)
		var wall_size := Vector3(HALF * 2.0 + 2.0, 40.0, 0.6) if horizontal else Vector3(0.6, 40.0, HALF * 2.0 + 2.0)
		var s := BoxShape3D.new()
		s.size = wall_size
		_collide(s, Transform3D(Basis(), wall_pos))
	# Soft hills and far mountains for a nicer horizon (no collision).
	for i in 22:
		var a := TAU * i / 22.0 + _rng.randf_range(-0.1, 0.1)
		var d := _rng.randf_range(110, 150)
		var h := _rng.randf_range(18, 42)
		var col := Color("#8fc6a0").lerp(Color("#b7c9f0"), clampf((d - 110.0) / 40.0, 0.0, 1.0))
		cyl(Vector3(cos(a) * d, h * 0.5 - 2.0, sin(a) * d), _rng.randf_range(16, 26), h, col, false, _rng.randf_range(2, 6), 10)
	for i in 16:
		var a := TAU * i / 16.0 + 0.2
		ball(Vector3(cos(a) * 88, -3.0, sin(a) * 88), _rng.randf_range(10, 16), Color("#79c07a"), false, 0.45)


func _build_clouds() -> void:
	for i in 16:
		var cloud := Node3D.new()
		cloud.position = Vector3(_rng.randf_range(-110, 110), _rng.randf_range(30, 48), _rng.randf_range(-110, 110))
		add_child(cloud)
		# One merged mesh per cloud: five puffs, one draw call.
		var puffs := MeshBatch.new()
		for k in 5:
			var sm := SphereMesh.new()
			sm.radius = _rng.randf_range(2.0, 3.2)
			sm.height = sm.radius * 1.6
			var at := Vector3(k * 2.4 - 4.8, _rng.randf_range(-0.4, 0.8), _rng.randf_range(-1.2, 1.2))
			puffs.add(sm, Transform3D(Basis(), at), Color("#ffffff"))
		puffs.build(cloud, _batch_mat, false)
		cloud.set_meta("speed", _rng.randf_range(0.5, 1.2))
		_clouds.append(cloud)


func _build_balloons() -> void:
	var colors := [C_RED, C_YELLOW, C_BLUE, C_PINK, C_MINT, C_LILAC]
	for i in 10:
		var b := Node3D.new()
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(18, 55)
		b.position = Vector3(cos(a) * d, _rng.randf_range(9, 20), sin(a) * d)
		add_child(b)
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.4
		var str_mesh := BoxMesh.new()
		str_mesh.size = Vector3(0.02, 1.6, 0.02)
		var parts := MeshBatch.new()
		parts.add(sm, Transform3D(), colors[i % colors.size()])
		parts.add(str_mesh, Transform3D(Basis(), Vector3(0, -1.5, 0)), C_WHITE)
		parts.build(b, _batch_mat, false)
		b.set_meta("phase", _rng.randf() * TAU)
		b.set_meta("base", b.position)
		_balloons.append(b)


# --- animation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	# Wall-clock time so every client sees roughly the same ride positions.
	var wall := fmod(Time.get_unix_time_from_system(), 3600.0)
	if _carousel:
		_carousel.rotation.y = fmod(wall * 0.5, TAU)
	if _seesaw:
		_seesaw.rotation.z = sin(wall * 0.9) * 0.22
	for s in _swings:
		s.pivot.rotation.x = sin(wall * 1.6 + s.phase) * s.amp
	if _player:
		for area in _slides:
			if area.overlaps_body(_player):
				_player.external_push = area.get_meta("dir")
		if not _player.seated and _player.can_sit() and _player.is_on_floor():
			for seat in _seats:
				# Only when actually standing on the seat, not brushing past the bench.
				if seat.area.overlaps_body(_player) and _player.global_position.y > seat.top - 0.12:
					_player.sit_on(seat.center, seat.basis)
					break


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += delta * float(c.get_meta("speed"))
		if c.position.x > 120.0:
			c.position.x = -120.0
	for b in _balloons:
		var base: Vector3 = b.get_meta("base")
		var ph: float = b.get_meta("phase")
		b.position = base + Vector3(sin(_t * 0.4 + ph) * 1.5, sin(_t * 0.8 + ph) * 0.8, cos(_t * 0.3 + ph) * 1.5)
	for d in _ducks:
		var ph: float = d.get_meta("phase")
		d.position.x = POND_CENTER.x + sin(_t * 0.25 + ph) * 7.0
		d.position.z = POND_CENTER.z - 3.0 + cos(_t * 0.25 + ph) * 2.5
		d.rotation.y = _t * 0.25 + ph + PI * 0.5
		d.position.y = -0.1 + sin(_t * 2.0 + ph) * 0.03
	for j in _fountain_jets:
		j.scale.y = 1.0 + sin(_t * 6.0 + j.position.x) * 0.1
	if _star:
		_star.rotation.y += delta * 1.6
	if _prize:
		_prize.rotation.y += delta
		_prize.position.y += sin(_t * 2.0) * delta * 0.2
