extends Node3D
## The player's ship in 3D. The keys swing its heading (main.aim: A/D turn, R/F pitch, Q/E roll) and the
## ship turns to follow at its turn rate. W/S raise/lower the throttle, X brakes, SHIFT boosts. Guns fire
## from the model's muzzles toward whatever the mouse reticle is on, but a gun can't fire through your own
## hull: it has to be able to see the target.
##
## Flight model: the ship "grips" space, so sideways drift dies off quickly and you go where the nose
## points; slowing down is quicker than speeding up.

const THROTTLE_RATE := 1.6  # throttle change per second while W/S is held
const REVERSE_MAX := 0.35  # reverse thrust is weaker than forward
const GRIP := 2.6  # how fast sideways drift dies off (times top speed, per second)
const BOOST_MULT := 1.8
const BOOST_DRAIN := 35.0  # energy per second
const BOLT_SPEED_MULT := 2.5  # bolts fly this much faster than the weapon numbers say (over half the time: a bit more range)
const FIRE_RATE_MULT := 1.5  # and the guns cycle this much quicker
const SHIELD_SHADER = preload("res://shaders/shield.gdshader")
const PLUME_SHADER = preload("res://shaders/plume.gdshader")
const Fx = preload("res://scripts/fx.gd")
const Trail = preload("res://scripts/trail.gd")

var main
var vel := Vector3.ZERO
var throttle := 0.0  # -REVERSE_MAX..1
var hull := 100.0
var shield := 50.0
var energy := 100.0
var boosting := false
var st := {}
var control := true
var alive := true
var radius := 4.0
var thrusting := false
var muzzles := []  # Node3D markers, one per gun slot (front-left, front-right, ...)
var engines := []
var guns_ready := []  # per gun: can it fire at the aim point right now (for the debug screen)
var hull_box := Vector3(5, 1.6, 6)  # width, height, length of the hull itself
var model: Node3D
var _model_id := ""
var _glows := []
var _trails := []
var _plumes := []
var _nozzle := 1.0
var _mflash := []  # a glow at each muzzle, lit for a moment when that gun fires
var _mflash_t := []
var _smoke: Node3D  # smoke and fire pouring off the hull when it's badly damaged
var _hit_age := 10.0
var _shield_mat: ShaderMaterial
var _shield_mesh: MeshInstance3D
var _fire_cd := 0.0  # shortest cooldown left on any slot (for the debug screen)
var _slot_cd := []
var _since_hit := 99.0
var _since_boost := 99.0
var _flash := 0.0
var _detent := false  # throttle parked at 0 until W/S is released
var _bank := 0.0


func _ready() -> void:
	Game.changed.connect(_refresh_stats)
	_shield_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	_shield_mesh.mesh = sm
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mesh.material_override = _shield_mat
	_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield_mesh)


func setup() -> void:
	_refresh_stats()
	heal_full()


func _refresh_stats() -> void:
	st = Game.stats_ship()
	hull = minf(hull, st.hull)
	shield = minf(shield, st.shield)
	energy = minf(energy, st.energy)
	if _model_id != Game.ship_id:
		_build_model()


func _build_model() -> void:
	_model_id = Game.ship_id
	if model:
		model.queue_free()
	for t in _trails:
		t.queue_free()
	model = Models.ship(Game.ship_id)
	add_child(model)
	muzzles = Models.markers(model, "Muzzle")
	engines = Models.markers(model, "Engine")
	hull_box = Models.hull(Game.ship_id)
	var size := Models.size(Game.ship_id)
	radius = maxf(size.x, size.z) * 0.45
	_shield_mesh.scale = Vector3(size.x * 0.62, maxf(size.y * 1.4, size.x * 0.3), size.z * 0.62)
	_slot_cd = []
	_slot_cd.resize(muzzles.size())
	_slot_cd.fill(0.0)
	_glows = []
	_trails = []
	_plumes = []
	var nozzle := clampf(hull_box.x * 0.18, 0.6, 3.0)
	_nozzle = nozzle
	for e in engines:
		var g := Models.glow_quad(Color(1.0, 0.6, 0.25, 0.9), nozzle * 0.8)
		g.material_override = g.material_override.duplicate()  # tinted per frame, so not the shared one
		e.add_child(g)
		_glows.append(g)
		var pl := plume(nozzle)
		e.add_child(pl)
		_plumes.append(pl)
		var t := _trail(nozzle * 0.5)
		e.add_child(t)
		_trails.append(t)
	_mflash = []
	_mflash_t = []
	for m in muzzles:
		var q := Models.glow_quad(Color.WHITE, 1.0)
		q.visible = false
		m.add_child(q)
		_mflash.append(q)
		_mflash_t.append(0.0)


