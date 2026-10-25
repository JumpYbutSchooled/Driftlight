extends Control
## EVE-style overview in the top-right corner: everything worth knowing about at this location (stations,
## gates, ore veins and loose ore, wrecks, ships), nearest first, with distances. Filters along the top
## narrow it to one kind of thing and to ore of at least a given quality. With the cursor free (C) you click
## a row to select it; the selected row is highlighted and its target panel opens at the top of the screen.

const UI = preload("res://scripts/ui/ui.gd")
const ROWS := 14
const ROW_H := 25.0
const W := 380.0
const TOP := 96.0  # rows start under the two filter lines
const CATS := [["all", "ALL"], ["places", "PLACES"], ["ships", "SHIPS"], ["ore", "ORE"], ["loot", "LOOT"]]
const QUALS := [[-1, "ANY ORE"], [1, "NORMAL+"], [2, "SUPERIOR+"], [3, "PRISTINE"]]

var main
var _rows := []  # {"t": target, "name", "icon", "color"}
var _refresh := 0.0
var _hover := -1
var _frame: StyleBox
var cat := "all"  # which kind of thing to list
var minq := -1  # lowest ore quality to list (-1: any, unscanned veins included)
var _chips := []  # [Rect2, "cat" or "q", value] for the filter buttons, as last drawn


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_frame = UI.frame("panel")


func _process(delta: float) -> void:
	visible = main.mode == "fly" and main.player.alive and not main.debug
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.3
		_rows = main.overview_entries(ROWS, cat, minq)
	var vs := get_viewport_rect().size
	position = Vector2(vs.x - W - 24.0, 18.0)
	size = Vector2(W, TOP + maxf(1, _rows.size()) * ROW_H + 40.0)
	queue_redraw()


func _row_at(p: Vector2) -> int:
	var i := floori((p.y - TOP) / ROW_H)
	return i if p.y >= TOP and i < _rows.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _row_at(event.position)
	elif event is InputEventMouseButton and event.pressed:
		for c in _chips:
			if (c[0] as Rect2).has_point(event.position) and event.button_index == MOUSE_BUTTON_LEFT:
				if c[1] == "cat":
					cat = c[2]
				else:
					minq = c[2]
				_refresh = 0.0
				Sfx.play("click", -10.0)
				accept_event()
				return
		var i := _row_at(event.position)
		if i >= 0:
			if event.button_index == MOUSE_BUTTON_LEFT:
				main.select(_rows[i].t)
				if event.double_click:
					main.order("approach")
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				main.select(_rows[i].t)
				main.order("warp")
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _text(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		f: Font = null) -> void:
	var use := f if f else UI.body
	draw_string_outline(use, pos, text, align, width, font_size, 4, Color(0.0, 0.0, 0.0, color.a * 0.6))
	draw_string(use, pos, text, align, width, font_size, color)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.005, 0.01, 0.28))
	_text(Vector2(12, 26), "OVERVIEW", 13, Color(0.75, 0.85, 0.95, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	_text(Vector2(0, 26), "%d nearby" % _rows.size(), 14, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 12)
	draw_line(Vector2(12, 34), Vector2(size.x - 12, 34), UI.LINE, 1.0)
	_chips = []
	_chip_row(CATS, "cat", cat, 56.0)
	_chip_row(QUALS, "q", minq, 80.0)
	var pp: Vector3 = main.player.position
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if not main.target_valid(r.t):
			continue
		var y := TOP + i * ROW_H
		var sel: bool = main.is_selected(r.t)
		if sel:
			draw_rect(Rect2(6, y, size.x - 12, ROW_H - 2), Color(0.91, 0.78, 0.42, 0.1))
			draw_rect(Rect2(6, y, 2, ROW_H - 2), UI.GOLD)
		elif i == _hover:
			draw_rect(Rect2(6, y, size.x - 12, ROW_H - 2), Color(1, 1, 1, 0.06))
		UI.glyph(self, r.icon, Vector2(24, y + ROW_H * 0.5 - 1), 5.5, Color(r.color, 0.9))
		_text(Vector2(42, y + 17), r.name, 16, UI.GOLD if sel else r.color.lerp(UI.TEXT, 0.55), HORIZONTAL_ALIGNMENT_LEFT, 250)
		_text(Vector2(0, y + 17), UI.dist(pp.distance_to(main.target_pos(r.t))), 15, Color(UI.TEXT, 0.85), HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 12)
	if _rows.is_empty():
		_text(Vector2(0, TOP + 18), "nothing matches" if cat != "all" or minq >= 0 else "nothing nearby", 14, UI.MUTED,
			HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var hint := "click: select   double-click: approach   right-click: warp"
	_text(Vector2(0, size.y - 12), hint, 13, Color(UI.MUTED, 0.7), HORIZONTAL_ALIGNMENT_CENTER, size.x)


## One line of filter buttons: the active one bright and underlined, the others dim.
func _chip_row(items: Array, kind: String, current, y: float) -> void:
	var x := 12.0
	for it in items:
		var on: bool = it[0] == current
		var w := UI.title.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6.0
		var col := Color(0.9, 0.82, 0.55, 0.95) if on else Color(0.7, 0.78, 0.88, 0.45)
		_text(Vector2(x, y), it[1], 12, col, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
		if on:
			draw_line(Vector2(x, y + 5), Vector2(x + w - 6, y + 5), Color(col, 0.7), 1.0)
		_chips.append([Rect2(x - 3, y - 15, w + 2, 22), kind, it[0]])
		x += w + 12.0