extends CenterContainer
## A yes/no popup, used for the Wild-system warning.

const UI = preload("res://scripts/ui/ui.gd")

var _label: Label
var _yes: Button
var _on_yes: Callable
var _on_no: Callable
var _check: CheckBox  # an optional "don't ask again" box
var _on_check: Callable  # called with whether it was ticked, once you say yes


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.frame("danger", 28))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	_label = UI.lbl("", 20)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(640, 0)
	v.add_child(_label)
	_check = CheckBox.new()
	_check.focus_mode = FOCUS_NONE
	_check.visible = false
	_check.size_flags_horizontal = SIZE_SHRINK_CENTER
	v.add_child(_check)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	_yes = UI.btn("", _answer.bind(true))
	_yes.custom_minimum_size = Vector2(200, 48)
	h.add_child(_yes)
	var no := UI.btn("Cancel", _answer.bind(false))
	no.custom_minimum_size = Vector2(200, 48)
	h.add_child(no)


## `check_text`: adds a checkbox with that label; `on_check` is called with its state when you say yes.
func ask(text: String, yes_text: String, on_yes: Callable, on_no: Callable, check_text := "", on_check := Callable()) -> void:
	_label.text = text
	_yes.text = yes_text
	_on_yes = on_yes
	_on_no = on_no
	_check.visible = check_text != ""
	_check.text = check_text
	_check.button_pressed = false
	_on_check = on_check
	show()


func _answer(yes: bool) -> void:
	hide()
	if yes:
		if _check.visible and _on_check.is_valid():
			_on_check.call(_check.button_pressed)
		_on_yes.call()
	else:
		_on_no.call()
