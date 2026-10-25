extends Control
## The selected target, at the top of the screen: what it is, how far, and what you can do with it.
## Approach (Q) flies you to it, Orbit (R) circles it, Warp (F) jumps you across the location to it when
## it's far, and Dock / Jump / Use (G) flies there and uses it. The buttons can be clicked too.

const UI = preload("res://scripts/ui/ui.gd")
const W := 600.0
const H := 112.0

var main
var _frame: StyleBox
var _buttons := []  # {"rect": Rect2, "order": String}
var _hover := ""


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_frame = UI.frame("panel")


func _process(_delta: float) -> void:
	visible = main.mode == "fly" and main.player.alive and main.target_valid(main.selected) and not main.debug
	if not visible:
		return
	var vs := get_viewport_rect().size
	position = Vector2((vs.x - W) / 2.0, 62.0 if Game.route_path().is_empty() else 66.0)
	size = Vector2(W, H)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = ""
		for b in _buttons:
			if b.rect.has_point(event.position) and b.enabled:
				_hover = b.order
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for b in _buttons:
			if b.rect.has_point(event.position) and b.enabled:
				Sfx.play("click", -8.0)
				main.order(b.order)
		accept_event()


func _text(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		f: Font = null) -> void:
	var use := f if f else UI.body
	draw_string_outline(use, pos, text, align, width, font_size, 4, Color(0.0, 0.0, 0.0, color.a * 0.6))
	draw_string(use, pos, text, align, width, font_size, color)


func _draw() -> void:
	var t = main.selected
	if not main.target_valid(t):
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.005, 0.01, 0.28))
	var info: Dictionary = main.target_info(t)
	var col: Color = info.color
	UI.glyph(self, info.icon, Vector2(26, 30), 8.0, col)
	_text(Vector2(48, 38), info.name, 21, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400)
	var d: float = main.player.position.distance_to(main.target_pos(t))
	_text(Vector2(0, 38), UI.dist(d), 21, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14)
	var sub: String = info.sub
	if not main.autopilot.is_empty():
		sub = main.autopilot_text()
	_text(Vector2(48, 60), sub, 15, Color("9fd0ee") if not main.autopilot.is_empty() else UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 540)
	_buttons = []
	var orders := [["approach", "1  Approach"], ["orbit", "2  Orbit"], ["warp", "3  Warp to"]]
	if info.use != "":
		orders.append(["use", "G  " + info.use])
	var bw := (size.x - 28.0 - (orders.size() - 1) * 8.0) / orders.size()
	for i in orders.size():
		var r := Rect2(14 + i * (bw + 8.0), 74, bw, 28)
		var enabled: bool = main.order_ok(orders[i][0])
		var active: bool = main.autopilot.get("mode", "") == orders[i][0]
		var c := UI.GOLD if active else (UI.TEXT if enabled else Color(UI.MUTED, 0.5))
		if active or _hover == orders[i][0]:
			draw_rect(r, Color(0.91, 0.78, 0.42, 0.1) if active else Color(1, 1, 1, 0.06))
		draw_line(r.position + Vector2(0, r.size.y), r.end, Color(c, 0.45), 1.0)
		_text(Vector2(r.position.x, r.position.y + 19), orders[i][1], 15, c, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_buttons.append({"rect": r, "order": orders[i][0], "enabled": enabled})
