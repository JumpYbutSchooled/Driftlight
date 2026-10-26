extends Node3D
## The player's ship in 3D. The keys turn it (Q/E turn, W/S pitch, A/D roll, with momentum: see _turn).
## R/F raise/lower the throttle, X brakes, SHIFT boosts. Each gun
## slot is a turret (on a pod, on the deck, under the keel or out on a flank, depending on the ship) that
## swings round on its own to track whatever the crosshair is on; a turret only fires once it's on target,
## within its arc, and with a clear line past your own hull: it has to be able to see the target.
##
## Flight model: a heavy ship. It takes seconds to build up speed and to bleed it off again, and the
## flight computer slowly damps out sideways drift so you end up going where the nose points. Turning
## has momentum too: holding a turn key spins the ship up to its turn rate, and letting go spins it down
## again, rather than the nose snapping round at a fixed rate. The autopilot and the warp drive steer by
## setting main.aim; the same spin-up / spin-down brings the nose round to it and settles it there.

const SPEED_MULT := 0.45  # top speeds are this fraction of the ship's speed stat (in 3D units)
const ACCEL := 0.22  # throttle response: fraction of top speed gained per second
const DECEL := 0.3  # easing off the throttle sheds speed a little quicker
const BRAKE := 0.6  # X
const THROTTLE_RATE := 0.8  # throttle change per second while R/F is held
const REVERSE_MAX := 0.35  # reverse thrust is weaker than forward
const GRIP := 0.5  # how fast the flight computer damps sideways drift (times top speed, per second)
const TURN_MULT := 0.45  # top turn rate (rad/s) is this times the ship's turn stat; rolling is quicker
const SPIN_UP := 1.3  # turn rate gained per second, as a fraction of the top turn rate
const BOOST_MULT := 1.8
const BOOST_DRAIN := 8.0  # energy per second (a full tank boosts for a good while)
const BOLT_SPEED_MULT := 2.5  # bolts fly this much faster than the weapon numbers say (over half the time: a bit more range)
const FIRE_RATE_MULT := 1.5  # and the guns cycle this much quicker
const BOLT_RANGE := 8000.0  # metres: every weapon reaches as far as you can see to aim
const BEAM_RANGE := 4000.0  # metres a mining beam reaches
const GUN_REF := 0.85  # a starter ship's turret size: bolts and beams are drawn to scale against it
const BEAM_COLLECT := [0.5, 0.6, 0.75, 0.9, 1.0]  # share of the ore a mining beam cuts straight into the hold, by mark
const TRACTOR_BEAMS := 6  # most loose chunks the tractor pulls in at once
const LASER_SHADER = preload("res://shaders/laser.gdshader")
const SHIELD_SHADER = preload("res://shaders/shield.gdshader")
const PLUME_SHADER = preload("res://shaders/plume.gdshader")
const NOZZLE_SHADER = preload("res://shaders/nozzle.gdshader")
const Fx = preload("res://scripts/fx.gd")
const Turrets = preload("res://scripts/turrets.gd")

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
var muzzles := []  # the turrets' barrel tips, one per gun slot (front-left, front-right, ...)
var turrets := []  # per gun slot: {base, yaw, pitch, muzzle} nodes of its turret
var engines := []
var guns_ready := []  # per gun: can it fire at the aim point right now (for the debug screen)
var turret_why := []  # per gun: why it can't (for the debug screen and tests)
var hull_box := Vector3(5, 1.6, 6)  # width, height, length of the hull itself
var model: Node3D
var _model_id := ""
var _glows := []
var _plumes := []
var _nozzles := []  # per engine: nozzle size, metres
var _guns  # the Turrets on this model
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
var _detent := false  # throttle parked at 0 until R/F is released
var _bank := 0.0
var turn_input := Vector3.ZERO  # from the keys (main._steer): x pitch, y yaw, z roll, each -1..1
var ang_vel := Vector3.ZERO  # world-space angular velocity, rad/s
var cruise_v := 0.0  # set by main's cruise autopilot: the speed to hold (0: not cruising)
var beam_lock = null  # what the mining beams are locked on to (while the trigger's held)
var _beams := []  # per gun slot: its beam (a Node3D holding the beam mesh and a glow at the far end), or null
var _beam_dmg := 0.0  # beam damage built up on a ship or crate, dealt in bites
var _beam_fx := 0.0
var _tractor := []  # the tractor beam meshes
var _loadout_sig := ""
var _lights := []  # an engine light per nozzle, lighting the hull while it burns


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
		var fresh := _model_id != ""
		_build_model()
		if fresh:
			heal_full()  # (a ship you've just boarded comes out of the hangar repaired)
	elif _loadout_sig != str(Game.loadout()):
		_guns.build(_kinds())  # a different weapon on a turret: its own turret model
		_after_turrets()


