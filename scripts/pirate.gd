extends Node3D
## A pirate (or anomaly Sentinel) in 3D. Stats come from Game.ENEMIES; it circles the player at its
## preferred distance on its own tilted orbit, its turrets tracking you, and each turret that's on target
## shoots with a lead. Drops ore and pays a bounty.
## Badly damaged pirates trail smoke and fire.

const Ship = preload("res://scripts/ship.gd")
const Fx = preload("res://scripts/fx.gd")
const Turrets = preload("res://scripts/turrets.gd")

var main
var type := "raider"
var data := {}
var vel := Vector3.ZERO
var hp := 50.0
var max_hp := 50.0
var radius := 3.0
var speed := 30.0
var shot := {}
var aggro := false
var home := Vector3.ZERO
var muzzles := []
var guns  # Turrets
var slow_t := 0.0
var model: Node3D
var _dead := false
var _fire_cd := 1.0
var _orbit_axis := Vector3.UP
var _orbit := 1.0
var _wander := Vector3.ZERO
var _plumes := []
var _nozzles := []
var _mflash := []
var _mflash_t := 0.0
var _smoke: Node3D
var _engine_col := Color("ff5a2a")


func setup(enemy_type: String, cat: int) -> void:
	type = enemy_type
	data = Game.ENEMIES[type]
	var danger: float = Game.CAT_DANGER[cat]
	var k := Game.WORLD_SCALE
	max_hp = data.hp * danger
	hp = max_hp
	speed = data.speed * k * 0.6  # in step with the player's heavier, slower ships
	shot = {"damage": data.damage * danger, "speed": data.bolt * k, "life": data.range / data.bolt + 0.2, "mining": 0.0,
		"color": Color("d080ff") if type == "sentinel" else Color("ff4a4a"),
		"size": Vector2(3, 7) if data.has("boss") else Vector2(2, 5), "pierce": 0, "homing": 0.0, "slow": 0.0}
	home = position
	_orbit = [-1.0, 1.0].pick_random()
	_orbit_axis = Vector3(randf_range(-0.4, 0.4), 1.0, randf_range(-0.4, 0.4)).normalized()
	_fire_cd = randf_range(0.8, 2.0)
	add_to_group("pirates")
	model = Models.ship(type)
	add_child(model)
	guns = Turrets.new(model)
	muzzles = guns.muzzles()
	var size := Models.size(type)
	radius = maxf(size.x, size.z) * 0.5
	_engine_col = Color("d080ff") if type == "sentinel" else Color("ff5a2a")
	for m in muzzles:
		var fq := Models.glow_quad(Color(Color(shot.color).lerp(Color.WHITE, 0.4), 0.9), 0.8 if data.has("boss") else 0.5)
		fq.visible = false
		m.add_child(fq)
		_mflash.append(fq)
	for e in Models.markers(model, "Engine"):
		_nozzles.append(Ship.nozzle_size(e))
		var pl := Ship.plume(_nozzles[-1])
		e.add_child(pl)
		_plumes.append(pl)



func describe() -> String:
	return "%s  -  %d / %d hull" % [data.name, ceili(hp), ceili(max_hp)]


