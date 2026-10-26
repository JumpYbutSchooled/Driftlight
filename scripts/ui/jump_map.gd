extends Control
## The jump map: when a warp between systems finishes, the galaxy map takes the screen and swoops from the
## system you left to the one you're reaching - a comet runs along the route, the view pulls back and pushes in -
## then the new system loads behind it and the map fades away. main drives it: play() as the tunnel ends,
## finish() once the arrival has happened behind it.

const UI = preload("res://scripts/ui/ui.gd")
const DURATION := 2.4  # seconds the map holds the screen before main arrives behind it
const FADE_IN := 0.3
const FADE_OUT := 0.9
const RUN_FROM := 0.35  # the comet leaves the old system...
const RUN_TO := 1.7  # ...and reaches the new one

var main
var _t := -1.0
var _out := -1.0  # seconds since the arrival (the map is fading away), -1 before it
var _from := 0
var _to := 0
var _pinged := false
var _center := Vector2.ZERO
var _zoom := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


func play(from_id: int, to_id: int) -> void:
	_from = from_id
	_to = to_id
	_t = 0.0
	_out = -1.0
	_pinged = false
	visible = true


## The arrival happened behind the map: let it fade away.
func finish() -> void:
	_out = 0.0


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _out >= 0.0:
		_out += delta
		if _out >= FADE_OUT:
			_t = -1.0
			visible = false
			return
	if not _pinged and _t >= RUN_TO:
		_pinged = true
		Sfx.play("found", -12.0, 1.5)
	queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + (p - _center) * _zoom