## The weapon (base id) on each gun slot: picks each turret's model.
func _kinds() -> Array:
	return Game.loadout().map(func(w): return Game.WEAPONS[w].base)


func _build_model() -> void:
	_model_id = Game.ship_id
	if model:
		model.queue_free()
	model = Models.ship(Game.ship_id)
	add_child(model)
	engines = Models.markers(model, "Engine")
	hull_box = Models.hull(Game.ship_id)
	# a turret on every gun mount (on top, underneath or out to the side: the mount says which way)
	_guns = Turrets.new(model, _kinds())
	var size := Models.size(Game.ship_id)
	radius = maxf(size.x, size.z) * 0.45
	_shield_mesh.scale = Vector3(size.x * 0.62, maxf(size.y * 1.4, size.x * 0.3), size.z * 0.62)
	_after_turrets()
	_glows = []
	_plumes = []
	for l in _lights:
		l.queue_free()
	_lights = []
	_nozzles = []
	for e in engines:
		# the hot throat of the nozzle (a disc facing out the back), the exhaust plume, and a light that
		# throws the burn's glow onto the hull and anything close behind
		var nozzle := nozzle_size(e)
		_nozzles.append(nozzle)
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * nozzle * 0.85
		g.mesh = q
		var nm := ShaderMaterial.new()
		nm.shader = NOZZLE_SHADER
		g.material_override = nm
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.position = Vector3(0, 0, -nozzle * 0.05)
		e.add_child(g)
		_glows.append(g)
		var pl := plume(nozzle)
		e.add_child(pl)
		_plumes.append(pl)
		var l := OmniLight3D.new()
		l.position = Vector3(0, 0, nozzle * 1.6)
		l.omni_range = nozzle * 9.0
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.light_energy = 0.0
		e.add_child(l)
		_lights.append(l)


## After the turrets were (re)built: their muzzles, cooldowns, muzzle flashes and mining beams.
func _after_turrets() -> void:
	_loadout_sig = str(Game.loadout())
	turrets = _guns.list
	muzzles = _guns.muzzles()
	_slot_cd = []
	_slot_cd.resize(muzzles.size())
	_slot_cd.fill(0.0)
	_mflash = []
	_mflash_t = []
	for m in muzzles:
		var q := Models.glow_quad(Color.WHITE, 1.0)
		q.visible = false
		m.add_child(q)
		_mflash.append(q)
		_mflash_t.append(0.0)
	for b in _beams:
		if b != null:
			b.queue_free()
	_beams = []
	var lo := Game.loadout()
	for i in muzzles.size():
		var w: Dictionary = Game.WEAPONS[lo[i] if i < lo.size() else Game.BLASTER]
		_beams.append(_beam_node(w.color, Vector2(w.size).x * 0.35) if w.get("beam", false) else null)
	beam_lock = null


## A beam: a steady laser core from the muzzle to whatever it hits, with a glow where it lands. Placed in
## world space each frame (see _update_beams).
func _beam_node(color: Color, width: float) -> Node3D:
	var holder := Node3D.new()
	holder.top_level = true
	holder.visible = false
	var core := MeshInstance3D.new()
	core.mesh = Models.streak_mesh(1.0, 1.0)
	var m := ShaderMaterial.new()
	m.shader = LASER_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("steady", 1.0)
	core.material_override = m
	core.rotation.x = -PI / 2.0
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.set_meta("width", width)
	holder.add_child(core)
	holder.add_child(Models.glow_quad(Color(color.lerp(Color.WHITE, 0.4), 0.85), maxf(2.0, width * 8.0)))
	add_child(holder)
	return holder


