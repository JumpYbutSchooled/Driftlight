extends Control
## Full galaxy map (M). Drag to pan, wheel to zoom, click a system to plot a route.

const UI = preload("res://scripts/ui/ui.gd")

var main
var zoom := 0.6
var center := Vector2.ZERO
var hovered := -1
var font: Font
var _drag := false
var _drag_dist := 0.0
var _counts := [0, 0, 0, 0]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	font = ThemeDB.fallback_font


func open() -> void:
	_counts = [0, 0, 0, 0]
	for s in Game.systems:
		_counts[s.cat] += 1
	center = Game.systems[Game.current_system].pos
	zoom = 0.6
	hovered = -1
	show()


func _to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + (p - center) * zoom


func _to_map(s: Vector2) -> Vector2:
	return center + (s - size / 2.0) / zoom


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(e.position, 1.15)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(e.position, 1.0 / 1.15)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if e.double_click and Game.admin and hovered >= 0:
					main.admin_jump(hovered)  # admin: straight there
					accept_event()
					return
				_drag = true
				_drag_dist = 0.0
			else:
				_drag = false
				if _drag_dist < 6.0 and hovered >= 0:
					_set_route(hovered)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and Game.route_target >= 0:
			Game.route_target = -1
			Game.say("Route cleared.", Color("ffe066"))
		accept_event()
	elif e is InputEventMouseMotion:
		if _drag:
			center -= e.relative / zoom
			_drag_dist += e.relative.length()
		_update_hover(e.position)


func _zoom_at(sp: Vector2, f: float) -> void:
	var before := _to_map(sp)
	zoom = clampf(zoom * f, 0.12, 4.0)
	center += before - _to_map(sp)


func _update_hover(sp: Vector2) -> void:
	hovered = -1
	var best := 14.0
	for s in Game.systems:
		var d := _to_screen(s.pos).distance_to(sp)
		if d < best:
			best = d
			hovered = s.id


func _set_route(id: int) -> void:
	if id == Game.current_system:
		return
	Game.route_target = id
	var path := Game.route_path()
	Game.say("Route set to %s: %d jumps. Follow the << ROUTE gate in your warp menu." % [Game.systems[id].name, path.size()],
		Color("ffe066"))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.035, 0.97))
	var t := Time.get_ticks_msec() / 1000.0
	var view := Rect2(Vector2.ZERO, size).grow(800.0)
	for s in Game.systems:
		var a := _to_screen(s.pos)
		for l in s.links:
			if l > s.id:
				var b := _to_screen(Game.systems[l].pos)
				if view.has_point(a) or view.has_point(b):
					draw_line(a, b, Color(0.5, 0.6, 0.8, 0.16), 1.0)
	var path := Game.route_path()
	var prev := _to_screen(Game.systems[Game.current_system].pos)
	for id in path:
		var b := _to_screen(Game.systems[id].pos)
		draw_line(prev, b, Color("ffe066"), 3.0)
		prev = b
	var sz := roundf(clampf(4.0 * zoom + 3.0, 4.0, 14.0))
	for s in Game.systems:
		var p := _to_screen(s.pos).round()
		if p.x < -20.0 or p.y < -20.0 or p.x > size.x + 20.0 or p.y > size.y + 20.0:
			continue
		var c: Color = Game.CAT_COLORS[s.cat]
		if not s.visited:
			c = c.darkened(0.4)
		draw_rect(Rect2(p - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), c)
		if s.visited:
			draw_rect(Rect2(p - Vector2(sz + 6, sz + 6) / 2.0, Vector2(sz + 6, sz + 6)), c, false, 1.0)
		if zoom > 1.3 or s.id == 0:
			draw_string(font, p + Vector2(-80, sz + 14), s.name, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(c, 0.85))
	var cur: Dictionary = Game.systems[Game.current_system]
	var cp := _to_screen(cur.pos)
	draw_arc(cp, 12.0 + sin(t * 4.0) * 3.0, 0.0, TAU, 24, Color.WHITE, 2.0)
	draw_string(font, cp + Vector2(-40, -20), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)
	if Game.route_target >= 0:
		draw_arc(_to_screen(Game.systems[Game.route_target].pos), 14.0, 0.0, TAU, 24, Color("ffe066"), 2.0)

	if hovered >= 0:
		var h: Dictionary = Game.systems[hovered]
		var hp := _to_screen(h.pos) + Vector2(18, -10)
		var lines := [h.name, "%s System" % Game.CAT_NAMES[h.cat]]
		lines.append("Visited" if h.visited else "Unexplored")
		if hovered != Game.current_system:
			lines.append("%d jumps away - click to plot a route" % Game.find_path(Game.current_system, hovered).size())
		if h.cat == Game.CAT_PURPLE:
			lines.append("DANGER: pirates on most planets")
		elif h.cat == Game.CAT_RED:
			lines.append("No stations. Pirates about.")
		var box := Rect2(hp, Vector2(330, 16 + lines.size() * 22))
		draw_rect(box, Color(0.03, 0.04, 0.08, 0.95))
		draw_rect(box, Game.CAT_COLORS[h.cat], false, 2.0)
		for i in lines.size():
			var col: Color = Game.CAT_COLORS[h.cat] if i < 2 else Color("c9d3e6")
			draw_string(font, hp + Vector2(10, 26 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if i == 0 else 14, col)

	draw_string(UI.title, Vector2(24, 50), "GALAXY MAP  %d SYSTEMS" % Game.systems.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.HEAD)
	if Game.admin:
		draw_string(font, Vector2(24, 106), "ADMIN: double-click a system to jump straight there", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.GOLD)
	draw_string(font, Vector2(24, 80), "Wheel: zoom    Drag: pan    Click a system: plot route    Right click: clear route    M / Esc: close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8090a8"))
	for i in 4:
		var ly := size.y - 130.0 + i * 26.0
		draw_rect(Rect2(24, ly - 12, 14, 14), Game.CAT_COLORS[i])
		var desc: String = ["Core - safe, inferior ores", "Secure - rarer ores, few pirates", "Unsecure - no stations, rare spices",
			"Wild - very dangerous, anomalies"][i]
		draw_string(font, Vector2(48, ly), "%s   (%d)" % [desc, _counts[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Game.CAT_COLORS[i])
