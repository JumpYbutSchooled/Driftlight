extends CenterContainer
## Save codes: shows the current save as a code to copy (Save Code), or takes a pasted one and makes it this
## slot's save (Load Code), so a game can be carried to another device. See Game.save_code / import_code.

const UI = preload("res://scripts/ui/ui.gd")

var main
var _title: Label
var _hint: Label
var _text: TextEdit
var _status: Label
var _copy: Button
var _paste: Button
var _load: Button
var _importing := false
var _on_loaded: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # (it opens over the paused ESC menu too)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_title = UI.heading("", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_hint = UI.lbl("", 17, UI.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(860, 0)
	v.add_child(_hint)
	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(860, 230)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.add_theme_font_size_override("font_size", 14)
	v.add_child(_text)
	_status = UI.lbl("", 17, UI.GOOD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(860, 0)
	v.add_child(_status)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	_copy = UI.btn("Copy to clipboard", _do_copy)
	_paste = UI.btn("Paste from clipboard", _do_paste)
	_load = UI.btn("Load this save", _do_load)
	var close_btn := UI.btn("Close", close)
	for b in [_copy, _paste, _load, close_btn]:
		b.custom_minimum_size = Vector2(210, 46)
		h.add_child(b)


## Show the current save as a code.
func open_export() -> void:
	var code := Game.save_code()
	_importing = false
	_title.text = "SAVE CODE"
	_hint.text = "Copy this whole code and keep it somewhere safe (a message to yourself works). On another device, choose Load Code on the title screen and paste it there to carry on from this exact point. It holds your whole save, so it's long."
	_text.text = code
	_text.editable = false
	_status.text = "" if code != "" else "There's no save to make a code from yet."
	_status.add_theme_color_override("font_color", UI.GOOD if code != "" else UI.BAD)
	_copy.visible = code != ""
	_paste.visible = false
	_load.visible = false
	_show()
	if code != "":
		_text.select_all()


## Ask for a code and make it this slot's save. `on_loaded` is called once it has been.
func open_import(on_loaded := Callable()) -> void:
	_importing = true
	_on_loaded = on_loaded
	_title.text = "LOAD CODE"
	_hint.text = "Paste a save code from another device. It replaces your current %s save (the old one is kept in the backups folder), then you can press Continue." % (
		"Sandbox" if Game.sandbox else "pilot")
	_text.text = ""
	_text.editable = true
	_status.text = ""
	_copy.visible = false
	_paste.visible = true
	_load.visible = true
	_show()
	_text.grab_focus()


func _show() -> void:
	show()
	UI.pop_in(self)


func close() -> void:
	hide()


func _do_copy() -> void:
	DisplayServer.clipboard_set(_text.text)
	_status.text = "Copied. (%d characters)" % _text.text.length()
	_status.add_theme_color_override("font_color", UI.GOOD)
	Sfx.play("click", -10.0)


func _do_paste() -> void:
	_text.text = DisplayServer.clipboard_get().strip_edges()
	_status.text = ""


func _do_load() -> void:
	var err := Game.import_code(_text.text)
	if err != "":
		_status.text = err
		_status.add_theme_color_override("font_color", UI.BAD)
		return
	Sfx.play("found", -6.0)
	if _on_loaded.is_valid():
		_on_loaded.call()
	_status.text = "Save loaded. Close this and press Continue."
	_status.add_theme_color_override("font_color", UI.GOOD)
	_load.visible = false
	_paste.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("close"):
		close()
		get_viewport().set_input_as_handled()
