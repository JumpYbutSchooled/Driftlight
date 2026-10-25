extends CenterContainer
## The hold-SPACE quick warp menu. While it's open the mouse is captured: moving it up and down (or the
## wheel) moves the highlight, and releasing SPACE (or clicking) warps to the highlighted entry. The first
## entry is Cancel, and it's selected by default, so a quick tap of SPACE does nothing.

const UI = preload("res://scripts/ui/ui.gd")
const STEP := 46.0  # mouse pixels of movement per row

var main
var _list: VBoxContainer
var _title: Label
var _sub: Label
var _built_sys := -1  # the system this list was built for
var _rows := []  # {"loc": location index or -1 for Cancel, "button": Button}
var _selected := 0
var _acc := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_title = UI.heading("", 18)
	v.add_child(_title)
	_sub = UI.lbl("", 16, UI.MUTED)
	v.add_child(_sub)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	v.add_child(_list)


func _process(_delta: float) -> void:
	# never show a stale list: if the system changed while the menu is up, rebuild it
	if visible and _built_sys != Game.current_system:
		open()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_acc += event.relative.y
		while _acc >= STEP:
			_acc -= STEP
			_move(1)
		while _acc <= -STEP:
			_acc += STEP
			_move(-1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN: _move(1)
			MOUSE_BUTTON_WHEEL_UP: _move(-1)
			MOUSE_BUTTON_LEFT: main.confirm_warp_menu()
		get_viewport().set_input_as_handled()


## The location to warp to if the menu closed now, or -1 for Cancel.
func selected_loc() -> int:
	return _rows[_selected].loc if _selected < _rows.size() else -1


func _move(d: int) -> void:
	var i := clampi(_selected + d, 0, _rows.size() - 1)
	if i != _selected:
		_selected = i
		Sfx.play("hover", -10.0)
		_highlight()


func _highlight() -> void:
	for k in _rows.size():
		var b: Button = _rows[k].button
		b.button_pressed = k == _selected
		var base: String = _rows[k].text
		b.text = ("> " + base) if k == _selected else ("   " + base)


func open() -> void:
	_built_sys = Game.current_system
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows = []
	_acc = 0.0
	var sys: Dictionary = Game.systems[Game.current_system]
	_title.text = "WARP  -  " + sys.name.to_upper()
	_title.add_theme_color_override("font_color", Game.CAT_COLORS[sys.cat])
	_sub.text = "Move the mouse up/down to choose.  Release SPACE to warp.  Pick Cancel to stay put."
	_add_row(-1, "Cancel", "skull", UI.BAD, UI.TEXT)
	# places across this location, kilometres away (warp entries 1000+ are landmark indices)
	var here := []
	for k in main.landmarks.size():
		if main.player.position.distance_to(main.landmarks[k].pos) > main.LOCAL_WARP_MIN:
			here.append(k)
	if not here.is_empty():
		_list.add_child(UI.heading("HERE  (ACROSS THIS LOCATION)", 12, UI.MUTED))
		for k in here:
			var lm: Dictionary = main.landmarks[k]
			_add_row(1000 + k, "%s    %s away" % [lm.name, UI.dist(main.player.position.distance_to(lm.pos))], lm.icon,
				Color("ffe066"), UI.TEXT)
	var path := Game.route_path()
	var next_hop: int = path[0] if not path.is_empty() else -1
	for group in [["planet", "PLANETS IN THIS SYSTEM"], ["gate", "STARGATES (LEAVE THIS SYSTEM)"], ["anomaly", "ANOMALIES"]]:
		var idx := []
		for i in sys.locs.size():
			var l: Dictionary = sys.locs[i]
			if l.kind == group[0] and (l.kind != "anomaly" or l.found) and i != Game.current_loc:
				idx.append(i)
		if idx.is_empty():
			continue
		_list.add_child(UI.heading(group[1], 12, UI.MUTED))
		for i in idx:
			_add_loc(sys, i, next_hop)
	_list.add_child(UI.lbl("You are at: " + sys.locs[Game.current_loc].name, 15, UI.MUTED))
	_selected = 0
	_highlight()
	show()


func _add_loc(sys: Dictionary, i: int, next_hop: int) -> void:
	var l: Dictionary = sys.locs[i]
	var text := ""
	var col := UI.TEXT
	var icon := "planet"
	var icon_col := Color.WHITE
	match l.kind:
		"planet":
			text = "%s    %s" % [l.name, Game.loc_summary(l)]
			icon_col = Game.PLANET_COLORS[l.planet_type]
			if not l.scanned:
				col = UI.MUTED
			elif l.pirates:
				col = Color("ffa08f")
			if l.station:
				icon = "station"
		"gate":
			var d: Dictionary = Game.systems[l.gate_to]
			text = "Stargate to %s    (%s space)" % [d.name, Game.CAT_NAMES[d.cat]]
			col = Game.CAT_COLORS[d.cat]
			icon = "gate"
			icon_col = col
			if l.gate_to == next_hop:
				text += "      << ROUTE"
				col = UI.GOLD
		"anomaly":
			text = "%s    %s" % [l.name, Game.loc_summary(l)]
			col = Color("e080ff")
			icon = "anomaly"
			icon_col = col
	_add_row(i, text, icon, icon_col, col)


func _add_row(loc: int, text: String, _icon: String, _icon_col: Color, col: Color) -> void:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_IGNORE  # chosen with mouse movement, not by pointing
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(820, 44)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_pressed_color", UI.GOLD)
	_list.add_child(b)
	_rows.append({"loc": loc, "button": b, "text": text})
