extends MultiMeshInstance3D
## Space dust round the camera, wrapped so there's always some nearby. Fine motes catch the sunlight and
## stretch along your motion, so you feel your speed (in warp they become long streaks rushing past), and
## a few big, very faint puffs of dust drift in a wider box, so space never looks perfectly clean.

const COUNT := 800
const BOX := 160.0
const PUFFS := 40
const PUFF_BOX := 1400.0

var cam: Camera3D
var offset := Vector3.ZERO  # extra scroll (warp): the dust rushes past along -dir
var stretch := 0.0  # 0..1 warp streaking
var dir := Vector3.FORWARD
var _base := []
var _puff_base := []
var _puffs: MultiMeshInstance3D
var _last := Vector3.ZERO
var _vel := Vector3.ZERO


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = COUNT
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.85, 0.8, 0.72, 0.22)
	box.material = m
	mm.mesh = box
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _process(delta: float) -> void:
	if cam == null:
		return
	var cp := cam.global_position + offset
	if delta > 0.0:
		_vel = _vel.lerp((cp - _last) / delta, 0.2)
	_last = cp
	var move := _vel
	if stretch > 0.0:
		move = dir * 600.0 * stretch
	var length := clampf(move.length() * 0.025, 0.1, 45.0)
	var d := move.normalized() if move.length() > 0.5 else Vector3.FORWARD
	var b3 := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT).scaled_local(Vector3(1, 1, length))
	for i in COUNT:
		var b: Vector3 = _base[i]
		var p := Vector3(fposmod(b.x - cp.x, BOX), fposmod(b.y - cp.y, BOX), fposmod(b.z - cp.z, BOX)) - Vector3.ONE * BOX * 0.5
		multimesh.set_instance_transform(i, Transform3D(b3, cam.global_position + p))
	_puffs.global_transform = Transform3D.IDENTITY
	for i in PUFFS:
		var b: Vector3 = _puff_base[i][0]
		var p := Vector3(fposmod(b.x - cp.x, PUFF_BOX), fposmod(b.y - cp.y, PUFF_BOX), fposmod(b.z - cp.z, PUFF_BOX)) \
			- Vector3.ONE * PUFF_BOX * 0.5
		_puffs.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * _puff_base[i][1]), cam.global_position + p))
