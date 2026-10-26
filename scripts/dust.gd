extends MultiMeshInstance3D
## Space dust round the camera, wrapped so there's always some nearby. Fine motes catch the sunlight and
## streak out along the path they've taken past you (shaders/dust_trail.gdshader), so you feel your speed -
## and when the ship turns, the streaks bend round the curve with it rather than swinging about as straight
## lines. In warp they become long streaks rushing past. A few big, very faint puffs of dust drift in a wider
## box, so space never looks perfectly clean.

const TRAIL_SHADER = preload("res://shaders/dust_trail.gdshader")
const COUNT := 800
const BOX := 160.0
const PUFFS := 40
const PUFF_BOX := 1400.0
const POINTS := 8  # points along each streak (the shader's too)
const MAX_TRAIL := 45.0  # longest streak, metres (longer in warp)
const MIN_TRAIL := 0.15  # shortest: a mote at rest is still a speck

var cam: Camera3D
var offset := Vector3.ZERO  # extra scroll (warp): the dust rushes past along -dir
var stretch := 0.0  # 0..1 warp streaking
var dir := Vector3.FORWARD
var _base := []
var _puff_base := []
var _puffs: MultiMeshInstance3D
var _mat: ShaderMaterial
var _hist := []  # [time, camera position + scroll], newest last, the last half second or so
var _vel := Vector3.ZERO


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = COUNT
	mm.mesh = _strip()
	multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = TRAIL_SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the motes move every frame wherever the camera goes: never cull them by a stale box
	custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in COUNT:
		_base.append(Vector3(rng.randf(), rng.randf(), rng.randf()) * BOX)
	# the big faint puffs
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.instance_count = PUFFS
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	pmat.albedo_texture = Models.soft_texture()
	pmat.albedo_color = Color(0.3, 0.27, 0.24, 0.05)
	pmat.proximity_fade_enabled = true
	pmat.proximity_fade_distance = 120.0
	pmat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	pmat.distance_fade_min_distance = 60.0
	pmat.distance_fade_max_distance = 260.0
	q.material = pmat
	pm.mesh = q
	_puffs = MultiMeshInstance3D.new()
	_puffs.multimesh = pm
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puffs)
	for i in PUFFS:
		_puff_base.append([Vector3(rng.randf(), rng.randf(), rng.randf()) * PUFF_BOX, rng.randf_range(150.0, 420.0)])


## A thin strip of POINTS pairs of vertices: x -1/+1 across it, z 0 (the mote) to 1 (the end of its trail).
static func _strip() -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in POINTS:
		var z := float(k) / (POINTS - 1)
		verts.append(Vector3(-1.0, 0.0, z))
		verts.append(Vector3(1.0, 0.0, z))
		if k > 0:
			var a := (k - 1) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	if cam == null:
		return
	var cp := cam.global_position + offset
	var now := Time.get_ticks_usec() / 1000000.0
	# a jump (arriving somewhere new) wipes the history, or every mote would streak across the location
	if not _hist.is_empty() and (cp - _hist[-1][1]).length() > 4000.0:
		_hist.clear()
	_hist.append([now, cp])
	while _hist.size() > 2 and now - _hist[1][0] > 0.6:
		_hist.pop_front()
	if delta > 0.0 and _hist.size() >= 2:
		_vel = _vel.lerp((cp - _hist[-2][1]) / maxf(now - _hist[-2][0], 0.001), 0.25)
	_update_trail(now, cp)
	for i in COUNT:
		var b: Vector3 = _base[i]
		var p := Vector3(fposmod(b.x - cp.x, BOX), fposmod(b.y - cp.y, BOX), fposmod(b.z - cp.z, BOX)) - Vector3.ONE * BOX * 0.5
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, cam.global_position + p))
	_puffs.global_transform = Transform3D.IDENTITY
	for i in PUFFS:
		var b: Vector3 = _puff_base[i][0]
		var p := Vector3(fposmod(b.x - cp.x, PUFF_BOX), fposmod(b.y - cp.y, PUFF_BOX), fposmod(b.z - cp.z, PUFF_BOX)) \
			- Vector3.ONE * PUFF_BOX * 0.5
		_puffs.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * _puff_base[i][1]), cam.global_position + p))


## The trail every mote shares: how far the camera has come since each of POINTS moments over a short window
## (shorter the faster you go, so a streak is never longer than MAX_TRAIL). The window follows the camera's real
## path, so on a turn the trail curves.
func _update_trail(now: float, cp: Vector3) -> void:
	var speed := _vel.length()
	var longest := MAX_TRAIL * (1.0 + stretch)
	var window := clampf(longest / maxf(speed, 1.0), 0.03, 0.1)
	var pts := []
	for k in POINTS:
		pts.append(cp - _pos_at(now - window * k / (POINTS - 1.0), cp))
	var length := 0.0
	for k in range(1, POINTS):
		length += (pts[k] - pts[k - 1]).length()
	if length < MIN_TRAIL:
		# barely moving: a short straight speck along the way you're drifting (or just ahead)
		var d := _vel.normalized() if speed > 0.01 else -cam.global_basis.z
		for k in POINTS:
			pts[k] = d * MIN_TRAIL * k / (POINTS - 1.0)
	_mat.set_shader_parameter("trail", PackedVector3Array(pts))


## Where the camera (with the warp scroll) was at time `t`, from the history.
func _pos_at(t: float, fallback: Vector3) -> Vector3:
	if _hist.is_empty():
		return fallback
	if t <= _hist[0][0]:
		return _hist[0][1]
	for i in range(_hist.size() - 1, 0, -1):
		var a: Array = _hist[i - 1]
		var b: Array = _hist[i]
		if t >= a[0]:
			var k: float = (t - a[0]) / maxf(b[0] - a[0], 0.000001)
			return (a[1] as Vector3).lerp(b[1], clampf(k, 0.0, 1.0))
	return _hist[-1][1]
