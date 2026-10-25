extends Node3D
## The warp tunnel around your ship, EVE style: three nested tubes of streaming light wrapped round the
## ship along its heading, and thin threads of light rushing past. `power` 0..1 fades
## it in and out; the main script drives it from the warp phase. Sized from the camera distance so the
## camera always sits inside the tunnel.

const SHADER = preload("res://shaders/warp3d.gdshader")

var power := 0.0
var tint := Color(0.45, 0.7, 1.0)
var heading := Vector3.FORWARD
var radius := 30.0
var _layers := []
var _streaks: CPUParticles3D


func _ready() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 48
	cm.rings = 16
	cm.cap_top = false
	cm.cap_bottom = false
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("layer", float(i))
		m.set_shader_parameter("speed", [1.6, 2.4, 3.4][i])
		m.set_shader_parameter("twist", [0.12, -0.08, 0.2][i])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_layers.append(mi)
	_streaks = CPUParticles3D.new()
	_streaks.amount = 360
	_streaks.lifetime = 0.5
	_streaks.local_coords = true
	_streaks.mesh = Models.streak_mesh(0.4, 40.0)
	_streaks.particle_flag_align_y = true
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_streaks.direction = Vector3(0, 0, 1)
	_streaks.spread = 2.0
	_streaks.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.85, 0.95, 1.0, 0.7), Color(0.6, 0.8, 1.0, 0)])
	_streaks.color_ramp = g
	_streaks.emitting = false
	add_child(_streaks)
	visible = false


func place(at: Vector3) -> void:
	global_position = at
	if heading.length() > 0.01:
		global_basis = Basis.looking_at(heading, Vector3.UP if absf(heading.normalized().y) < 0.98 else Vector3.RIGHT)


func _process(_delta: float) -> void:
	visible = power > 0.01
	_streaks.emitting = power > 0.3
	if not visible:
		return
	var length := radius * 60.0
	for i in _layers.size():
		var mi: MeshInstance3D = _layers[i]
		var r: float = radius * [1.0, 1.35, 1.8][i]
		# the cylinder's height runs along local Y: lay it along -Z (forward) with the front (+Y) ahead
		mi.basis = Basis(Vector3.RIGHT, -PI / 2.0) * Basis.from_scale(Vector3(r, length, r))
		var m: ShaderMaterial = mi.material_override
		m.set_shader_parameter("intensity", power * [1.0, 0.7, 0.45][i])
		m.set_shader_parameter("tint", tint)
	_streaks.emission_sphere_radius = radius * 1.2
	_streaks.position = Vector3(0, 0, -radius * 6.0)
	_streaks.initial_velocity_min = radius * 30.0
	_streaks.initial_velocity_max = radius * 45.0
