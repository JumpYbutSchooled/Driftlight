extends CenterContainer
## ESC menu: pauses the game. Resume, save, volume settings, quit to title or desktop.

const UI = preload("res://scripts/ui/ui.gd")

var main


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var h := UI.heading("PAUSED", 28)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	v.add_child(HSeparator.new())
	for b in [["Resume", close, "throttle"], ["Save Game", _save, "cargo"]]:
		var btn := UI.btn(b[0], b[1], b[2], UI.HEAD)
		btn.custom_minimum_size = Vector2(0, 52)
		v.add_child(btn)
	v.add_child(UI.heading("VOLUME", 12, UI.MUTED))
	for bus in ["Master", "Music", "SFX"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var l := UI.lbl(bus, 19)
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = Sfx.volumes[bus]
		s.size_flags_horizontal = SIZE_EXPAND_FILL
		s.size_flags_vertical = SIZE_SHRINK_CENTER
		s.focus_mode = FOCUS_NONE
		s.value_changed.connect(_volume.bind(bus))
		row.add_child(s)
		v.add_child(row)
	v.add_child(HSeparator.new())
	for b in [["Save & Quit to Title", _to_title, "gate"], ["Quit to Desktop", _quit, "skull"]]:
		var btn := UI.btn(b[0], b[1], b[2], UI.BAD if b[0].begins_with("Quit") else UI.TEXT)
		btn.custom_minimum_size = Vector2(0, 52)
		v.add_child(btn)


func open() -> void:
	show()
	# the game is paused, so main won't release the mouse or switch the cursor: do it here
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.set_cursor("arrow")
	get_tree().paused = true


func close() -> void:
	hide()
	get_tree().paused = false
	Sfx.save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("close"):
		close()
		get_viewport().set_input_as_handled()


func _volume(v: float, bus: String) -> void:
	Sfx.set_volume(bus, v)


func _save() -> void:
	Game.save_game()
	Game.say("Game saved.", UI.GOOD)
	close()


func _to_title() -> void:
	close()
	main.quit_to_title()


func _quit() -> void:
	Game.save_game()
	Sfx.save_settings()
	get_tree().quit()
