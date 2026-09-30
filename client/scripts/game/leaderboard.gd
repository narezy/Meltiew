class_name Leaderboard
extends PanelContainer
## The player list with a place's stats (leaderstats), like Roblox's: each player's
## values in columns, grouped by team when the place has teams. Closed by default;
## Tab or the button at the top right opens it.

const REFRESH := 0.5
const MAX_STATS := 4

var game: Node  # the Game scene: users, place_host
var _t := 0.0
var _grid: GridContainer
var _title: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG_2, 0.86)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(8)
	add_child(v)
	_title = UI.label(L.t("players"), 15, UI.MUTED, "black")
	v.add_child(_title)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(_grid)


func toggle() -> void:
	visible = not visible
	if visible:
		_t = 0.0
		_rebuild()


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH
		_rebuild()


## Rows: {name, color, stats: {stat -> text}, sort, team}. Stats come from the place
## (Players/<player>/leaderstats); the playground just lists who's here.
func _rows() -> Dictionary:
	var out := {"stats": [], "rows": [], "teams": []}
	var host: PlaceHost = game.get("place_host") if game else null
	var tree: PlaceTree = host.tree if host else null
	if tree == null:
		for u in (game.users.values() if game else []):
			out.rows.append({"name": str(u.get("display_name", "?")), "color": UI.TEXT, "stats": {}, "sort": 0.0, "team": ""})
		return out
	var teams_svc := tree.service("Teams")
	if teams_svc != "":
		for t in tree.kids(teams_svc):
			if tree.cls(t) == "Team":
				out.teams.append(t)
	var ps := tree.service("Players")
	if ps == "":
		return out
	for p in tree.kids(ps):
		if tree.cls(p) != "Player":
			continue
		var stats := {}
		var ls := tree.child_named(p, "leaderstats")
		var first := 0.0
		if ls != "":
			for s in tree.kids(ls):
				if not tree.cls(s).ends_with("Value"):
					continue
				var name := tree.name_of(s)
				if not name in out.stats:
					if out.stats.size() >= MAX_STATS:
						continue
					out.stats.append(name)
				var val: Variant = tree.prop(s, "Value")
				stats[name] = _fmt(val)
				if name == out.stats[0] and (val is float or val is int):
					first = float(val)
		var team_ref: Variant = tree.prop(p, "Team")
		var team := str(team_ref["$i"]) if team_ref is Dictionary and team_ref.has("$i") else ""
		var neutral: bool = tree.prop(p, "Neutral") != false
		var col: Color = tree.prop(p, "TeamColor") if not neutral and tree.prop(p, "TeamColor") is Color else UI.TEXT
		out.rows.append({"name": UI.tame(str(tree.prop(p, "DisplayName"))), "color": col, "stats": stats, "sort": first, "team": team})
	return out


static func _fmt(v: Variant) -> String:
	if v is float:
		return str(int(v)) if is_equal_approx(v, roundf(v)) and absf(v) < 1e12 else "%.1f" % v
	if v is bool:
		return "✓" if v else "—"
	return UI.tame(str(v))


func _rebuild() -> void:
	var data := _rows()
	var stats: Array = data.stats
	for c in _grid.get_children():
		c.queue_free()
	_grid.columns = 1 + stats.size()
	_title.text = L.t("players") + " · %d" % data.rows.size()
	if not stats.is_empty():
		_grid.add_child(UI.label("", 13, UI.MUTED))
		for s in stats:
			var h := UI.label(UI.tame(str(s)), 13, UI.MUTED, "bold")
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_grid.add_child(h)
	var rows: Array = data.rows
	rows.sort_custom(func(a, b): return a.sort > b.sort if a.sort != b.sort else a.name < b.name)
	var host: PlaceHost = game.get("place_host") if game else null
	var groups: Array = []  # [label, color, rows]
	if data.teams.is_empty():
		groups.append(["", UI.TEXT, rows])
	else:
		for t in data.teams:
			groups.append([UI.tame(host.tree.name_of(t)), host.tree.prop(t, "TeamColor"), rows.filter(func(r): return r.team == t)])
		var neutral := rows.filter(func(r): return r.team == "")
		if not neutral.is_empty():
			groups.append([L.t("lb_neutral"), UI.MUTED, neutral])
	for g in groups:
		if g[0] != "":
			var th := UI.label(str(g[0]), 14, g[1] if g[1] is Color else UI.TEXT, "black")
			_grid.add_child(th)
			for s in stats:
				_grid.add_child(Control.new())
		for r in g[2]:
			var n := UI.label(str(r.name), 15, r.color, "bold")
			n.custom_minimum_size.x = 120
			n.clip_text = true
			_grid.add_child(n)
			for s in stats:
				var cell := UI.label(str(r.stats.get(s, "")), 15, UI.TEXT)
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				cell.custom_minimum_size.x = 48
				_grid.add_child(cell)
