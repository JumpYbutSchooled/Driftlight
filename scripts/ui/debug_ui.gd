extends Control
## F3 technical overlay, Minecraft style: lines of data down the left and right edges.


var main
var font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _lines(x: float, y: float, lines: Array, right: bool) -> float:
	for l in lines:
		var text: String = l if l is String else l[0]
		var col: Color = Color("e8e8e8") if l is String else l[1]
		if text != "":
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var lx := x - w - 8.0 if right else x
			draw_rect(Rect2(lx, y - 15.0, w + 8.0, 20.0), Color(0.2, 0.2, 0.2, 0.55))
			draw_string(font, Vector2(lx + 4.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		y += 20.0
	return y


func _deg(a: float) -> float:
	return fposmod(rad_to_deg(a), 360.0)


func _draw() -> void:
	var p = main.player
	var sys: Dictionary = Game.systems[Game.current_system]
	var loc: Dictionary = sys.locs[Game.current_loc]
	var st: Dictionary = p.st
	var lo := Game.loadout()
	var fwd: Vector3 = p.forward()
	var aim_fwd: Vector3 = -main.aim.z
	var speed: float = p.vel.length()
	var drift := 0.0 if speed < 1.0 else rad_to_deg(p.vel.angle_to(fwd))
	var lag := rad_to_deg(fwd.angle_to(aim_fwd))
	var heading := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var path := Game.route_path()
	var found := 0
	for a in Game.anomalies:
		if Game.systems[a.sys].locs[a.loc].found:
			found += 1
	var visited := Game.systems.filter(func(s): return s.visited).size()
	var links := 0
	for s in Game.systems:
		links += s.links.size()
	var k := Game.WORLD_SCALE

	var left := [
		["Driftlight 3D (Godot %s)" % Engine.get_version_info().string, Color("ffe7a3")],
		"%d fps   frame %.2f ms   physics %d Hz" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Engine.physics_ticks_per_second],
		"Objects %d   Nodes %d   Draw calls %d   Primitives %d" % [Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)],
		"Static memory %.1f MB   Video memory %.1f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0],
		"",
		["SHIP", Color("9fd3ff")],
		"%s (%s)   mode: %s" % [Game.SHIPS[Game.ship_id].name, Game.SHIPS[Game.ship_id]["class"], main.mode],
		"XYZ: %.1f / %.1f / %.1f" % [p.position.x, p.position.y, p.position.z],
		"Speed %.1f / %.0f m/s   drift %.1f deg off nose" % [speed, st.speed * k, drift],
		"Heading %.1f deg   pitch %.1f deg" % [heading, pitch],
		"Throttle %d%%   target %.0f m/s" % [roundi(p.throttle * 100.0), p.throttle * st.speed * k],
		"Turn rate %.2f rad/s   nose is %.1f deg behind your aim" % [st.turn, lag],
		"Hull %.1f / %.0f   Shield %.1f / %.0f   regen %.1f/s" % [p.hull, st.hull, p.shield, st.shield, st.regen],
		"Shield recharge in %.1f s" % maxf(0.0, st.shield_delay - p._since_hit),
		"Radius %.1f m   hull box %.1f x %.1f x %.1f m" % [p.radius, p.hull_box.x, p.hull_box.y, p.hull_box.z],
		"Camera FOV %.0f" % main.camera.fov,
		"",
		["LOCATION", Color("9fd3ff")],
		"System #%d %s   [%s]   depth %.3f" % [sys.id, sys.name, Game.CAT_NAMES[sys.cat], sys.depth],
		"Galaxy pos: %.0f, %.0f   gates: %d" % [sys.pos.x, sys.pos.y, sys.links.size()],
		"Loc #%d %s (%s)   pirates: %s" % [Game.current_loc, loc.name, loc.kind, loc.pirates],
		"Route: %s" % ("none" if path.is_empty() else "%s, %d jumps" % [Game.systems[Game.route_target].name, path.size()]),
		"Galaxy: %d systems, %d gates, seed %d, built in %d ms" % [Game.systems.size(), int(links / 2.0), Game.GALAXY_SEED, Game.gen_ms],
		"Visited %d   Anomalies found %d / %d" % [visited, found, Game.anomalies.size()],
	]
	_lines(8.0, 22.0, left, false)

	var total: int = p.muzzles.size()
	var gun_lines := []
	for g in total:
		var clear: bool = p.guns_ready[g] if g < p.guns_ready.size() else false
		var side := "L" if g % 2 == 0 else "R"
		gun_lines.append(["Slot %d (%s%d) %s: %s" % [g + 1, side, (g >> 1) + 1, Game.WEAPONS[lo[g]].name, "CLEAR" if clear else "BLOCKED by hull"],
			Color(0.4, 1.0, 0.5) if clear else Color(1.0, 0.4, 0.4)])
	var tgt = main.aim_target
	var right := [
		["WEAPONS  (%d gun slots)" % total, Color("9fd3ff")],
		"Next shot in %.2f s" % maxf(0.0, p._fire_cd),
		"Aim point %.0f m away" % main.camera.global_position.distance_to(main.aim_point),
		"Target: %s" % (tgt.describe() if tgt != null and is_instance_valid(tgt) and tgt.has_method("describe") else "none"),
	]
	right.append_array(gun_lines)
	right.append_array([
		"",
		["WORLD", Color("9fd3ff")],
		"Asteroids %d   Ore chunks %d" % [get_tree().get_nodes_in_group("asteroids").size(), get_tree().get_nodes_in_group("chunks").size()],
		"Pirates %d   Next wave %s" % [get_tree().get_nodes_in_group("pirates").size(),
			"-" if main._pirate_timer < 0.0 else "%.1f s" % main._pirate_timer],
		"Interactables %d" % main.interactables.size(),
		"Cargo %d / %d   Probes %d" % [Game.cargo_used(), st.cargo, Game.probes],
		"Blessings: %s" % (", ".join(Game.blessings.keys()) if not Game.blessings.is_empty() else "none"),
		"Warp: %s" % (main.travel.get("phase", "-")),
	])
	_lines(size.x - 8.0, 22.0, right, true)