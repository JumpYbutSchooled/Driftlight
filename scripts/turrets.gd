extends RefCounted
## The gun turrets on a ship model: a turret.glb on every Gun_N mount. A mount's own rotation and scale
## (set in Blender) decide which way its turret faces - up off the deck, down under the keel or out to one
## side - and how big it is. aim() swings each turret toward a point at its own pace (yaw on its base,
## then its barrels up and down within their arc) and says which are pointing at it.

const YAW_SPEED := 3.2  # radians per second a turret swings round
const PITCH_SPEED := 2.4  # and raises / lowers its barrels
const PITCH_MIN := -0.3  # barrels can dip a little below the mount's deck...
const PITCH_MAX := 1.45  # ...and nearly straight out from it
const ON_TARGET := 0.05  # radians: how close to the target the barrels must point

var list := []  # per mount, in gun-slot order: {base, yaw, pitch, muzzle}
var on_target := []  # per turret, from the last aim(): pointing at the target
var in_arc := []  # per turret: the target is within its arc


func _init(model: Node) -> void:
	for mount in Models.markers(model, "Gun"):
		var t := Models.prop("turret")
		mount.add_child(t)
		list.append({"base": t, "yaw": t.find_child("Yaw", true, false), "pitch": t.find_child("Pitch", true, false),
			"muzzle": t.find_child("Muzzle", true, false)})


func muzzles() -> Array:
	return list.map(func(tu): return tu.muzzle)


## Swing every turret toward `target` (`speed` scales how fast they turn).
func aim(delta: float, target: Vector3, speed := 1.0) -> void:
	on_target = []
	in_arc = []
	for tu in list:
		var base: Node3D = tu.base
		var yaw_node: Node3D = tu.yaw
		var pitch_node: Node3D = tu.pitch
		var local: Vector3 = base.global_transform.affine_inverse() * target
		var want_yaw := atan2(-local.x, -local.z)  # the barrels point down -Z
		yaw_node.rotation.y = rotate_toward(yaw_node.rotation.y, want_yaw, YAW_SPEED * speed * delta)
		var lp: Vector3 = yaw_node.global_transform.affine_inverse() * target - pitch_node.position
		var want_pitch := atan2(lp.y, Vector2(lp.x, lp.z).length())
		var arc := want_pitch >= PITCH_MIN and want_pitch <= PITCH_MAX
		pitch_node.rotation.x = rotate_toward(pitch_node.rotation.x, clampf(want_pitch, PITCH_MIN, PITCH_MAX),
			PITCH_SPEED * speed * delta)
		var mz: Vector3 = tu.muzzle.global_position
		var barrel := (-pitch_node.global_basis.z).normalized()
		in_arc.append(arc)
		on_target.append(arc and barrel.dot((target - mz).normalized()) > cos(ON_TARGET))


## Idle: every turret drifts back to facing straight out along its mount (civilian ships, between fights).
func rest(delta: float) -> void:
	for tu in list:
		tu.yaw.rotation.y = rotate_toward(tu.yaw.rotation.y, 0.0, YAW_SPEED * 0.3 * delta)
		tu.pitch.rotation.x = rotate_toward(tu.pitch.rotation.x, 0.0, PITCH_SPEED * 0.3 * delta)
