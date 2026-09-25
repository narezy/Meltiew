extends Node3D
## Playground session: world, local player, remote players and networking.

const SEND_HZ := 15.0

## The built-in Playground, or a PlaceWorld stand-in for studio places
## (their world is drawn by place_host.scene).
var world: Node3D
## The connection: the Net autoload, or a LocalNet during a Studio play test.
var net: Node
var place_host: PlaceHost
var console_lines: Array = []
var _is_place := false
var _pos_timer := 0.0
var _press_pos := Vector2.ZERO
var player: LocalPlayer
var hud: GameHud
var menu: GameMenu
var remotes := {}  # user id -> RemotePlayer
var users := {}  # user id -> public user dict (everyone incl. me)
var my_id := -1
var server_info := {}
var _send_accum := 0.0
var _last_sent := {}
var _last_sent_at := 0
var _ping_ms := -1
var _ping_timer := 0.0
var _stats_timer := 0.0
var _joined := false
var _leaving := false
var _retries := 0
var _my_bubble: Label3D
var _my_bubble_time := 0.0
var _heart_tex: Texture2D
var _last_heart := -100000
const HEART_COOLDOWN_MS := 2500
var _island_announced := false


func _ready() -> void:
	# Android back button should open the menu, not kill the app.
	get_tree().quit_on_go_back = false
	get_tree().set_auto_accept_quit(false)
	_is_place = Session.pending_game != "playground"
	if not Session.test_marp.is_empty():
		net = LocalNet.new(Session.test_marp)
		add_child(net)
	else:
		net = Net
	world = PlaceWorld.new() if _is_place else Playground.new()
	add_child(world)
	player = LocalPlayer.new()
	add_child(player)
	world.attach_player(player)
	player.global_position = world.spawn_point
	player.avatar.apply_user(Session.user)
	player.jumped.connect(func(): Sfx.play("jump", randf_range(0.95, 1.08)))
	player.landed.connect(func(impact):
		if impact > 9.0:
			Sfx.play("land", clampf(1.3 - impact / 60.0, 0.7, 1.2)))
	player.hurt.connect(func(_amount): Sfx.play("hurt"))
	player.died.connect(_on_died)
	player.respawned.connect(func(): hud.big_message(""))
	if world is Playground:
		world.bounced.connect(func(s): Sfx.play("boing", clampf(1.4 - s / 40.0, 0.8, 1.3)))
		world.reached_island.connect(_on_island)
		world.maze_solved.connect(func():
			Sfx.play("coin")
			hud.big_message(L.t("maze_solved"), 3.0))
	else:
		# Studio places: health and respawns come from the server; wait for the world.
		player.server_health = true
		player.set_physics_process(false)

	_my_bubble = GameBubble.make()
	player.add_child(_my_bubble)

	hud = GameHud.new()
	add_child(hud)
	hud.bind_player(player)
	hud.menu_requested.connect(_open_menu)
	hud.chat_submitted.connect(func(t): net.send({"t": "chat", "m": t}))
	hud.emote_picked.connect(_emote)

	menu = GameMenu.new()
	menu.game = self
	add_child(menu)
	menu.reset_requested.connect(func(): player.die())
	menu.leave_requested.connect(_confirm_leave)
	menu.settings_changed.connect(_apply_quality)
	Session.settings_changed.connect(_on_settings_changed)
	_apply_quality()

	net.connected.connect(_on_connected)
	net.disconnected.connect(_on_disconnected)
	net.message.connect(_on_message)
	hud.show_overlay(L.t("loading_place") if _is_place else L.t("joining_playground"))
	net.connect_to_game()


func _exit_tree() -> void:
	net.close()
	if place_host:
		place_host.close()
	var vp := get_viewport()
	vp.scaling_3d_scale = 1.0
	Engine.max_fps = 0
	get_tree().quit_on_go_back = true
	get_tree().set_auto_accept_quit(true)


var _applied_quality := ""


func _on_settings_changed() -> void:
	_apply_quality()
	hud.set_stats(int(Engine.get_frames_per_second()), _ping_ms)


