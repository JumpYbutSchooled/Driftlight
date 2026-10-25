extends Node3D
## A stargate, built as a railgun (tools/blender/props.py gate(), shown five times its built size: about
## 600 m from mouth to muzzle). Its barrel points down local -Z, the way it fires; main.gd turns it to face
## the system it leads to. Ships fly in at the mouth (local +Z end) and the coils launch them out of the
## muzzle. Each coil carries a ring of light that flares as a launch passes through it.

const SCALE := 5.0  # props.py gate() is built at a fifth of its size in game
const COILS := [-48.0, -32.0, -16.0, 0.0, 16.0, 32.0, 48.0]  # coil positions along the barrel (built units, +firing)
const MOUTH := 285.0  # metres from the centre back to the mouth
const MUZZLE := 290.0  # and forward to the muzzle
const BORE := 44.0  # radius of the clear bore through the coils, metres

var color := Color("4aa8ff")
var dest := ""
var _rings := []  # [MeshInstance3D, material] per coil, mouth to muzzle
var _launch_t := -1.0  # seconds into a launch, or -1
var _launch_len := 4.0


func _ready() -> void:
	add_child(Models.prop("gate"))
	var tm := TorusMesh.new()
	tm.inner_radius = BORE + 1.0
	tm.outer_radius = BORE + 5.0
	tm.rings = 48
	tm.ring_segments = 8
	for y in COILS:
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(color.lerp(Color(0.6, 0.95, 1.0), 0.5), 0.12)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.x = PI / 2.0  # round the barrel's axis (local Z)
		mi.position = Vector3(0, 0, -y * SCALE)
		add_child(mi)
		_rings.append([mi, m])
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 500.0
	light.position = Vector3(0, 0, MOUTH - 40.0)
	add_child(light)
	var sign := Label3D.new()
	sign.text = "STARGATE\nto " + dest
	sign.font = ThemeDB.fallback_font
	sign.font_size = 96
	sign.outline_size = 16
	sign.modulate = color.lightened(0.4)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 130, MOUTH - 20.0)
	sign.pixel_size = 0.3
	add_child(sign)


## Fire a launch: the coils flare one after another down the barrel over `seconds`.
func launch(seconds: float) -> void:
	_launch_t = 0.0
	_launch_len = maxf(0.5, seconds)


func _process(delta: float) -> void:
	var base := 0.12
	for i in _rings.size():
		var a := base
		if _launch_t >= 0.0:
			# each coil fires as the ship (accelerating down the barrel) reaches it
			var reach := sqrt(float(i + 1) / _rings.size()) * _launch_len
			var since := _launch_t - reach
			a = base + (1.4 * exp(-since * 4.0) if since >= 0.0 else 0.25 * clampf(1.0 + since * 2.0, 0.0, 1.0))
		_rings[i][1].albedo_color.a = clampf(a, 0.0, 1.0)
	if _launch_t >= 0.0:
		_launch_t += delta
		if _launch_t > _launch_len + 1.5:
			_launch_t = -1.0
