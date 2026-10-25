extends Node3D
## A bolt in 3D. Friendly bolts mine rocks, break crates and hit pirates; pirate bolts hit the player.
## Hits are checked along the whole path travelled each frame, so fast bolts can't skip through things.
## Optional: pierce (passes through targets), homing (curves toward pirates), slow (freezes pirates).
## The visible beam grows out of the muzzle as the bolt flies (up to its full length), so none of it ever
## shows behind the gun that fired it.

var main
var beam: MeshInstance3D  # the laser beam mesh, stretched back from the bolt's head (set by main.spawn_bullet)
var beam_len := 10.0  # full length of the beam, metres
var beam_width := 0.6
var _travelled := 0.0
var vel := Vector3.ZERO
var life := 1.2
var damage := 5.0
var mining := 1.0
var friendly := true
var color := Color.WHITE
var pierce := 0
var homing := 0.0
var slow := 0.0
var _hit := []


func _process(delta: float) -> void:
	if homing > 0.0:
		var target = _nearest_pirate()
		if target:
			var want: Vector3 = (target.position - position).normalized()
			var cur := vel.normalized()
			var ang := cur.angle_to(want)
			if ang > 0.001:
				cur = cur.slerp(want, minf(1.0, homing * delta / ang))
			vel = cur * vel.length()
			look_at(position + vel, Vector3.UP if absf(cur.y) < 0.99 else Vector3.RIGHT)
	var from := position
	position += vel * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_travelled += vel.length() * delta
	_stretch()
	for a in (main.group("asteroids") if main.near_field(position) else []):
		if not is_instance_valid(a) or a.is_queued_for_deletion():
			continue
		if _crosses(from, a.position, a.radius):
			var n: Vector3 = (from - a.position).normalized()
			main.rock_hit(a.position + n * a.radius * 0.9, Game.ORES[a.ore_id].color, n)
			if friendly:
				a.hit(mining, vel.normalized())
			queue_free()
			return
	if friendly:
		for group in ["pirates", "crates"]:
			for p in main.group(group):
				if not is_instance_valid(p) or p.is_queued_for_deletion():
					continue
				if not _hit.has(p) and _crosses(from, p.position, p.radius):
					p.take_damage(damage)
					if slow > 0.0 and group == "pirates":
						p.slow_t = slow
					_impact(p)
					return
	else:
		var pl = main.player
		if pl.alive and _crosses(from, pl.position, pl.radius * 0.8):
			pl.take_damage(damage, position)
			_impact(null)


## Lay the beam back from the head, only as far as the bolt has actually travelled.
func _stretch() -> void:
	if beam == null:
		return
	var length := clampf(_travelled, 0.05, beam_len)
	beam.scale = Vector3(beam_width, length, beam_width)
	beam.position = Vector3(0, 0, length * 0.5)


## Did this frame's path (from -> current position) pass within r of c?
func _crosses(from: Vector3, c: Vector3, r: float) -> bool:
	var seg := position - from
	var l2 := seg.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((c - from).dot(seg) / l2, 0.0, 1.0)
	return (from + seg * t).distance_squared_to(c) < r * r


func _nearest_pirate():
	var best = null
	var bd := 90.0 * 90.0
	for p in main.group("pirates"):
		if not is_instance_valid(p):
			continue
		var d := position.distance_squared_to(p.position)
		if d < bd:
			bd = d
			best = p
	return best


func _impact(target) -> void:
	main.sparks(position, color, 6)
	if target != null and pierce > 0:
		pierce -= 1
		_hit.append(target)
		return
	queue_free()
