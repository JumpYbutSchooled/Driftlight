extends Control
## EVE-style overview in the top-right corner: everything worth knowing about at this location (stations,
## gates, ore veins and loose ore, wrecks, ships), with distances. Filter lines along the top narrow it to one
## kind of thing (veins and loose ore separately), to ore of at least a given quality and to one ore; the sort
## line orders it by distance, name, ore (rarest first), quality or amount (click the active one again to flip
## it). The list scrolls with the wheel. With the cursor free (C) you click a row to select it.

const UI = preload("res://scripts/ui/ui.gd")
const ROWS := 16  # rows shown at once
const ROW_H := 24.0
const W := 430.0
const TOP := 150.0  # rows start under the filter lines
const CATS := [["all", "ALL"], ["places", "PLACES"], ["ships", "SHIPS"], ["veins", "VEINS"], ["loose", "LOOSE ORE"], ["loot", "LOOT"]]
const QUALS := [[-1, "ANY"], [1, "NORMAL+"], [2, "SUPERIOR+"], [3, "PRISTINE"]]
const SORTS := [["dist", "DIST"], ["name", "NAME"], ["ore", "ORE"], ["quality", "QUALITY"], ["size", "AMOUNT"]]

var main
var cat := "all"  # which kind of thing to list
var minq := -1  # lowest ore quality to list (-1: any, unscanned veins included)
var ore := ""  # only this ore ("" any)
var sort := "dist"
var reverse := false
var _rows := []  # see main.overview_rows
var _ores_here := []  # ores among what's listed (for the ore filter line)
var _refresh := 0.0
var _hover := -1
var _scroll := 0
var _chips := []  # [Rect2, kind, value] for the filter / sort buttons, as last drawn


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	visible = main.mode == "fly" and main.player.alive and not main.debug
	if not visible:
		return
	modulate.a = main.hud.part_alpha(13)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.3
		_rows = main.overview_rows(cat, minq, ore, sort, reverse)
		var seen := {}
		var pool: String = cat if cat in ["veins", "loose"] else "ore"
		for r in main.overview_rows(pool, minq):
			if r.ore != "":
				seen[r.ore] = true
		_ores_here = Game.ORE_ORDER.filter(func(o): return seen.has(o) or o == ore)
		_scroll = clampi(_scroll, 0, maxi(0, _rows.size() - ROWS))
	var vs := get_viewport_rect().size
	position = Vector2(vs.x - W - 24.0, 18.0)
	size = Vector2(W, TOP + ROWS * ROW_H + 34.0)
	queue_redraw()


