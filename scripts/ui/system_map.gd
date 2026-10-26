extends Control
## Map of the current system (N). Launch probes from here to scan planets and hunt anomalies.

const UI = preload("res://scripts/ui/ui.gd")
const PROBE_TIME := 14.0
const PROBE_SPEED := 0.42  # map units per second (the system is about 2 units across)

var main
var font: Font
var probe_on := false
var probe_pos := Vector2.ZERO
var probe_life := 0.0
var probe_target = null  # overrides the mouse when set (used by the screenshot script)
var _probe_speed := PROBE_SPEED
var trail := []
var _prox := 0.0
var _beep_t := 0.0
var _trail_t := 0.0
var _btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	font = ThemeDB.fallback_font
	_btn = UI.btn("", launch_probe)
	_btn.custom_minimum_size = Vector2(340, 50)
	add_child(_btn)


func open() -> void:
	show()
	UI.pop_in(self)


func close() -> void:
	probe_on = false
	trail.clear()
	hide()


func launch_probe() -> void:
	if Game.probes <= 0 or probe_on:
		return
	Game.probes -= 1
	Game.changed.emit()
	probe_on = true
	var mult: float = Game.stats_ship().probe
	probe_life = PROBE_TIME * mult
	_probe_speed = PROBE_SPEED * (1.0 + (mult - 1.0) * 0.5)
	trail.clear()
	probe_pos = Game.systems[Game.current_system].locs[Game.current_loc].map_pos


func _scale() -> float:
	return minf(size.x, size.y) * 0.36


func _to_screen(m: Vector2) -> Vector2:
	return size / 2.0 + m * _scale()


func _to_map(s: Vector2) -> Vector2:
	return (s - size / 2.0) / _scale()


func _process(delta: float) -> void:
	if not visible:
		return
	_btn.position = Vector2(size.x - 370.0, size.y - 86.0)
	if probe_on:
		_btn.text = "Probe flying... %.0fs" % probe_life
	elif Game.probes > 0:
		_btn.text = "Launch Probe  (%d left)" % Game.probes
	else:
		_btn.text = "No probes - build them at a station"
	_btn.disabled = probe_on or Game.probes <= 0
	if probe_on:
		_update_probe(delta)
	for tp in trail:
		tp.a -= delta / 3.0
	trail = trail.filter(func(tp): return tp.a > 0.0)
	queue_redraw()


func _update_probe(delta: float) -> void:
	var target: Vector2 = probe_target if probe_target != null else _to_map(get_local_mouse_position())
	probe_pos = probe_pos.move_toward(target, _probe_speed * delta)
	probe_life -= delta
	var sys: Dictionary = Game.systems[Game.current_system]
	var nd := INF
	for l in sys.locs:
		if l.kind == "anomaly" and not l.found:
			nd = minf(nd, probe_pos.distance_to(l.map_pos))
	_prox = 0.0 if nd == INF else clampf(1.0 - nd / 0.9, 0.0, 1.0)
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.03
		trail.append({"p": probe_pos, "c": Color(0.75, 0.9, 1.0).lerp(Color(1.0, 0.08, 0.08), _prox), "a": 1.0})
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = lerpf(1.1, 0.07, pow(_prox, 0.8))
		Sfx.play("beep", -12.0, 1.0 + _prox * 0.6)
	for i in sys.locs.size():
		var l: Dictionary = sys.locs[i]
		var d: float = probe_pos.distance_to(l.map_pos)
		if l.kind == "planet" and not l.scanned and d < 0.07:
			l.scanned = true
			Game.note_loc(Game.current_system, i)
			Game.say("Probe scan: %s - %s" % [l.name, Game.loc_summary(l)], Color("9fd3ff"))
			Game.event("scan")
			Sfx.play("pickup", -8.0, 0.8)
		elif l.kind == "anomaly" and not l.found and d < 0.05:
			l.found = true
			Game.note_loc(Game.current_system, i)
			Game.say("ANOMALY FOUND: %s! It now shows in your warp menu." % l.name, Color("e080ff"))
			Game.event("anomaly")
			Sfx.play("found")
	if probe_life <= 0.0:
		probe_on = false
		_prox = 0.0
		Game.say("Probe signal lost.", Color("8a94a8"))


