extends Node3D
## An ore vein: a huge rock (tens of metres across) holding 15-100 ore. Shooting it splits ore chunks off
## the side you hit until it's empty; rarer ores are harder. The survey scanner (V) reveals what's in it.

const ROCK_SHADER = preload("res://shaders/rock.gdshader")

var main
var ore_id := "corrite"
var quality := 0
var total := 20
var remaining := 20
var radius := 5.0
var _base_r := 5.0
var scanned := false
var _acc := 0.0
var _spin_axis := Vector3.UP
var _spin := 0.0
var _drift := Vector3.ZERO
var _hit_t := 0.0
var _mesh: MeshInstance3D
var _mat: ShaderMaterial


func setup(ore: String, q: int, amount: int, rock_seed: int, size: float) -> void:
	ore_id = ore
	quality = q
	total = amount
	remaining = amount
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	_base_r = size
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Models.rock_mesh(rng.randi())
	_mat = ShaderMaterial.new()
	_mat.shader = ROCK_SHADER
	_mat.set_shader_parameter("ore_color", Game.ORES[ore].color)
	_mat.set_shader_parameter("ore_amount", [0.22, 0.3, 0.4, 0.5][q])
	_mat.set_shader_parameter("glow", [0.1, 0.25, 0.5, 0.9][q])
	_mat.set_shader_parameter("sparkle", 1.0 if q == 3 else 0.0)
	_mat.set_shader_parameter("offset", Vector3(rng.randf() * 50.0, rng.randf() * 50.0, rng.randf() * 50.0))
	_mat.set_shader_parameter("size", size)
	_mesh.material_override = _mat
	add_child(_mesh)
	rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	_spin_axis = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	_spin = rng.randf_range(-0.04, 0.04)  # big rocks turn slowly
	_drift = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * 0.15
	add_to_group("asteroids")
	_resize()


func describe() -> String:
	if not scanned:
		return "Asteroid  -  %d m across  -  V to survey it" % roundi(radius * 2.0)
	return "%s vein (%s)  -  %d ore left  -  %d%% to next piece" % [Game.ORES[ore_id].name, Game.Q_NAMES[quality], remaining,
		roundi(_acc / Game.hardness(ore_id) * 100.0)]


func _resize() -> void:
	var s := _base_r * (0.45 + 0.55 * sqrt(float(remaining) / total))
	_mesh.scale = Vector3.ONE * s
	radius = s * 1.05


func _process(delta: float) -> void:
	rotate(_spin_axis, _spin * delta)
	position += _drift * delta
	if _hit_t > 0.0:
		_hit_t = maxf(0.0, _hit_t - delta * 6.0)
		_mat.set_shader_parameter("hit", _hit_t * 0.06)


## A brief glint when the survey scanner's pulse reaches this rock, delay seconds from now.
func ping(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(self):
		_hit_t = 4.0  # a brighter glint than a bolt hit


func hit(power: float, dir: Vector3) -> void:
	if remaining <= 0:
		return
	_hit_t = 1.0
	_acc += power
	var cost := Game.hardness(ore_id)
	while _acc >= cost and remaining > 0:
		_acc -= cost
		remaining -= 1
		# pieces break off the side you're shooting at
		var out := (-dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.45).normalized()
		var amount := 2 if Game.blessings.has("plenty") else 1
		main.spawn_chunk(ore_id, quality, amount, position + out * radius * 0.9, out * randf_range(6.0, 12.0) - dir * 3.0)
	if remaining <= 0:
		main.explosion(position, minf(radius / 6.0, 6.0), Game.ORES[ore_id].color, true)
		queue_free()
		return
	_resize()
