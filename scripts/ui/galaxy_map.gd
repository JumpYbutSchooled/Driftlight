extends Control
## Full galaxy map (M). Drag to pan, wheel to zoom. Click a system to plot a route there, shift-click to add
## it as a further stop, right-click to clear the route. The galaxy is split into regions (each with its own
## ore): their names float over them and hovering a system says which it's in. With a jump drive its reach is
## ringed and a double-click jumps; a double-click can also open a portable wormhole, or (Sandbox) jump at once.

const UI = preload("res://scripts/ui/ui.gd")

var main
var zoom := 0.6
var center := Vector2.ZERO
var hovered := -1
var font: Font
var _drag := false
var _drag_dist := 0.0
var _counts := [0, 0, 0, 0]
var _region_at := []  # [label position, region] for each region, computed once
var _pulse: Control  # the ring round where you are
var _top: Control  # what's drawn over the ring
var _sig := []  # what the map showed when it was last drawn


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	font = ThemeDB.fallback_font
	for k in 2:
		var c := Control.new()
		c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		c.mouse_filter = MOUSE_FILTER_IGNORE
		c.draw.connect(_draw_pulse if k == 0 else _draw_top)
		add_child(c)
		if k == 0:
			_pulse = c
		else:
			_top = c


func open() -> void:
	_counts = [0, 0, 0, 0]
	for s in Game.systems:
		_counts[s.cat] += 1
	if _region_at.is_empty():
		var sums := {}
		for s in Game.systems:
			var r: int = s.region
			if not sums.has(r):
				sums[r] = [Vector2.ZERO, 0]
			sums[r][0] += s.pos
			sums[r][1] += 1
		for r in sums:
			_region_at.append([sums[r][0] / sums[r][1], r])
	center = Game.systems[Game.current_system].pos
	zoom = 0.6
	hovered = -1
	_sig = []
	show()
	UI.pop_in(self)


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
				if e.double_click and hovered >= 0 and hovered != Game.current_system:
					_double(hovered)
					accept_event()
					return
				_drag = true
				_drag_dist = 0.0
			else:
				_drag = false
				if _drag_dist < 6.0 and hovered >= 0:
					if e.shift_pressed:
						_add_stop(hovered)
					else:
						_set_route(hovered)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed and Game.route_target >= 0:
			Game.clear_route()
			main.stop_auto()
			Game.say("Route cleared.", Color("ffe066"))
		accept_event()
	elif e is InputEventMouseMotion:
		if _drag:
			center -= e.relative / zoom
			_drag_dist += e.relative.length()
		_update_hover(e.position)


## Double-click: the Sandbox jumps straight there; a jump drive jumps there if it reaches; otherwise a portable
## wormhole can take you (it asks first: they're rare).
func _double(id: int) -> void:
	if Game.sandbox:
		main.admin_jump(id)
	elif main.can_jump_drive(id):
		main.jump_drive(id)
	elif Game.portals > 0:
		var sys: Dictionary = Game.systems[id]
		main.close_maps()
		main.ask("Open a portable wormhole to %s?\n\n%s space, %s.   You have %d portable wormhole%s; this uses one up." % [sys.name,
			Game.CAT_NAMES[sys.cat], Game.REGIONS[sys.region].name, Game.portals, "" if Game.portals == 1 else "s"], "Open it",
			main.open_portal.bind(id))
	elif main.player.st.get("jump", 0.0) > 0.0:
		Game.say("That's beyond your jump drive's reach.", UI.MUTED)


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
	Game.clear_route()
	Game.route_target = id
	var path := Game.route_path()
	Game.say("Route set to %s: %d jumps. Press T to auto-travel, or follow the << ROUTE gate in your warp menu." % [
		Game.systems[id].name, path.size()], Color("ffe066"))


func _add_stop(id: int) -> void:
	if id == Game.current_system and Game.route_target < 0:
		return
	Game.add_stop(id)
	Game.say("Stop added: %s. The route is %d jumps in all." % [Game.systems[id].name, Game.route_jumps()], Color("ffe066"))


## A thousand systems and their lanes take a while to draw, so the map is only drawn again when something on it
## changes (panning, zooming, hovering, the route...); the pulsing ring has a layer of its own.
func _process(_delta: float) -> void:
	if not visible:
		return
	_pulse.queue_redraw()
	var sig := [zoom, center, size, hovered, Game.current_system, Game.route_target, Game.route_stops.duplicate(), Game.portals,
		Game.sandbox, Game.regions_seen.size(), main.player.st.get("jump", 0.0), main.can_jump_drive(hovered) if hovered >= 0 else false]
	if sig != _sig:
		_sig = sig
		queue_redraw()
		_top.queue_redraw()


