extends Label3D
## A floating damage number that pops up, drifts upward and fades. Always readable: same size on screen
## and drawn on top.

var _t := 0.0
var _drift := Vector3.ZERO


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true
	pixel_size = 0.0009
	font_size = 34
	outline_size = 10
	outline_modulate = Color(0, 0, 0, 0.85)
	font = ThemeDB.fallback_font
	_drift = Vector3(randf_range(-1.5, 1.5), 4.0, 0)


func _process(delta: float) -> void:
	_t += delta
	position += _drift * delta
	_drift *= pow(0.2, delta)
	modulate.a = clampf((0.8 - _t) * 3.0, 0.0, 1.0)
	outline_modulate.a = modulate.a * 0.85
	if _t > 0.8:
		queue_free()