## Point a beam from `from` to `to`.
static func place_beam(holder: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.01:
		holder.visible = false
		return
	var dir := d / length
	holder.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), from)
	var core: MeshInstance3D = holder.get_child(0)
	core.scale = Vector3(width, length, width)
	core.position = Vector3(0, 0, -length * 0.5)
	holder.get_child(1).position = Vector3(0, 0, -length)
	holder.visible = true


## How wide an engine's nozzle is: Blender scales each Engine_N marker by its nozzle's radius. (The scale is
## taken off the marker, so the plume and glow hung on it come out the right size.)
static func nozzle_size(e: Node3D) -> float:
	var r := e.scale.x
	e.scale = Vector3.ONE
	return clampf(r * 2.0, 0.3, 6.0)


## An exhaust plume behind a nozzle (shaders/plume.gdshader), flaring a little as it leaves the bell;
## stretched and tinted each frame by the caller.
static func plume(nozzle: float) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = nozzle * 0.32
	cm.top_radius = nozzle * 0.55
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


func heal_full() -> void:
	hull = st.hull
	shield = st.shield
	energy = st.energy


func stop() -> void:
	vel = Vector3.ZERO
	throttle = 0.0
	ang_vel = Vector3.ZERO
	cruise_v = 0.0


## Cruising speed at full throttle, m/s.
func top_speed() -> float:
	return st.speed * Game.WORLD_SCALE * SPEED_MULT


## Top turn rate, rad/s (yaw and pitch; roll is half as quick again).
func turn_rate() -> float:
	return st.turn * TURN_MULT


func set_dead(dead: bool) -> void:
	alive = not dead
	visible = not dead
	stop()


func forward() -> Vector3:
	return -global_transform.basis.z


func _process(delta: float) -> void:
	if not alive:
		return
	var want_boost := false
	var braking := false
	if control:
		if main.autopilot.is_empty():
			_update_throttle(delta)  # (on autopilot R/F set its power instead: see main)
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

	_turn(delta)

	var base := top_speed()
	var top: float = base * (BOOST_MULT if boosting else 1.0)
	var tgt := top if boosting else throttle * top
	var fwd := forward()
	var vf := vel.dot(fwd)
	var lateral := vel - fwd * vf
	var accel := base * (ACCEL * 2.0 if boosting else ACCEL)
	if absf(tgt) < absf(vf) or signf(tgt) * signf(vf) < 0.0:
		accel = base * (BRAKE if braking else DECEL)
	var grip := base * GRIP
	if cruise_v > 0.0:
		# cruising: the cruise drive holds a speed far above normal and the flight computer keeps the ship
		# tracking its nose through the turns
		tgt = cruise_v
		accel = maxf(cruise_v * 0.5, base)
		grip = cruise_v * 1.5
	elif absf(vf) > top * 1.05:
		accel = maxf(accel, absf(vf) * 1.2)  # out of cruise: the extra speed bleeds off in a couple of seconds
	vf = move_toward(vf, tgt, accel * delta)
	lateral = lateral.move_toward(Vector3.ZERO, grip * delta)
	if main.mode != "warp":  # during a warp the warp sequence drives the ship
		vel = fwd * vf + lateral
	thrusting = absf(tgt) > 0.5 or main.travel.get("phase", "") in ["charge", "travel"]
	# soft edge of the playable area
	if position.length() > 30000.0:
		vel -= position.normalized() * 60.0 * delta
	position += vel * delta
	_collide_rocks()

	var aim_pt: Vector3 = main.aim_point
	_aim_turrets(delta, aim_pt)
	_update_beams(delta)
	_update_tractor()
	_fire_cd = INF
	for i in _slot_cd.size():
		_slot_cd[i] = maxf(0.0, _slot_cd[i] - delta)
		_fire_cd = minf(_fire_cd, _slot_cd[i])
	if control and not main.cursor_free() and Input.is_action_pressed("fire"):
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


