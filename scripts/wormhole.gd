extends Node3D
## A wormhole: a turning spiral of light that always faces you, with a purple glow and light.

const SHADER = preload("res://shaders/wormhole.gdshader")

var _disc: MeshInstance3D


func _ready() -> void:
	_disc = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.05
	cm.radial_segments = 64
	_disc.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_disc.material_override = m
	_disc.scale = Vector3(160.0, 1.0, 160.0)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	add_child(Models.glow_quad(Color(0.7, 0.35, 1.0, 0.6), 560.0))
	var light := OmniLight3D.new()
	light.light_color = Color("b366ff")
	light.light_energy = 6.0
	light.omni_range = 900.0
	add_child(light)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		# keep the disc turned toward the camera so it always reads as a hole in space
		var to := (cam.global_position - global_position).normalized()
		if to.length() > 0.1:
			_disc.global_basis = Basis.looking_at(to, Vector3.UP if absf(to.y) < 0.98 else Vector3.RIGHT) \
				* Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(160.0, 1.0, 160.0))
