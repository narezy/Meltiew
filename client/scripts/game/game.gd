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
## ProximityPrompts and "Hug" by players waiting for one (see PlacePrompts).
var prompts: PlacePrompts
var remotes := {}  # user id -> RemotePlayer
var voice: Voice
var _watching := 0  # whose character the place's camera follows (spectating)
var _watching_at := -100000
var users := {}  # user id -> public user dict (everyone incl. me)
var my_id := -1
var admin: AdminPanel
var _phys_claims := {}  # part id -> when we last asked to take it over
var _pending_phys_owners := {}
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
var _my_bubble: GameBubble
var _heart_tex: Texture2D
var _last_heart := -100000
const HEART_COOLDOWN_MS := 2500
var _island_announced := false
var _mouse_rest := Vector2.INF  # where the cursor waits while the camera turns


func _ready() -> void:
	# Android back button should open the menu, not kill the app.
	get_tree().quit_on_go_back = false
	get_tree().set_auto_accept_quit(false)
	_is_place = Session.pending_game != "playground"
	if not Session.test_melt.is_empty():
		net = LocalNet.new(Session.test_melt)
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
	# (No landing thud: it got on everyone's nerves.)
	player.hurt.connect(func(_amount): Sfx.play("hurt"))
	player.died.connect(_on_died)
	player.bumped.connect(func(body: Node):
		if place_host and place_host.scene:
			place_host.scene.claim_part(body))
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
		# Not in the world until the place spawns us (standing at the origin would shove parts there).
		player._collision.disabled = true

	_my_bubble = GameBubble.new()
	_my_bubble.avatar = player.avatar
	player.add_child(_my_bubble)

	hud = GameHud.new()
	add_child(hud)
	hud.leaderboard.game = self
	prompts = PlacePrompts.new()
	prompts.player = player
	prompts.typing = func() -> bool: return hud.chat_open() or get_viewport().gui_get_focus_owner() is LineEdit
	prompts.extra = _hug_prompts
	hud.add_child(prompts)
	hud.prompts = prompts
	hud.bind_player(player)
	hud.menu_requested.connect(_open_menu)
	hud.chat_submitted.connect(func(t: String):
		# ":a" opens the owner's admin panel instead of going to the chat.
		if t.strip_edges().to_lower() == ":a" and _is_owner():
			_toggle_admin()
			return
		net.send({"t": "chat", "m": t}))
	hud.admin_requested.connect(_toggle_admin)
	hud.emote_picked.connect(_emote)
	hud.tool_picked.connect(_pick_tool)
	hud.tool_used.connect(_use_tool)
	hud.tool_dropped.connect(_drop_tool)
	voice = Voice.new()
	voice.net = net
	voice.remotes = remotes
	add_child(voice)
	hud.mic_toggled.connect(voice.set_mic)
	voice.speaking_changed.connect(hud.set_speaking)

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
	# The place's cover, icon, name and author while it loads.
	_loading = LoadingScreen.new()
	add_child(_loading)
	hud.overlay_shown.connect(_finish_loading)
	var known: Dictionary = Session.get_meta("pending_place", {})
	if not Session.test_melt.is_empty():
		known = {"name": str(Session.test_melt.get("meta", {}).get("name", ""))}
	_loading.show_place(Session.pending_game if _is_place else "playground", L.t("loading_world"), known)
	Session.remove_meta("pending_place")
	net.connect_to_game()
	if VR.active:
		VR.attach(self)


func _exit_tree() -> void:
	if VR.active:
		VR.detach()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(null)
	net.close()
	if place_host:
		place_host.close()
	var vp := get_viewport()
	vp.scaling_3d_scale = 1.0
	Session.apply_fps(false)
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
	var mobile := Session.phone
	# The frame limit from the settings (phones default to 60).
	Session.apply_fps(true)
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
	_base_scale = vp.scaling_3d_scale
	_render_scale = _base_scale
	_shadow_dropped = false
	world.apply_quality(q)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()
	# The window's close button, Alt+F4, the window manager's "close" (Super+Q): the app
	# closes, like any other (Android's back gesture comes as GO_BACK above).
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_leaving = true
		net.close()
		get_tree().quit()
	# "Play" on the website while already in a game: go there instead.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		var launch := Launcher.take()
		if not launch.is_empty() and Session.test_melt.is_empty():
			_leaving = true
			net.close()
			Api.request("GET", "/api/launch")
			Session.pending_server = launch.server
			Session.pending_game = launch.game
			get_tree().reload_current_scene()


## Escape / the menu button: opens the menu, or closes it when it's already open.
func _open_menu() -> void:
	if menu.visible:
		menu.close()
		return
	hud.release_touches()
	menu.open()


# --- networking -------------------------------------------------------------

