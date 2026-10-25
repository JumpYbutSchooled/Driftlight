extends Node
## Loads the Blender-made models (models/*.glb, built by tools/blender), swaps their plain painted
## materials for the hull detail shader, and makes the shared glow materials, textures and meshes the 3D
## effects use.

const HULL_SHADER = preload("res://shaders/hull.gdshader")
const HULL_2S = preload("res://shaders/hull_2s.gdshader")

var meta := {}  # per ship: hull [W, L, H], size [x, length, height], guns  (Blender axes, metres)
var _scenes := {}
var _meshes := {}
var _mats := {}
var _detailed := {}  # [imported material, scale] -> its hull-shader replacement
# props shown bigger than they were built (the citadel is built full size; these are scaled up in game)
const PROP_SCALE := {"station": 3.0, "gate": 5.0, "obelisk": 4.0, "spice_stand": 3.0, "wreck": 4.0, "crate": 1.5}
# sub-panels per model unit: the full-size citadel gets coarser plating lines than ship-scale models
const PROP_PANEL := {"station": 1.3}
var _radial: GradientTexture2D
var _ring: GradientTexture2D


func _ready() -> void:
	var f := FileAccess.open("res://models/ship_meta.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			meta = data
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	_radial = GradientTexture2D.new()
	_radial.gradient = g
	_radial.fill = GradientTexture2D.FILL_RADIAL
	_radial.fill_from = Vector2(0.5, 0.5)
	_radial.fill_to = Vector2(1.0, 0.5)
	_radial.width = 64
	_radial.height = 64
	var rg := Gradient.new()
	rg.offsets = PackedFloat32Array([0.0, 0.6, 0.82, 0.9, 1.0])
	rg.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	_ring = GradientTexture2D.new()
	_ring.gradient = rg
	_ring.fill = GradientTexture2D.FILL_RADIAL
	_ring.fill_from = Vector2(0.5, 0.5)
	_ring.fill_to = Vector2(1.0, 0.5)
	_ring.width = 256
	_ring.height = 256


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## A ship model (player ship or pirate) with its animations playing.
func ship(id: String) -> Node3D:
	var folder := "ships" if Game.SHIPS.has(id) else "enemies"
	var n: Node3D = _scene("res://models/%s/%s.glb" % [folder, id]).instantiate()
	play_anims(n)
	_detail(n)
	return n


func prop(prop_name: String) -> Node3D:
	var n: Node3D = _scene("res://models/props/%s.glb" % prop_name).instantiate()
	play_anims(n)
	var k: float = PROP_SCALE.get(prop_name, 1.0)
	n.scale = Vector3.ONE * k
	_detail(n, k, PROP_PANEL.get(prop_name, 1.6 * k), 1.0 if prop_name == "turret" else 0.45)
	return n


## Gives every plain painted surface in a model the hull detail shader (see-through surfaces keep their
## imported material; glowing ones too, dimmed by `glow` - lamps and windows that look right on a ship
## are too much spread over a whole station).
func _detail(node: Node, scale_k := 1.0, panel := 1.6, glow := 1.0) -> void:
	var stack := [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(i)
			if not m is StandardMaterial3D or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if m.emission_enabled:
				if glow != 1.0:
					var gkey := [m, glow]
					if not _detailed.has(gkey):
						var dim: StandardMaterial3D = m.duplicate()
						dim.emission_energy_multiplier *= glow
						_detailed[gkey] = dim
					mi.set_surface_override_material(i, _detailed[gkey])
				continue
			var key := [m, panel]
			if not _detailed.has(key):
				var sm := ShaderMaterial.new()
				# open tubes (engine bells) are seen from inside too; everything else is closed and one-sided
				sm.shader = HULL_2S if String(m.resource_name).contains("engine_bell") else HULL_SHADER
				sm.set_shader_parameter("albedo", m.albedo_color)
				sm.set_shader_parameter("metallic", m.metallic)
				sm.set_shader_parameter("roughness", m.roughness)
				sm.set_shader_parameter("panel", panel)
				if String(m.resource_name).contains("_win"):
					sm.set_shader_parameter("windows", 0.35)
					# windows stay a real size (a few metres) however much the model is scaled up
					sm.set_shader_parameter("window_cell", Vector2(2.6, 3.8) / scale_k)
				_detailed[key] = sm
			mi.set_surface_override_material(i, _detailed[key])


## The first mesh inside a model file (for things drawn many times with our own materials).
func mesh_of(path: String) -> Mesh:
	if not _meshes.has(path):
		var n := _scene(path).instantiate()
		var mi := _find_mesh(n)
		_meshes[path] = mi.mesh if mi else BoxMesh.new()
		n.free()
	return _meshes[path]


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null


func rock_mesh(i: int) -> Mesh:
	return mesh_of("res://models/props/rock_%d.glb" % posmod(i, 6))


func crystal_mesh() -> Mesh:
	return mesh_of("res://models/props/crystal.glb")


## Marker empties from Blender (Muzzle_0, Engine_1, ...) under `node`, in number order.
func markers(node: Node, prefix: String) -> Array:
	var out := []
	var stack := [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name.begins_with(prefix):
			out.append(n)
		stack.append_array(n.get_children())
	out.sort_custom(func(a, b): return int(str(a.name).get_slice("_", 1)) < int(str(b.name).get_slice("_", 1)))
	return out


## Every animation in a model loops forever (station ring, gate collar, obelisk shards, sentinel plates).
func play_anims(node: Node) -> void:
	var stack := [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			var names: PackedStringArray = n.get_animation_list()
			for a in names:
				n.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			if not names.is_empty():
				n.play(names[0])
		stack.append_array(n.get_children())


## Hull box of a ship in Godot axes (width, height, length), for the can't-shoot-through-your-hull check.
func hull(id: String) -> Vector3:
	var h: Array = meta.get(id, {}).get("hull", [5, 6, 1.6])
	return Vector3(h[0], h[2], h[1])


## Overall size of a ship in Godot axes (width, height, length).
func size(id: String) -> Vector3:
	var s: Array = meta.get(id, {}).get("size", [6, 7, 2])
	return Vector3(s[0], s[2], s[1])


## Additive, camera-facing glow (engines, bolts, lights). Cached per colour.
func glow_mat(color: Color) -> StandardMaterial3D:
	var key := "glow:" + color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = _radial
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.albedo_color = color
		_mats[key] = m
	return _mats[key]


## Material for particle quads: additive glowing sparks, or soft smoke.
func particle_mat(additive := true) -> StandardMaterial3D:
	var key := "particle:%s" % additive
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _radial
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_mats[key] = m
	return _mats[key]


## A solid, very bright material (bolts, crystals): blooms through the glow pass.
func bright_mat(color: Color, energy := 4.0) -> StandardMaterial3D:
	var key := "bright:%s:%s" % [color.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color.darkened(0.3)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


func glow_quad(color: Color, size_m: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = glow_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A soft round blob (clouds, haze).
func soft_texture() -> Texture2D:
	return _radial


## Additive particle material without billboarding, for meshes that point along their velocity (streaks).
func streak_mat() -> StandardMaterial3D:
	if not _mats.has("streak"):
		var m: StandardMaterial3D = particle_mat(true).duplicate()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["streak"] = m
	return _mats["streak"]


## Two crossed quads along +Y, so a spark stretched along its flight path shows from any angle.
func streak_mesh(width: float, length: float) -> ArrayMesh:
	var key := "streak:%s:%s" % [width, length]
	if not _meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			var a: Vector3 = axis * width * 0.5
			var h := Vector3.UP * length * 0.5
			var quad := [[-a - h, Vector2(0, 1)], [a - h, Vector2(1, 1)], [a + h, Vector2(1, 0)], [-a + h, Vector2(0, 0)]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color.WHITE)
				st.set_uv(quad[k][1])
				st.add_vertex(quad[k][0])
		var mesh := st.commit()
		mesh.surface_set_material(0, streak_mat())
		_meshes[key] = mesh
	return _meshes[key]


## A flat additive ring (explosion shockwaves). Cached per colour.
func ring_mat(color: Color) -> StandardMaterial3D:
	var key := "ring:" + color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = _ring
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.albedo_color = color
		_mats[key] = m
	return _mats[key]


## Scorched hull material for explosion debris.
func debris_mat() -> StandardMaterial3D:
	if not _mats.has("debris"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.16, 0.18)
		m.metallic = 0.6
		m.roughness = 0.7
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.1)
		m.emission_energy_multiplier = 0.6
		_mats["debris"] = m
	return _mats["debris"]