func _row_at(p: Vector2) -> int:
	var i := floori((p.y - TOP) / ROW_H)
	return i + _scroll if p.y >= TOP and i < ROWS and i + _scroll < _rows.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _row_at(event.position)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll = maxi(0, _scroll - 2)
				accept_event()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll = clampi(_scroll + 2, 0, maxi(0, _rows.size() - ROWS))
				accept_event()
				return
		for c in _chips:
			if (c[0] as Rect2).has_point(event.position) and event.button_index == MOUSE_BUTTON_LEFT:
				match c[1]:
					"cat":
						cat = c[2]
						ore = ""
					"q": minq = c[2]
					"ore": ore = c[2] if ore != c[2] else ""
					"sort":
						reverse = not reverse if sort == c[2] else false
						sort = c[2]
				_refresh = 0.0
				_scroll = 0
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.005, 0.01, 0.3))
	_text(Vector2(12, 26), "OVERVIEW", 13, Color(0.75, 0.85, 0.95, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	_text(Vector2(0, 26), "%d listed" % _rows.size(), 14, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 12)
	draw_line(Vector2(12, 34), Vector2(size.x - 12, 34), UI.LINE, 1.0)
	_chips = []
	_chip_row(CATS, "cat", cat, 56.0)
	_chip_row(QUALS, "q", minq, 80.0, "QUALITY ")
	_ore_row(104.0)
	var sorts := []
	for s in SORTS:
		sorts.append([s[0], (s[1] + (" ^" if reverse else " v")) if s[0] == sort else s[1]])
	_chip_row(sorts, "sort", sort, 128.0, "SORT ")
	draw_line(Vector2(12, TOP - 6), Vector2(size.x - 12, TOP - 6), UI.LINE, 1.0)
	for k in mini(ROWS, _rows.size() - _scroll):
		var i := k + _scroll
		var r: Dictionary = _rows[i]
		if not main.target_valid(r.t):
			continue
		var y := TOP + k * ROW_H
		var sel: bool = main.is_selected(r.t)
		if sel:
			draw_rect(Rect2(6, y, size.x - 12, ROW_H - 2), Color(0.91, 0.78, 0.42, 0.1))
			draw_rect(Rect2(6, y, 2, ROW_H - 2), UI.GOLD)
		elif i == _hover:
			draw_rect(Rect2(6, y, size.x - 12, ROW_H - 2), Color(1, 1, 1, 0.06))
		UI.glyph(self, r.icon, Vector2(24, y + ROW_H * 0.5 - 1), 5.5, Color(r.color, 0.9))
		_text(Vector2(42, y + 17), r.name, 15, UI.GOLD if sel else r.color.lerp(UI.TEXT, 0.55), HORIZONTAL_ALIGNMENT_LEFT, 260)
		if r.ore != "":
			_text(Vector2(0, y + 17), "x%d" % r.size, 13, Color(UI.MUTED, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 92)
		_text(Vector2(0, y + 17), UI.dist(r.dist), 15, Color(UI.TEXT, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 12)
	if _rows.is_empty():
		_text(Vector2(0, TOP + 18), "nothing matches" if cat != "all" or minq >= 0 or ore != "" else "nothing nearby", 14, UI.MUTED,
			HORIZONTAL_ALIGNMENT_CENTER, size.x)
	elif _rows.size() > ROWS:
		# a scroll bar down the right edge
		var h := ROWS * ROW_H
		var bar_h := maxf(18.0, h * ROWS / _rows.size())
		var by := TOP + (h - bar_h) * _scroll / maxf(1.0, _rows.size() - ROWS)
		draw_rect(Rect2(size.x - 5, TOP, 2, h), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(size.x - 5, by, 2, bar_h), Color(0.75, 0.85, 0.95, 0.5))
	var hint := "wheel: scroll   click: select   double-click: approach   right-click: warp"
	_text(Vector2(0, size.y - 10), hint, 12, Color(UI.MUTED, 0.7), HORIZONTAL_ALIGNMENT_CENTER, size.x)


## One line of filter buttons: the active one bright and underlined, the others dim.
func _chip_row(items: Array, kind: String, current, y: float, label := "") -> void:
	var x := 12.0
	if label != "":
		_text(Vector2(x, y), label, 11, Color(UI.MUTED, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
		x += UI.title.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 6.0
	for it in items:
		var on: bool = it[0] == current
		var w := UI.title.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 6.0
		var col := Color(0.9, 0.82, 0.55, 0.95) if on else Color(0.7, 0.78, 0.88, 0.45)
		_text(Vector2(x, y), it[1], 11, col, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
		if on:
			draw_line(Vector2(x, y + 5), Vector2(x + w - 6, y + 5), Color(col, 0.7), 1.0)
		_chips.append([Rect2(x - 3, y - 15, w + 2, 22), kind, it[0]])
		x += w + 10.0


## The ores present here, each a chip in its own colour: click one to list only that ore, again for all.
func _ore_row(y: float) -> void:
	var x := 12.0
	_text(Vector2(x, y), "ORE ", 11, Color(UI.MUTED, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
	x += 36.0
	if _ores_here.is_empty():
		_text(Vector2(x, y), "none in reach", 12, Color(UI.MUTED, 0.5))
		return
	for o in _ores_here:
		var on: bool = o == ore
		var nm: String = Game.ORES[o].name.substr(0, 4).to_upper()
		var w := UI.title.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 6.0
		if x + w > size.x - 8.0:
			break
		var col: Color = Game.ORES[o].color
		_text(Vector2(x, y), nm, 11, Color(col, 1.0 if on or ore == "" else 0.4), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.title)
		if on:
			draw_line(Vector2(x, y + 5), Vector2(x + w - 6, y + 5), col, 1.0)
		_chips.append([Rect2(x - 3, y - 15, w + 2, 22), "ore", o])
		x += w + 8.0