func _on_connected() -> void:
	_retries = 0
	net.send({"t": "join", "game": Session.pending_game, "server": Session.pending_server, "vr": VR.active})


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
					remotes[id].set_state(Vector3(s[1], s[2], s[3]), float(s[4]), str(s[5]), s[6] if s.size() > 6 else null, s[7] if s.size() > 7 else null)
		"join":
			_add_remote(m.player)
			Sfx.play("pop", 1.2)
			_refresh_players()
		"leave":
			_remove_remote(int(m.id))
			_refresh_players()
		"wallet":
			Economy.set_wallet(m.get("wallet", {}))
		"badge":
			hud.badge_popup(m.get("badge", {}))
		"look":
			var u: Dictionary = m.player
			users[int(u.id)] = u
			if remotes.has(int(u.id)):
				remotes[int(u.id)].user = u
				remotes[int(u.id)].refresh_look()
			elif int(u.id) == my_id:
				# A place's Appearance (or a profile change): only this game's Melly, not the saved avatar.
				player.avatar.apply_user(u)
			_refresh_players()
		"chat":
			var id := int(m.id)
			var is_me := id == my_id
			hud.add_chat(str(m.name), str(m.m), UI.ACCENT if is_me else UI.MINT, str(m.get("role", "")))
			if is_me:
				_my_bubble.show_text(str(m.m))
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
				"muted":
					hud.add_chat("", L.t("sys_muted"))
				"unmuted":
					hud.add_chat("", L.t("sys_unmuted"))
				"no_chat":
					hud.add_chat("", L.t("sys_no_chat"))
				"admin":
					hud.add_chat("Meltiew", str(m.get("m", "")), Color("#ffd166"))
					hud.big_message(str(m.get("m", "")), 3.5)
		"voice":
			voice.heard(int(m.get("id", 0)), str(m.get("d", "")), m.get("p"))
		"hug":
			# Someone took our open arms, or we took theirs: face to face, one hug.
			if m.has("pos"):
				var p: Array = m.pos
				player.global_position = Vector3(p[0], p[1], p[2])
				player.reset_physics_interpolation()
				player.velocity = Vector3.ZERO
				player.face(float(m.get("r", 0.0)))
			player.play_custom("hugging")
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
			if str(m.get("code", "")) == "device":
				# This build can't run place scripts (32-bit phones): nothing to retry.
				_leaving = true
				net.close()
				hud.show_overlay(str(m.get("m", "")), [[L.t("to_menu"), _leave]])
				return
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
		"teleport":
			_teleport(m)
		"vh":
			_on_vehicles(m.get("v", []))
		"kicked":
			_leaving = true
			net.close()
			match str(m.get("code", "")):
				"update":
					# Only games need the new version: offer it, but let them go back (Studio keeps working).
					var msg := str(m.get("m", ""))
					hud.show_overlay(msg if msg != "" else L.t("update_body"), [
						[L.t("update_button"), func(): OS.shell_open(Api.BASE_URL + "/download")],
						[L.t("to_menu"), _leave, "ghost"],
					])
				"banned":
					hud.show_overlay(L.t("kicked_banned"), [[L.t("to_menu"), _leave]])
				"kicked":
					hud.show_overlay(L.t("kicked_admin"), [[L.t("to_menu"), _leave]])
				"closed":
					hud.show_overlay(L.t("server_closed"), [[L.t("to_menu"), _leave]])
				"place":
					# Kicked by the place's own script (player:Kick("...")), with its reason.
					_show_kick(str(m.get("m", "")))
				_:
					hud.show_overlay(L.t("err_duplicate"), [[L.t("to_menu"), _leave]])
		"rejoin":
			# The place was updated: everyone here moves to a server running the new version.
			if not Session.test_melt.is_empty():
				return
			_leaving = true
			hud.show_overlay(str(m.get("m", "")) if str(m.get("m", "")) != "" else L.t("place_updated"))
			await get_tree().create_timer(1.2).timeout
			net.close()
			Session.pending_server = str(m.get("server", "auto"))
			get_tree().reload_current_scene()
		"phys":
			if place_host and place_host.scene:
				place_host.scene.phys_update(m.get("u", []))
		"phys_own":
			if place_host and place_host.scene:
				place_host.scene.set_phys_owners(m.get("o", {}))
			else:
				_pending_phys_owners.merge(m.get("o", {}), true)
		"admin":
			if admin:
				admin.on_result(m)
		"admin_kill":
			player.die()
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
	# A moment for the world to draw its first frames, then the loading screen goes.
	get_tree().create_timer(0.4).timeout.connect(_finish_loading)
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
	place_host.send.connect(func(msg: Dictionary):
		# Shots, hits, tool uses: say where you are right now, so the server checks them
		# from there and not from where it last heard of you (a sprint's worth behind).
		if msg.get("t") in ["remote", "invoke", "tool", "prompt"]:
			var at := player.global_position
			msg["p"] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
		net.send(msg))
	place_host.output.connect(_on_output)
	place_host.spawn_requested.connect(func(pos: Vector3):
		player.set_physics_process(true)
		player.respawn_at(pos))
	place_host.glide_requested.connect(func(pos: Vector3, seconds: float):
		player.glide_to(pos, seconds))
	place_host.teleport_requested.connect(func(pos: Vector3):
		player.global_position = pos
		player.reset_physics_interpolation()
		player.velocity = Vector3.ZERO)
	place_host.mouse_settings_changed.connect(_apply_cursor)
	place_host.camera_control.connect(_camera_control)
	hud.drag_handler = _touch_drag
	place_host.velocity_requested.connect(func(v: Vector3):
		if not player.dead and not player.seated:
			player.velocity = v)
	place_host.sit_requested.connect(func(id: String):
		# No seat: the server says get up (someone else sat there first).
		if id == "" and player.seated:
			player.stand_up()
			return
		if place_host.tree.has(id) and not player.dead:
			if player.seated:
				player.stand_up()
			_sit(id))
	player.climb_check = func(collider: Object) -> bool:
		var id := PlaceScene.id_of(collider)
		return id != "" and place_host.tree.has(id) and place_host.tree.prop(id, "Climbable") == true
	place_host.animation_requested.connect(func(anim: String): player.play_custom(anim))
	place_host.core_gui_changed.connect(func(k, on): hud.set_core_gui(k, on))
	place_host.kicked.connect(func(reason: String):
		_leaving = true
		net.close()
		_show_kick(reason))
	place_host.actions_changed.connect(func(): hud.set_actions(place_host.action_buttons, place_host.action_touch))
	hud.is_bound = func(k: String) -> bool: return place_host != null and place_host.is_bound(k)
	Controls.device_changed.connect(func(_d): if place_host: place_host.device_changed())
	Input.joy_connection_changed.connect(func(_id, _on): if place_host: place_host.device_changed())
	place_host.passes = p.get("passes", [])
	place_host.pass_info = p.get("pass_info", [])
	place_host.badges = p.get("badges", [])
	place_host.badge_info = p.get("badge_info", [])
	# Gamepasses belong to the game (its main place), in every sub-place.
	var place_id := str(p.get("game_id", p.get("id", "")))
	place_host.place_info = {"id": str(p.get("id", "")), "game_id": place_id, "join": p.get("join")}
	place_host.pass_prompt.connect(func(pass_id: int):
		hud.release_touches()
		var bought: bool = await Economy.gamepass_prompt(self, place_id, pass_id)
		if place_host:
			place_host.pass_result(pass_id, bought))
	if not place_host.start(my_id, L.lang, p.get("strings", {}), p.get("snapshot", []), world):
		hud.add_chat("", L.t("place_unsupported"))
	place_host.scene.avatar_of = _avatar_of_character
	# The place's ProximityPrompts join the prompts shown by the HUD.
	prompts.host = place_host
	# Physics parts: report the ones this app simulates, ask for the ones we bump into.
	place_host.scene.phys_report.connect(func(u: Array): net.send({"t": "phys", "u": u}))
	place_host.scene.phys_claim.connect(func(id: String):
		var now := Time.get_ticks_msec()
		if now - int(_phys_claims.get(id, 0)) > 400:
			_phys_claims[id] = now
			net.send({"t": "phys_claim", "id": id}))
	if not _pending_phys_owners.is_empty():
		place_host.scene.set_phys_owners(_pending_phys_owners)
		_pending_phys_owners = {}
	place_host.scene.apply_quality(str(Session.settings.quality))
	world.set_scene(place_host.scene)


