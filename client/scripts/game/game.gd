extends Node3D
## Playground session: world, local player, remote players and networking.

const SEND_HZ := 15.0

var world: Playground
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
var _island_announced := false


func _ready() -> void:
	# Android back button should open the menu, not kill the app.
	get_tree().quit_on_go_back = false
	get_tree().set_auto_accept_quit(false)
	world = Playground.new()
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
	world.bounced.connect(func(s): Sfx.play("boing", clampf(1.4 - s / 40.0, 0.8, 1.3)))
	world.reached_island.connect(_on_island)
	world.maze_solved.connect(func():
		Sfx.play("coin")
		hud.big_message(L.t("maze_solved"), 3.0))

	_my_bubble = GameBubble.make()
	player.add_child(_my_bubble)

	hud = GameHud.new()
	add_child(hud)
	hud.bind_player(player)
	hud.menu_requested.connect(_open_menu)
	hud.chat_submitted.connect(func(t): Net.send({"t": "chat", "m": t}))
	hud.emote_picked.connect(_emote)

	menu = GameMenu.new()
	menu.game = self
	add_child(menu)
	menu.reset_requested.connect(func(): player.die())
	menu.leave_requested.connect(_confirm_leave)
	menu.settings_changed.connect(_apply_quality)
	Session.settings_changed.connect(_on_settings_changed)
	_apply_quality()

	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	Net.message.connect(_on_message)
	hud.show_overlay(L.t("joining_playground"))
	Net.connect_to_game()


func _exit_tree() -> void:
	Net.close()
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
	match q:
		"low":
			vp.scaling_3d_scale = 0.6
			vp.msaa_3d = Viewport.MSAA_DISABLED
			player.camera.far = 140.0
			Engine.max_fps = 40
		"medium":
			vp.scaling_3d_scale = 0.8
			vp.msaa_3d = Viewport.MSAA_2X
			player.camera.far = 400.0
			Engine.max_fps = 60
		_:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			player.camera.far = 700.0
			Engine.max_fps = 60
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
	Net.send({"t": "join", "game": "playground", "server": Session.pending_server})


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
			Net.connect_to_game()
		return
	hud.show_overlay(reason, [
		[L.t("retry"), func():
			_retries = 0
			hud.show_overlay(L.t("connecting"))
			Net.connect_to_game()],
		[L.t("to_menu"), _leave, "ghost"],
	])


func _on_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"welcome":
			_on_welcome(m)
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
		"error":
			if str(m.get("code", "")) == "birthdate":
				_leaving = true
				Net.close()
				hud.show_overlay(L.t("birthdate_needed"), [[L.t("to_menu"), _leave]])
				return
			if not _joined:
				hud.show_overlay(str(m.get("m", "Error")), [
					[L.t("other_server"), func():
						Session.pending_server = "auto"
						hud.show_overlay(L.t("finding_server"))
						Net.send({"t": "join", "game": "playground", "server": "auto"})],
					[L.t("to_menu"), _leave, "ghost"],
				])
		"kicked":
			_leaving = true
			Net.close()
			match str(m.get("code", "")):
				"update":
					UI.show_update_required(str(m.get("m", "")), Api.BASE_URL + "/download")
				"banned":
					hud.show_overlay(L.t("kicked_banned"), [[L.t("to_menu"), _leave]])
				"kicked":
					hud.show_overlay(L.t("kicked_admin"), [[L.t("to_menu"), _leave]])
				"closed":
					hud.show_overlay(L.t("server_closed"), [[L.t("to_menu"), _leave]])
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
			Net.send(state)
			_last_sent = state
			_last_sent_at = now


func _process(delta: float) -> void:
	_ping_timer -= delta
	if _ping_timer <= 0.0 and _joined:
		_ping_timer = 3.0
		Net.send({"t": "ping", "c": Time.get_ticks_msec()})
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
		_spawn_heart(player)
		Net.send({"t": "emote", "e": "heart"})
		return
	player.play_emote(e)


func _on_died() -> void:
	Ragdoll.spawn(self, player.avatar.global_transform, player.avatar.get_colors(), player.velocity)
	Net.send({"t": "dead"})
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
	Sfx.play("coin", 1.3)


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
	Net.close()
	UI.goto("res://scenes/main_menu.tscn")
