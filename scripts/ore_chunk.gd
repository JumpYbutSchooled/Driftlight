extends Node3D
## A chunk of ore-bearing rock knocked off a vein. It tumbles away, slows to a stop and waits there until
## you fly into it to collect it (it never disappears). Better quality ore shows more, brighter veins.

const ROCK_SHADER = preload("res://shaders/rock.gdshader")

var main
var ore_id := "corrite"
var quality := 0
var amount := 1
var vel := Vector3.ZERO
var radius := 1.6
var _spin := Vector3.ZERO
var _mesh: MeshInstance3D
static var _mats := {}


func _ready() -> void:
	_spin = Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Models.rock_mesh(randi())
	_mesh.material_override = _material(ore_id, quality)
	radius = randf_range(1.4, 2.0) * (1.0 + 0.15 * amount)
	_mesh.scale = Vector3.ONE * radius
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var c: Color = Game.ORES[ore_id].color
	add_child(Models.glow_quad(Color(c, 0.18 + 0.1 * quality), radius * 3.0))
	add_to_group("chunks")


## Rock that's mostly ore, shared by every chunk of the same ore and quality.
static func _material(ore: String, q: int) -> ShaderMaterial:
	var key := "%s:%d" % [ore, q]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = ROCK_SHADER
		m.set_shader_parameter("ore_color", Game.ORES[ore].color)
		m.set_shader_parameter("ore_amount", [0.45, 0.55, 0.65, 0.75][q])
		m.set_shader_parameter("glow", [0.35, 0.6, 0.9, 1.4][q])
		m.set_shader_parameter("sparkle", 1.0 if q == 3 else 0.0)
		m.set_shader_parameter("offset", Vector3(randf() * 50.0, randf() * 50.0, randf() * 50.0))
		m.set_shader_parameter("size", 1.8)
		m.set_shader_parameter("bump", 0.4)
		m.set_shader_parameter("ore_tint", 0.35)
		_mats[key] = m
	return _mats[key]


func describe() -> String:
	return "%s ore (%s)  x%d  -  fly into it to collect" % [Game.ORES[ore_id].name, Game.Q_NAMES[quality], amount]


func _physics_process(delta: float) -> void:
	position += vel * delta
	vel = vel.move_toward(Vector3.ZERO, 3.0 * delta)
	rotation += _spin * delta * clampf(vel.length() / 4.0, 0.15, 1.0)
	var p = main.player
	if not p.alive:
		return
	var to: Vector3 = p.position - position
	var d := to.length()
	if p.st.tractor and d < 60.0:
		vel = vel.move_toward(to.normalized() * 30.0, 70.0 * delta)
	if d < p.radius + radius + 1.5:
		if Game.add_cargo(ore_id, quality, amount):
			Sfx.play("pickup", -12.0, randf_range(0.95, 1.1))
			queue_free()
		else:
			main.cargo_full()