func _process(delta: float) -> void:
	var p = main.player
	var to: Vector3 = p.position - position
	var d := to.length()
	var k := Game.WORLD_SCALE
	var sight: float = data.sight * k * p.st.get("stealth", 1.0) + p.radius  # (a capital ship's a big target)
	if not p.alive or main.mode == "docked" or main.invulnerable():
		aggro = false
	elif d < sight:
		aggro = true
	elif d > sight * 2.0:
		aggro = false
	slow_t = maxf(0.0, slow_t - delta)
	var spd := speed * (0.5 if slow_t > 0.0 else 1.0)
	var desired := Vector3.ZERO
	var face := vel
	if aggro:
		var n := to / maxf(d, 0.1)
		var tangent := n.cross(_orbit_axis).normalized() * _orbit
		desired = n * (d - data.keep * k - p.radius) * 1.5 + tangent * spd * 0.8
		face = to
		guns.aim(delta, _lead(p), 0.8)
		_fire_cd -= delta
		if _fire_cd <= 0.0 and d < data.range * k + p.radius and guns.on_target.has(true):
			_fire(p)
			_fire_cd = 1.0 / data.rate * randf_range(0.8, 1.3)
	else:
		guns.rest(delta)
		if _wander == Vector3.ZERO or position.distance_to(_wander) < 6.0:
			_wander = home + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * randf_range(15.0, 45.0)
		desired = _wander - position
	desired = desired.limit_length(spd)
	vel = vel.move_toward(desired, spd * 2.0 * delta)
	position += vel * delta
	position += main.push_out(position, radius * 0.6)
	if face.length() > 0.5:
		var want := Basis.looking_at(face.normalized(), Vector3.UP if absf(face.normalized().y) < 0.98 else Vector3.RIGHT)
		basis = basis.slerp(want, 1.0 - exp(-2.2 * delta)).orthonormalized()
	for a in get_tree().get_nodes_in_group("asteroids"):
		var off: Vector3 = position - a.position
		var minr: float = a.radius + radius * 0.6
		if off.length_squared() < minr * minr and off.length_squared() > 0.01:
			position = a.position + off.normalized() * minr
	if randf() < delta * 0.25:
		_orbit = -_orbit
	var moving := vel.length() > 3.0
	var push := 3.0 + 5.0 * clampf(vel.length() / maxf(speed, 1.0), 0.0, 1.0)  # plume length in nozzle widths
	for i in _plumes.size():
		Ship.set_plume(_plumes[i], _nozzles[i] * push, 0.9 if moving else 0.3, _engine_col)
	_mflash_t = maxf(0.0, _mflash_t - delta * 12.0)
	for fq in _mflash:
		fq.visible = _mflash_t > 0.0
		fq.scale = Vector3.ONE * (0.4 + _mflash_t)
	if hp < max_hp * 0.4 and _smoke == null and type != "sentinel":
		_smoke = Fx.damage_emitter(clampf(radius * 0.3, 0.6, 2.5))
		_smoke.position = Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3)) * radius
		add_child(_smoke)


## Where to aim so a bolt meets the player (roughly: they may turn).
func _lead(p) -> Vector3:
	return p.position + p.vel * (position.distance_to(p.position) / shot.speed) * 0.6


## Every turret that's on target fires at the lead point.
func _fire(p) -> void:
	var lead := _lead(p)
	var pellets: int = data.get("pellets", 1)
	for gi in muzzles.size():
		if not guns.on_target[gi]:
			continue
		var m: Node3D = muzzles[gi]
		var mp: Vector3 = m.global_position
		var dir := (lead - mp).normalized()
		for i in pellets:
			var off := 0.0 if pellets == 1 else (i - (pellets - 1) / 2.0) * 0.08
			var dd := dir.rotated(Vector3.UP, off + randf_range(-0.03, 0.03))
			dd = dd.rotated(dd.cross(Vector3.UP).normalized() if absf(dd.y) < 0.99 else Vector3.RIGHT, randf_range(-0.03, 0.03))
			main.spawn_bullet(mp, dd, shot, false)
	_mflash_t = 1.0
	Sfx.play("laser", -20.0, 0.55 if data.has("boss") else 0.7)


func take_damage(dmg: float) -> void:
	if _dead:
		return
	hp -= dmg
	aggro = true
	main.dmg_number(position + Vector3.UP * radius, dmg, Color("ffe066") if dmg >= 20.0 else Color.WHITE)
	if hp <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	var sys: Dictionary = Game.systems[Game.current_system]
	main.explosion(position, 3.0 if data.has("boss") else 1.5, Color("d080ff") if type == "sentinel" else Color("ff8a3d"))
	for i in randi_range(data.loot / 2, data.loot):
		var roll := Game.roll_ore(sys, type == "sentinel")
		var out := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		main.spawn_chunk(roll[0], roll[1], 1, position, out * randf_range(5.0, 14.0))
	var bounty := int(data.credits * Game.CAT_DANGER[sys.cat])
	Game.add_credits(bounty)
	Game.say("%s destroyed!  +%d credits" % [data.name, bounty], Color("ffb36b"))
	if type in ["sentinel", "captain"] and randf() < 0.03:
		Game.portals += 1
		Game.toast.emit("RARE FIND", "A portable wormhole drifted out of the wreckage!", "anomaly", Color("e080ff"))
	Game.event("kill", {"type": type, "sys": sys.id})
	queue_free()
