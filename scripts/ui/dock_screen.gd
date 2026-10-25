extends Control
## The black screen round docking. Docking: the view fades to black under "DOCKING" while the clamps take
## the ship, and stays black behind the station menus. Undocking: a startup sequence on the black screen -
## the ship's systems coming online one by one - then the view fades back in with the ship on the pad.

const UI = preload("res://scripts/ui/ui.gd")
const STARTUP := [["DOCKING CLAMPS", "RELEASED"], ["REACTOR", "ONLINE"], ["LIFE SUPPORT", "NOMINAL"],
	["SHIELDS", "CHARGED"], ["THRUSTERS", "ONLINE"], ["NAVIGATION", "ONLINE"], ["WEAPONS", "SAFE"]]
const LINE_GAP := 0.14  # seconds between startup lines
const DOCK_TIME := 0.75  # seconds of fade to black while docking

var main
var _state := "off"  # off, docking, docked, launch
var _t := 0.0
var _black := 0.0  # 0..1 cover
var _title := ""
var _done: Callable
var _shown := 0  # startup lines printed so far


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


## Fade to black over the docking, then call `done` (which opens the station).
func dock(station_name: String, done: Callable) -> void:
	_state = "docking"
	_t = 0.0
	_title = station_name
	_done = done
	visible = true


## Undock: the startup sequence on the black screen, then fade the view back in and call `done`.
func launch(done: Callable) -> void:
	_state = "launch"
	_t = 0.0
	_shown = 0
	_black = 1.0
	_done = done
	visible = true
	Sfx.play("charge", -10.0, 0.7)


func busy() -> bool:
	return _state in ["docking", "launch"]


## Off at once (quitting to the title, dying).
func reset() -> void:
	_state = "off"
	_black = 0.0
	visible = false


func _process(delta: float) -> void:
	if _state == "off":
		return
	_t += delta
	match _state:
		"docking":
			_black = clampf(_t / (DOCK_TIME * 0.75), 0.0, 1.0)
			if _t >= DOCK_TIME:
				_state = "docked"
				Sfx.play("dock", -4.0)
				_done.call()
		"docked":
			_black = 1.0
		"launch":
			var lines := floori(_t / LINE_GAP)
			if lines > _shown and _shown < STARTUP.size():
				_shown = mini(lines, STARTUP.size())
				Sfx.play("beep", -16.0, 0.8 + _shown * 0.05)
			var fade_from := STARTUP.size() * LINE_GAP + 0.3
			_black = 1.0 - clampf((_t - fade_from) / 0.5, 0.0, 1.0)
			if _t >= fade_from + 0.5:
				_state = "off"
				visible = false
				_done.call()
	queue_redraw()


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, _black))
	var a := _black
	match _state:
		"docking":
			var cy := vs.y * 0.5
			_text(Vector2(0, cy - 10), "DOCKING", 26, Color(UI.HEAD, a * 0.9), vs.x, UI.title)
			_text(Vector2(0, cy + 24), _title, 18, Color(UI.MUTED, a * 0.8), vs.x)
			var w := 260.0
			var k := clampf(_t / DOCK_TIME, 0.0, 1.0)
			draw_rect(Rect2((vs.x - w) / 2.0, cy + 44, w, 2), Color(1, 1, 1, 0.1 * a))
			draw_rect(Rect2((vs.x - w) / 2.0, cy + 44, w * k, 2), Color(UI.GOLD, 0.8 * a))
		"launch":
			var x := vs.x / 2.0 - 230.0
			var y := vs.y / 2.0 - STARTUP.size() * 15.0 - 20.0
			_text(Vector2(0, y - 26), "SYSTEMS STARTUP", 16, Color(UI.MUTED, a * 0.8), vs.x, UI.title)
			for i in _shown:
				var line: Array = STARTUP[i]
				var ly := y + 14 + i * 30.0
				var fresh := clampf((_t - (i + 1) * LINE_GAP) * 4.0, 0.0, 1.0)
				_text(Vector2(x, ly), line[0], 17, Color(UI.TEXT, a * 0.85), -1.0, UI.title, HORIZONTAL_ALIGNMENT_LEFT)
				draw_line(Vector2(x + 190, ly - 5), Vector2(x + 330, ly - 5), Color(1, 1, 1, 0.12 * a), 1.0)
				_text(Vector2(x + 340, ly), line[1], 17, Color(UI.GOOD, a * fresh), -1.0, UI.title, HORIZONTAL_ALIGNMENT_LEFT)
			if _shown >= STARTUP.size():
				_text(Vector2(0, y + 14 + STARTUP.size() * 30.0 + 26), "CLEAR TO LAUNCH", 20, Color(UI.GOLD, a), vs.x, UI.title)


func _text(pos: Vector2, text: String, font_size: int, color: Color, width := -1.0, f: Font = null,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string(f if f else UI.body, pos, text, align, width, font_size, color)
