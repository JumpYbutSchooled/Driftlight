extends CenterContainer
## Ship fitting (L): your ship turning slowly in its own little hangar view with every turret numbered, and
## beside it a row per turret to choose the weapon it carries, plus the ship's modules. Works anywhere
## (spare weapons and modules live in your ship's stores). Swapping a weapon puts the old one back in store.

const UI = preload("res://scripts/ui/ui.gd")
const Turrets = preload("res://scripts/turrets.gd")

var main
var _view: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _guns
var _overlay: Control
var _model_id := ""
var _list: VBoxContainer
var _title: Label
var _sel := -1  # the turret slot picked in the list (highlighted in the view)
var _spin := 0.0
var _dist := 10.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 860)
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(tv)
	_title = UI.heading("SHIP FITTING", 24)
	tv.add_child(_title)
	tv.add_child(UI.lbl("Choose the weapon on each turret. Press L or Esc to close.", 16, UI.MUTED))
	var close := UI.btn("Close", func(): main.close_fitting())
	close.custom_minimum_size = Vector2(150, 52)
	close.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	# the hangar view
	var vc := SubViewportContainer.new()
	vc.custom_minimum_size = Vector2(760, 700)
	vc.stretch = true
	body.add_child(vc)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	vc.add_child(_view)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.8, 0.6, 0.0)
	key.light_energy = 2.2
	key.shadow_enabled = true
	_view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, 2.8, 0.0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.6, 0.75, 1.0)
	_view.add_child(rim)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_view.add_child(_cam)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_labels)
	vc.add_child(_overlay)
	# the turret list
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	Game.changed.connect(_on_changed)


func _on_changed() -> void:
	if visible:
		_rebuild()


func open() -> void:
	_sel = -1
	_rebuild()
	show()
	UI.pop_in(get_child(0))


func _process(delta: float) -> void:
	if not visible or _model == null:
		return
	_spin += delta * 0.25
	_pivot.rotation.y = _spin
	_cam.position = Vector3(sin(0.6) * _dist, _dist * 0.45, cos(0.6) * _dist)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	# the picked turret tracks a point circling the ship, so you can see which one it is
	var t := Time.get_ticks_msec() / 1000.0
	if _sel >= 0 and _sel < _guns.list.size():
		var aim := Vector3(cos(t * 1.4), 0.4, sin(t * 1.4)) * _dist
		var tu: Dictionary = _guns.list[_sel]
		var local: Vector3 = tu.base.global_transform.affine_inverse() * aim
		tu.yaw.rotation.y = rotate_toward(tu.yaw.rotation.y, atan2(-local.x, -local.z), Turrets.YAW_SPEED * delta)
	_overlay.queue_redraw()


func _rebuild() -> void:
	if _model_id != Game.ship_id:
		_build_model()
	elif _guns != null and str(_guns.list.map(func(tu): return tu.kind)) != str(_kinds()):
		_guns.build(_kinds())  # each weapon has its own turret
	var ship: Dictionary = Game.SHIPS[Game.ship_id]
	_title.text = "SHIP FITTING  -  %s  (%s)" % [ship.name, ship["class"]]
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var lo := Game.loadout()
	_list.add_child(UI.heading("TURRETS  (%d)" % lo.size(), 18))
	_list.add_child(UI.lbl("Every weapon reaches as far as you can see. Empty turrets carry the free Blaster.", 15, UI.MUTED))
	for i in lo.size():
		_list.add_child(_slot_row(i, lo[i]))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.add_child(UI.btn("All Blasters", Game.mount_all.bind(Game.BLASTER), "weapon"))
	for id in Game.WEAPON_ORDER:
		if id != Game.BLASTER and Game.spare_weapon(id) > 0 and bar.get_child_count() < 4:
			bar.add_child(UI.btn("Fill with %s" % Game.WEAPONS[id].name, Game.mount_all.bind(id), "weapon", Game.WEAPONS[id].color))
	_list.add_child(bar)
	var st := Game.stats_ship()
	_list.add_child(UI.heading("MODULES  (%d / %d)" % [Game.modules_equipped.size(), st.slots], 18))
	for i in Game.modules_equipped.size():
		var mid: String = Game.modules_equipped[i]
		var m: Dictionary = Game.MODULES[mid]
		_list.add_child(_module_row(mid, m.name + "   installed", m.desc, "Remove", Game.unequip_module.bind(i), true))
	for id in Game.MODULE_ORDER:
		var n: int = Game.spare_module(id)
		if n > 0:
			var m: Dictionary = Game.MODULES[id]
			_list.add_child(_module_row(id, "%s  x%d" % [m.name, n], m.desc, "Install", Game.equip_module.bind(id),
				Game.modules_equipped.size() < st.slots and Game.module_fits(id)))
	if Game.modules_equipped.is_empty() and Game.MODULE_ORDER.all(func(m): return Game.spare_module(m) <= 0):
		_list.add_child(UI.lbl("No modules yet: build them in a station's Fabricator, or find them in wrecks.", 15, UI.MUTED))