func _on_output(line: Dictionary) -> void:
	console_lines.append(line)
	# A Studio play test hands its output back to the editor.
	if not Session.test_melt.is_empty():
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
		player.step_height = float(t.prop(hum, "StepHeight"))
		player.step_speed = float(t.prop(hum, "StepSpeed"))
		player.can_jump = t.prop(hum, "CanJump")
		player.can_sprint = t.prop(hum, "CanSprint") != false
		player.max_stamina = float(t.prop(hum, "MaxStamina"))
		player.stamina_drain = float(t.prop(hum, "StaminaDrain"))
		player.stamina_regen = float(t.prop(hum, "StaminaRegen"))
		player.traction = float(t.prop(hum, "Traction"))
		player.bhop = t.prop(hum, "Bhop") == true
		player.bhop_max = float(t.prop(hum, "BhopMaxSpeed"))
		player.floating = t.prop(hum, "Floating") == true
		var hp := float(t.prop(hum, "Health"))
		var mx := float(t.prop(hum, "MaxHealth"))
		if not is_equal_approx(hp, player.hp) or not is_equal_approx(mx, player.max_hp):
			player.set_server_health(hp, mx)
	player.gravity = float(h.workspace_prop("Gravity"))
	player.void_height = float(h.workspace_prop("FallHeight"))
	player.set_camera_rules(str(h.player_prop("CameraMode")), float(h.player_prop("CameraMinZoom")), float(h.player_prop("CameraMaxZoom")))
	hud.set_view_toggle(player.can_toggle_view())
	_sync_emote_overrides()
	_sync_joints()
	_check_seats()
	_step_vehicles(delta)
	_move_drag(delta)
	_sync_tools()
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
	# In VR the mouse is the laser on the panel: missing a button isn't a click in the world.
	if VR.active and event is InputEventMouse:
		return
	# Gamepad buttons for the place's scripts (the sticks and triggers: _send_pad_axes).
	if event is InputEventJoypadButton:
		var key := Controls.pad_button_name(event.button_index)
		if key != "":
			place_host.pad_event(key, event.pressed)
		return
	if event is InputEventKey and not event.echo:
		if event.pressed and event.keycode == KEY_F9:
			_console_in_chat = not _console_in_chat
			hud.add_chat("", L.t("console") + (": on" if _console_in_chat else ": off"))
			return
		if event.pressed and event.keycode == KEY_BACKSPACE and not hud.chat_open():
			_drop_tool()
		place_host.key_event(OS.get_keycode_string(event.keycode), event.pressed)
	if event is InputEventMouseButton:
		var touch := DisplayServer.is_touchscreen_available()
		var at := _pointer_pos(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				place_host.pointer_event("MouseWheel", event.button_index == MOUSE_BUTTON_WHEEL_UP, at)
			return
		var kind := "MouseButton1" if event.button_index == MOUSE_BUTTON_LEFT else ("MouseButton2" if event.button_index == MOUSE_BUTTON_RIGHT else "")
		if kind == "":
			return
		if touch and not hud.tap_allowed(event.position):
			return
		_update_mouse(at)
		if touch:
			# Phones: a quick tap is a click (a drag turns the camera instead).
			if event.pressed:
				_press_pos = event.position
			elif event.position.distance_to(_press_pos) < 12.0:
				place_host.pointer_event("Touch", true, at)
				place_host.pointer_event("Touch", false, at)
				_use_tool(true)
				_use_tool(false)
				_click_at(at)
			return
		place_host.pointer_event(kind, event.pressed, at)
		if kind == "MouseButton1":
			# A part with a DragDetector under the mouse: picked up.
			if event.pressed:
				var cam := player.camera
				_drag.try_start(cam.project_ray_origin(at), cam.project_ray_normal(at))
			else:
				_drag.end()
			_use_tool(event.pressed)
			# A click (not a drag) on a part with a ClickDetector.
			if event.pressed:
				_press_pos = event.position
			elif event.position.distance_to(_press_pos) < 12.0:
				_click_at(at)


var _drag := PartDrag.new()
var _drag_finger := Vector2.INF  # where the finger dragging a part is (phones)


## Phones: a finger that comes down on a draggable part drags it (not the camera).
func _touch_drag(phase: String, pos: Vector2) -> bool:
	var cam := player.camera
	match phase:
		"start":
			if _drag.try_start(cam.project_ray_origin(pos), cam.project_ray_normal(pos)):
				_drag_finger = pos
				return true
			return false
		"move":
			_drag_finger = pos
		"end":
			_drag.end()
			_drag_finger = Vector2.INF
	return true


## Every frame while dragging a part: it follows the mouse or the finger.
func _move_drag(delta: float) -> void:
	if not _drag.active() or VR.active:
		return
	var at := _drag_finger if _drag_finger != Vector2.INF else _pointer_pos(get_viewport().get_mouse_position())
	var cam := player.camera
	_drag.move(cam.project_ray_origin(at), cam.project_ray_normal(at), delta)


func _click_at(screen: Vector2) -> void:
	var cam := player.camera
	_click_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


## VR: a controller pointed into the world is the mouse there (Mouse.Hit / Target for
## scripts). Returns where it hits (or null), for drawing the laser.
## VR: the pointing hand is the mouse in the world. {at: where it meets the world, click:
## whether there's something there to click (a ClickDetector in reach, or a tool in your
## hand)}, or null when it points at nothing.
func vr_point(from: Vector3, dir: Vector3) -> Variant:
	if place_host == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, PlaceScene.LAYER_WORLD | PlaceScene.LAYER_GHOST)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# Dragging a part with the laser: it follows the hand.
	if _drag.active():
		_drag.move(from, dir, 0.05)
	var at: Vector3 = hit.position if not hit.is_empty() else from + dir * 500.0
	var part := PlaceScene.id_of(hit.collider) if not hit.is_empty() else ""
	place_host.mouse_state(get_viewport().get_visible_rect().size / 2.0, from, dir, at, part)
	if hit.is_empty():
		return null
	var det := place_host.tree.child_of_class(part, "ClickDetector") if part != "" else ""
	var click := place_host.equipped_tool() != "" \
		or (det != "" and at.distance_to(player.global_position) <= float(place_host.tree.prop(det, "MaxDistance")) + 2.0)
	return {"at": at, "click": click}


