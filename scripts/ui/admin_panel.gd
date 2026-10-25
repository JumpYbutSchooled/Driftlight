extends CenterContainer
## F8 on the admin save: god mode, fill your hangar and holds, reveal the galaxy, jump to any system,
## finish every furnace, call in pirates. Only the admin slot (which only opens on the admin device) has it.

const UI = preload("res://scripts/ui/ui.gd")

var main
var _god_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var h := UI.heading("ADMIN", 26, UI.GOLD)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var note := UI.lbl("Everything is free on this save. Double-click a system on the galaxy map (M) to jump straight there.", 16,
		UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	v.add_child(HSeparator.new())
	_god_btn = _button(v, "", _toggle_god)
	_label_god()
	_button(v, "Fill everything  (all ships, gear, ores, spices, credits)", _fill)
	_button(v, "Reveal the galaxy  (visit, scan and find everything)", _reveal)
	_button(v, "Jump to a system...", _jump)
	_button(v, "Repair and recharge", _repair)
	_button(v, "Finish every furnace", _furnaces)
	_button(v, "Call in a pirate wave here", _pirates)
	v.add_child(HSeparator.new())
	_button(v, "Close  (F8 / Esc)", close)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := UI.btn(text, cb)
	b.custom_minimum_size = Vector2(0, 44)
	parent.add_child(b)
	return b


func open() -> void:
	_label_god()
	show()


func close() -> void:
	hide()
	if main.mode == "admin":
		main.mode = "fly"


func _label_god() -> void:
	_god_btn.text = "God mode: %s" % ("ON - nothing can hurt you" if Game.god else "OFF")


func _toggle_god() -> void:
	Game.god = not Game.god
	_label_god()


func _fill() -> void:
	Game.admin_fill()
	Game.say("Admin: hangar, holds and wallet filled.", UI.GOLD)


func _reveal() -> void:
	Game.admin_reveal()
	Game.say("Admin: the whole galaxy is charted.", UI.GOLD)


func _jump() -> void:
	close()
	main.mode = "map"
	main.galaxy_map.open()


func _repair() -> void:
	main.player.heal_full()
	Game.say("Admin: hull, shields and boost restored.", UI.GOLD)


func _furnaces() -> void:
	Game.tick_refineries(1.0e9)
	Game.say("Admin: every furnace is done - dock to collect.", UI.GOLD)


func _pirates() -> void:
	close()
	main.call_pirates()
