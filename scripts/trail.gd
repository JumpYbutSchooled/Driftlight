extends MeshInstance3D
## A smooth glowing ribbon left behind an engine: it remembers where its parent (an Engine marker) has
## been for the last moment and draws a camera-facing strip through those points, narrowing and fading
## toward the tail. Lives in world space (top_level) so the ribbon stays where the ship has been.

const LIFE := 0.35  # seconds of history drawn
const JUMP := 25.0  # a bigger move than this in one frame is a teleport (warp arrival): start afresh

var width := 1.0
var color := Color(1.0, 0.6, 0.25, 0.6)
var emitting := false
var _pts := []  # [position, age]
var _im := ImmediateMesh.new()
static var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.vertex_color_use_as_albedo = true
	material_override = _mat


func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for p in _pts:
		p[1] += delta
	while not _pts.is_empty() and _pts[0][1] > LIFE:
		_pts.pop_front()
	var parent := get_parent() as Node3D
	if emitting and parent and parent.is_visible_in_tree():
		if not _pts.is_empty() and (_pts[-1][0] as Vector3).distance_to(parent.global_position) > JUMP:
			_pts.clear()
		_pts.append([parent.global_position, 0.0])
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if _pts.size() < 2 or cam == null:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _pts.size()
	for i in n:
		var pos: Vector3 = _pts[i][0]
		var nxt: Vector3 = _pts[mini(i + 1, n - 1)][0]
		var prv: Vector3 = _pts[maxi(i - 1, 0)][0]
		var along := nxt - prv
		if along.length_squared() < 0.000001:
			along = Vector3.FORWARD
		var side := along.cross(cam.global_position - pos).normalized()
		var k := 1.0 - clampf(_pts[i][1] / LIFE, 0.0, 1.0)  # 1 at the engine, 0 at the tail
		var c := Color(color, color.a * k * k * minf(1.0, float(i) / 3.0 + 0.2))
		var w := width * (0.25 + 0.75 * k) * 0.5
		_im.surface_set_color(c)
		_im.surface_add_vertex(pos + side * w)
		_im.surface_set_color(c)
		_im.surface_add_vertex(pos - side * w)
	_im.surface_end()