## Turning with momentum. With a turn key held the ship spins up toward its turn rate about that axis;
## with none held it spins down to a stop and holds that heading (main.aim follows the nose). While the
## autopilot or the warp drive is steering, it turns toward main.aim instead: spinning up, then easing off
## in time to come to rest with the nose on it.
func _turn(delta: float) -> void:
	var rate := turn_rate()
	var accel := rate * SPIN_UP
	var b := global_transform.basis.orthonormalized()
	var want := Vector3.ZERO
	var steering: bool = not main.autopilot.is_empty() or not main.travel.is_empty()
	var ang := 0.0
	if control and turn_input != Vector3.ZERO:
		steering = false
		want = b * Vector3(turn_input.x * rate, turn_input.y * rate, -turn_input.z * rate * 1.5)
	elif steering:
		var err: Quaternion = main.aim.get_rotation_quaternion() * b.get_rotation_quaternion().inverse()
		if err.w < 0.0:
			err = -err
		ang = err.get_angle()
		if ang > 0.0005:
			want = err.get_axis().normalized() * minf(rate, sqrt(2.0 * accel * ang) * 0.85)
	ang_vel = ang_vel.move_toward(want, accel * delta)
	var spin := ang_vel.length()
	if steering and ang < 0.002 and spin < 0.02:
		b = main.aim.orthonormalized()  # settled on the heading
		ang_vel = Vector3.ZERO
	elif spin > 0.00001:
		b = Basis(ang_vel / spin, spin * delta) * b
	basis = b.orthonormalized()
	if not steering:
		main.aim = basis  # hold whatever heading the ship has turned to
	# lean into a yaw a little, like an aircraft banking
	var yaw_rate: float = (basis.inverse() * ang_vel).y
	_bank = lerpf(_bank, clampf(yaw_rate / maxf(rate, 0.01) * 0.3, -0.3, 0.3), 1.0 - exp(-3.0 * delta))
	if model:
		model.rotation.z = _bank


## R/F move the throttle lever; it stays where you leave it, and stops at 0% on the way down so it's
## easy to sit still.
func _update_throttle(delta: float) -> void:
	var up := Input.is_action_pressed("move_up")
	var down := Input.is_action_pressed("move_down")
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


## Plume length and brightness, nozzle glow, engine lights and the engine rumble, from the throttle.
func _update_exhaust() -> void:
	var warping: bool = main.travel.get("phase", "") == "travel"
	var hot := boosting or warping or cruise_v > 0.0
	var power := 1.5 if hot else absf(throttle)
	var col := Color(0.66, 0.84, 1.0) if hot else Color(0.5, 0.68, 1.0)
	var burn: float = (minf(power, 1.0) * 0.85 + 0.15) if thrusting else 0.0
	for g in _glows:
		var m: ShaderMaterial = g.material_override
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("power", maxf(burn, 0.08))
	var length := (16.0 if warping else 11.0) if hot else 3.0 + 7.0 * power  # in nozzle widths
	for i in _plumes.size():
		set_plume(_plumes[i], _nozzles[i] * length * randf_range(0.98, 1.02), burn, col)
	for l in _lights:
		l.light_color = col
		l.light_energy = burn * (2.2 if hot else 1.4) * randf_range(0.93, 1.0)
	Sfx.set_engine(burn if alive and main.mode in ["fly", "warp"] else 0.0, hot)


func _collide_rocks() -> void:
	# stations, gates and other big structures
	var push: Vector3 = main.push_out(position, radius * 0.6)
	if push != Vector3.ZERO:
		position += push
		var pn := push.normalized()
		var pv := vel.dot(pn)
		if pv < 0.0:
			vel -= pn * pv * 1.3
	for a in main.group("asteroids"):
		var d: Vector3 = position - a.position
		var minr: float = a.radius + radius * 0.6
		if d.length_squared() < minr * minr and d.length_squared() > 0.01:
			var n := d.normalized()
			position = a.position + n * minr
			var vn := vel.dot(n)
			if vn < 0.0:
				vel -= n * vn * 1.25


