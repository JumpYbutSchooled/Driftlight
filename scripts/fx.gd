extends Node3D
## One-shot 3D effects: explosions (white-hot flash, fireball, shockwave, streaking sparks, smoke, embers
## and tumbling debris), rocks bursting into dust and chunks, impact sparks and the directional warp
## particles. Built from CPU particles with glowing quads plus a short light flash; frees itself when
## everything has faded.

var _life := 0.5
var _t := 0.0
var _debris := []  # [node, velocity, spin axis, spin speed, size]


func _process(delta: float) -> void:
	_t += delta
	for d in _debris:
		var n: Node3D = d[0]
		n.position += d[1] * delta
		d[1] *= exp(-0.35 * delta)
		n.rotate(d[2], d[3] * delta)
		n.scale = Vector3.ONE * d[4] * clampf((_life - 0.3 - _t) / 0.8, 0.0, 1.0)
	if _t > _life:
		queue_free()


static func _ramp(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 4.0
	for p in points:
		c.add_point(p)
	return c


func _burst(n: int, color: Color, spd: float, life: float, size_m: float, additive := true, dir := Vector3.ZERO,
		spread := 180.0, local := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, n)
	p.lifetime = life
	p.local_coords = local
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	q.material = Models.particle_mat(additive)
	p.mesh = q
	p.gravity = Vector3.ZERO
	if dir != Vector3.ZERO:
		p.direction = dir
	p.spread = spread
	p.initial_velocity_min = spd * 0.35
	p.initial_velocity_max = spd
	p.damping_min = spd * 0.4
	p.damping_max = spd * 0.9
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0.25)])
	p.color_ramp = _ramp([Color(color, color.a), Color(color, 0.0)], [0.0, 1.0])
	add_child(p)
	p.emitting = true
	_life = maxf(_life, life + 0.2)
	return p


func _streaks(n: int, color: Color, spd: float, life: float, width: float, length: float, dir := Vector3.ZERO,
		spread := 180.0) -> CPUParticles3D:
	var p := _burst(n, color, spd, life, 1.0, true, dir, spread)
	p.mesh = Models.streak_mesh(width, length)
	p.particle_flag_align_y = true
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.damping_min = spd * 0.6
	p.damping_max = spd * 1.2
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0.1)])
	return p


func _light(color: Color, range_m: float, energy: float, time: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = range_m
	l.light_energy = energy
	add_child(l)
	create_tween().tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT)
	_life = maxf(_life, time + 0.1)


func _flash(color: Color, size_m: float, grow: float, time: float) -> void:
	var f := Models.glow_quad(color, size_m)
	add_child(f)
	var tw := f.create_tween().set_parallel()
	tw.tween_property(f, "scale", Vector3.ONE * grow, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(f, "transparency", 1.0, time)


func _shockwave(s: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = Models.ring_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(-PI / 2.0 + randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.5, 0.5))
	mi.scale = Vector3.ONE * 2.0 * s
	add_child(mi)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 30.0 * s, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tw.tween_property(mi, "transparency", 1.0, 0.7).set_ease(Tween.EASE_IN)


## Chunks that tumble away, each trailing a thin smoky ember stream.
func _debris_burst(n: int, s: float, mesh_fn: Callable, mat: Material, trail: bool) -> void:
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_fn.call(i)
		mi.material_override = mat
		var size := randf_range(0.35, 1.0) * s
		mi.scale = Vector3.ONE * size
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(mi)
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_debris.append([mi, dir * randf_range(8.0, 22.0) * sqrt(s), Vector3(randf_range(-1, 1), randf_range(-1, 1), 1).normalized(),
			randf_range(-5.0, 5.0), size])
		if trail:
			var p := CPUParticles3D.new()
			p.local_coords = false
			p.amount = 18
			p.lifetime = 0.7
			var q := QuadMesh.new()
			q.size = Vector2.ONE * (0.5 + 0.4 * s)
			q.material = Models.particle_mat(true)
			p.mesh = q
			p.gravity = Vector3.ZERO
			p.spread = 180.0
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 1.0
			p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 1.5)])
			p.color_ramp = _ramp([Color(1, 0.8, 0.4, 0.9), Color(1, 0.35, 0.1, 0.5), Color(0.2, 0.18, 0.2, 0.0)], [0.0, 0.3, 1.0])
			mi.add_child(p)
	_life = maxf(_life, 3.0)


func _box_mesh(_i: int) -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(randf_range(0.4, 1.2), randf_range(0.3, 0.8), randf_range(0.6, 1.6))
	return b


func _rock_piece(i: int) -> Mesh:
	return Models.rock_mesh(i)


