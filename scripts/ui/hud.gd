extends Control
## On-screen info, kept minimal and see-through: status readout, mission / pinned recipe / cargo / furnace
## lists, radar, messages, toasts, prompts and the warp readout. Text over the scene, hairline rules, no boxes.
##
## Each part is its own child canvas (PARTS), drawn by the matching function here through `_ci`, so the parts
## can come back on one at a time: after a warp, undocking or a respawn each flickers on in its own way.

const UI = preload("res://scripts/ui/ui.gd")
const RADAR_RANGE := 3000.0  # metres
const RADAR_R := 115.0
const SWEEP_SPEED := 1.6  # radians per second
const MARK := Color(0.95, 0.86, 0.6)  # landmarks (stations, gates, fields...)
# what else shows on the radar, and its colour (rocks take their ore's)
const RADAR_GROUPS := {"npcs": Color("9fc8e8"), "asteroids": Color.WHITE, "chunks": Color("eee0a0"), "crates": Color("c4a060"),
	"pirates": Color("ee5a4a")}
# part: flicker seed (each comes on differently)
const PARTS := {"markers": 1, "crosshair": 2, "status": 3, "side": 4, "radar": 5, "route": 6, "msgs": 7, "toast": 0,
	"title": 9, "warp": 0, "prompt": 10, "keys": 11, "hover": 12}

var main
var prompt := ""
var hover_text := ""
var font: Font
var boot := 99.0  # seconds since the HUD started coming back on
var _ci: CanvasItem  # the part being drawn
var _parts := {}
var _msgs := []
var _toasts := []
var _title := ""
var _title_sub := ""
var _title_color := Color.WHITE
var _title_t := 0.0
var _saved_t := 0.0
var _sweep := 0.0
var _marks := {}  # radar contacts as last painted by the sweep: key -> {off, color, size, kind, age}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	font = UI.body
	_ci = self
	Game.toast.connect(push_toast)
	Game.saved.connect(func(): _saved_t = 2.0)
	for p in PARTS:
		var c := Control.new()
		c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		c.mouse_filter = MOUSE_FILTER_IGNORE
		c.draw.connect(_draw_part.bind(p, c))
		add_child(c)
		_parts[p] = c


## Bring the HUD back on, part by part.
func flicker_in() -> void:
	boot = 0.0
	Sfx.play("beep", -20.0, 0.7)


## How visible a part is right now (for the overview and target panel too).
func part_alpha(part_seed: int) -> float:
	return 1.0 if part_seed == 0 else UI.flicker(boot, part_seed)


func push_message(text: String, color: Color) -> void:
	_msgs.append({"t": text, "c": color, "life": 8.0})
	if _msgs.size() > 7:
		_msgs.pop_front()


func push_toast(title: String, text: String, icon: String, color: Color) -> void:
	_toasts.append({"title": title, "text": text, "icon": icon, "c": color, "life": 5.0})


func show_title(text: String, color: Color, sub: String) -> void:
	_title = text
	_title_sub = sub
	_title_color = color
	_title_t = 4.0


func _process(delta: float) -> void:
	for m in _msgs:
		m.life -= delta
	_msgs = _msgs.filter(func(m): return m.life > 0.0)
	if not _toasts.is_empty():
		_toasts[0].life -= delta
		if _toasts[0].life <= 0.0:
			_toasts.pop_front()
	_title_t = maxf(0.0, _title_t - delta)
	_saved_t = maxf(0.0, _saved_t - delta)
	boot += delta
	_update_radar(delta)
	for p in _parts:
		_parts[p].modulate.a = part_alpha(PARTS[p])
		_parts[p].queue_redraw()


# ---------------------------------------------------------------- drawing helpers

func _text(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, f: Font = null) -> void:
	var use := f if f else font
	_ci.draw_string_outline(use, pos, text, align, width, font_size, 4, Color(0.0, 0.0, 0.0, color.a * 0.75))
	_ci.draw_string(use, pos, text, align, width, font_size, color)