func _apply_quality() -> void:
	var q := str(Session.settings.quality)
	if q == _applied_quality:
		return
	_applied_quality = q
	var vp := get_viewport()
	var mobile := OS.has_feature("mobile")
	# No FPS cap: vsync already follows the display (60/90/120 Hz).
	Engine.max_fps = 0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	match q:
		"low":
			vp.scaling_3d_scale = 0.75 if mobile else 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED
			player.camera.far = 140.0
		"medium":
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED if mobile else Viewport.MSAA_2X
			player.camera.far = 300.0
		_:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X if mobile else Viewport.MSAA_4X
			player.camera.far = 700.0
	world.apply_quality(q)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if menu and menu.visible:
			menu.close()
		else:
			_open_menu()


func _open_menu() -> void:
	hud.release_touches()
	menu.open()


# --- networking -------------------------------------------------------------

func _on_connected() -> void:
	_retries = 0
	net.send({"t": "join", "game": Session.pending_game, "server": Session.pending_server})


func _on_disconnected(reason: String) -> void:
	if _leaving:
		return
	_joined = false
	for id in remotes.keys():
		_remove_remote(id)
	if _retries < 3 and reason != L.t("err_duplicate"):
		_retries += 1
		hud.show_overlay("%s\n%s" % [reason, L.t("reconnecting", [_retries])])
		await get_tree().create_timer(1.5 * _retries).timeout
		if not _leaving and is_inside_tree():
			if server_info.has("id"):
				Session.pending_server = str(server_info.id)
			net.connect_to_game()
		return
	hud.show_overlay(reason, [
		[L.t("retry"), func():
			_retries = 0
			hud.show_overlay(L.t("connecting"))
			net.connect_to_game()],
		[L.t("to_menu"), _leave, "ghost"],
	])


func _on_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"welcome":
			_on_welcome(m)
		"r":
			if place_host:
				place_host.server_ops(m.o)
		"s":
			for s in m.s:
				var id := int(s[0])
				if remotes.has(id):
					remotes[id].set_state(Vector3(s[1], s[2], s[3]), float(s[4]), str(s[5]))
		"join":
			_add_remote(m.player)
			Sfx.play("pop", 1.2)
			_refresh_players()
		"leave":
			_remove_remote(int(m.id))
			_refresh_players()
		"look":
			var u: Dictionary = m.player
			users[int(u.id)] = u
			if remotes.has(int(u.id)):
				remotes[int(u.id)].user = u
				remotes[int(u.id)].refresh_look()
			_refresh_players()
		"chat":
			var id := int(m.id)
			var is_me := id == my_id
			hud.add_chat(str(m.name), str(m.m), UI.ACCENT if is_me else UI.MINT)
			if is_me:
				GameBubble.show(_my_bubble, str(m.m))
				_my_bubble_time = 6.0
			elif remotes.has(id):
				remotes[id].show_bubble(str(m.m))
			Sfx.play("pop", 1.4)
		"sys":
			match str(m.get("k", "")):
				"joined":
					hud.add_chat("", L.t("sys_joined", [m.get("n", "")]))
				"left":
					hud.add_chat("", L.t("sys_left", [m.get("n", "")]))
				"slow":
					hud.add_chat("", L.t("sys_slow"))
				"no_chat":
					hud.add_chat("", L.t("sys_no_chat"))
				"admin":
					hud.add_chat("Meltiew", str(m.get("m", "")), Color("#ffd166"))
					hud.big_message(str(m.get("m", "")), 3.5)
		"emote":
			var id := int(m.id)
			if remotes.has(id) and m.e == "heart":
				_spawn_heart(remotes[id])
		"dead":
			var id := int(m.id)
			if remotes.has(id):
				remotes[id].shatter()
		"correct":
			# The server's anti-cheat put us back where we legitimately were.
			var cp: Array = m.p
			player.global_position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
			player.reset_physics_interpolation()
			player.velocity = Vector3.ZERO
		"error":
			if str(m.get("code", "")) == "birthdate":
				_leaving = true
				net.close()
				hud.show_overlay(L.t("birthdate_needed"), [[L.t("to_menu"), _leave]])
				return
			if not _joined:
				hud.show_overlay(str(m.get("m", "Error")), [
					[L.t("other_server"), func():
						Session.pending_server = "auto"
						hud.show_overlay(L.t("finding_server"))
						net.send({"t": "join", "game": Session.pending_game, "server": "auto"})],
					[L.t("to_menu"), _leave, "ghost"],
				])
		"kicked":
			_leaving = true
			net.close()
			match str(m.get("code", "")):
				"update":
					UI.show_update_required(str(m.get("m", "")), Api.BASE_URL + "/download")
				"banned":
					hud.show_overlay(L.t("kicked_banned"), [[L.t("to_menu"), _leave]])
				"kicked":
					hud.show_overlay(L.t("kicked_admin"), [[L.t("to_menu"), _leave]])
				"closed":
					hud.show_overlay(L.t("server_closed"), [[L.t("to_menu"), _leave]])
				"place":
					# Kicked by the place's own script (player:Kick("...")).
					hud.show_overlay(str(m.get("m", "")) if str(m.get("m", "")) != "" else L.t("kicked_admin"), [[L.t("to_menu"), _leave]])
				_:
					hud.show_overlay(L.t("err_duplicate"), [[L.t("to_menu"), _leave]])
		"pong":
			_ping_ms = Time.get_ticks_msec() - int(m.c)