## Under the ring: the regions, the lanes, the route, the systems and the region names.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.035, 0.97))
	var view := Rect2(Vector2.ZERO, size).grow(800.0)
	# each region's systems softly tinted in its colour, under everything else
	var sz := roundf(clampf(4.0 * zoom + 3.0, 4.0, 14.0))
	for s in Game.systems:
		var p := _to_screen(s.pos)
		if view.has_point(p) and s.region > 0:
			draw_circle(p, sz * 3.2, Color(Game.REGIONS[s.region].color, 0.05))
	for s in Game.systems:
		var a := _to_screen(s.pos)
		for l in s.links:
			if l > s.id:
				var b := _to_screen(Game.systems[l].pos)
				if view.has_point(a) or view.has_point(b):
					draw_line(a, b, Color(0.5, 0.6, 0.8, 0.16), 1.0)
	# the route, and any further stops
	var prev := _to_screen(Game.systems[Game.current_system].pos)
	var at := Game.current_system
	var legs := [Game.route_target] + Game.route_stops if Game.route_target >= 0 else []
	for k in legs.size():
		for id in Game.find_path(at, legs[k]):
			var b := _to_screen(Game.systems[id].pos)
			draw_line(prev, b, Color("ffe066") if k == 0 else Color("ffe066", 0.5), 3.0 if k == 0 else 2.0)
			prev = b
		at = legs[k]
		draw_arc(_to_screen(Game.systems[at].pos), 14.0, 0.0, TAU, 24, Color("ffe066"), 2.0)
		if k > 0:
			draw_string(UI.title, _to_screen(Game.systems[at].pos) + Vector2(-20, -18), "%d" % (k + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 14,
				Color("ffe066"))
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
	# region names
	for ra in _region_at:
		var reg: Dictionary = Game.REGIONS[ra[1]]
		var rp := _to_screen(ra[0])
		if view.has_point(rp):
			var known: bool = Game.regions_seen.has(ra[1])
			draw_string(UI.title, rp + Vector2(-200, 0), reg.name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 400, 18,
				Color(reg.color, 0.55 if known else 0.3))
			if reg.ore != "":
				draw_string(font, rp + Vector2(-200, 20), Game.ORES[reg.ore].name if known else "?", HORIZONTAL_ALIGNMENT_CENTER, 400, 14,
					Color(reg.color, 0.45 if known else 0.25))
	var cur: Dictionary = Game.systems[Game.current_system]
	var cp := _to_screen(cur.pos)
	var reach: float = main.player.st.get("jump", 0.0)
	if reach > 0.0:
		draw_arc(cp, reach * zoom, 0.0, TAU, 96, Color(0.75, 0.5, 1.0, 0.55), 1.5, true)
		draw_string(font, cp + Vector2(-120, -reach * zoom - 8), "JUMP DRIVE REACH", HORIZONTAL_ALIGNMENT_CENTER, 240, 13, Color("c080ff"))


## The ring round where you are, pulsing (redrawn every frame: it's all that moves).
func _draw_pulse() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_pulse.draw_arc(_to_screen(Game.systems[Game.current_system].pos), 12.0 + sin(t * 4.0) * 3.0, 0.0, TAU, 24, Color.WHITE, 2.0)


## Over the ring: its label, the hovered system's card, the title and the key.
func _draw_top() -> void:
	var c := _top
	var cp := _to_screen(Game.systems[Game.current_system].pos)
	c.draw_string(font, cp + Vector2(-40, -20), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)

	if hovered >= 0:
		var h: Dictionary = Game.systems[hovered]
		var reg: Dictionary = Game.REGIONS[h.region]
		var hp := _to_screen(h.pos) + Vector2(18, -10)
		var lines := [h.name, "%s System  -  %s" % [Game.CAT_NAMES[h.cat], reg.name]]
		lines.append(("Visited" if h.visited else "Unexplored") + "  -  " + Game.system_look(h).star)
		if reg.ore != "" and Game.regions_seen.has(h.region):
			lines.append("Regional ore: %s" % Game.ORES[reg.ore].name)
		if hovered != Game.current_system:
			lines.append("%d jumps away - click: route, shift-click: add a stop" % Game.find_path(Game.current_system, hovered).size())
			if main.can_jump_drive(hovered):
				lines.append("In jump drive reach: double-click to jump")
			elif Game.portals > 0 and not Game.sandbox:
				lines.append("Double-click: open a portable wormhole (%d)" % Game.portals)
		if h.cat == Game.CAT_PURPLE:
			lines.append("DANGER: pirates on most planets")
		elif h.cat == Game.CAT_RED:
			lines.append("No stations. Pirates about.")
		var box := Rect2(hp, Vector2(400, 16 + lines.size() * 22))
		c.draw_rect(box, Color(0.03, 0.04, 0.08, 0.95))
		c.draw_rect(box, Game.CAT_COLORS[h.cat], false, 2.0)
		for i in lines.size():
			var col: Color = Game.CAT_COLORS[h.cat] if i < 2 else Color("c9d3e6")
			c.draw_string(font, hp + Vector2(10, 26 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if i == 0 else 14, col)

	c.draw_string(UI.title, Vector2(24, 50), "GALAXY MAP  %d SYSTEMS" % Game.systems.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.HEAD)
	c.draw_string(font, Vector2(24, 80), "Wheel: zoom    Drag: pan    Click: plot a route    Shift-click: add a stop    Right click: clear    T: auto-travel    M / Esc: close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8090a8"))
	if Game.sandbox:
		c.draw_string(font, Vector2(24, 106), "SANDBOX: double-click a system to jump straight there", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.GOLD)
	if Game.route_target >= 0:
		c.draw_string(font, Vector2(24, 132), "Route: %d jumps%s" % [Game.route_jumps(), "" if Game.route_stops.is_empty() else
			" over %d stops" % (Game.route_stops.size() + 1)], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffe066"))
	for i in 4:
		var ly := size.y - 130.0 + i * 26.0
		c.draw_rect(Rect2(24, ly - 12, 14, 14), Game.CAT_COLORS[i])
		var desc: String = ["Core - safe, the common ores", "Secure - two regions, a few pirates", "Unsecure - three regions, no stations",
			"Wild - four regions, anomalies, very dangerous"][i]
		c.draw_string(font, Vector2(48, ly), "%s   (%d)" % [desc, _counts[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Game.CAT_COLORS[i])
