extends Node3D
## A stargate: the Blender ring model (shown five times its built size, about 250 m across), a shimmering
## energy sheet across it, lights, and a sign.

const FIELD_SHADER = preload("res://shaders/gate_field.gdshader")

var color := Color("4aa8ff")
var dest := ""


func _ready() -> void:
	add_child(Models.prop("gate"))
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.05
	cm.radial_segments = 48
	disc.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = FIELD_SHADER
	m.set_shader_parameter("color", color)
	disc.material_override = m
	disc.scale = Vector3(107.0, 1.0, 107.0)
	disc.rotation.x = PI / 2.0  # the ring stands in the XY plane; ships fly through along Z
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.5
	light.omni_range = 450.0
	add_child(light)
	var sign := Label3D.new()
	sign.text = "STARGATE\nto " + dest
	sign.font = ThemeDB.fallback_font
	sign.font_size = 96
	sign.outline_size = 16
	sign.modulate = color.lightened(0.4)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 180, 0)
	sign.pixel_size = 0.3
	add_child(sign)