func _on_welcome(m: Dictionary) -> void:
	_joined = true
	server_info = m.server
	my_id = int(m.you)
	for id in remotes.keys():
		_remove_remote(id)
	users.clear()
	users[my_id] = Session.user
	for u in m.players:
		_add_remote(u)
	if m.get("place") is Dictionary:
		_start_place(m.place)
	else:
		var sp: Array = m.spawn
		player.spawn_point = Vector3(sp[0], sp[1], sp[2])
		player.global_position = player.spawn_point
		player.reset_physics_interpolation()
		player.velocity = Vector3.ZERO
	hud.hide_overlay()
	hud.set_chat_enabled(bool(m.get("chat", true)))
	_refresh_players()
	Sfx.play("join")
	hud.add_chat("", L.t("welcome_server", [L.field(server_info, "name")]))


# --- studio places ------------------------------------------------------------------

func _start_place(p: Dictionary) -> void:
	if place_host:
		place_host.close()
		place_host.queue_free()
		if place_host.scene:
			place_host.scene.queue_free()
	place_host = PlaceHost.new()
	add_child(place_host)
	place_host.send.connect(func(msg): net.send(msg))
	place_host.output.connect(_on_output)
	place_host.spawn_requested.connect(func(pos: Vector3):
		player.set_physics_process(true)
		player.respawn_at(pos))
	place_host.teleport_requested.connect(func(pos: Vector3):
		player.global_position = pos
		player.reset_physics_interpolation()
		player.velocity = Vector3.ZERO)
	if not place_host.start(my_id, L.lang, p.get("strings", {}), p.get("snapshot", []), world):
		hud.add_chat("", L.t("place_unsupported"))
	place_host.scene.apply_quality(str(Session.settings.quality))
	world.set_scene(place_host.scene)


func _on_output(line: Dictionary) -> void:
	console_lines.append(line)
	# A Studio play test hands its output back to the editor.
	if not Session.test_marp.is_empty():
		var out: Array = Session.get_meta("test_output", [])
		out.append(line)
		Session.set_meta("test_output", out)
	if console_lines.size() > 300:
		console_lines.pop_front()
	# Script errors also show in the console tab; F9 toggles a quick view in the chat.
	if str(line.get("level", "")) == "error" and _console_in_chat:
		hud.add_chat("", "[%s] %s" % [str(line.get("src", "script")), str(line.get("msg", ""))], UI.DANGER)


var _console_in_chat := false