## VR: the trigger pointed into the world: a mouse click there (scripts, tools, ClickDetectors).
func vr_click(down: bool, from: Vector3, dir: Vector3) -> void:
	if place_host == null:
		_use_tool(down)
		return
	vr_point(from, dir)
	if down:
		_drag.try_start(from, dir)
	else:
		_drag.end()
	place_host.pointer_event("MouseButton1", down, get_viewport().get_visible_rect().size / 2.0)
	_use_tool(down)
	if not down:
		_click_ray(from, dir)


func _click_ray(from: Vector3, dir: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0, PlaceScene.LAYER_WORLD | PlaceScene.LAYER_GHOST)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var part := PlaceScene.id_of(hit.collider)
	var det := place_host.tree.child_of_class(part, "ClickDetector") if part != "" else ""
	if det != "" and hit.position.distance_to(player.global_position) <= float(place_host.tree.prop(det, "MaxDistance")) + 2.0:
		net.send({"t": "click", "id": det})
		Sfx.click()


# --- tools, pointer and camera for studio places ------------------------------------

var _tools_sig := ""
var _tool_down := ""
var _mouse_timer := 0.0
var _cam_timer := 0.0
var _cursor_tex: Texture2D


## The Melly drawn for a character Model (so held tools find her hand).
func _avatar_of_character(model: String) -> MellyAvatar:
	var uid := place_host.user_of_character(model)
	if uid == my_id:
		return player.avatar if not player.dead else null
	var r: RemotePlayer = remotes.get(uid)
	return r.avatar if r and r.avatar.visible else null


func _sync_tools() -> void:
	var h := place_host
	var list: Array = []
	for id in h.tools():
		list.append({"id": id, "name": h.tree.name_of(id), "icon": str(h.tree.prop(id, "TextureId")), "tip": str(h.tree.prop(id, "ToolTip"))})
	var held := h.equipped_tool()
	var sig := JSON.stringify([list, held])
	if sig != _tools_sig:
		_tools_sig = sig
		hud.set_tools(list, held)


func _pick_tool(id: String) -> void:
	if player.dead:
		return
	Sfx.click()
	place_host.tool_event(id, "unequip" if id == place_host.equipped_tool() else "equip")


func _use_tool(down: bool) -> void:
	var held := place_host.equipped_tool()
	if down and held != "" and not player.dead:
		_tool_down = held
		place_host.tool_event(held, "activate")
	elif not down and _tool_down != "":
		place_host.tool_event(_tool_down, "deactivate")
		_tool_down = ""


func _drop_tool() -> void:
	var held := place_host.equipped_tool()
	if held != "" and place_host.tree.prop(held, "CanBeDropped"):
		var front := player.global_position + Basis(Vector3.UP, player.avatar.rotation.y) * Vector3(0, 1.0, -2.5)
		place_host.tool_event(held, "drop", {"p": SValue.encode(front)})


## Screen point the scripts see: the middle of the screen while the mouse is locked
## (where it rests while the right button turns the camera).
func _pointer_pos(p: Vector2) -> Vector2:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and hud.mouse_look() and not player.first_person and _mouse_rest != Vector2.INF:
		return _mouse_rest
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return get_viewport().get_visible_rect().size / 2.0
	return p


## Mouse.Hit / Mouse.Target: what's under the pointer.
func _update_mouse(screen: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, PlaceScene.LAYER_WORLD | PlaceScene.LAYER_GHOST)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else from + dir * 500.0
	var target := PlaceScene.id_of(hit.collider) if not hit.is_empty() else ""
	place_host.mouse_state(screen, from, dir, at, target)


## Every frame: pointer and camera for scripts, the script camera, mouse lock.
func _tick_place(delta: float) -> void:
	var h := place_host
	_mouse_timer -= delta
	if _mouse_timer <= 0.0 and not VR.active:  # (in VR the controller is the mouse: vr_point)
		_mouse_timer = 0.05
		_update_mouse(_pointer_pos(get_viewport().get_mouse_position()))
	var cam_id := h.camera()
	var cam := player.camera
	if cam_id != "":
		cam.fov = float(h.tree.prop(cam_id, "FieldOfView"))
		var want: Variant = _script_camera(cam_id)
		if want is Transform3D:
			# Smoothing (seconds): glide towards where the script wants the camera.
			var smooth := float(h.tree.prop(cam_id, "Smoothing"))
			if smooth > 0.0 and player.scripted_camera is Transform3D:
				want = (player.scripted_camera as Transform3D).interpolate_with(want, 1.0 - exp(-delta / smooth))
			player.scripted_camera = want
		else:
			player.scripted_camera = null
		_cam_timer -= delta
		if _cam_timer <= 0.0:
			_cam_timer = 0.05
			var look := -cam.global_basis.z
			h.camera_state(cam.global_position, player.global_position + Vector3(0, 1.5, 0) if player.scripted_camera == null else h.tree.prop(cam_id, "Focus"), look)
	_apply_mouse_mode()


