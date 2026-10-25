extends Node3D
## A floating cargo container. Shoot it open for ore and a few credits.

var main
var hp := 20.0
var radius := 2.2
var _drift := Vector3.ZERO
var _spin := Vector3.ZERO


func _ready() -> void:
	add_child(Models.prop("crate"))
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_drift = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 0.8
	_spin = Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
	add_to_group("crates")


func describe() -> String:
	return "Cargo container  -  shoot it open"


func _process(delta: float) -> void:
	position += _drift * delta
	rotation += _spin * delta


func take_damage(dmg: float) -> void:
	hp -= dmg
	main.dmg_number(position + Vector3.UP * 2.0, dmg, Color.WHITE)
	if hp <= 0.0 and not is_queued_for_deletion():
		var sys: Dictionary = Game.systems[Game.current_system]
		main.explosion(position, 0.8, Color("c49a3c"))
		for i in randi_range(3, 7):
			var roll := Game.roll_ore(sys, false)
			var out := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			main.spawn_chunk(roll[0], roll[1], 1, position, out * randf_range(5.0, 12.0))
		var cr: int = randi_range(3, 12) * (sys.cat + 1)
		Game.add_credits(cr)
		Game.say("Container cracked open!  +%d credits" % cr, Color("ffd24a"))
		queue_free()
