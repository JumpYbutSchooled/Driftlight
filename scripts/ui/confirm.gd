extends CenterContainer
## A yes/no popup, used for the Wild-system warning.

const UI = preload("res://scripts/ui/ui.gd")

var _label: Label
var _yes: Button
var _on_yes: Callable
var _on_no: Callable


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


func ask(text: String, yes_text: String, on_yes: Callable, on_no: Callable) -> void:
	_label.text = text
	_yes.text = yes_text
	_on_yes = on_yes
	_on_no = on_no
	show()


func _answer(yes: bool) -> void:
	hide()
	if yes:
		_on_yes.call()
	else:
		_on_no.call()