## A soft cone of exhaust light behind a nozzle; stretched and tinted each frame by the caller.
static func plume(nozzle: float) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = nozzle * 0.6
	cm.top_radius = nozzle * 0.12
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 2
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = PLUME_SHADER
	mi.material_override = m
	mi.rotation.x = PI / 2.0  # the cylinder's +Y now points out behind the nozzle
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


## Stretch a plume to `length` metres at brightness `power` in colour `col`.
static func set_plume(pl: MeshInstance3D, length: float, power: float, col: Color) -> void:
	pl.visible = power > 0.02
	pl.scale = Vector3(1.0, length, 1.0)
	pl.position = Vector3(0, 0, length * 0.5)
	var m: ShaderMaterial = pl.material_override
	m.set_shader_parameter("power", power)
	m.set_shader_parameter("color", col)


## A glowing exhaust ribbon left behind in world space.
func _trail(width: float) -> Node3D:
	var t := Trail.new()
	t.width = width
	t.color = Color(1.0, 0.62, 0.3, 0.55)
	return t

func heal_full() -> void:
	hull = st.hull
	shield = st.shield
	energy = st.energy


func stop() -> void:
	vel = Vector3.ZERO
	throttle = 0.0


func set_dead(dead: bool) -> void:
	alive = not dead
	visible = not dead
	stop()