func console_bbcode() -> String:
	var out := PackedStringArray()
	for line in console_lines:
		var color: String = {"error": "#ff6b7a", "warn": "#ffd166"}.get(str(line.get("level", "")), "#f4f1ec")
		var who := "[color=#9d96b0]%s%s[/color] " % ["server " if line.get("server", false) else "", str(line.get("src", ""))]
		out.append(who + "[color=%s]%s[/color]" % [color, str(line.get("msg", "")).replace("[", "[lb]")])
	return "\n".join(out) if not out.is_empty() else "[color=#9d96b0]...[/color]"


## Keeps the character in sync with the place's Humanoid, Workspace and StarterPlayer.
func _sync_place(delta: float) -> void:
	var h := place_host
	var hum := h.local_humanoid()
	if hum != "":
		var t := h.tree
		player.walk_speed = float(t.prop(hum, "WalkSpeed"))
		player.sprint_speed = float(t.prop(hum, "SprintSpeed"))
		player.jump_velocity = float(t.prop(hum, "JumpPower"))
		player.can_jump = t.prop(hum, "CanJump")
		var hp := float(t.prop(hum, "Health"))
		var mx := float(t.prop(hum, "MaxHealth"))
		if not is_equal_approx(hp, player.hp) or not is_equal_approx(mx, player.max_hp):
			player.set_server_health(hp, mx)
	player.gravity = float(h.workspace_prop("Gravity"))
	player.void_height = float(h.workspace_prop("FallHeight"))
	if not player.dead:
		for i in player.get_slide_collision_count():
			h.report_contact(PlaceScene.id_of(player.get_slide_collision(i).get_collider()))
		_ghost_contacts()
	_pos_timer -= delta
	if _pos_timer <= 0.0:
		_pos_timer = 0.1
		h.report_position(player.global_position + Vector3(0, 0.9, 0))


var _ghost_query: PhysicsShapeQueryParameters3D


## Touches on parts that don't block players (CanCollide = false).
func _ghost_contacts() -> void:
	if _ghost_query == null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45
		cap.height = 1.9
		_ghost_query = PhysicsShapeQueryParameters3D.new()
		_ghost_query.shape = cap
		_ghost_query.collision_mask = PlaceScene.LAYER_GHOST
	_ghost_query.transform = Transform3D(Basis(), player.global_position + Vector3(0, 0.95, 0))
	for hit in get_world_3d().direct_space_state.intersect_shape(_ghost_query, 8):
		place_host.report_contact(PlaceScene.id_of(hit.collider))


func _unhandled_input(event: InputEvent) -> void:
	if not place_host:
		return
	if event is InputEventKey and not event.echo:
		if event.pressed and event.keycode == KEY_F9:
			_console_in_chat = not _console_in_chat
			hud.add_chat("", L.t("console") + (": on" if _console_in_chat else ": off"))
			return
		place_host.key_event(OS.get_keycode_string(event.keycode), event.pressed)
	# A tap/click (not a camera drag) on a part with a ClickDetector.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < 12.0:
			_click_at(event.position)


func _click_at(screen: Vector2) -> void:
	var cam := player.camera
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 120.0, PlaceScene.LAYER_WORLD | PlaceScene.LAYER_GHOST)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var part := PlaceScene.id_of(hit.collider)
	var det := place_host.tree.child_of_class(part, "ClickDetector") if part != "" else ""
	if det != "" and hit.position.distance_to(player.global_position) <= float(place_host.tree.prop(det, "MaxDistance")) + 2.0:
		net.send({"t": "click", "id": det})
		Sfx.click()


func _add_remote(u: Dictionary) -> void:
	var id := int(u.id)
	if id == my_id:
		return
	users[id] = u
	if remotes.has(id):
		remotes[id].user = u
		remotes[id].refresh_look()
		return
	var r := RemotePlayer.new()
	r.user = u
	add_child(r)
	remotes[id] = r
	if u.has("p"):
		r.set_state(Vector3(u.p[0], u.p[1], u.p[2]), float(u.get("r", 0.0)), str(u.get("a", "idle")))