## Swing every turret toward `target` and work out which can fire: on target, within its arc (a turret on
## top can't shoot down through the deck, one underneath can't shoot up), and with a clear line past the hull.
## Mining beams locked on to something aim at that instead.
func _aim_turrets(delta: float, target: Vector3) -> void:
	var targets := []
	for i in turrets.size():
		targets.append(_beam_point(i) if i < _beams.size() and _beams[i] != null and beam_lock != null else null)
	_guns.aim(delta, target, 1.0, targets)
	guns_ready = []
	turret_why = []
	for i in turrets.size():
		var clear := can_fire(turrets[i].muzzle, target if targets[i] == null else targets[i])
		guns_ready.append(_guns.on_target[i] and clear)
		turret_why.append("ready" if guns_ready[-1] else ("out of arc" if not _guns.in_arc[i] else ("swinging"
			if not _guns.on_target[i] else "hull in the way")))


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


## How much bigger than a starter ship's this gun is (never smaller): its bolts and beam are drawn that much
## bigger, so a capital ship's guns don't spit specks.
static func gun_scale(muzzle: Node3D) -> float:
	return maxf(1.0, muzzle.global_basis.get_scale().x / GUN_REF)


## The bolt a weapon fires from this ship: its numbers with ship/module/blessing bonuses applied, in 3D units.
func shot(w: Dictionary) -> Dictionary:
	return {"damage": w.damage * st.damage, "speed": w.speed * st.bolt * Game.WORLD_SCALE * BOLT_SPEED_MULT,
		"life": BOLT_RANGE / (w.speed * st.bolt * Game.WORLD_SCALE * BOLT_SPEED_MULT),
		"mining": w.mining * st.mining, "color": w.color, "size": w.size, "pierce": w.get("pierce", 0),
		"homing": w.get("homing", 0.0), "slow": w.get("slow", 0.0)}


## Fires every ready gun slot that has a clear shot at `aim`. Each slot fires its own mounted weapon on
## its own cooldown. Returns how many slots fired.
func fire_at(aim: Vector3) -> int:
	var loadout := Game.loadout()
	var fired := 0
	var spread_shot := false
	for i in muzzles.size():
		if _slot_cd[i] > 0.0 or i >= guns_ready.size() or not guns_ready[i]:
			continue
		var w: Dictionary = Game.WEAPONS[loadout[i] if i < loadout.size() else Game.BLASTER]
		if w.get("beam", false):
			continue  # beams fire continuously (see _update_beams)
		var s := shot(w)
		var pellets: int = w.get("pellets", 1)
		var spread: float = deg_to_rad(w.get("spread", 0.0))
		var mp: Vector3 = muzzles[i].global_position
		var dir := (aim - mp).normalized()
		var right := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT
		for k in pellets:
			var off := 0.0 if pellets == 1 else lerpf(-spread / 2.0, spread / 2.0, k / float(pellets - 1))
			var d := dir.rotated(Vector3.UP, off + randf_range(-0.01, 0.01)).rotated(right, randf_range(-0.01, 0.01))
			main.spawn_bullet(mp, d, s, true, gun_scale(muzzles[i]))
		_slot_cd[i] = 1.0 / (w.rate * st.fire * FIRE_RATE_MULT)
		_mflash_t[i] = 1.0
		_mflash[i].material_override = Models.glow_mat(Color(Color(w.color).lerp(Color.WHITE, 0.5), 0.9))
		_mflash[i].mesh.size = Vector2.ONE * (0.35 + Vector2(w.size).x * 0.1)  # a small, sharp flash at the barrels
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

# ---------------------------------------------------------------- mining beams and tractor beams

## Where slot i's beam lands on the locked target (its surface, on the side facing that turret).
func _beam_point(i: int):
	if beam_lock == null or not main.target_valid(beam_lock):
		return null
	var c: Vector3 = beam_lock.global_position
	var from: Vector3 = muzzles[i].global_position if i < muzzles.size() else position
	return c + (from - c).normalized() * beam_lock.radius * 0.9