## Where a script's camera goes this frame, or null for the game's own camera.
## Scriptable: Position → Focus. Watch: Position → the subject. Track: the subject
## plus CameraOffset. Follow: like Track, with the offset turning with the subject.
func _script_camera(cam_id: String) -> Variant:
	var h := place_host
	var kind := str(h.tree.prop(cam_id, "CameraType"))
	var pos: Vector3
	var focus: Vector3
	match kind:
		"Scriptable":
			pos = h.tree.prop(cam_id, "Position")
			focus = h.tree.prop(cam_id, "Focus")
		"Watch", "Track", "Follow":
			var subj := _camera_subject(cam_id)
			focus = subj[0]
			var offset: Vector3 = h.tree.prop(cam_id, "CameraOffset")
			match kind:
				"Watch":
					pos = h.tree.prop(cam_id, "Position")
				"Track":
					pos = focus + offset
				_:
					pos = focus + Basis(Vector3.UP, float(subj[1])) * offset
		_:
			return null
	var t := Transform3D(Basis(), pos)
	if not pos.is_equal_approx(focus):
		t = t.looking_at(focus, Vector3.UP if absf((focus - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	var roll := float(h.tree.prop(cam_id, "Roll"))
	if roll != 0.0:
		t.basis = t.basis.rotated(t.basis.z, deg_to_rad(roll))
	return t


## Camera.CameraSubject: [where it is, which way it faces (radians)]. Empty or your
## own character: you. A Humanoid means its character; a Model, its root part.
func _camera_subject(cam_id: String) -> Array:
	var h := place_host
	var ref: Variant = h.tree.prop(cam_id, "CameraSubject")
	var id := str(ref["$i"]) if ref is Dictionary and ref.has("$i") else ""
	if id != "" and h.tree.has(id) and h.tree.cls(id) == "Humanoid":
		id = h.tree.parent_of(id)
	if id == "" or not h.tree.has(id) or id == h.character():
		return [player.get_global_transform_interpolated().origin + Vector3(0, 1.5, 0), player.avatar.rotation.y]
	# Someone else's character: where they're drawn. Their parts in the place's tree
	# stay where they spawned (positions come on their own, not as replication), so
	# following those left spectator cameras staring at the lobby.
	var uid := h.user_of_character(id)
	if uid != 0:
		_watching = uid
		_watching_at = Time.get_ticks_msec()
	if uid != 0 and remotes.has(uid):
		var rp: RemotePlayer = remotes[uid]
		return [rp.get_global_transform_interpolated().origin + Vector3(0, 1.5, 0), rp.avatar.rotation.y]
	var part := id
	if not h.tree.is_a(id, "BasePart"):
		part = ""
		var root := h.tree.child_named(id, "HumanoidRootPart")
		if root != "":
			part = root
		else:
			for d in h.tree.descendants(id):
				if h.tree.is_a(d, "BasePart"):
					part = d
					break
	if part == "":
		return [player.global_position, 0.0]
	var p: Variant = h.tree.prop(part, "Position")
	var r: Variant = h.tree.prop(part, "Rotation")
	return [p if p is Vector3 else Vector3.ZERO, deg_to_rad((r as Vector3).y) if r is Vector3 else 0.0]


## Camera:SetZoom / SetRotation / Shake from a LocalScript.
func _camera_control(op: Dictionary) -> void:
	match str(op.get("k", "")):
		"zoom":
			player.set_zoom(float(op.get("v", 8.0)))
		"rot":
			player.cam_yaw = -deg_to_rad(float(op.get("yaw", 0.0)))
			player.cam_pitch = deg_to_rad(float(op.get("pitch", -15.0)))
		"shake":
			player.shake(float(op.get("v", 1.0)), float(op.get("t", 0.4)))


## The mouse is held in place (hidden or as a crosshair) while the camera turns:
## in first person, while the right button is down, and when a place asks for
## LockCenter. Menus, the chat and the inventory give it back.
func _apply_mouse_mode() -> void:
	if DisplayServer.is_touchscreen_available():
		return
	var ms: Dictionary = place_host.mouse_settings if place_host else {"enabled": true, "behavior": "Default"}
	var orbit := hud.mouse_look()
	var lock: bool = ms.behavior != "Default" or player.first_person or orbit or player.shift_locked
	var busy := menu.visible or (admin != null and admin.visible) or hud.chat_open() or hud.inventory_open() or not get_window().has_focus() or not _joined
	var want := Input.MOUSE_MODE_VISIBLE
	if lock and not busy:
		want = Input.MOUSE_MODE_CAPTURED
	elif not ms.enabled and not busy:
		want = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		if want == Input.MOUSE_MODE_CAPTURED and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_mouse_rest = get_viewport().get_mouse_position()
		var was_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = want
		if was_captured and _mouse_rest != Vector2.INF:
			# Back where it was before the camera turn, not in the middle of the screen.
			get_viewport().warp_mouse(_mouse_rest)
		if want != Input.MOUSE_MODE_CAPTURED:
			_mouse_rest = Vector2.INF
	# A crosshair in the middle when aiming (first person, LockCenter); nothing while orbiting.
	hud.set_crosshair(_cursor_tex, want == Input.MOUSE_MODE_CAPTURED and ms.enabled and not (orbit and not player.first_person and not player.shift_locked and ms.behavior == "Default"))


## UserInputService.MouseIcon: any uploaded image as the cursor.
func _apply_cursor() -> void:
	var ref := str(place_host.mouse_settings.icon)
	if ref == "":
		_cursor_tex = null
		Input.set_custom_mouse_cursor(null)
		return
	AssetCache.fetch(ref, func(tex: Texture2D):
		if tex == null or str(place_host.mouse_settings.icon) != ref:
			return
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var side := maxi(img.get_width(), img.get_height())
		if side > 64:
			img.resize(maxi(1, img.get_width() * 64 / side), maxi(1, img.get_height() * 64 / side), Image.INTERPOLATE_BILINEAR)
		var small := ImageTexture.create_from_image(img)
		_cursor_tex = small
		Input.set_custom_mouse_cursor(small, Input.CURSOR_ARROW, Vector2(img.get_width(), img.get_height()) / 2.0))


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
	if voice:
		voice.forget(id)


func _is_owner() -> bool:
	return str(Session.user.get("role", "")) == "owner"


## The owner's admin panel (made on first use).
func _toggle_admin() -> void:
	if not _is_owner():
		return
	if admin == null:
		admin = AdminPanel.new()
		admin.game = self
		admin.visible = false
		add_child(admin)
	hud.release_touches()
	admin.toggle()


func _refresh_players() -> void:
	if admin:
		admin.refresh()
	hud.set_server(L.field(server_info, "name"), users.size(), int(server_info.get("max_players", 10)))


func _physics_process(delta: float) -> void:
	if not _joined:
		return
	if place_host:
		_sync_place(delta)
		_tick_place(delta)
	else:
		_apply_mouse_mode()
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
		# Spectating someone: the server's anti-wallhack then also looks from their camera.
		if Time.get_ticks_msec() - _watching_at < 500:
			state["w"] = _watching
		# In VR: where the hands are (avatar space), for others' view of your arms.
		if VR.active:
			var hands := []
			for side in ["left", "right"]:
				var h: Variant = VR.hand_in(player.avatar, side)
				hands.append_array([snappedf(h.x, 0.01), snappedf(h.y, 0.01), snappedf(h.z, 0.01)] if h is Vector3 else [null, null, null])
			state["h"] = hands
			# And how the head is turned, for everyone to see.
			var hd: Variant = VR.head_turn(player.avatar)
			if hd is Vector3:
				state["hd"] = [roundi(hd.x), roundi(hd.y), roundi(hd.z)]
		# Resend at least once a second so late joiners and interpolation stay fresh.
		var now := Time.get_ticks_msec()
		if state != _last_sent or now - _last_sent_at > 1000:
			net.send(state)
			_last_sent = state
			_last_sent_at = now


func _process(delta: float) -> void:
	# The scripts' view of the local character this frame (and the headset and hands).
	if place_host and _joined:
		var f := player.global_position
		var v := player.velocity
		var me := {"p": [f.x, f.y + 0.9, f.z], "v": [v.x, v.y, v.z]}
		if VR.active:
			me["vr"] = VR.user_poses(f)
		# Everyone else as this app shows them (their HumanoidRootPart.Position here).
		var others := {}
		for uid in remotes:
			var at: Vector3 = (remotes[uid] as Node3D).global_position
			others[str(uid)] = [snappedf(at.x, 0.01), snappedf(at.y + 0.9, 0.01), snappedf(at.z, 0.01)]
		place_host.step_info = {"me": me, "others": others}
	_ping_timer -= delta
	if _ping_timer <= 0.0 and _joined:
		_ping_timer = 3.0
		net.send({"t": "ping", "c": Time.get_ticks_msec()})
	_frame_ms += delta * 1000.0
	_frame_n += 1
	if place_host and not Input.get_connected_joypads().is_empty():
		_send_pad_axes()
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.5
		_measure_frames()


func _show_kick(reason: String) -> void:
	hud.show_overlay(L.t("kicked_place", [reason]) if reason != "" else L.t("kicked_place_plain"), [[L.t("to_menu"), _leave]])


## Back (the phone's gesture, B, a remote's Back): the menu opens or closes.
func go_back() -> void:
	if menu and menu.visible:
		menu.close()
	else:
		_open_menu()


# --- gamepad sticks and triggers for scripts -------------------------------------

var _pad_axes := {}  # key -> last Vector3 sent
var _triggers := {}  # "ButtonL2" / "ButtonR2" -> held


## The sticks (Thumbstick1/2, Y up) and triggers (ButtonL2/R2: Z, and a press past half)
## when they move, for UserInputService.InputChanged and ContextActionService.
func _send_pad_axes() -> void:
	var dev: int = Input.get_connected_joypads()[0]
	var now := {
		"Thumbstick1": Vector3(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), -Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y), 0),
		"Thumbstick2": Vector3(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y), 0),
		"ButtonL2": Vector3(0, 0, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)),
		"ButtonR2": Vector3(0, 0, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)),
	}
	for key in now:
		var v: Vector3 = now[key]
		if v.length() < 0.12:
			v = Vector3.ZERO
		var last: Vector3 = _pad_axes.get(key, Vector3.ZERO)
		if v.distance_to(last) > 0.03 or (v == Vector3.ZERO and last != Vector3.ZERO):
			_pad_axes[key] = v
			place_host.pad_axis(key, v)
		if key.begins_with("Button"):
			var held := v.z > 0.5
			if held != bool(_triggers.get(key, false)):
				_triggers[key] = held
				place_host.pad_event(key, held)