func _remove_remote(id: int) -> void:
	users.erase(id)
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)


func _refresh_players() -> void:
	hud.set_server(L.field(server_info, "name"), users.size(), int(server_info.get("max_players", 10)))


func _physics_process(delta: float) -> void:
	if not _joined:
		return
	if place_host:
		_sync_place(delta)
	_send_accum += delta
	if _send_accum >= 1.0 / SEND_HZ:
		_send_accum = 0.0
		var p := player.global_position
		var state := {
			"t": "state",
			"p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
			"r": snappedf(player.avatar.rotation.y, 0.01),
			"a": player.current_anim(),
		}
		# Resend at least once a second so late joiners and interpolation stay fresh.
		var now := Time.get_ticks_msec()
		if state != _last_sent or now - _last_sent_at > 1000:
			net.send(state)
			_last_sent = state
			_last_sent_at = now


func _process(delta: float) -> void:
	_ping_timer -= delta
	if _ping_timer <= 0.0 and _joined:
		_ping_timer = 3.0
		net.send({"t": "ping", "c": Time.get_ticks_msec()})
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.5
		hud.set_stats(int(Engine.get_frames_per_second()), _ping_ms)
	if _my_bubble_time > 0.0:
		_my_bubble_time -= delta
		if _my_bubble_time <= 0.0:
			_my_bubble.visible = false


# --- actions ----------------------------------------------------------------

func _emote(e: String) -> void:
	if player.dead:
		return
	if e == "heart":
		# Same cooldown as the server, so spamming doesn't even show locally.
		var now := Time.get_ticks_msec()
		if now - _last_heart < HEART_COOLDOWN_MS:
			return
		_last_heart = now
		_spawn_heart(player)
		net.send({"t": "emote", "e": "heart"})
		return
	player.play_emote(e)


func _on_died() -> void:
	Ragdoll.spawn(self, player.avatar.global_transform, player.avatar.get_colors(), player.velocity)
	net.send({"t": "dead"})
	hud.big_message(L.t("you_fell_apart"), 2.4)


func _spawn_heart(target: Node3D) -> void:
	if _heart_tex == null:
		_heart_tex = _make_heart_texture()
	for i in 3:
		var s := Sprite3D.new()
		s.texture = _heart_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 0.006
		s.shaded = false
		add_child(s)
		s.global_position = target.global_position + Vector3(randf_range(-0.4, 0.4), 2.2 + i * 0.2, randf_range(-0.4, 0.4))
		var t := s.create_tween().set_parallel()
		t.tween_property(s, "position:y", s.position.y + 1.6, 1.4).set_delay(i * 0.15).set_trans(Tween.TRANS_SINE)
		t.tween_property(s, "modulate:a", 0.0, 0.6).set_delay(0.9 + i * 0.15)
		t.chain().tween_callback(s.queue_free)


func _make_heart_texture() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var u := (x - n * 0.5) / (n * 0.42)
			var v := -(y - n * 0.55) / (n * 0.42)
			var f := pow(u * u + v * v - 1.0, 3.0) - u * u * v * v * v
			if f <= 0.0:
				img.set_pixel(x, y, UI.PINK if f < -0.02 else UI.PINK.darkened(0.25))
	return ImageTexture.create_from_image(img)


func _on_island() -> void:
	if _island_announced:
		return
	_island_announced = true
	Sfx.play("coin")
	hud.big_message(L.t("island_reached"), 3.0)


func _confirm_leave() -> void:
	if _leaving:
		return
	var yes: bool = await UI.confirm(menu, L.t("leave_q"), L.t("leave_body"), L.t("leave_game"))
	if yes:
		_leave()


func _leave() -> void:
	_leaving = true
	net.close()
	# A Studio play test goes back to the editor.
	if not Session.test_marp.is_empty():
		Session.test_marp = {}
		UI.goto("res://scenes/studio.tscn")
		return
	UI.goto("res://scenes/main_menu.tscn")