## Mining beams: a click locks them on to the rock (or ship, or container) under the crosshair and they keep
## cutting it on their own - the turrets track it whatever the crosshair does - until it's used up or you click
## again to stop. A better mark sends more of the ore it cuts straight into the hold.
func _update_beams(delta: float) -> void:
	if _beams.is_empty():
		return
	if not alive or main.mode != "fly":
		beam_lock = null
	elif beam_lock != null and not main.target_valid(beam_lock):
		beam_lock = null
		Game.say("Mining beam: target gone - click another rock.", Color("8cd8ff"))
	elif control and not main.cursor_free() and Input.is_action_just_pressed("fire"):
		if beam_lock != null:
			beam_lock = null  # click again: stop
		else:
			var t = main.aim_target
			if t != null and is_instance_valid(t) and not t.is_in_group("npcs") and \
					position.distance_to(t.global_position) < BEAM_RANGE + t.radius + radius:
				beam_lock = t
	if beam_lock != null and position.distance_to(beam_lock.global_position) > (BEAM_RANGE + beam_lock.radius + radius) * 2.0:
		beam_lock = null  # flown well away from it
	var lo := Game.loadout()
	var any := false
	var power := 0.0
	var dmg := 0.0
	var collect := 0.0
	var col := Color.WHITE
	for i in _beams.size():
		var holder = _beams[i]
		if holder == null:
			continue
		var p = _beam_point(i)
		if p == null or i >= guns_ready.size() or not guns_ready[i] or position.distance_to(p) > BEAM_RANGE + radius:
			holder.visible = false
			continue
		var w: Dictionary = Game.WEAPONS[lo[i]]
		var core: MeshInstance3D = holder.get_child(0)
		var width: float = core.get_meta("width") * gun_scale(muzzles[i]) * (1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.04 + i * 1.7))
		place_beam(holder, muzzles[i].global_position, p, width)
		any = true
		var k: float = w.rate * st.fire * FIRE_RATE_MULT * delta
		power += w.mining * st.mining * k
		dmg += w.damage * st.damage * k
		collect = maxf(collect, BEAM_COLLECT[w.tier - 1])
		col = w.color
	if any and beam_lock != null:
		var to_ship: Vector3 = (position - beam_lock.global_position).normalized()
		if beam_lock.is_in_group("asteroids"):
			beam_lock.hit(power, -to_ship, collect)
		else:
			_beam_dmg += dmg
			if _beam_dmg >= 4.0 or beam_lock.get("hp") != null and _beam_dmg >= beam_lock.hp:
				beam_lock.take_damage(_beam_dmg)
				_beam_dmg = 0.0
		_beam_fx -= delta
		if _beam_fx <= 0.0 and main.target_valid(beam_lock):
			_beam_fx = 0.12
			var at: Vector3 = beam_lock.global_position + to_ship * beam_lock.radius * 0.9
			main.rock_hit(at, col, to_ship)
	Sfx.set_beam(1.0 if any else 0.0)


## How far the tractor beam reaches: a short pull on every ship, much further with Tractor Beam modules (and
## the big ships reach further anyway).
func tractor_range() -> float:
	return st.get("tractor", 90.0) + radius * 1.5


## Faint beams to the loose chunks the tractor is pulling in (the chunks pull themselves: see ore_chunk.gd).
func _update_tractor() -> void:
	var pulled := []
	var reach := tractor_range()
	if alive and main.mode in ["fly", "warp"]:
		for c in main.group("chunks"):
			if c.tractored and position.distance_to(c.position) < reach:
				pulled.append(c)
	pulled.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
	while _tractor.size() < mini(pulled.size(), TRACTOR_BEAMS):
		_tractor.append(_beam_node(Color(0.45, 0.85, 1.0), 0.5 + radius * 0.02))
	for i in _tractor.size():
		if i < pulled.size():
			place_beam(_tractor[i], position, pulled[i].position, _tractor[i].get_child(0).get_meta("width"))
			_tractor[i].get_child(1).scale = Vector3.ONE * 0.4
		else:
			_tractor[i].visible = false