# --- frame time and resolution -------------------------------------------------

var _frame_ms := 0.0
var _frame_n := 0
var _measuring := false
var _render_scale := 1.0  # the 3D resolution now (phones lower it when the GPU can't keep up)
var _base_scale := 1.0  # the quality setting's resolution
var _gpu_heavy := 0
var _shadow_dropped := false
var _gpu_light := 0


## Twice a second: the numbers under the FPS counter, and on phones, the 3D resolution.
## When the GPU can't draw 60 frames a second, the world is drawn a bit smaller (down to
## 60%) and stretched; the interface stays sharp. It goes back up when there's room.
func _measure_frames() -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	var phone := Session.phone
	var want := bool(Session.settings.show_fps) or phone
	if want != _measuring:
		_measuring = want
		RenderingServer.viewport_set_measure_render_time(vp_rid, want)
	var frame := _frame_ms / maxf(1.0, _frame_n)
	_frame_ms = 0.0
	_frame_n = 0
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid) if _measuring else 0.0
	if phone and gpu > 0.0:
		var target := 60.0 if Engine.max_fps <= 0 else minf(60.0, float(Engine.max_fps))
		var budget := 1000.0 / target
		_gpu_heavy = _gpu_heavy + 1 if gpu > budget * 0.9 else 0
		_gpu_light = _gpu_light + 1 if gpu < budget * 0.55 else 0
		var next := _render_scale
		if _gpu_heavy >= 3:
			# At the lowest resolution already: the sun's shadow goes (it's drawn apart).
			if _render_scale <= 0.61 and not _shadow_dropped and world.has_method("drop_sun_shadow"):
				_shadow_dropped = true
				world.drop_sun_shadow()
			next = maxf(0.6, _render_scale - 0.1)
			_gpu_heavy = 0
		elif _gpu_light >= 6 and _render_scale < _base_scale:
			next = minf(_base_scale, _render_scale + 0.05)
			_gpu_light = 0
		if not is_equal_approx(next, _render_scale):
			_render_scale = next
			get_viewport().scaling_3d_scale = next
	var detail := ""
	if bool(Session.settings.show_fps):
		detail = L.t("stats_detail", ["%.1f" % frame, "%.1f" % gpu if gpu > 0.0 else "—", roundi(_render_scale * 100.0),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	hud.set_stats(int(Engine.get_frames_per_second()), _ping_ms, detail)


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
	if e.begins_with("anim://"):
		player.play_custom(e)
		return
	player.play_emote(e)


var _emote_sig := ""
var _seat_id := ""
## The seat just jumped off: not sat on again until you've stopped touching it.
var _seat_left := ""


## Touching a Seat sits you on it (jump gets you up); the server learns who sits where.
func _check_seats() -> void:
	if _seat_id != "" and not player.seated:
		_seat_left = _seat_id
		_seat_id = ""
		net.send({"t": "seat"})
		# Out of the driver's seat: the car rolls on to a stop by itself.
		if is_instance_valid(_drive):
			_drive.let_go()
	if player.seated:
		return
	var t := place_host.tree
	var touching_left := false
	for i in player.get_slide_collision_count():
		var id := PlaceScene.id_of(player.get_slide_collision(i).get_collider())
		if id == _seat_left:
			touching_left = true
			continue
		if id != "" and player.can_sit() and t.is_a(id, "Seat") and t.prop(id, "Disabled") != true and not _seat_taken(id):
			_sit(id)
			return
	if not touching_left and player.is_on_floor():
		_seat_left = ""


## Someone else is already sitting there (one per seat).
func _seat_taken(id: String) -> bool:
	var occ: Variant = place_host.tree.prop(id, "Occupant")
	if not (occ is Dictionary and occ.has("$i")):
		return false
	var hum := str(occ["$i"])
	return hum != place_host.local_humanoid() and place_host.tree.has(hum)


func _sit(id: String) -> void:
	var top := _seat_top(id)
	player.sit_on(top.origin, top.basis)
	_seat_id = id
	_seat_yaw = INF
	net.send({"t": "seat", "id": id})
	# The driver's seat: this app drives the vehicle now.
	if place_host.tree.cls(id) == "VehicleSeat":
		if is_instance_valid(_drive):
			_drive.queue_free()
		_vehicle_views.erase(id)
		_drive = VehicleDrive.new()
		_drive.player = player
		_drive.setup(place_host.scene, id)
		_drive.report.connect(func(m: Dictionary): net.send(m))
		add_child(_drive)


## Where you sit on a seat: its top, looking out of its front (-Z); where the seat is
## drawn right now (a moving vehicle), else where the tree has it.
func _seat_top(id: String) -> Transform3D:
	var t := place_host.tree
	var size: Vector3 = t.prop(id, "Size")
	var body := place_host.scene.body_of(id)
	var xf := body.global_transform if body else place_host.scene.part_transform(id)
	var b := xf.basis.orthonormalized()
	return Transform3D(Basis(-b.x, b.y, -b.z), xf.origin + b.y * size.y * 0.5)


# --- vehicles ------------------------------------------------------------------------

var _drive: VehicleDrive  # the vehicle this app drives (or lets roll to a stop)
var _vehicle_views := {}  # VehicleSeat id -> { vehicle: Vehicle, snaps: [[ms, pos, deg, speed, steer]] }
var _seat_yaw := INF


## Someone else drives: their reports, 20 a second.
func _on_vehicles(list: Array) -> void:
	if place_host == null:
		return
	var now := Time.get_ticks_msec()
	for u in list:
		if not (u is Array) or u.size() < 9:
			continue
		var id := str(u[0])
		if is_instance_valid(_drive) and _drive.seat == id or not place_host.tree.has(id):
			continue
		if not _vehicle_views.has(id):
			var v := Vehicle.new()
			v.setup(place_host.scene, id)
			add_child(v)
			_vehicle_views[id] = {"vehicle": v, "snaps": []}
		var snaps: Array = _vehicle_views[id].snaps
		snaps.append([now, Vector3(float(u[1]), float(u[2]), float(u[3])), Vector3(float(u[4]), float(u[5]), float(u[6])), float(u[7]), float(u[8])])
		while snaps.size() > 30:
			snaps.pop_front()


## Every physics step: other people's vehicles glide between their reports; whoever sits
## in a moving vehicle rides along (you, and others as this app shows them).
func _step_vehicles(delta: float) -> void:
	var render_t := Time.get_ticks_msec() - RemotePlayer.DELAY_MS
	for id in _vehicle_views.keys():
		var e: Dictionary = _vehicle_views[id]
		var v: Vehicle = e.vehicle
		if not place_host.tree.has(id):
			v.queue_free()
			_vehicle_views.erase(id)
			continue
		var snaps: Array = e.snaps
		while snaps.size() >= 2 and snaps[1][0] <= render_t:
			snaps.pop_front()
		if snaps.is_empty():
			continue
		var a: Array = snaps[0]
		var pos: Vector3 = a[1]
		var rot := Vehicle.basis_of(a[2])
		var sp: float = a[3]
		var st: float = a[4]
		if snaps.size() >= 2 and render_t > a[0]:
			var b: Array = snaps[1]
			var k := clampf((render_t - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0)
			pos = pos.lerp(b[1], k)
			rot = Basis(Quaternion(rot.orthonormalized()).slerp(Quaternion(Vehicle.basis_of(b[2]).orthonormalized()), k))
			sp = lerpf(sp, b[3], k)
			st = lerpf(st, b[4], k)
		elif snaps.size() == 1 and render_t - a[0] > 1500:
			continue  # it stopped: stays where it is
		v.place(Transform3D(rot, pos), sp, st, delta)
	# Riders: the seats of every moving vehicle carry whoever sits in them.
	for r in remotes.values():
		(r as RemotePlayer).pinned = null
	var moving: Array = _vehicle_views.values().map(func(e): return e.vehicle)
	if is_instance_valid(_drive):
		moving.append(_drive)
	for v: Vehicle in moving:
		for id in v.parts:
			if not place_host.tree.is_a(id, "Seat"):
				continue
			var uid := _occupant_user(id)
			if uid != 0 and uid != my_id and remotes.has(uid):
				var top := _seat_top(id)
				(remotes[uid] as RemotePlayer).pinned = Transform3D(top.basis, top.origin - top.basis.y * 0.17)
	if player.seated and _seat_id != "" and place_host.tree.has(_seat_id):
		var top := _seat_top(_seat_id)
		player.sit_follow(top.origin, top.basis)
		# The camera turns with the car.
		var f := -top.basis.z
		var yaw := atan2(f.x, f.z)
		if _seat_yaw != INF:
			var turn := angle_difference(_seat_yaw, yaw)
			if absf(turn) > 0.0001:
				player.cam_yaw += turn
				if VR.active:
					VR._turn(turn)
		_seat_yaw = yaw
	# The speedometer while you drive (VehicleSeat.HeadsUpDisplay).
	var shown: bool = is_instance_valid(_drive) and _drive.driving and place_host.tree.prop(_drive.seat, "HeadsUpDisplay") != false
	hud.set_speed(roundi(absf(_drive.speed) * 3.6) if shown else -1)


## The player sitting on a seat (from its Occupant, a character's Humanoid), or 0.
func _occupant_user(seat: String) -> int:
	var t := place_host.tree
	var occ: Variant = t.prop(seat, "Occupant")
	if not (occ is Dictionary and occ.has("$i")):
		return 0
	var model := t.parent_of(str(occ["$i"]))
	for k in t.kids(t.service("Players")):
		var ch: Variant = t.prop(k, "Character")
		if ch is Dictionary and str(ch.get("$i", "")) == model:
			return int(t.prop(k, "UserId"))
	return 0


## EmoteOverride objects in StarterPlayer swap wheel moves for the place's own animations.
## Scripts turning characters' joints (Humanoid *Angle properties): every Melly shows it.
func _sync_joints() -> void:
	var t := place_host.tree
	for k in t.kids(t.service("Players")):
		if t.cls(k) != "Player":
			continue
		var ch: Variant = t.prop(k, "Character")
		var model := str(ch["$i"]) if ch is Dictionary and ch.has("$i") else ""
		if model == "" or not t.has(model):
			continue
		var hum := t.child_of_class(model, "Humanoid")
		if hum == "":
			continue
		var uid := int(t.prop(k, "UserId"))
		var av: MellyAvatar = player.avatar if uid == my_id else (remotes[uid].avatar if remotes.has(uid) else null)
		if av:
			av.set_joint_angles(place_host.scene.joint_angles_of(hum))
			av.set_part_shapes(place_host.scene.part_shapes_of(hum))
			place_host.scene.dress_parts(av, hum)
			if uid == my_id:
				player.set_hip(av.hip_shift())


func _sync_emote_overrides() -> void:
	var t := place_host.tree
	var sp := t.service("StarterPlayer")
	var o := {}
	if sp != "":
		for k in t.kids(sp):
			if t.cls(k) == "EmoteOverride":
				o[str(t.prop(k, "Slot"))] = [str(t.prop(k, "Title")), str(t.prop(k, "Animation"))]
	var sig := str(o)
	if sig != _emote_sig:
		_emote_sig = sig
		hud.wheel.set_overrides(o)


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
	# Already on the way out (kicked, an error, a place update) but still here: just go.
	if _leaving:
		_leave()
		return
	if _confirming:
		return
	_confirming = true
	var yes: bool = await UI.confirm(self, L.t("leave_q"), L.t("leave_body"), L.t("leave_game"))
	_confirming = false
	if yes:
		_leave()


var _confirming := false


var _loading: LoadingScreen


func _finish_loading() -> void:
	if is_instance_valid(_loading):
		_loading.finish()
	_loading = null


## TeleportService sent us to another place of this game (in a Studio test: another place
## of the game being edited, loaded from the server or the editor itself).
func _teleport(m: Dictionary) -> void:
	if _leaving:
		return
	_leaving = true
	var place := str(m.get("game", ""))
	# The place we're going to, while we go.
	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.show_place(place, L.t("teleporting").trim_suffix("…"))
	net.close()
	if not Session.test_melt.is_empty():
		var melt: Dictionary = {}
		if place == Session.studio_place_id:
			melt = Session.studio_melt
		else:
			var r := await Api.request("GET", "/api/studio/places/" + place)
			if r.ok and r.data.get("melt") is Dictionary:
				melt = r.data.melt
		if melt.is_empty():
			_leaving = false
			hud.show_overlay(L.t("teleport_failed"), [[L.t("to_menu"), _leave]])
			return
		Session.set_meta("tp_join", {"data": m.get("data"), "from": str(Session.get_meta("test_place", Session.studio_place_id))})
		Session.set_meta("test_place", place)
		Session.test_melt = melt
	else:
		Session.pending_game = place
		Session.pending_server = str(m.get("server", "auto"))
	await get_tree().create_timer(0.4).timeout
	get_tree().reload_current_scene()


func _leave() -> void:
	_leaving = true
	net.close()
	# A Studio play test goes back to the editor.
	if not Session.test_melt.is_empty():
		Session.test_melt = {}
		UI.goto("res://scenes/studio.tscn")
		return
	UI.goto("res://scenes/main_menu.tscn")
	# Should the fade get stuck somehow, out anyway: nobody stays locked in a place. (Gone
	# by then as it should be: the timer's call goes with this scene.)
	var tree := get_tree()
	tree.create_timer(2.0).timeout.connect(func():
		if is_inside_tree():
			tree.change_scene_to_file("res://scenes/main_menu.tscn"))


## "Hug" by everyone near who's waiting for one (the hug emote, arms open).
func _hug_prompts() -> Array:
	var out: Array = []
	if player == null or player.current_anim() == "hug":
		return out
	for uid in remotes:
		var rp: RemotePlayer = remotes[uid]
		if rp.current_anim != "hug" or not rp.visible:
			continue
		out.append({"id": "hug:%d" % uid, "at": rp.global_position + Vector3(0, 1.0, 0), "range": 8.0, "key": "E",
			"action": L.t("hug_action"), "object": str(rp.user.get("display_name", "")), "hold": 0.0,
			"use": func(): net.send({"t": "hug", "id": uid})})
	return out
