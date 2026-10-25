extends CenterContainer
## F8 in the Sandbox: god mode, peaceful space, fill your hangar and holds, reveal the galaxy, jump to any
## system, finish every furnace, call in any kind of pirate, drop an ore field of any ore in front of you.
## Anyone can play the Sandbox (its own save slot; nothing there touches your pilot).

const UI = preload("res://scripts/ui/ui.gd")

var main
var _god_btn: Button
var _peace_btn: Button
var _pirate := OptionButton.new()
var _ore := OptionButton.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var h := UI.heading("SANDBOX", 26, UI.GOLD)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var note := UI.lbl("Everything is free here. Double-click a system on the galaxy map (M) to jump straight there.", 16, UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	v.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_god_btn = _button(row, "", _toggle_god)
	_god_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_peace_btn = _button(row, "", _toggle_peace)
	_peace_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_button(v, "Fill everything  (all ships, gear, ores, spices, credits)", _fill)
	_button(v, "Reveal the galaxy  (visit, scan and find everything)", _reveal)
	_button(v, "Jump to a system...", _jump)
	_button(v, "Repair and recharge", _repair)
	_button(v, "Finish every furnace", _furnaces)
	v.add_child(UI.heading("SPAWN", 13, UI.MUTED))
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	v.add_child(pr)
	_pirate.focus_mode = FOCUS_NONE
	_pirate.size_flags_horizontal = SIZE_EXPAND_FILL
	_pirate.add_item("A pirate wave (the usual mix)")
	for id in Game.ENEMIES:
		_pirate.add_item("3 x %s" % Game.ENEMIES[id].name)
	pr.add_child(_pirate)
	var pb := _button(pr, "Call them in", _pirates)
	pb.custom_minimum_size = Vector2(180, 44)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 10)
	v.add_child(orow)
	_ore.focus_mode = FOCUS_NONE
	_ore.size_flags_horizontal = SIZE_EXPAND_FILL
	_ore.add_item("An ore field (this system's mix)")
	for id in Game.ORE_ORDER:
		_ore.add_item("A field of %s" % Game.ORES[id].name)
	orow.add_child(_ore)
	var ob := _button(orow, "Spawn ahead", _field)
	ob.custom_minimum_size = Vector2(180, 44)
	v.add_child(HSeparator.new())
	_button(v, "Close  (F8 / Esc)", close)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := UI.btn(text, cb)
	b.custom_minimum_size = Vector2(0, 44)
	parent.add_child(b)
	return b


func open() -> void:
	_label()
	show()
	UI.pop_in(get_child(0))


func close() -> void:
	hide()
	if main.mode == "admin":
		main.mode = "fly"


func _label() -> void:
	_god_btn.text = "God mode: %s" % ("ON" if Game.god else "OFF")
	_peace_btn.text = "Peaceful: %s" % ("ON - no pirates" if Game.peaceful else "OFF")


func _toggle_god() -> void:
	Game.god = not Game.god
	_label()


func _toggle_peace() -> void:
	Game.peaceful = not Game.peaceful
	if Game.peaceful:
		for p in main.get_tree().get_nodes_in_group("pirates"):
			p.queue_free()
	_label()


func _fill() -> void:
	Game.sandbox_fill()
	Game.say("Sandbox: hangar, holds and wallet filled.", UI.GOLD)


func _reveal() -> void:
	Game.sandbox_reveal()
	Game.say("Sandbox: the whole galaxy is charted.", UI.GOLD)


func _jump() -> void:
	close()
	main.mode = "map"
	main.galaxy_map.open()


func _repair() -> void:
	main.player.heal_full()
	Game.say("Sandbox: hull, shields and boost restored.", UI.GOLD)


func _furnaces() -> void:
	Game.tick_refineries(1.0e9)
	Game.say("Sandbox: every furnace is done - dock to collect.", UI.GOLD)


func _pirates() -> void:
	var i := _pirate.selected
	close()
	if i <= 0:
		main.call_pirates()
	else:
		main.call_pirates(Game.ENEMIES.keys()[i - 1], 3)


func _field() -> void:
	var i := _ore.selected
	close()
	main.spawn_field_here("" if i <= 0 else Game.ORE_ORDER[i - 1])
	Game.say("Sandbox: an ore field, 3.5 km ahead.", UI.GOLD)