## A small spaced-out heading with a hairline under it.
func _heading(pos: Vector2, text: String, color: Color, width: float) -> void:
	_text(pos, text, 13, color, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	_ci.draw_line(pos + Vector2(0, 7), pos + Vector2(width, 7), Color(color, 0.25), 1.0)


## A labelled hairline bar: label on the left, value on the right, the bar underneath.
func _bar(pos: Vector2, w: float, frac: float, color: Color, label: String, value: String) -> void:
	_text(pos, label, 14, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	_text(pos, value, 16, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_ci.draw_rect(Rect2(pos + Vector2(0, 7), Vector2(w, 3)), Color(1, 1, 1, 0.08))
	_ci.draw_rect(Rect2(pos + Vector2(0, 7), Vector2(w * clampf(frac, 0.0, 1.0), 3)), Color(color, 0.9))


# ---------------------------------------------------------------- the parts

func _draw_part(part: String, c: Control) -> void:
	if main == null or main.mode == "title":
		return
	_ci = c
	var vs := size
	var flying: bool = main.mode == "fly" and main.player.alive
	if main.mode == "warp":
		# warping: everything else gets out of the way
		if part == "warp":
			_text(Vector2(0, vs.y - 120.0), "warping...", 17, Color(UI.TEXT, 0.32), HORIZONTAL_ALIGNMENT_CENTER, vs.x, UI.title)
		elif part == "toast":
			_draw_toast(vs)
		return
	var p = main.player
	if not main.mode in ["fly", "dead"] and not part in ["msgs", "toast"]:
		return  # a menu is open: only the messages show through it
	match part:
		"markers":
			if main.mode in ["fly", "warp"] and p.alive:
				_draw_markers(vs)
		"crosshair":
			if flying:
				_draw_crosshair(vs)
		"status":
			if not main.debug:
				_draw_status(p, p.st)
		"side":
			if not main.debug:
				_draw_side_panels(vs, _status_bottom())
		"radar":
			if not main.debug:
				_draw_radar(Vector2(vs.x - RADAR_R - 40.0, vs.y - RADAR_R - 70.0))
		"route":
			_draw_route(vs)
		"msgs":
			var my := vs.y - 250.0
			for m in _msgs:
				var col: Color = m.c
				col.a = clampf(m.life, 0.0, 1.0)
				_text(Vector2(30, my), m.t, 18, col)
				my += 25.0
			if _saved_t > 0.0:
				_text(Vector2(30, vs.y - 54), "game saved", 14, Color(UI.GOOD, clampf(_saved_t, 0.0, 1.0) * 0.8))
		"toast":
			_draw_toast(vs)
		"title":
			# big title when entering a system
			if _title_t > 0.0 and not main.debug:
				var a := clampf(_title_t, 0.0, 1.0)
				_text(Vector2(0, vs.y * 0.3), _title, 46, Color(_title_color, a * 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x, UI.title)
				_text(Vector2(0, vs.y * 0.3 + 38), _title_sub, 19, Color(UI.TEXT, a * 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		"warp":
			if not main.travel.is_empty():
				_draw_travel(vs, main.travel)
		"prompt":
			if prompt != "":
				_text(Vector2(0, vs.y - 150), prompt, 22, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
			if main.command:
				_text(Vector2(0, vs.y - 44), "CURSOR FREE  -  click to select  -  C or ESC for mouse look", 14, Color(UI.GOLD, 0.85),
					HORIZONTAL_ALIGNMENT_CENTER, vs.x, UI.title)
		"keys":
			var keys := "W/S pitch   Q/E turn   A/D roll   R/F throttle   X brake   SHIFT boost   click fire   right-click select   1 approach   2 orbit   3 warp   5 cruise   G use   O collect   V scan   SPACE warp   T auto-travel   I inventory   L fitting   N/M maps   H guide"
			_text(Vector2(0, vs.y - 20), keys, 14, Color(UI.MUTED, 0.75), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		"hover":
			if hover_text != "":
				_text(Vector2(main.reticle.x - 400.0, main.reticle.y + 58.0), hover_text, 17, Color(UI.TEXT, 0.9),
					HORIZONTAL_ALIGNMENT_CENTER, 800.0)


## Achievements, missions and discoveries: a line of text across the top of the screen for a few seconds.
func _draw_toast(vs: Vector2) -> void:
	if _toasts.is_empty():
		return
	var t: Dictionary = _toasts[0]
	var a := clampf((5.0 - t.life) * 4.0, 0.0, 1.0) * clampf(t.life * 3.0, 0.0, 1.0)
	var y := 150.0
	_text(Vector2(0, y), t.title, 15, Color(t.c, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, UI.title)
	_ci.draw_line(Vector2(vs.x / 2.0 - 160.0, y + 10.0), Vector2(vs.x / 2.0 + 160.0, y + 10.0), Color(t.c, a * 0.35), 1.0)
	_text(Vector2(0, y + 36), t.text, 20, Color(UI.TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## The route along the top: where to, how many jumps, the next gate; and the autopilot / auto-travel state.
func _draw_route(vs: Vector2) -> void:
	var path := Game.route_path()
	if not path.is_empty():
		var dest: Dictionary = Game.systems[Game.route_target]
		var nxt: Dictionary = Game.systems[path[0]]
		var more := "" if Game.route_stops.is_empty() else "  (+%d stop%s)" % [Game.route_stops.size(), "" if Game.route_stops.size() == 1 else "s"]
		_text(Vector2(0, 36), "ROUTE  %s  -  %d jumps  -  next gate %s%s" % [dest.name.to_upper(), path.size(), nxt.name, more], 15, UI.GOLD,
			HORIZONTAL_ALIGNMENT_CENTER, vs.x, UI.title)
	if main.auto_travel and main.mode in ["fly", "warp"]:
		_text(Vector2(0, 36 if path.is_empty() else 56), "AUTO-TRAVEL  -  T to stop", 14, Color("8cd8ff"), HORIZONTAL_ALIGNMENT_CENTER,
			vs.x, UI.title)


## The crosshair in the middle of the screen (the turrets aim at whatever it's on), with a pip per turret
## under it: lit once that turret is on target with a clear shot, dim red if not (still swinging round, out
## of its arc, or your own hull in the way). A small ring marks where the ship's nose points.
func _draw_crosshair(_vs: Vector2) -> void:
	var c: Vector2 = main.reticle.round()
	var hostile: bool = main.aim_target != null and is_instance_valid(main.aim_target) and main.aim_target.is_in_group("pirates")
	var col := Color("ee6a5a") if hostile else Color(1, 1, 1, 0.85)
	_ci.draw_circle(c, 1.6, col)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_ci.draw_line(c + d * 8.0, c + d * 15.0, Color(col, 0.6), 1.5)
	var cam: Camera3D = main.camera
	var p = main.player
	if p.beam_lock != null and main.target_valid(p.beam_lock) and not cam.is_position_behind(p.beam_lock.global_position):
		# the mining beams' lock: a turning diamond on what they're cutting
		var lp := cam.unproject_position(p.beam_lock.global_position)
		var r := 14.0
		var a := Time.get_ticks_msec() / 400.0
		var pts := PackedVector2Array()
		for k in 5:
			pts.append(lp + Vector2.from_angle(a + k * PI / 2.0) * r)
		_ci.draw_polyline(pts, Color("66ffcc"), 1.5, true)
		_text(lp + Vector2(-150, 34), "beams locked  -  click to stop", 13, Color("66ffcc", 0.85), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	var guns: Array = p.guns_ready
	if not guns.is_empty():
		var clear := 0
		for i in guns.size():
			var gx := c.x + (i - (guns.size() - 1) / 2.0) * 7.0
			_ci.draw_circle(Vector2(gx, c.y + 24.0), 2.2, Color(0.75, 1.0, 0.85, 0.85) if guns[i] else Color(0.93, 0.4, 0.35, 0.45))
			clear += 1 if guns[i] else 0
		if clear == 0 and Input.is_action_pressed("fire"):
			_text(Vector2(c.x - 150.0, c.y + 44.0), "no turret can bear", 13, Color(0.93, 0.48, 0.42, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	var nose: Vector3 = p.position + p.forward() * (300.0 + p.radius * 4.0)
	if not cam.is_position_behind(nose):
		var n := cam.unproject_position(nose).round()
		if n.distance_to(c) > 6.0:
			_ci.draw_arc(n, 5.0, 0.0, TAU, 16, Color(0.6, 0.9, 1.0, 0.6), 1.5, true)


## Markers on the notable things here (and arrows at the screen edge when they're off-screen), plus red
## brackets and health bars on nearby pirates.
func _draw_markers(vs: Vector2) -> void:
	var cam: Camera3D = main.camera
	var pp: Vector3 = main.player.position
	for it in main.landmarks:
		_marker(vs, cam, it.pos, it.get("name", ""), it.get("icon", "station"), MARK, pp.distance_to(it.pos))
	_draw_selection(vs, cam, pp)
	_draw_bay(cam, pp)
	_draw_self(vs, cam)
	_draw_chunk_tags(cam, pp)
	for pir in main.group("pirates"):
		if not is_instance_valid(pir):
			continue
		var d: float = pp.distance_to(pir.position)
		if d > 500.0 + main.player.radius * 2.0 or cam.is_position_behind(pir.position):
			continue
		var sp := cam.unproject_position(pir.position)
		var half := clampf(pir.radius / maxf(d, 1.0) * vs.y * 0.9, 10.0, 90.0)
		var c := Color("ee5a4a") if pir.aggro else Color("e8a090")
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				var corner := sp + Vector2(sx, sy) * half
				_ci.draw_line(corner, corner - Vector2(sx * half * 0.35, 0), c, 1.5)
				_ci.draw_line(corner, corner - Vector2(0, sy * half * 0.35), c, 1.5)
		if pir.hp < pir.max_hp:
			var w := half * 2.0
			_ci.draw_rect(Rect2(sp.x - w / 2.0, sp.y - half - 10.0, w, 3), Color(1, 1, 1, 0.12))
			_ci.draw_rect(Rect2(sp.x - w / 2.0, sp.y - half - 10.0, w * pir.hp / pir.max_hp, 3),
				Color("b080ee") if pir.type == "sentinel" else Color("ee5a4a"))


func _marker(vs: Vector2, cam: Camera3D, pos: Vector3, label: String, icon: String, color: Color, dist: float) -> void:
	var behind := cam.is_position_behind(pos)
	var sp := cam.unproject_position(pos)
	var centre := vs / 2.0
	var margin := 70.0
	var on_screen := not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin
	var text := "%s  %s" % [label, UI.dist(dist)]
	if on_screen:
		UI.glyph(_ci, icon, sp, 7.0, Color(color, 0.9))
		_text(sp + Vector2(-150, 26), text, 15, Color(color, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 300)
	else:
		var dir := sp - centre
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		dir = dir.normalized()
		var edge := centre + dir * minf((vs.x / 2.0 - margin) / maxf(absf(dir.x), 0.001), (vs.y / 2.0 - margin) / maxf(absf(dir.y), 0.001))
		var tip := edge + dir * 12.0
		var side := dir.orthogonal() * 6.0
		_ci.draw_polyline(PackedVector2Array([edge - side, tip, edge + side]), Color(color, 0.8), 1.5, true)
		_text(edge - dir * 20.0 + Vector2(-150, 5), text, 14, Color(color, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 300)


## Where the side lists start: under the status readout and any blessings.
func _status_bottom() -> float:
	return 262.0 + Game.blessings.size() * 22.0


## Corner brackets round the selected target, wherever it is.
func _draw_selection(vs: Vector2, cam: Camera3D, pp: Vector3) -> void:
	var t = main.selected
	if not main.target_valid(t):
		return
	var pos: Vector3 = main.target_pos(t)
	if cam.is_position_behind(pos):
		return
	var sp := cam.unproject_position(pos)
	var d := cam.global_position.distance_to(pos)
	var half := clampf(main.target_size(t) / maxf(d, 1.0) * vs.y * 0.8, 14.0, vs.y * 0.3)
	var c := Color(UI.GOLD, 0.85)
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var corner := sp + Vector2(sx, sy) * half
			_ci.draw_line(corner, corner - Vector2(sx * minf(half * 0.4, 16.0), 0), c, 1.5)
			_ci.draw_line(corner, corner - Vector2(0, sy * minf(half * 0.4, 16.0)), c, 1.5)
	if not t is Dictionary:
		_text(sp + Vector2(-200, half + 20), "%s  %s" % [main.target_info(t).name, UI.dist(pp.distance_to(pos))], 15, c,
			HORIZONTAL_ALIGNMENT_CENTER, 400)


## Near a station or stargate, corner brackets round the mouth of its docking bay or barrel (and its
## distance), so it's easy to line up on. Fly in to dock, or to be fired down the gate.
func _draw_bay(cam: Camera3D, pp: Vector3) -> void:
	if main.player.st.get("capital", false):
		return  # (too big to fly in: capital ships dock by tether)
	for lm in main.landmarks:
		if lm.has("bay"):
			_bay_brackets(cam, pp, lm)


func _bay_brackets(cam: Camera3D, pp: Vector3, lm: Dictionary) -> void:
	var bay: Dictionary = lm.bay
	var m: Vector3 = bay.mouth
	if pp.distance_to(m) > 9000.0 or pp.distance_to(m) < 300.0:
		return  # (and not once you're at the mouth or inside: then it's all round you)
	var right: Vector3 = bay.right
	var up: Vector3 = right.cross(bay.out).normalized()
	var pts := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var w: Vector3 = m + right * c.x * bay.hw + up * c.y * bay.hh
		if cam.is_position_behind(w):
			return
		pts.append(cam.unproject_position(w))
	var col := Color(0.5, 0.95, 1.0, 0.75)
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		_ci.draw_line(a, a.lerp(b, 0.2), col, 1.5)
		_ci.draw_line(b, b.lerp(a, 0.2), col, 1.5)
	var e1: Vector2 = (pts[0] + pts[1]) / 2.0
	var e2: Vector2 = (pts[2] + pts[3]) / 2.0
	var top: Vector2 = e1 if e1.y < e2.y else e2  # label the upper edge
	var label := "DOCKING BAY" if lm.kind == "station" else "GATE"
	_text(top + Vector2(-150, -12), "%s  %s" % [label, UI.dist(pp.distance_to(m))], 14, col, HORIZONTAL_ALIGNMENT_CENTER, 300.0,
		UI.title)


## Zoomed far out your ship is a speck: mark it.
func _draw_self(_vs: Vector2, cam: Camera3D) -> void:
	if main.zoom < 6.0:
		return
	var p = main.player
	if cam.is_position_behind(p.position):
		return
	var sp := cam.unproject_position(p.position)
	var c := Color(0.6, 0.92, 1.0, clampf((main.zoom - 6.0) / 6.0, 0.0, 0.85))
	_ci.draw_arc(sp, 10.0, 0.0, TAU, 24, c, 1.5, true)
	var f: Vector3 = p.position + p.forward() * p.radius * 30.0
	if not cam.is_position_behind(f):
		var tip := cam.unproject_position(f)
		_ci.draw_line(sp + (tip - sp).limit_length(10.0), sp + (tip - sp).limit_length(24.0), c, 1.5)
	_text(sp + Vector2(-100, 28), "you", 13, c, HORIZONTAL_ALIGNMENT_CENTER, 200)


## Small rings on loose ore chunks near you, so they're easy to find against a huge rock.
func _draw_chunk_tags(cam: Camera3D, pp: Vector3) -> void:
	var reach: float = 900.0 + main.player.radius * 3.0
	for n in main.group("chunks"):
		if not is_instance_valid(n):
			continue
		var d: float = pp.distance_to(n.position)
		if d > reach or cam.is_position_behind(n.position):
			continue
		var sp := cam.unproject_position(n.position)
		var col: Color = Game.ORES[n.ore_id].color.lightened(0.3)
		_ci.draw_arc(sp, 6.0, 0.0, TAU, 12, Color(col, 0.7 if not n.tractored else 1.0), 1.5 if not n.tractored else 2.0, true)


## The warp readout, low on the screen: what's happening, where to, and a thin progress line.
func _draw_travel(vs: Vector2, trip: Dictionary) -> void:
	if trip.phase in ["exit", "chart"]:
		return
	var aligning: bool = trip.phase == "align"
	var charging: bool = trip.phase == "charge" or aligning
	var total: float = trip.charge if charging else trip.travel
	var frac := clampf(trip.t / total, 0.0, 1.0)
	var word: String = {"warp": "WARP", "local": "WARP", "wormhole": "WORMHOLE", "jumpdrive": "JUMP"}.get(trip.kind, "JUMP")
	var head := ("CHARGING %s DRIVE" % word) if charging else ("IN %s" % word if trip.kind != "jump" else "JUMPING")
	if trip.kind == "local" and not charging:
		head = "WARPING"
	if aligning:
		head = "ALIGNING"
		frac = 1.0 - clampf(main.player.forward().angle_to(trip.heading) / trip.align_total, 0.0, 1.0)
	var col := UI.GOLD if charging else Color("9fd0ee")
	var w := 520.0
	var x := (vs.x - w) / 2.0
	var y := vs.y - 118.0
	_text(Vector2(x, y), head, 14, col, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	_text(Vector2(x, y), "--" if aligning else "%.1fs" % maxf(0.0, total - trip.t), 16, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(0, y + 26), trip.dest, 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_ci.draw_rect(Rect2(x, y + 38, w, 2), Color(1, 1, 1, 0.1))
	_ci.draw_rect(Rect2(x, y + 38, w * frac, 2), col)
	if charging:
		_text(Vector2(0, y + 60), "ESC or X to cancel", 14, Color(UI.MUTED, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_status(p, st: Dictionary) -> void:
	var sys: Dictionary = Game.systems[Game.current_system]
	var loc: Dictionary = sys.locs[Game.current_loc]
	var cc: Color = Game.CAT_COLORS[sys.cat].lerp(UI.TEXT, 0.2)
	var reg: Dictionary = Game.REGIONS[sys.region]
	var x := 30.0
	var w := 340.0
	_text(Vector2(x, 44), sys.name.to_upper(), 21, cc, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	_text(Vector2(x, 44), reg.name, 15, Color(reg.color, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(x, 68), "%s system  -  %s" % [Game.CAT_NAMES[sys.cat], loc.name], 16, UI.MUTED)
	_bar(Vector2(x, 102), w, p.shield / maxf(st.shield, 1.0), Color("5fc8ee"), "SHIELD", "%d / %d" % [ceili(p.shield), st.shield])
	_bar(Vector2(x, 132), w, p.hull / maxf(st.hull, 1.0), Color("e8845a"), "HULL", "%d / %d" % [ceili(p.hull), st.hull])
	_bar(Vector2(x, 162), w, p.energy / maxf(st.energy, 1.0), Color("a890e0"), "BOOST",
		("%d  >>>" if p.boosting else "%d") % roundi(p.energy))
	var rev: bool = p.throttle < 0.0
	if not main.autopilot.is_empty():
		_bar(Vector2(x, 192), w, main.ap_power, Color("8cd8ff"), "AUTOPILOT  R/F", "power %d%%   %d m/s" % [roundi(main.ap_power * 100.0),
			roundi(p.vel.length())])
	else:
		_bar(Vector2(x, 192), w, absf(p.throttle), Color("e89a5a") if rev else Color("e8c66a"), "REVERSE" if rev else "THROTTLE",
			"%d%%   %d m/s" % [roundi(absf(p.throttle) * 100.0), roundi(p.vel.length())])
	var full: bool = Game.cargo_used() >= st.cargo
	var y := 226.0
	_text(Vector2(x, y), "%d cr" % Game.credits, 17, UI.GOLD)
	_text(Vector2(x + 96, y), "cargo %d / %d" % [Game.cargo_used(), st.cargo], 17, UI.BAD if full else UI.TEXT)
	var extra := "probes %d" % Game.probes
	if Game.portals > 0:
		extra += "   portals %d" % Game.portals
	_text(Vector2(x + 236, y), extra, 15, UI.TEXT)
	var by := 256.0
	if st.get("jump", 0.0) > 0.0:
		var cd: float = main._jump_cd
		_text(Vector2(x, by - 4), "JUMP DRIVE  %s" % ("ready  -  double-click a system on the map (M)" if cd <= 0.0 else "recharging %ds" % ceili(cd)),
			13, Color("c080ff"), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
		by += 20.0
	for b in Game.blessings:
		_text(Vector2(x, by), "Blessing of %s  %ds" % [b.capitalize(), ceili(Game.blessings[b])], 16, Color("d090ee"))
		by += 22.0


## Missions, pinned recipes, cargo and furnaces, down the left side under the status readout (the overview has
## the right).
func _draw_side_panels(vs: Vector2, top: float) -> void:
	var x := 30.0
	var w := 340.0
	var y := top + 24.0 + (20.0 if main.player.st.get("jump", 0.0) > 0.0 else 0.0)
	var limit := vs.y - 280.0
	if not Game.missions.is_empty():
		_heading(Vector2(x, y), "MISSIONS", UI.GOOD, w)
		y += 30.0
		for m in Game.missions:
			_text(Vector2(x, y), m.title, 16, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
			var prog := "%d / %d" % [m.have, m.need]
			if m.type == "deliver":
				prog = "%d / %d ready to turn in" % [mini(Game.have(m.ore), m.need), m.need]
			elif m.type == "explore":
				prog = "travel there"
			_text(Vector2(x, y + 19), prog, 14, UI.MUTED)
			y += 44.0
		y += 12.0
	if not Game.pinned.is_empty() and y + 60.0 < limit:
		_heading(Vector2(x, y), "PINNED", Color("8cd8ff"), w)
		y += 28.0
		for pin in Game.pinned:
			var cost := Game.build_cost(pin[0], pin[1])
			var ready := Game.can_afford(cost)
			_text(Vector2(x, y), Game.pin_name(pin), 16, UI.GOOD if ready else UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
			if ready:
				_text(Vector2(x, y), "ready to build", 13, UI.GOOD, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 19.0
			var cx := x
			for k in cost:
				var have: int = Game.have(k)
				var part := "%s %d/%d" % [Game.item_name(k), mini(have, cost[k]), cost[k]]
				var pw := font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
				if cx + pw > x + w:
					cx = x
					y += 17.0
				_text(Vector2(cx, y), part, 13, (Game.item_color(k) if have >= cost[k] else Color(Game.item_color(k), 0.55)).lerp(
					UI.GOOD if have >= cost[k] else UI.BAD, 0.35))
				cx += pw
			y += 24.0
		y += 6.0
	if not Game.cargo.is_empty() and y + 60.0 < limit:
		var keys := Game.cargo.keys()
		keys.sort()
		var more := 0
		var fit := maxi(1, floori((limit - y - 40.0) / 22.0))
		if keys.size() > fit:
			more = keys.size() - fit + 1
			keys = keys.slice(0, fit - 1)
		_heading(Vector2(x, y), "CARGO", UI.HEAD, w)
		y += 28.0
		for key in keys:
			var parts: PackedStringArray = key.split(":")
			var q := int(parts[1])
			_text(Vector2(x, y), ("%s  %s" % [Game.ORES[parts[0]].name, Game.q_tag(q).to_lower()]).strip_edges(), 16,
				Game.ORES[parts[0]].color.lerp(UI.TEXT, 0.3))
			_text(Vector2(x, y), "x%d" % Game.cargo[key], 16, Game.Q_COLORS[q].lerp(UI.TEXT, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 22.0
		if more > 0:
			_text(Vector2(x, y), "...and %d more (I)" % more, 15, UI.MUTED)
			y += 22.0
		y += 12.0
	# furnaces working (or finished) at stations around the galaxy
	var busy := []
	for key in Game.refineries:
		var r: Dictionary = Game.refineries[key]
		if not r.queue.is_empty() or not r.output.is_empty():
			busy.append(r)
	if not busy.is_empty() and y + 80.0 < limit:
		busy = busy.slice(0, clampi(floori((limit - y - 30.0) / 44.0), 1, 3))
		_heading(Vector2(x, y), "FURNACES", Color("e8a060"), w)
		y += 30.0
		for r in busy:
			_text(Vector2(x, y), r.name, 16, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
			if r.queue.is_empty():
				_text(Vector2(x, y + 19), "done - dock there to collect", 14, UI.GOOD)
			else:
				var left := 0
				for item in r.queue:
					left += item[2]
				var cur: Array = r.queue[0]
				var frac: float = r.progress / Game.refine_time(cur[0], cur[1])
				_ci.draw_rect(Rect2(x, y + 12, 140, 2), Color(1, 1, 1, 0.1))
				_ci.draw_rect(Rect2(x, y + 12, 140 * frac, 2), Color("e8a060"))
				_text(Vector2(x + 152, y + 19), "%d left  %s" % [left, _clock(Game.refinery_seconds_left(r))], 14, UI.MUTED)
			y += 44.0


func _clock(t: float) -> String:
	return UI.clock(t)


# ---------------------------------------------------------------- radar

## Radar contacts are only refreshed when the sweep line passes over them, like a real radar: each
## contact is painted at its position at that moment and fades until the line comes round again.
func _update_radar(delta: float) -> void:
	if main == null or main.mode == "title":
		return
	var prev := _sweep
	_sweep = fposmod(_sweep + SWEEP_SPEED * delta, TAU)
	var swept := fposmod(_sweep - prev, TAU)
	for k in _marks:
		_marks[k].age += delta
	var p = main.player
	var inv: Basis = p.global_transform.basis.inverse()
	var pp: Vector3 = p.position
	var k: float = RADAR_R / (RADAR_RANGE + p.radius * 4.0)
	var seen := {}
	for i in main.landmarks.size():
		var lm: Dictionary = main.landmarks[i]
		var key := "lm%d" % i
		seen[key] = true
		var l: Vector3 = inv * (lm.pos - pp)
		var off := Vector2(l.x, l.z) * k
		var behind := fposmod(_sweep - off.angle(), TAU)  # how far the line has gone past this contact
		if not _marks.has(key) or behind <= swept:
			_marks[key] = {"off": off, "color": MARK, "size": 5.0, "kind": lm.icon, "age": behind / SWEEP_SPEED}
	# (everything else, hundreds of rocks and chunks, is only worked out in full when the line paints it)
	for group in RADAR_GROUPS:
		for n in main.group(group):
			if not n.visible:
				continue
			var id: int = n.get_instance_id()
			seen[id] = true
			var l: Vector3 = inv * (n.position - pp)
			var off := Vector2(l.x, l.z) * k
			var behind := fposmod(_sweep - off.angle(), TAU)
			if _marks.has(id) and behind > swept:
				continue
			var col: Color = RADAR_GROUPS[group]
			var s := 3.0
			match group:
				"asteroids":
					col = Game.ORES[n.ore_id].color.darkened(0.25)
					s = clampf(n.radius * 0.05, 2.5, 7.0)
				"chunks":
					s = 1.6
				"pirates":
					s = 5.0 if n.data.has("boss") else 3.5
			_marks[id] = {"off": off, "color": col, "size": s, "kind": "pirate" if group == "pirates" else "", "age": behind / SWEEP_SPEED}
	for key in _marks.keys():
		if not seen.has(key):
			_marks.erase(key)


func _draw_radar(c: Vector2) -> void:
	_ci.draw_circle(c, RADAR_R, Color(0.0, 0.01, 0.015, 0.35))
	for r in [RADAR_R, RADAR_R * 0.66, RADAR_R * 0.33]:
		_ci.draw_arc(c, r, 0.0, TAU, 64, Color(0.7, 0.85, 1.0, 0.12 if r < RADAR_R else 0.22), 1.0, true)
	# the sweep, with a fading trail behind it
	for i in 14:
		var a := _sweep - i * 0.035
		_ci.draw_line(c, c + Vector2.from_angle(a) * RADAR_R, Color(0.6, 0.9, 1.0, 0.3 * (1.0 - i / 14.0)), 1.5, true)
	var period := TAU / SWEEP_SPEED
	for key in _marks:
		var m: Dictionary = _marks[key]
		var off: Vector2 = m.off
		var landmark: bool = str(key).begins_with("lm")
		if off.length() > RADAR_R - 4.0:
			if not landmark:
				continue
			off = off.limit_length(RADAR_R - 4.0)
		var fade := clampf(1.0 - m.age / period, 0.12, 1.0)
		var col := Color(m.color, fade)
		var pos := c + off
		if landmark or m.kind == "pirate":
			UI.glyph(_ci, m.kind if m.kind != "" else "ore", pos, m.size, col)
		else:
			_ci.draw_circle(pos, m.size * 0.5, col)
	_text(c + Vector2(-RADAR_R, RADAR_R + 22.0), UI.dist(RADAR_RANGE + main.player.radius * 4.0), 13, Color(UI.MUTED, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER, RADAR_R * 2.0)
