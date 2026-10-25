extends Node
## The mouse cursor: a plain dot while flying; in menus a ring pops up around the dot (and shrinks
## away again when you go back to flying). Over buttons the ring turns gold. Runs while paused too.

const POP_TIME := 0.22  # seconds for the ring to pop in or out

var target := 0.0  # 0 = dot (flying), 1 = ring (menus)
var _p := 0.0
var _frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var last: int = Pix.RING_FRAMES.size() - 1
	Input.set_custom_mouse_cursor(Pix.cursor_ring(last, Color("ffd24a")), Input.CURSOR_POINTING_HAND, Pix.RING_HOTSPOT)
	_apply()


func _process(delta: float) -> void:
	_p = move_toward(_p, target, delta / POP_TIME)
	_apply()


func _apply() -> void:
	var f := roundi(_p * (Pix.RING_FRAMES.size() - 1))
	if f != _frame:
		_frame = f
		Input.set_custom_mouse_cursor(Pix.cursor_ring(f), Input.CURSOR_ARROW, Pix.RING_HOTSPOT)


func _exit_tree() -> void:
	# let go of the custom cursor textures so nothing leaks at shutdown
	Input.set_custom_mouse_cursor(null)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