## One turret: its number and where it sits, the weapon on it (pick another from your stores), and what
## that weapon does.
func _slot_row(i: int, current: String) -> Control:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", UI.frame("card", 10))
	var v := VBoxContainer.new()
	cell.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var w: Dictionary = Game.WEAPONS[current]
	var num := UI.btn(str(i + 1), _pick_slot.bind(i), "", UI.GOLD if i == _sel else UI.TEXT)
	num.custom_minimum_size = Vector2(44, 40)
	h.add_child(num)
	var where := UI.lbl(_where(i), 16, UI.MUTED)
	where.custom_minimum_size = Vector2(170, 0)
	h.add_child(where)
	h.add_child(UI.icon_rect("weapon", w.color, 3))
	var pick := OptionButton.new()
	pick.focus_mode = FOCUS_NONE
	pick.size_flags_horizontal = SIZE_EXPAND_FILL
	pick.add_theme_font_override("font", UI.bold)
	var ids := []
	for id in Game.WEAPON_ORDER:
		var spare: int = Game.spare_weapon(id)
		if id == Game.BLASTER or id == current or spare > 0:
			pick.add_item(Game.WEAPONS[id].name + ("" if id == Game.BLASTER or id == current else "  (%d spare)" % spare))
			ids.append(id)
	pick.selected = ids.find(current)
	pick.item_selected.connect(_choose.bind(i, ids))
	h.add_child(pick)
	v.add_child(UI.lbl(weapon_line(w), 14, Color(w.color).lerp(UI.TEXT, 0.5)))
	return cell


## A module: its kind's icon and colour (so the kinds are easy to tell apart), name, what it does, a button.
func _module_row(id: String, title: String, desc: String, action: String, cb: Callable, enabled: bool) -> Control:
	var col := Game.module_color(id)
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", UI.frame("card", 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	cell.add_child(h)
	h.add_child(UI.icon_rect(Game.module_icon(id), col, 3))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UI.lbl("%s   %s" % [title, Game.MODULE_CATS[Game.MODULES[id].cat].name.to_upper()], 16, col.lerp(UI.TEXT, 0.25)))
	var d := UI.lbl(desc, 14, UI.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var b := UI.btn(action, cb)
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(110, 40)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(b)
	return cell


func _kinds() -> Array:
	return Game.loadout().map(func(w): return Game.WEAPONS[w].base)


static func weapon_line(w: Dictionary) -> String:
	var t := "Damage %.0f   %.1f shots/s   Mining %.1f" % [w.damage, w.rate, w.mining]
	if w.get("pellets", 1) > 1:
		t += "   %d pellets" % w.pellets
	if w.get("pierce", 0) > 0:
		t += "   pierces %d" % w.pierce
	if w.get("homing", 0.0) > 0.0:
		t += "   homing"
	if w.get("slow", 0.0) > 0.0:
		t += "   freezes"
	return t


func _choose(index: int, slot: int, ids: Array) -> void:
	_sel = slot
	Game.mount(slot, ids[index])


func _pick_slot(slot: int) -> void:
	_sel = slot
	_rebuild()


## Where a turret sits: on top, underneath or on a flank, and fore, amidships or aft.
func _where(i: int) -> String:
	if i >= _guns.list.size():
		return ""
	var base: Node3D = _guns.list[i].base
	var tf: Transform3D = _model.global_transform.affine_inverse() * base.global_transform
	var up := tf.basis.y.normalized()
	var face := "top" if up.y > 0.7 else ("underside" if up.y < -0.7 else ("right flank" if up.x > 0 else "left flank"))
	var length: float = Models.size(Game.ship_id).z
	var z := tf.origin.z
	var along := "fore" if z < -length * 0.15 else ("aft" if z > length * 0.15 else "amidships")
	return "%s, %s" % [face, along]


func _build_model() -> void:
	_model_id = Game.ship_id
	if _model:
		_model.queue_free()
	_model = Models.ship(Game.ship_id)
	_pivot.add_child(_model)
	_guns = Turrets.new(_model, _kinds())
	var size := Models.size(Game.ship_id)
	_dist = maxf(size.x, size.z) * 1.55 + 3.0
	_cam.far = _dist * 10.0


## Turret numbers over the view, each at its turret (the picked one gold).
func _draw_labels() -> void:
	if _guns == null:
		return
	var f := UI.title
	for i in _guns.list.size():
		var p: Vector3 = _guns.list[i].base.global_position
		if _cam.is_position_behind(p):
			continue
		var sp := _cam.unproject_position(p)
		var col := UI.GOLD if i == _sel else Color(0.75, 0.9, 1.0, 0.9)
		_overlay.draw_circle(sp, 13.0, Color(0, 0, 0, 0.55))
		_overlay.draw_arc(sp, 13.0, 0.0, TAU, 24, col, 1.5, true)
		_overlay.draw_string(f, sp + Vector2(-12, 6), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 24, 16, col)