func explode(s: float, color: Color, rocky := false) -> void:
	if rocky:
		_rock_burst(s, color)
		return
	_flash(Color(1.0, 0.92, 0.75, 1.0), 9.0 * s, 2.4, 0.35)
	# a fireball of billowing puffs cooling from white through orange to dark red
	var fire := _burst(int(14 * s) + 8, Color.WHITE, 9.0 * s, 1.0, 3.4 * s)
	fire.lifetime_randomness = 0.4
	fire.color_ramp = _ramp([Color(1, 1, 0.9, 1), Color(1, 0.72, 0.3, 0.95), Color(1, 0.32, 0.08, 0.6), Color(0.3, 0.06, 0.04, 0.0)],
		[0.0, 0.18, 0.5, 1.0])
	fire.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(0.3, 1.0), Vector2(1, 1.4)])
	_burst(int(10 * s) + 4, color, 16.0 * s, 0.7, 2.0 * s)
	_streaks(int(28 * s) + 10, Color(1.0, 0.85, 0.5), 48.0 * sqrt(s), 0.8, 0.12 + 0.08 * s, 1.2 + 0.8 * s)
	_shockwave(s, color.lerp(Color(1.0, 0.8, 0.55), 0.5))
	# smoke that hangs around after the fire is out
	var smoke := _burst(int(8 * s) + 5, Color.WHITE, 5.0 * s, 2.8, 4.8 * s, false)
	smoke.lifetime_randomness = 0.3
	smoke.color_ramp = _ramp([Color(0.3, 0.22, 0.18, 0.0), Color(0.2, 0.18, 0.2, 0.55), Color(0.1, 0.1, 0.12, 0.0)], [0.0, 0.12, 1.0])
	smoke.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.8)])
	# embers drifting off
	var em := _burst(int(16 * s) + 8, Color(1.0, 0.6, 0.25), 12.0 * s, 2.2, 0.3 + 0.15 * s)
	em.explosiveness = 0.7
	em.damping_min = 1.0
	em.damping_max = 4.0
	em.lifetime_randomness = 0.5
	_debris_burst(int(3 + 3 * s), s, _box_mesh, Models.debris_mat(), true)
	_light(Color("ffb060"), 45.0 * s, 10.0, 0.8)


## An asteroid breaking up: a dust cloud, tumbling rock chunks and a few glints of its ore.
func _rock_burst(s: float, ore: Color) -> void:
	_flash(Color(1.0, 0.95, 0.85, 0.6), 6.0 * s, 2.0, 0.3)
	var dust := _burst(int(12 * s) + 8, Color.WHITE, 7.0 * s, 3.0, 5.0 * s, false)
	dust.lifetime_randomness = 0.4
	dust.color_ramp = _ramp([Color(0.45, 0.41, 0.37, 0.0), Color(0.42, 0.38, 0.34, 0.5), Color(0.3, 0.28, 0.26, 0.0)], [0.0, 0.1, 1.0])
	dust.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.0)])
	_streaks(int(8 * s) + 6, Color(ore.lerp(Color(1, 0.8, 0.5), 0.4), 0.8), 30.0 * sqrt(s), 0.5, 0.06, 0.7)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.32, 0.29, 0.26).lerp(ore, 0.2)
	rock.roughness = 0.95
	_debris_burst(int(5 + 3 * s), s * 1.6, _rock_piece, rock, false)
	_light(ore.lerp(Color.WHITE, 0.5), 30.0 * s, 3.0, 0.4)


## Bolt impact: a pinpoint flash and a spray of sparks.
func sparks(color: Color, n: int) -> void:
	_flash(Color(color.lerp(Color.WHITE, 0.6), 0.9), 1.6, 1.8, 0.12)
	_streaks(n, color.lerp(Color.WHITE, 0.3), 22.0, 0.35, 0.08, 0.7)
	_light(color, 7.0, 1.6, 0.15)


## A bolt chipping a rock: grit and dust kicked off the surface, with a glint of ore.
func rock_hit(color: Color, normal: Vector3) -> void:
	_flash(Color(color.lerp(Color.WHITE, 0.6), 0.8), 1.4, 1.6, 0.12)
	var d := _burst(5, Color.WHITE, 5.0, 1.2, 2.2, false, normal, 50.0)
	d.color_ramp = _ramp([Color(0.42, 0.38, 0.34, 0.45), Color(0.3, 0.28, 0.26, 0.0)], [0.0, 1.0])
	d.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.5)])
	_streaks(6, Color(color.lerp(Color(1, 0.8, 0.5), 0.4), 0.8), 16.0, 0.35, 0.05, 0.45, normal, 60.0)


## A directional spray of thin streaks of light along `dir` (warp entry blasts backward, arrival sprays
## forward). Streaks only, no round blobs.
func jet(n: int, color: Color, dir: Vector3, spd: float, spread_deg: float, life: float) -> void:
	_streaks(n, color.lightened(0.4), spd * 1.3, life, 0.12, 3.0, dir, spread_deg)


## Continuous smoke and flickering fire pouring off a badly damaged hull (not a one-shot: the caller owns it).
static func damage_emitter(size_m: float) -> Node3D:
	var root := Node3D.new()
	for fire in [false, true]:
		var p := CPUParticles3D.new()
		p.local_coords = false
		p.amount = 14 if fire else 20
		p.lifetime = 0.5 if fire else 1.8
		var q := QuadMesh.new()
		q.size = Vector2.ONE * size_m * (0.7 if fire else 1.2)
		q.material = Models.particle_mat(fire)
		p.mesh = q
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = size_m * 0.6
		p.gravity = Vector3.ZERO
		p.spread = 180.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 2.0
		p.angle_min = -180.0
		p.angle_max = 180.0
		if fire:
			p.color_ramp = _ramp([Color(1, 0.9, 0.6, 0.9), Color(1, 0.4, 0.1, 0.6), Color(0.4, 0.1, 0.05, 0.0)], [0.0, 0.4, 1.0])
			p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0.3)])
		else:
			p.color_ramp = _ramp([Color(0.25, 0.22, 0.22, 0.0), Color(0.18, 0.17, 0.19, 0.5), Color(0.1, 0.1, 0.12, 0.0)], [0.0, 0.15, 1.0])
			p.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.0)])
		root.add_child(p)
	return root
