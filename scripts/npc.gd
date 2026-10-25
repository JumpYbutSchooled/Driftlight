extends Node3D
## Civilian traffic that makes a location feel lived in. Haulers lift off the pad in the station's docking
## bay, fly out through its mouth, run out to far points (the gate, the ore field, empty space), then line
## up in front of the bay again and fly back in to land. Miners hover beside
## asteroids working them with a mining beam, then move on to another rock. Harmless and untouchable,
## but you can select them and fly alongside.

const Ship = preload("res://scripts/ship.gd")
const Turrets = preload("res://scripts/turrets.gd")
const NAMES := ["Patient Mule", "Long Haul", "Coreward", "Saltwind", "Ironbelly", "Lantern", "Quiet Margin",
	"Brass Gull", "Halcyon", "Old Reliable", "Ninth Ledger", "Morrow", "Slow Comet", "Tallyman", "Weathervane",
	"Second Wind", "Kettle", "Far Harbour", "Dust Choir", "Good Return"]

var main
var role := "hauler"  # hauler or miner
var ship_name := ""
var radius := 6.0
var speed := 80.0
var home := Vector3.ZERO  # haulers: the landing pad in the docking bay.  miners: the middle of the ore field
var lane := Vector3.ZERO  # haulers: out in front of the bay's mouth, where they line up to go in or out
var home_out := Vector3.FORWARD  # which way the bay faces
var _leg := ""  # haulers: "in" (lining up, then into the bay) or "out" (leaving it)
var route := []  # far points a hauler runs to
var model: Node3D
var vel := Vector3.ZERO
var _goal := Vector3.ZERO
var _docked := 0.0  # seconds left inside the station
var _plumes := []
var _nozzles := []
var _guns
var _rock: Node3D
var _work := 0.0
var _work_len := 30.0
var _beam: MeshInstance3D
var _beam_col := Color.WHITE
var _spark_t := 0.0


func setup(kind: String, model_id: String, rng: RandomNumberGenerator) -> void:
	role = kind
	ship_name = NAMES[rng.randi() % NAMES.size()]
	model = Models.ship(model_id)
	add_child(model)
	var size := Models.size(model_id)
	radius = maxf(size.x, size.z) * 0.5
	speed = rng.randf_range(20.0, 34.0) if role == "hauler" else rng.randf_range(12.0, 20.0)
	_guns = Turrets.new(model)  # armed like any ship, but they never need them here
	for e in Models.markers(model, "Engine"):
		_nozzles.append(Ship.nozzle_size(e))
		var pl := Ship.plume(_nozzles[-1])
		e.add_child(pl)
		_plumes.append(pl)

	if role == "miner":
		_beam = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.35
		cm.height = 1.0
		cm.radial_segments = 8
		_beam.mesh = cm
		_beam.top_level = true
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.visible = false
		add_child(_beam)
	add_to_group("npcs")
	_next_goal()


func overview_name() -> String:
	return "%s  (%s)" % [ship_name, "Hauler" if role == "hauler" else "Miner"]


func describe() -> String:
	return overview_name() + ("  -  working an asteroid" if _work > 0.0 and _rock else "")


func _next_goal() -> void:
	if role == "miner":
		_rock = null
		var rocks := get_tree().get_nodes_in_group("asteroids").filter(func(a): return a.position.distance_to(home) < 3500.0)
		if rocks.is_empty():
			_goal = home + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 800.0
			return
		_rock = rocks.pick_random()
		var side := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()
		_goal = _rock.position + side * (_rock.radius + radius + 40.0)
		_work = 0.0
		_work_len = randf_range(25.0, 50.0)
	else:
		if not route.is_empty() and randf() < 0.6:
			_goal = route.pick_random()
			_leg = ""
		else:
			_goal = lane  # head home: line up in front of the bay first
			_leg = "in"


func _process(delta: float) -> void:
	if _docked > 0.0:
		_docked -= delta
		if _docked <= 0.0:
			# lift off and fly out of the bay
			visible = true
			position = home
			vel = home_out * speed * 0.2
			_goal = lane
			_leg = "out"
		return
	var to := _goal - position
	var d := to.length()
	var want := Vector3.ZERO
	if role == "miner" and _rock != null and is_instance_valid(_rock) and d < 40.0:
		_mine(delta)
	else:
		if _beam:
			_beam.visible = false
		want = to / maxf(d, 0.01) * minf(speed, d * 0.5 + 8.0)
		if d < 40.0:
			if role == "hauler" and _goal.distance_to(home) < 1.0:
				visible = false  # landed
				_docked = randf_range(15.0, 45.0)
				return
			if role == "hauler" and _leg == "in" and _goal.distance_to(lane) < 1.0:
				_goal = home  # lined up: straight in to the pad
				return
			if role == "hauler" and _leg == "out":
				_leg = ""
				_goal = route.pick_random() if not route.is_empty() else lane + home_out * 4000.0
				return
			_next_goal()
	vel = vel.move_toward(want, speed * 0.6 * delta)
	position += vel * delta
	position += main.push_out(position, radius * 0.6)
	var face := vel if vel.length() > 2.0 else (_rock.position - position if _rock and is_instance_valid(_rock) else Vector3.ZERO)
	if face.length() > 0.1:
		var f := face.normalized()
		var target := Basis.looking_at(f, Vector3.UP if absf(f.y) < 0.98 else Vector3.RIGHT)
		basis = basis.slerp(target, 1.0 - exp(-1.5 * delta)).orthonormalized()
	var power := clampf(vel.length() / speed, 0.0, 1.0)
	for i in _plumes.size():
		Ship.set_plume(_plumes[i], _nozzles[i] * (2.5 + 5.0 * power), 0.2 + 0.7 * power, Color(0.55, 0.7, 1.0))


## Hover by the rock with the mining beam on it; move on after a while (they don't really use the rock up).
func _mine(delta: float) -> void:
	_work += delta
	var surface: Vector3 = _rock.position + (position - _rock.position).normalized() * _rock.radius * 0.9
	var from := global_position + (surface - global_position).normalized() * radius * 0.6
	var mid := (from + surface) / 2.0
	var length := from.distance_to(surface)
	_beam.visible = length > 1.0 and fmod(_work, 9.0) < 7.0
	if _beam.visible:
		var col: Color = Game.ORES[_rock.ore_id].color
		if col != _beam_col:
			_beam_col = col
			_beam.material_override = Models.bright_mat(col.lerp(Color.WHITE, 0.3), 5.0)
		var dir := (surface - from) / length
		var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI / 2.0)
		_beam.global_transform = Transform3D(b * Basis.from_scale(Vector3(1.0, length, 1.0)), mid)
		_spark_t -= delta
		if _spark_t <= 0.0 and global_position.distance_to(main.player.position) < 2500.0:
			_spark_t = randf_range(0.3, 0.8)
			main.rock_hit(surface, col, (from - surface).normalized())
	if _work > _work_len:
		_next_goal()