func _draw() -> void:
	if _t < 0.0:
		return
	var a := clampf(_t / FADE_IN, 0.0, 1.0)
	if _out >= 0.0:
		a *= 1.0 - smoothstep(0.0, 1.0, clampf(_out / FADE_OUT, 0.0, 1.0))
	var A: Dictionary = Game.systems[_from]
	var B: Dictionary = Game.systems[_to]
	var span: float = A.pos.distance_to(B.pos)
	# the run along the route, eased, and the view: it follows the comet, pulling back for long jumps
	var u := smoothstep(0.0, 1.0, clampf((_t - RUN_FROM) / (RUN_TO - RUN_FROM), 0.0, 1.0))
	var z_near := 2.1
	var z_far := clampf(minf(size.x, size.y) * 0.5 / maxf(span, 1.0), 0.28, z_near)
	var land := clampf((_t - RUN_TO) / (DURATION - RUN_TO), 0.0, 1.0)  # the slow push-in on the new system
	_center = A.pos.lerp(B.pos, u)
	_zoom = lerpf(z_near, z_far, sin(PI * u)) * (0.85 + 0.15 * smoothstep(0.0, 1.0, minf(_t / 0.8, 1.0))) * (1.0 + 0.18 * land)
	var head: Vector2 = A.pos.lerp(B.pos, u)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.012, 0.03, 0.96 * a))
	var view := Rect2(Vector2.ZERO, size).grow(300.0)
	var sz := roundf(clampf(4.0 * _zoom + 3.0, 4.0, 13.0))
	# regions tinted under everything, then the lanes
	for s in Game.systems:
		var p := _to_screen(s.pos)
		if view.has_point(p) and s.region > 0:
			draw_circle(p, sz * 3.4, Color(Game.REGIONS[s.region].color, 0.05 * a))
	for s in Game.systems:
		var p := _to_screen(s.pos)
		for l in s.links:
			if l > s.id:
				var q := _to_screen(Game.systems[l].pos)
				if view.has_point(p) or view.has_point(q):
					draw_line(p, q, Color(0.5, 0.6, 0.8, 0.16 * a), 1.0)
	# the route: a faint dashed line the whole way, a bright trail behind the comet
	var pa := _to_screen(A.pos)
	var pb := _to_screen(B.pos)
	var dashes := maxi(2, floori(pa.distance_to(pb) / 14.0))
	for i in range(0, dashes, 2):
		draw_line(pa.lerp(pb, float(i) / dashes), pa.lerp(pb, float(i + 1) / dashes), Color("ffe066", 0.28 * a), 1.5)
	var ph := _to_screen(head)
	var trail := 26
	for i in trail:
		var k0 := float(i) / trail
		var k1 := float(i + 1) / trail
		var col := Color("ffe9a0", (0.12 + 0.88 * k1 * k1) * a)
		draw_line(pa.lerp(ph, k0), pa.lerp(ph, k1), col, 1.5 + 2.5 * k1)
	# systems, with the names of the ones the comet is passing
	for s in Game.systems:
		var p := _to_screen(s.pos).round()
		if p.x < -20.0 or p.y < -20.0 or p.x > size.x + 20.0 or p.y > size.y + 20.0:
			continue
		var c: Color = Game.CAT_COLORS[s.cat]
		if not s.visited:
			c = c.darkened(0.4)
		var near := 1.0 - clampf(s.pos.distance_to(head) / (150.0 if _t < RUN_TO else 110.0), 0.0, 1.0)
		var big := 1.0 + near * 0.6
		var r := Vector2(sz, sz) * big
		draw_rect(Rect2(p - r / 2.0, r), Color(c, (0.75 + 0.25 * near) * a))
		if s.visited:
			draw_rect(Rect2(p - (r + Vector2(6, 6)) / 2.0, r + Vector2(6, 6)), Color(c, a), false, 1.0)
		if near > 0.15 and s.id != _to and s.id != _from:
			draw_string(UI.body, p + Vector2(-80, sz + 16), s.name, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(c, near * a))
	# the old system, ringed and quiet
	draw_arc(pa, 13.0, 0.0, TAU, 28, Color(0.7, 0.8, 0.95, 0.55 * a), 1.5)
	draw_string(UI.title, pa + Vector2(-120, -22), A.name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 240, 13, Color(0.7, 0.8, 0.95, 0.7 * a))
	# the new one: ringed in its colour, pulsing out once the comet gets there
	var cb: Color = Game.CAT_COLORS[B.cat]
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	draw_arc(pb, 15.0 + pulse * 3.0, 0.0, TAU, 32, Color(cb, (0.4 + 0.6 * u) * a), 2.0)
	if _t > RUN_TO:
		for k in 2:
			var w := fposmod((_t - RUN_TO) * 0.9 - k * 0.45, 1.4)
			draw_arc(pb, 16.0 + w * 150.0, 0.0, TAU, 48, Color(cb, 0.55 * (1.0 - w / 1.4) * a), 1.5, true)
	# the comet's head
	draw_circle(ph, 15.0, Color("fff3c0", 0.16 * a))
	draw_circle(ph, 6.0, Color("fff3c0", 0.45 * a))
	draw_circle(ph, 2.6, Color(1, 1, 1, a))
	# the caption, rising in as the comet lands
	var reveal := smoothstep(0.0, 1.0, clampf((_t - (RUN_TO - 0.35)) / 0.5, 0.0, 1.0)) * a
	var y := size.y * 0.74
	draw_line(Vector2(size.x / 2.0 - 190.0, y - 34.0), Vector2(size.x / 2.0 + 190.0, y - 34.0), Color(cb, 0.5 * reveal), 1.0)
	draw_string(UI.title, Vector2(0, y - 46.0), "JUMP COMPLETE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(UI.MUTED, 0.9 * reveal))
	draw_string(UI.title, Vector2(0, y + 6.0), B.name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(cb.lerp(Color.WHITE, 0.25), reveal))
	draw_string(UI.body, Vector2(0, y + 38.0), "%s System  -  %s" % [Game.CAT_NAMES[B.cat], Game.REGIONS[B.region].name],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, Color(UI.TEXT, 0.8 * reveal))