func forward() -> Vector3:
	return -global_transform.basis.z


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var want_boost := false
	var braking := false
	if control:
		_update_throttle(delta)
		braking = Input.is_action_pressed("cut_throttle")
		if braking:
			throttle = 0.0
		want_boost = Input.is_action_pressed("boost")
	if want_boost and energy > 1.0:
		if not boosting:
			Sfx.play("boost", -10.0)
		boosting = true
		energy = maxf(0.0, energy - BOOST_DRAIN * delta)
		_since_boost = 0.0
	else:
		boosting = false
		_since_boost += delta
		if _since_boost > 1.0:
			energy = minf(st.energy, energy + st.energy_regen * delta)

	# swing the nose toward the aim at the ship's turn rate (the warp sequence steers while warping)
	var q := global_transform.basis.get_rotation_quaternion()
	var target: Quaternion = main.aim.get_rotation_quaternion()
	var ang := q.angle_to(target)
	if ang > 0.0001:
		var step: float = st.turn * 1.15 * delta
		q = q.slerp(target, minf(1.0, step / ang))
	# bank into turns: roll a little toward the side the aim is on
	var side: float = main.aim.z.dot(global_transform.basis.x)
	_bank = lerpf(_bank, clampf(side * 2.5, -0.6, 0.6), 1.0 - exp(-4.0 * delta))
	basis = Basis(q)
	if model:
		model.rotation.z = _bank

	var top: float = st.speed * Game.WORLD_SCALE * (BOOST_MULT if boosting else 1.0)
	var tgt := top if boosting else throttle * top
	var fwd := forward()
	var vf := vel.dot(fwd)
	var lateral := vel - fwd * vf
	var accel := top * (2.2 if boosting else 1.3)
	if absf(tgt) < absf(vf) or signf(tgt) * signf(vf) < 0.0:
		accel = top * (3.5 if braking else 1.8)  # slowing down is quicker than speeding up
	vf = move_toward(vf, tgt, accel * delta)
	lateral = lateral.move_toward(Vector3.ZERO, top * GRIP * delta)
	if main.mode != "warp":  # during a warp the warp sequence drives the ship
		vel = fwd * vf + lateral
	thrusting = absf(tgt) > 0.5 or main.travel.get("phase", "") in ["charge", "travel"]
	# soft edge of the playable area
	if position.length() > 30000.0:
		vel -= position.normalized() * 60.0 * delta
	position += vel * delta
	_collide_rocks()

	var aim_pt: Vector3 = main.aim_point
	guns_ready = []
	for m in muzzles:
		guns_ready.append(can_fire(m, aim_pt))
	_fire_cd = INF
	for i in _slot_cd.size():
		_slot_cd[i] = maxf(0.0, _slot_cd[i] - delta)
		_fire_cd = minf(_fire_cd, _slot_cd[i])
	if control and not main.pointer_on_ui() and Input.is_action_pressed("fire"):
		fire_at(aim_pt)

	_since_hit += delta
	if _since_hit > st.shield_delay and shield < st.shield:
		shield = minf(st.shield, shield + st.shield * st.shield_rate * delta)
	if st.regen > 0.0:
		hull = minf(st.hull, hull + st.regen * delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	_hit_age += delta
	_shield_mat.set_shader_parameter("hit", _flash if shield > 0.0 else 0.0)
	_shield_mat.set_shader_parameter("hit_age", _hit_age)
	for i in _mflash.size():
		_mflash_t[i] = maxf(0.0, _mflash_t[i] - delta * 14.0)
		_mflash[i].visible = _mflash_t[i] > 0.0
		_mflash[i].scale = Vector3.ONE * (0.4 + _mflash_t[i])
	var burning: bool = hull < st.hull * 0.3
	if burning and _smoke == null:
		_smoke = Fx.damage_emitter(clampf(radius * 0.25, 0.8, 3.0))
		_smoke.position = Vector3(randf_range(-0.3, 0.3) * hull_box.x, hull_box.y * 0.4, randf_range(-0.3, 0.3) * hull_box.z)
		add_child(_smoke)
	elif not burning and _smoke != null:
		_smoke.queue_free()
		_smoke = null
	_update_exhaust()


## W/S move the throttle lever; it stops at 0% on the way down so it's easy to sit still. With
## "hold to thrust" on, W is full throttle only while held and S is reverse.
func _update_throttle(delta: float) -> void:
	var up := Input.is_action_pressed("move_up")
	var down := Input.is_action_pressed("move_down")
	if Sfx.hold_thrust:
		throttle = 1.0 if up else (-REVERSE_MAX if down else 0.0)
		return
	if not up and not down:
		_detent = false
		return
	if _detent:
		return
	var before := throttle
	if up:
		throttle = minf(1.0, throttle + THROTTLE_RATE * delta)
	elif down:
		throttle = maxf(-REVERSE_MAX, throttle - THROTTLE_RATE * delta)
	if signf(before) != signf(throttle) and before != 0.0:
		throttle = 0.0
		_detent = true


func _update_exhaust() -> void:
	var warping: bool = main.travel.get("phase", "") == "travel"
	var hot := boosting or warping
	var power := 1.6 if hot else absf(throttle)
	var col := Color(0.55, 0.85, 1.0) if hot else Color(1.0, 0.62, 0.28)
	for g in _glows:
		g.visible = thrusting
		g.scale = Vector3.ONE * (0.6 + 0.5 * power + randf_range(-0.05, 0.05))
		(g.material_override as StandardMaterial3D).albedo_color = Color(col, 0.3 + 0.25 * minf(power, 1.0))
	var length := _nozzle * ((8.0 if warping else 5.5) if hot else 1.5 + 3.0 * power)
	for pl in _plumes:
		set_plume(pl, length * randf_range(0.95, 1.05), (minf(power, 1.0) * 0.9 + 0.1) if thrusting else 0.0, col)
	for t in _trails:
		t.emitting = thrusting and not warping and alive
		t.color = Color(col, 0.1 + 0.18 * minf(power, 1.0))


func _collide_rocks() -> void:
	# stations, gates and other big structures
	var push: Vector3 = main.push_out(position, radius * 0.6)
	if push != Vector3.ZERO:
		position += push
		var pn := push.normalized()
		var pv := vel.dot(pn)
		if pv < 0.0:
			vel -= pn * pv * 1.3
	for a in get_tree().get_nodes_in_group("asteroids"):
		var d: Vector3 = position - a.position
		var minr: float = a.radius + radius * 0.6
		if d.length_squared() < minr * minr and d.length_squared() > 0.01:
			var n := d.normalized()
			position = a.position + n * minr
			var vn := vel.dot(n)
			if vn < 0.0:
				vel -= n * vn * 1.25


## Can the gun at `muzzle` hit `aim` without its shot passing through the hull box?
func can_fire(muzzle: Node3D, aim: Vector3) -> bool:
	var inv := global_transform.affine_inverse()
	var a: Vector3 = inv * muzzle.global_position
	var b: Vector3 = inv * aim
	return not _segment_hits_box(a, b, hull_box * 0.5)


## Slab test: does the segment a->b pass through the box centred on the origin with half-size `h`?
static func _segment_hits_box(a: Vector3, b: Vector3, h: Vector3) -> bool:
	var d := b - a
	var t0 := 0.02
	var t1 := 1.0
	for i in 3:
		if absf(d[i]) < 0.00001:
			if a[i] < -h[i] or a[i] > h[i]:
				return false
		else:
			var ta := (-h[i] - a[i]) / d[i]
			var tb := (h[i] - a[i]) / d[i]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


## The bolt a weapon fires from this ship: its numbers with ship/module/blessing bonuses applied, in 3D units.
func shot(w: Dictionary) -> Dictionary:
	return {"damage": w.damage * st.damage, "speed": w.speed * st.bolt * Game.WORLD_SCALE * BOLT_SPEED_MULT, "life": w.life * 0.5,
		"mining": w.mining * st.mining, "color": w.color, "size": w.size, "pierce": w.get("pierce", 0),
		"homing": w.get("homing", 0.0), "slow": w.get("slow", 0.0)}


## Fires every ready gun slot that has a clear shot at `aim`. Each slot fires its own mounted weapon on
## its own cooldown. Returns how many slots fired.
func fire_at(aim: Vector3) -> int:
	var loadout := Game.loadout()
	var fired := 0
	var spread_shot := false
	for i in muzzles.size():
		if _slot_cd[i] > 0.0 or not can_fire(muzzles[i], aim):
			continue
		var w: Dictionary = Game.WEAPONS[loadout[i] if i < loadout.size() else Game.BLASTER]
		var s := shot(w)
		var pellets: int = w.get("pellets", 1)
		var spread: float = deg_to_rad(w.get("spread", 0.0))
		var mp: Vector3 = muzzles[i].global_position
		var dir := (aim - mp).normalized()
		var right := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT
		for k in pellets:
			var off := 0.0 if pellets == 1 else lerpf(-spread / 2.0, spread / 2.0, k / float(pellets - 1))
			var d := dir.rotated(Vector3.UP, off + randf_range(-0.01, 0.01)).rotated(right, randf_range(-0.01, 0.01))
			main.spawn_bullet(mp, d, s, true)
		_slot_cd[i] = 1.0 / (w.rate * st.fire * FIRE_RATE_MULT)
		_mflash_t[i] = 1.0
		_mflash[i].material_override = Models.glow_mat(Color(Color(w.color).lerp(Color.WHITE, 0.5), 0.9))
		_mflash[i].mesh.size = Vector2.ONE * (1.4 + Vector2(w.size).x * 0.35)
		spread_shot = spread_shot or pellets > 1
		fired += 1
	if fired > 0:
		Sfx.play("laser", -17.0 + minf(fired, 6) * 0.6, randf_range(0.9, 1.1) * (0.7 if spread_shot else 1.0))
	return fired


## `from`: where the hit landed (for the ripple across the shield bubble).
func take_damage(amount: float, from := Vector3.INF) -> void:
	if not alive or main.invulnerable() or Game.god:
		return
	amount *= st.armor
	_since_hit = 0.0
	_flash = 1.0
	if from != Vector3.INF and shield > 0.0:
		_hit_age = 0.0
		_shield_mat.set_shader_parameter("hit_dir", _shield_mesh.to_local(from).normalized())
	var s := minf(shield, amount)
	shield -= s
	hull -= amount - s
	Sfx.play("hit", -8.0)
	main.shake(0.15 if s >= amount else 0.4)
	if s < amount:
		main.hurt(0.25 + 0.5 * (amount - s) / st.hull * 4.0)
	if hull <= 0.0:
		hull = 0.0
		main.player_died()
