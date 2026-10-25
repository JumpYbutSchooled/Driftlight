extends Node3D
## A derelict ship drifting in space, sparking now and then. Fly close and press G to salvage it (once).

var salvaged := false
var _spin := Vector3.ZERO
var _model: Node3D
var _spark_t := 1.0
var main


func _ready() -> void:
	_model = Models.prop("wreck")
	add_child(_model)
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_spin = Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
	var light := OmniLight3D.new()
	light.light_color = Color("ff6a2a")
	light.light_energy = 2.5
	light.omni_range = 120.0
	add_child(light)
	add_to_group("wrecks")


func _process(delta: float) -> void:
	rotation += _spin * delta
	if not salvaged and main:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = randf_range(0.6, 2.5)
			main.sparks(global_position + Vector3(randf_range(-12, 12), randf_range(-4, 8), randf_range(-16, 16)), Color("ffb36b"), 8)


func mark_salvaged() -> void:
	salvaged = true
	for c in get_children():
		if c is OmniLight3D:
			c.visible = false