func _pix_circle(c: Vector2, r: float, color: Color, cell := 4.0) -> void:
	var n := ceili(r / cell)
	for gy in range(-n, n + 1):
		for gx in range(-n, n + 1):
			var off := Vector2(gx, gy) * cell
			if off.length() <= r:
				draw_rect(Rect2((c + off - Vector2(cell, cell) / 2.0).round(), Vector2(cell, cell)), color)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.035, 0.96))
	var sys: Dictionary = Game.systems[Game.current_system]
	var cc: Color = Game.CAT_COLORS[sys.cat]
	var t := Time.get_ticks_msec() / 1000.0
	var center := size / 2.0
	draw_string(UI.title, Vector2(24, 50), "SYSTEM MAP  %s" % sys.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, cc)
	draw_string(font, Vector2(24, 80), "Probes follow your mouse. Fly one over a planet to scan it. Near a hidden anomaly the beeping speeds up and the trail turns red.   N / Esc: close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8090a8"))

	# the star, in its own colour and size (and its companion, in a binary)
	var lk: Dictionary = Game.system_look(sys)
	var stc: Color = lk.star_color
	var sr := clampf(18.0 * sqrt(lk.star_size), 9.0, 42.0)
	_pix_circle(center, sr * 1.55, Color(stc, 0.15))
	_pix_circle(center, sr, stc.lerp(Color.WHITE, 0.15))
	_pix_circle(center, sr * 0.55, stc.lerp(Color.WHITE, 0.7))
	var below := sr * 1.55  # (the name goes under the star and its companion)
	if lk.binary:
		var off := Vector2.from_angle(lk.yaw * 3.0) * (sr + 26.0)
		var cc2: Color = lk.companion_color
		_pix_circle(center + off, 8.0, cc2.lerp(Color.WHITE, 0.3))
		below = maxf(below, off.y + 10.0)
	draw_string(font, center + Vector2(-150, below + 20.0), lk.star, HORIZONTAL_ALIGNMENT_CENTER, 300, 14, stc)
	for l in sys.locs:
		if l.kind == "planet":
			draw_arc(center, l.map_pos.length() * _scale(), 0.0, TAU, 128, Color(1, 1, 1, 0.06), 2.0)

	for i in sys.locs.size():
		var l: Dictionary = sys.locs[i]
		var p := _to_screen(l.map_pos).round()
		match l.kind:
			"planet":
				var pc: Color = Game.PLANET_COLORS[l.planet_type]
				_pix_circle(p, 16.0, pc if l.scanned else pc.darkened(0.6))
				draw_string(font, p + Vector2(-150, 38), l.name, HORIZONTAL_ALIGNMENT_CENTER, 300, 15, Color.WHITE)
				var sc := Color("ff8a7a") if l.pirates and l.scanned else Color("9aa6bb")
				draw_string(font, p + Vector2(-150, 56), "? unscanned" if not l.scanned else Game.loc_summary(l),
					HORIZONTAL_ALIGNMENT_CENTER, 300, 13, sc)
			"gate":
				var dc: Color = Game.CAT_COLORS[Game.systems[l.gate_to].cat]
				var pts := PackedVector2Array([p + Vector2(0, -12), p + Vector2(12, 0), p + Vector2(0, 12), p + Vector2(-12, 0)])
				draw_colored_polygon(pts, dc)
				draw_string(font, p + Vector2(-110, 30), "-> " + Game.systems[l.gate_to].name, HORIZONTAL_ALIGNMENT_CENTER, 220, 13, dc)
			"anomaly":
				if l.found:
					var ac := Color("e080ff")
					draw_rect(Rect2(p - Vector2(12, 3), Vector2(24, 6)), ac)
					draw_rect(Rect2(p - Vector2(3, 12), Vector2(6, 24)), ac)
					draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color.WHITE)
					draw_string(font, p + Vector2(-110, 32), l.name, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, ac)
		if i == Game.current_loc:
			draw_arc(p, 26.0 + sin(t * 4.0) * 3.0, 0.0, TAU, 32, Color.WHITE, 2.0)
			draw_string(font, p + Vector2(-40, -30), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color.WHITE)

	for tp in trail:
		var c: Color = tp.c
		c.a = tp.a
		var sp := _to_screen(tp.p).round()
		draw_rect(Rect2(sp - Vector2(3, 3), Vector2(6, 6)), c)
	if probe_on:
		var pp := _to_screen(probe_pos).round()
		draw_rect(Rect2(pp - Vector2(6, 6), Vector2(12, 12)), Color.WHITE if fmod(t, 0.3) < 0.2 else Color(1, 0.3, 0.3))
		var bar := Rect2(size.x - 300, 24, 270, 22)
		draw_rect(bar, Color(0.1, 0.02, 0.02))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _prox, bar.size.y)), Color(1.0, 0.15, 0.15))
		draw_rect(bar, Color("ff5050"), false, 2.0)
		draw_string(font, Vector2(size.x - 300, 66), "ANOMALY SIGNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ff8a7a"))
