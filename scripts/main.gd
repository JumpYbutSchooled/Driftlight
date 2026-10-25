extends Node3D
## Runs the 3D game: title screen, building each location, the mouse-aim camera, warping and gates,
## saving, and all the UI.
##
## Controls: W/S pitch, A/D turn, Q/E roll, R/F throttle, SHIFT boost, X brake. The mouse swings the
## camera round the ship (it never steers); the gun turrets swivel to whatever the crosshair in the middle
## of the screen is on, and left click fires (a turret whose shot would pass through your own hull won't).
## Right-click selects what's under the crosshair; with something selected 1 approaches, 2 orbits, 3 warps
## to it and G docks / jumps / uses it. C frees the cursor (or hold ALT), wheel zooms, middle-click
## puts the camera back behind the ship.
## F1 is photo mode: the UI hides, the action freezes and you fly a free camera (P saves a picture).
##
## Space is big: things at one location are kilometres apart (warp between them with F), stations are
## hundreds of metres across and ore veins are huge.

const Ship = preload("res://scripts/ship.gd")
const Bullet = preload("res://scripts/bullet.gd")
const Asteroid = preload("res://scripts/asteroid.gd")
const OreChunk = preload("res://scripts/ore_chunk.gd")
const Pirate = preload("res://scripts/pirate.gd")
const Wreck = preload("res://scripts/wreck.gd")
const Crate = preload("res://scripts/crate.gd")
const Fx = preload("res://scripts/fx.gd")
const Wormhole = preload("res://scripts/wormhole.gd")
const Dust = preload("res://scripts/dust.gd")
const DmgText = preload("res://scripts/dmg_text.gd")
const GateField = preload("res://scripts/gate_field.gd")
const WarpFx = preload("res://scripts/warp_fx.gd")
const Npc = preload("res://scripts/npc.gd")
const Overview = preload("res://scripts/ui/overview.gd")
const TargetPanel = preload("res://scripts/ui/target_panel.gd")
const RING_SHADER = preload("res://shaders/planet_ring.gdshader")
const CursorFx = preload("res://scripts/cursor.gd")
const SKY_SHADER = preload("res://shaders/sky.gdshader")
const PLANET_SHADER = preload("res://shaders/planet.gdshader")
const ATMO_SHADER = preload("res://shaders/atmosphere.gdshader")
const TUNNEL_SHADER = preload("res://shaders/warp_tunnel.gdshader")
const VIGNETTE_SHADER = preload("res://shaders/vignette.gdshader")
const UI = preload("res://scripts/ui/ui.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const WarpMenu = preload("res://scripts/ui/warp_menu.gd")
const GalaxyMap = preload("res://scripts/ui/galaxy_map.gd")
const SystemMap = preload("res://scripts/ui/system_map.gd")
const StationUI = preload("res://scripts/ui/station_ui.gd")
const InventoryUI = preload("res://scripts/ui/inventory_ui.gd")
const Fitting = preload("res://scripts/ui/fitting.gd")
const DebugUI = preload("res://scripts/ui/debug_ui.gd")
const Confirm = preload("res://scripts/ui/confirm.gd")
const Title = preload("res://scripts/ui/title.gd")
const Pause = preload("res://scripts/ui/pause.gd")
const AdminPanel = preload("res://scripts/ui/admin_panel.gd")
const Updater = preload("res://scripts/updater.gd")
const AUTOSAVE_EVERY := 30.0  # save at least this often...
const SAVE_AFTER_CHANGE := 5.0  # ...and within this many seconds of anything changing
# warp timings (seconds, before Warp Core / ship bonuses): charge-up, then time in the warp tunnel
const WARP_CHARGE := 2.0
const WARP_BASE := 2.0
const WARP_PER_UNIT := 3.0  # per system-map unit travelled (a system is about 2.2 units across)
# jumping to another system always takes longer than any warp inside a system
const JUMP_CHARGE := 4.0
const JUMP_BASE := 12.0
const JUMP_PER_PX := 1.0 / 25.0  # per galaxy-map pixel between the two systems
const WORMHOLE_TIME := 18.0
const MOUSE_SENS := 0.0022  # radians of aim per pixel of mouse movement
const FOV := 72.0
const WARP_SCROLL_MAX := 1400.0  # m/s the background streams past inside the tunnel
const FEATURE_SPACING := 16000.0  # metres between the things at one location
const LOCAL_WARP_MIN := 2500.0  # anything further away than this can be warped to without leaving
const ZOOM_MIN := 0.5
const ZOOM_MAX := 120.0
const SCAN_RANGE := 7000.0  # survey scanner reach (V)
const SCAN_COOLDOWN := 8.0
# how far from each kind of thing you drop out of warp, and how close you must be to use it
const ARRIVE := {"station": 5000.0, "gate": 1100.0, "ore": 3600.0, "obelisk": 700.0, "spice": 450.0, "wormhole": 1100.0,
	"wreck": 450.0}
const USE_RANGE := {"obelisk": 280.0, "spice": 170.0, "wormhole": 500.0, "wreck": 260.0}
# the station's docking bay, relative to the station (it opens toward -Z; see props.py station()): the middle
# of its mouth, the landing pad at the back, and the box you fly into to dock
const BAY_MOUTH := Vector3(0, 0, -540)
const BAY_PAD := Vector3(0, -50, -345)
const BAY_ZONE_C := Vector3(0, -15, -335)
const BAY_ZONE_H := Vector3(80, 50, 65)
const BAY_LANE := 800.0
const COLLECT_RANGE := 4000.0  # O: auto-collect reaches loose ore this far away
# 5: cruise - a fast run to something far off in this location, threading round the rocks on the way
const CRUISE_MIN := 700.0  # only worth it for things further than this
const CRUISE_SPOOL := 1.2  # seconds the cruise drive takes to spool up
const CRUISE_MULT := 12.0  # cruise speed: this many times the ship's normal top speed  # arriving at a station drops you this far out in front of the bay, lined up on it
# rough size of each thing (for picking it on screen and where "approach" stops)
const SIZE := {"station": 1000.0, "gate": 150.0, "ore": 2600.0, "obelisk": 60.0, "spice": 25.0, "wormhole": 160.0,
	"wreck": 35.0}

var mode := "title"  # title, fly, warp, docked, panel, map, inventory, dialog, dead, admin
var debug := false  # F3 overlay
var world: Node3D
var backdrop: Node3D  # the planet: lives outside `world` so it stays visible (and flies away) in the warp tunnel
var player
var camera: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D  # planetshine
var sky_mat: ShaderMaterial
var env: Environment
var hud
var debug_ui
var warp_menu
var galaxy_map
var system_map
var station_ui
var inventory
var fitting
var fields := []  # ore fields here: {"c": centre, "r": reach} (bolts only check rocks near one)
var _group_cache := {}
var _group_frame := -1
var title
var confirm
var pause
var admin_panel
var updater
var fade: ColorRect
var tunnel: ColorRect  # full-screen warp tunnel shader
var vignette: ColorRect
var dust
var cursor  # animated dot / dot-and-ring mouse cursor
var aim := Basis()  # where the crosshair points; the ship turns to follow it
var aim_point := Vector3.ZERO  # what the crosshair is on (or a point far ahead)
var aim_target = null  # the rock / pirate / crate under the crosshair
var force_warp_menu := false
var interactables := []  # landmarks you can use with E when close (dock, jump, salvage...)
var landmarks := []  # every notable thing at this location: {name, kind, icon, pos, arrive, radius, size, action?}
var obstacles := []  # big structures ships bump off (see push_out)
var selected = null  # the selected target: a node (rock, ship, crate) or a landmark dictionary
var autopilot := {}  # approach / orbit / use in progress: {mode, target, range, axis}
var reticle := Vector2.ZERO  # where the guns aim, on screen (the centre)
var command := false  # C: cursor freed to click the overview, target buttons and things in space (or hold ALT)
var zoom := 1.0
var overview
var target_panel
var warp_fx
var _zoom_to := 1.0
var sun_dir_world := Vector3.UP  # towards this system's sun
var _scan_cd := 0.0
var _cam_yaw := 0.0  # the camera orbits the ship by these (world space, set by the mouse)
var _cam_pitch := 0.0
var ui_layer: CanvasLayer
var vignette_layer: CanvasLayer
var photo := false  # F1 photo mode
var _photo_hint: Label
var _photo_hint_t := 0.0
var _photo_us := 0
var _photo_fov := 72.0
var travel := {}  # the warp/jump in progress: kind, dest, phase (align/charge/travel/exit), t, ...
# while warping, the background rushes past along your heading: dust and the planet scroll by this
var warp_scroll := Vector3.ZERO
var _scroll_speed := 0.0
var _scroll_base := Vector3.ZERO
var _planet_base := Vector3.ZERO
var _wormhole: Node3D
var _wormhole_armed := true
var _dock_armed := true  # false after undocking until you've left the docking zone
var _docked_bay := {}  # the bay you're docked in (you undock onto its pad)
var _gate_bay := {}  # the stargate you just flew into (it fires you down its barrel)
var _rush := Vector3.ZERO  # in a jump, how far the world has streamed away behind you (or, arriving, sits ahead)
var _rush_v := 0.0
var _pirate_timer := -1.0
var _full_warned := 0
var _shake := 0.0
var _since_save := 0.0
var _hurt := 0.0  # red screen-edge flash when the hull is hit
var _menu_latch := false  # warp menu was closed by a click: don't reopen until SPACE is let go
var _cursor := ""
var _title_t := 0.0
var _fov_kick := 0.0


func _ready() -> void:
	UI.setup_fonts()
	cursor = CursorFx.new()
	add_child(cursor)
	get_tree().auto_accept_quit = false  # we save first, then quit (see _notification)
	var autoshot := "--autoshot" in OS.get_cmdline_user_args()
	Game.no_save = autoshot
	_build_environment()
	backdrop = Node3D.new()
	add_child(backdrop)
	world = Node3D.new()
	add_child(world)
	player = Ship.new()
	player.main = self
	player.process_priority = -10  # moves before this node updates the camera each frame
	add_child(player)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.3
	camera.far = 1500000.0  # planets are tens of kilometres across and a hundred away
	add_child(camera)
	camera.make_current()
	dust = Dust.new()
	dust.cam = camera
	add_child(dust)
	warp_fx = WarpFx.new()
	add_child(warp_fx)

	var tl := CanvasLayer.new()
	tl.layer = 1
	add_child(tl)
	tunnel = _shader_rect(TUNNEL_SHADER)
	(tunnel.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
	tl.add_child(tunnel)
	var vl := CanvasLayer.new()
	vl.layer = 9
	vignette_layer = vl
	add_child(vl)
	vignette = _shader_rect(VIGNETTE_SHADER)
	vl.add_child(vignette)

	var ui := CanvasLayer.new()
	ui.layer = 10
	ui_layer = ui
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme()
	ui.add_child(root)
	hud = _ui(root, Hud.new())
	overview = _ui(root, Overview.new())
	target_panel = _ui(root, TargetPanel.new())
	debug_ui = _ui(root, DebugUI.new())
	warp_menu = _ui(root, WarpMenu.new())
	system_map = _ui(root, SystemMap.new())
	galaxy_map = _ui(root, GalaxyMap.new())
	station_ui = _ui(root, StationUI.new())
	inventory = _ui(root, InventoryUI.new())
	fitting = _ui(root, Fitting.new())
	title = _ui(root, Title.new())
	confirm = Confirm.new()
	root.add_child(confirm)
	pause = _ui(root, Pause.new())
	admin_panel = _ui(root, AdminPanel.new())
	updater = Updater.new()
	add_child(updater)
	fade = ColorRect.new()
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color(1, 1, 1, 0)
	root.add_child(fade)

	Game.notify.connect(hud.push_message)
	player.setup()
	enter_location(0, 0)
	player.set_dead(true)
	title.open()
	if autoshot:
		add_child(preload("res://scripts/devshots.gd").new())


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256  # sharp enough for metal to show real reflections
	env.sky = sky
	# dark, empty space: almost no ambient light, so the side facing away from the sun falls into shadow
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.27)
	env.ambient_light_energy = 0.16
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# a filmic camera response: highlights roll off and desaturate like a real sensor instead of clipping
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.tonemap_white = 12.0
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 1.0
	env.glow_bloom = 0.0  # only genuinely bright things (lamps, exhaust, the sun) bloom
	env.glow_hdr_threshold = 1.6
	env.set_glow_level(0, 0.0)  # bloom from the wider levels only: a soft lens glow, not a hard halo
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	# contact shadows in the hull plating and greebles
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.35
	# muted, slightly hard colour
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.78
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 0.98
	# a thin haze of dust: things kilometres off fade a little, giving a sense of distance
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.075, 0.068, 0.062)
	env.fog_light_energy = 1.0
	env.fog_density = 0.00004
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2500.0
	sun.directional_shadow_split_1 = 0.03
	sun.directional_shadow_split_2 = 0.12
	sun.directional_shadow_split_3 = 0.4
	sun.light_energy = 2.1
	sun.shadow_opacity = 1.0
	sun.light_angular_distance = 0.3  # a real sun's disc: shadows sharp up close, softening with distance
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 3.0  # no shadow acne striping flat hull plates
	add_child(sun)
	# light thrown back off the planet: a faint fill in its colour from its side (set in _make_planet)
	fill = DirectionalLight3D.new()
	fill.light_energy = 0.0
	fill.shadow_enabled = false
	fill.light_specular = 0.3
	add_child(fill)


func _shader_rect(shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	return r


func _ui(root: Control, node) -> Control:
	node.main = self
	root.add_child(node)
	return node


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if mode != "title":
			Game.save_game()
		Sfx.save_settings()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode != "title":
		Game.save_game()


# ---------------------------------------------------------------- game flow

func start_new_game() -> void:
	Game.new_game()
	if Game.admin:
		Game.admin_fill()
	_begin(0, 0)
	Game.say("Welcome aboard the Wren! You have nothing but your ship. Go mine some Corrite.", Color("9fd3ff"))
	Game.say("W/S pitch, A/D turn, Q/E roll, R/F throttle. The mouse looks around, click to fire. Hold SPACE to warp to the Core Belt.", Color("9fd3ff"))
	Game.save_game()


func continue_game() -> void:
	if not Game.load_game():
		Game.say("Couldn't read the save file, starting fresh.", UI.BAD)
		start_new_game()
		return
	_begin(Game.current_system, Game.current_loc)
	Game.say("Welcome back, pilot.", Color("9fd3ff"))


func _begin(sys_id: int, loc_i: int) -> void:
	title.hide()
	player.set_dead(false)
	player.setup()
	mode = "fly"
	hud._title = ""
	enter_location(sys_id, loc_i)
	_since_save = 0.0


func quit_to_title() -> void:
	Game.save_game()
	close_maps()
	close_inventory()
	station_ui.hide()
	warp_menu.hide()
	mode = "title"
	player.set_dead(true)
	title.open()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if photo:
		_update_photo()
		return
	_update_screen_fx(delta)
	# flying, the mouse is captured and swings the camera round the ship; C (or holding ALT) frees the
	# cursor to click things. The warp menu reads raw mouse movement, so it captures the mouse too.
	if command and not mode in ["fly", "warp"]:
		command = false
	var want_mouse := Input.MOUSE_MODE_VISIBLE
	if not get_tree().paused:
		if warp_menu.visible:
			want_mouse = Input.MOUSE_MODE_CAPTURED
		elif mode in ["fly", "warp", "dead"] and not cursor_free():
			want_mouse = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want_mouse:
		Input.mouse_mode = want_mouse
	set_cursor("arrow" if want_mouse == Input.MOUSE_MODE_VISIBLE else "dot")
	if mode == "title":
		_update_camera(delta)
		return
	if not travel.is_empty():
		_update_travel(delta)
	player.turn_input = Vector3.ZERO
	if mode == "fly":
		_steer()
		if not autopilot.is_empty():
			_update_autopilot(delta)
	if selected != null and not target_valid(selected):
		selected = null
	_scan_cd = maxf(0.0, _scan_cd - delta)
	# the camera follows the ship once it has moved this frame (the ship runs first: see _ready), so the
	# two never step out of time with each other
	_update_camera(delta)
	_aim_raycast()

	var holding: bool = mode == "fly" and Input.is_action_pressed("warp_menu")
	if not holding:
		_menu_latch = false
	var want_menu: bool = force_warp_menu or (holding and not _menu_latch)
	if want_menu and not warp_menu.visible:
		warp_menu.open()
	elif not want_menu and warp_menu.visible:
		confirm_warp_menu()
	player.control = mode == "fly" and not warp_menu.visible

	var near = _nearest_interactable() if mode == "fly" else null
	hud.prompt = near.label if near else ""
	if mode == "fly" and player.alive:
		_check_docking()
		if autopilot.get("mode", "") == "collect" and hud.prompt == "":
			hud.prompt = autopilot_text()
	hud.hover_text = aim_target.describe() if mode == "fly" and aim_target != null and is_instance_valid(aim_target) \
		and aim_target.has_method("describe") else ""

	if _wormhole and mode == "fly" and player.alive:
		var d: float = player.position.distance_to(_wormhole.position)
		if d < 130.0 and _wormhole_armed:
			_wormhole_armed = false
			enter_wormhole()
		elif d > 400.0:
			_wormhole_armed = true

	var loc: Dictionary = current_loc()
	if loc.pirates and mode != "dead":
		if _pirate_timer >= 0.0:
			_pirate_timer -= delta
			if _pirate_timer < 0.0:
				_spawn_pirates()
		elif get_tree().get_nodes_in_group("pirates").is_empty():
			_pirate_timer = randf_range(45.0, 70.0)

	_since_save += delta
	if mode != "dead" and ((Game.dirty and _since_save > SAVE_AFTER_CHANGE) or _since_save > AUTOSAVE_EVERY):
		_since_save = 0.0
		Game.save_game()


## Keys turn the ship: A/D yaw, W/S pitch, Q/E roll. The ship spins up and down with momentum (see
## ship._turn); taking the controls hands them back from the autopilot.
func _steer() -> void:
	var yaw := Input.get_axis("yaw_right", "yaw_left")
	var pitch := Input.get_axis("pitch_down", "pitch_up")
	var roll := Input.get_axis("roll_left", "roll_right")
	player.turn_input = Vector3(pitch, yaw, roll)
	if yaw != 0.0 or pitch != 0.0 or roll != 0.0:
		cancel_autopilot("Manual control")


## Is the cursor freed for clicking (C toggles it, holding ALT frees it for a moment)?
func cursor_free() -> bool:
	return command or (mode in ["fly", "warp"] and Input.is_key_pressed(KEY_ALT))


## Put the camera straight behind the ship (on arrival, and on a middle-click).
func snap_camera() -> void:
	var f: Vector3 = (-aim.z).normalized()
	_cam_yaw = atan2(-f.x, -f.z)
	_cam_pitch = asin(clampf(f.y, -1.0, 1.0))


## Chase camera that orbits the ship as you move the mouse; the ship itself is flown with the keys.
## On the title screen it slowly circles the station instead.
func _update_camera(delta: float) -> void:
	if mode == "title":
		_title_t += delta * 0.05
		camera.global_position = Vector3(cos(_title_t) * 2500.0, 480.0 + sin(_title_t * 0.7) * 260.0, sin(_title_t) * 2500.0)
		camera.look_at(Vector3(0, 30, 0), Vector3.UP)
		camera.fov = FOV
		camera.near = 3.0
		return
	# mouse wheel zoom: from right behind the ship out to a kilometre or so
	zoom = lerpf(zoom, _zoom_to, 1.0 - exp(-8.0 * delta))
	camera.near = clampf(zoom * 0.12, 0.3, 6.0)
	var view := Basis(Vector3.UP, _cam_yaw) * Basis(Vector3.RIGHT, _cam_pitch)
	var r: float = player.radius
	var target: Vector3 = player.position + (view.y * (r * 0.75 + 2.0) + view.z * (r * 2.4 + 7.0)) * zoom
	if not player.alive:
		target = camera.global_position
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-12.0 * delta))
	camera.global_basis = view
	camera.h_offset = randf_range(-1.0, 1.0) * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * _shake
	_shake = move_toward(_shake, 0.0, 2.5 * delta)
	var speed_fov: float = 6.0 if player.boosting else (10.0 if player.cruise_v > 0.0 else 0.0)
	var warp_fov := 0.0
	match travel.get("phase", ""):
		"charge": warp_fov = -4.0 * clampf(travel.t / travel.charge, 0.0, 1.0)
		"travel": warp_fov = 26.0
	_fov_kick = move_toward(_fov_kick, 0.0, 40.0 * delta)
	camera.fov = lerpf(camera.fov, FOV + speed_fov + warp_fov + _fov_kick, 1.0 - exp(-4.0 * delta))


## What the crosshair (the middle of the screen) is on: the nearest rock, pirate, crate or ship along the
## camera's line of sight. The turrets aim there.
func _aim_raycast() -> void:
	reticle = get_viewport().get_visible_rect().size / 2.0
	var o := camera.project_ray_origin(reticle)
	var d := camera.project_ray_normal(reticle)
	var best := 8000.0
	var shoot := 8000.0  # civilian ships can be picked out but not shot, so the turrets look past them
	aim_target = null
	for group in ["pirates", "crates", "asteroids", "npcs"]:
		for n in get_tree().get_nodes_in_group(group):
			if not n.visible:
				continue
			var t := _ray_sphere(o, d, n.position, n.radius)
			if t > 0.0 and t < best:
				best = t
				aim_target = n
			if t > 0.0 and t < shoot and group != "npcs":
				shoot = t
	aim_point = o + d * (shoot if shoot < 8000.0 else 2500.0)


static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.length_squared() - r * r)
	if disc < 0.0:
		return -1.0
	return -b - sqrt(disc)


func _input(event: InputEvent) -> void:
	if photo:
		if event is InputEventMouseMotion:
			camera.rotate(Vector3.UP, -event.relative.x * MOUSE_SENS * 0.8)
			camera.rotate_object_local(Vector3.RIGHT, -event.relative.y * MOUSE_SENS * 0.8)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_photo_fov = clampf(_photo_fov / 1.08, 8.0, 110.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_photo_fov = clampf(_photo_fov * 1.08, 8.0, 110.0)
		return
	# the mouse swings the camera round the ship (it never steers it)
	if event is InputEventMouseMotion and mode in ["fly", "warp", "dead"] and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not warp_menu.visible:
		_cam_yaw = wrapf(_cam_yaw - event.relative.x * MOUSE_SENS, -PI, PI)
		_cam_pitch = clampf(_cam_pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)


## Closes the quick warp menu and warps to whatever is highlighted (nothing, if it's Cancel).
func confirm_warp_menu() -> void:
	var pick: int = warp_menu.selected_loc()
	warp_menu.hide()
	if Input.is_action_pressed("warp_menu"):
		_menu_latch = true
	if pick >= 0 and mode == "fly" and not force_warp_menu:
		start_warp(pick)


## Hidden while the mouse is captured (the HUD draws the crosshair); in menus a ring pops up around the dot.
func set_cursor(want: String) -> void:
	_cursor = want
	cursor.target = 0.0 if want == "dot" else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if mode == "title":
		return
	if event.is_action_pressed("photo"):
		toggle_photo()
		return
	if photo:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_P, KEY_F12: _photo_save()
				KEY_H: _photo_hint_t = 0.0 if _photo_hint_t > 0.0 else 9999.0
				KEY_ESCAPE: toggle_photo()
		return
	if event is InputEventMouseButton and event.pressed and mode in ["fly", "warp"] and not warp_menu.visible:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_to = clampf(_zoom_to / 1.15, ZOOM_MIN, ZOOM_MAX)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_to = clampf(_zoom_to * 1.15, ZOOM_MIN, ZOOM_MAX)
				return
			MOUSE_BUTTON_MIDDLE:
				snap_camera()
				return
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT:
				# right-click selects what's under the crosshair (or under the cursor, once C has freed it);
				# with the cursor free a left click selects too, instead of firing
				if event.button_index == MOUSE_BUTTON_LEFT and not cursor_free():
					return
				var t = pick_at(event.position if cursor_free() else reticle)
				if t != null:
					select(t)
				return
	if event.is_action_pressed("command") and mode in ["fly", "warp"]:
		command = not command
		return
	if event.is_action_pressed("close") and command:
		command = false
		return
	if mode == "fly":
		for o in ["approach", "orbit", "warp_to", "cruise"]:
			if event.is_action_pressed(o):
				if selected == null and aim_target != null:
					select(aim_target)
				order({"warp_to": "warp"}.get(o, o))
				return
		if event.is_action_pressed("scan"):
			survey_scan()
			return
		if event.is_action_pressed("collect"):
			toggle_collect()
			return
		if not autopilot.is_empty() and (event.is_action_pressed("move_up") or event.is_action_pressed("move_down")
				or event.is_action_pressed("cut_throttle")):
			cancel_autopilot("Manual control")
	if event.is_action_pressed("admin") and Game.admin:
		if mode == "fly":
			mode = "admin"
			admin_panel.open()
		elif mode == "admin":
			admin_panel.close()
		return
	if event.is_action_pressed("interact") and mode == "fly" and selected is Dictionary and selected.has("action") \
			and _nearest_interactable() != selected:
		order("use")  # G with a station / gate selected: fly there and use it
		return
	if event.is_action_pressed("interact") and mode == "fly":
		var near = _nearest_interactable()
		var port := near_port(3500.0)
		if near:
			near.action.call()
		elif not port.is_empty():
			select(port)
			order("use")  # near a station or gate: the autopilot flies you into its bay or mouth
	elif event.is_action_pressed("galaxy_map"):
		if galaxy_map.visible:
			close_maps()
		elif mode == "fly" or system_map.visible:
			close_maps()
			mode = "map"
			galaxy_map.open()
	elif event.is_action_pressed("system_map"):
		if system_map.visible:
			close_maps()
		elif mode == "fly" or galaxy_map.visible:
			close_maps()
			mode = "map"
			system_map.open()
	elif event.is_action_pressed("inventory"):
		if mode == "inventory":
			close_inventory()
		elif mode == "fly":
			mode = "inventory"
			inventory.open()
	elif event.is_action_pressed("fitting"):
		if mode == "fitting":
			close_fitting()
		elif mode == "fly":
			mode = "fitting"
			fitting.open()
	elif event.is_action_pressed("debug"):
		debug = not debug
		debug_ui.visible = debug
	elif event.is_action_pressed("close"):
		match mode:
			"map": close_maps()
			"inventory": close_inventory()
			"fitting": close_fitting()
			"docked", "panel": close_panel()
			"admin": admin_panel.close()
			"fly": pause.open()


## Drives the warp tunnel overlay, the vignette (red when hurt, tinted while charging) and the space dust.
func _update_screen_fx(delta: float) -> void:
	var phase: String = travel.get("phase", "")
	var want := 0.0
	var glow := Color(0, 0, 0, 0)
	match phase:
		"charge":
			var k: float = clampf(travel.t / travel.charge, 0.0, 1.0)
			glow = Color(travel.color, k * 0.5)
		"travel":
			want = 1.0
			glow = Color(travel.color, 0.35)
	var tm := tunnel.material as ShaderMaterial
	var cur: float = tm.get_shader_parameter("intensity")
	tm.set_shader_parameter("intensity", move_toward(cur, want * 0.3, delta * (3.0 if want > cur else 6.0)))
	var vs := get_viewport().get_visible_rect().size
	tm.set_shader_parameter("res", vs)
	# the speed lines stream out of the point the ship is flying toward, wherever the camera is looking (or,
	# with it behind the camera, into the point it's flying away from)
	var hd: Vector3 = travel.get("heading", player.forward())
	var far: Vector3 = camera.global_position + hd * 100000.0
	var inward := 0.0
	if camera.is_position_behind(far):
		far = camera.global_position - hd * 100000.0
		inward = 1.0
	var vp := Vector2(0.5, 0.5)
	if not camera.is_position_behind(far):
		vp = camera.unproject_position(far) / vs
	tm.set_shader_parameter("center", vp)
	tm.set_shader_parameter("inward", inward)
	# the 3D warp tunnel wrapped round the ship
	var wp := 0.0
	match phase:
		"charge": wp = 0.3 * clampf(travel.t / travel.charge, 0.0, 1.0)
		"travel": wp = 1.0
		"exit": wp = 0.6 * (1.0 - clampf(travel.t / 0.6, 0.0, 1.0))
	warp_fx.power = move_toward(warp_fx.power, wp, delta * (1.5 if wp > warp_fx.power else 3.0))
	if not travel.is_empty():
		warp_fx.tint = Color(travel.color).lerp(Color(0.55, 0.8, 1.0), 0.55)
		warp_fx.heading = travel.heading
	warp_fx.radius = maxf(player.radius * 2.5, camera.global_position.distance_to(player.position) * 1.4)
	warp_fx.place(player.position)
	_hurt = maxf(0.0, _hurt - delta * 1.8)
	var vm := vignette.material as ShaderMaterial
	vm.set_shader_parameter("res", vs)
	vm.set_shader_parameter("damage", _hurt)
	vm.set_shader_parameter("glow", glow)
	dust.stretch = 1.0 if phase == "travel" else (0.5 if player.cruise_v > 0.0 else 0.0)
	dust.dir = player.forward()
	dust.offset = warp_scroll
	if backdrop.get_child_count() > 0:
		# the planet is far away and barely moves, until you warp: then it's left behind fast
		backdrop.position = -(warp_scroll - _scroll_base) * 3.0 - _rush


func hurt(amount: float) -> void:
	_hurt = clampf(_hurt + amount, 0.0, 0.9)


func dmg_number(pos: Vector3, amount: float, color: Color) -> void:
	var d := DmgText.new()
	d.text = str(roundi(amount))
	d.modulate = color
	d.position = pos
	world.add_child(d)


func _fx(pos: Vector3) -> Node3D:
	var f := Fx.new()
	# while the world is hidden (inside the warp tunnel) effects go on the main node so they still show
	if world.visible:
		world.add_child(f)
	else:
		add_child(f)
	f.global_position = pos
	return f


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func current_sys() -> Dictionary:
	return Game.systems[Game.current_system]


func current_loc() -> Dictionary:
	return Game.systems[Game.current_system].locs[Game.current_loc]


func _nearest_interactable():
	var best = null
	var bd := INF
	for it in interactables:
		var d: float = player.position.distance_to(it.pos)
		if d < it.radius and d < bd:
			bd = d
			best = it
	return best


## The station here, if any (its landmark, with the "bay").
func station_lm() -> Dictionary:
	for lm in landmarks:
		if lm.kind == "station":
			return lm
	return {}


static func in_box(p: Vector3, c: Vector3, h: Vector3) -> bool:
	var v := (p - c).abs()
	return v.x < h.x and v.y < h.y and v.z < h.z


## Is `p` inside a port's trigger zone: a station's docking zone over its pad, or a gate's bore just past
## its mouth?
func in_port(bay: Dictionary, p: Vector3) -> bool:
	if bay.has("zone_c"):
		return in_box(p, bay.zone_c, bay.zone_h)
	var into: Vector3 = -bay.out
	var rel: Vector3 = p - bay.mouth
	var along := rel.dot(into)
	return along > 30.0 and along < 260.0 and (rel - into * along).length() < bay.bore


## The nearest port (a landmark with a "bay": station or gate) within `range_m`, or {}.
func near_port(range_m: float) -> Dictionary:
	var best := {}
	var bd := range_m
	for lm in landmarks:
		if lm.has("bay") and player.position.distance_to(lm.bay.mouth) < bd:
			bd = player.position.distance_to(lm.bay.mouth)
			best = lm
	return best


## Ports: fly into a station's docking bay onto the pad to dock, or into a stargate's mouth to be fired
## down its barrel. Near one the prompt says so (and that G lets the autopilot fly you in).
func _check_docking() -> void:
	var inside := false
	for lm in landmarks:
		if not lm.has("bay") or not in_port(lm.bay, player.position):
			continue
		inside = true
		if _dock_armed:
			_dock_armed = false
			cancel_autopilot()
			if lm.kind == "station":
				_docked_bay = lm.bay
			else:
				_gate_bay = lm.bay
			lm.action.call()
			return
	if not inside:
		_dock_armed = true
	var lm := near_port(3500.0)
	if hud.prompt == "" and not lm.is_empty() and not inside:
		var station: bool = lm.kind == "station"
		if autopilot.get("mode", "") == "dock":
			hud.prompt = "Docking autopilot engaged" if station else "Autopilot: lining up on the gate"
		else:
			hud.prompt = "Fly into the docking bay to dock   -   G: docking autopilot" if station \
				else "Fly into the gate to jump to %s   -   G: autopilot" % lm.bay.dest


## Where the docking autopilot heads next: lined up out in front of the port's mouth first (round the
## station or gate if it's in the way), then straight in to the pad.
func _dock_goal(lm: Dictionary) -> Vector3:
	var bay: Dictionary = lm.bay
	var p: Vector3 = player.position
	var rel: Vector3 = p - bay.mouth
	var along: float = rel.dot(bay.out)  # metres out in front of the mouth (negative: inside the bay)
	var lateral: float = (rel - bay.out * along).length()
	if (along < 30.0 and lateral < bay.bore) or (along >= 0.0 and along < BAY_LANE * 1.4 and lateral < 40.0 + along * 0.12):
		return bay.pad
	var goal: Vector3 = bay.mouth + bay.out * 450.0
	var c: Vector3 = lm.pos
	var seg := goal - p
	var t := clampf((c - p).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
	if (p + seg * t).distance_to(c) < bay.clear:
		var side: Vector3 = p - c
		side -= bay.out * side.dot(bay.out)
		if side.length() < 1.0:
			side = Vector3.RIGHT
		goal = c + side.normalized() * (bay.clear + 300.0) + bay.out * 300.0
	return goal


# ---------------------------------------------------------------- locations

func enter_location(sys_id: int, loc_i: int, spawn = null) -> void:
	for c in world.get_children():
		c.queue_free()
	for c in backdrop.get_children():
		c.queue_free()
	world.position = Vector3.ZERO
	_scroll_base = warp_scroll
	backdrop.position = Vector3.ZERO
	interactables.clear()
	landmarks.clear()
	obstacles.clear()
	fields.clear()
	selected = null
	autopilot = {}
	_wormhole = null
	_pirate_timer = -1.0
	var prev_sys := Game.current_system
	Game.current_system = sys_id
	Game.current_loc = loc_i
	var sys: Dictionary = Game.systems[sys_id]
	var loc: Dictionary = sys.locs[loc_i]
	var new_sys: bool = not sys.visited
	sys.visited = true
	loc.scanned = true
	if loc.kind == "anomaly" and not loc.found:
		loc.found = true
		Game.event("anomaly")
	_set_sky(sys, loc)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sys_id, loc_i, 7])  # the same layout every visit

	fill.light_energy = 0.0
	if loc.kind != "gate":
		_make_planet(loc.planet_type if loc.kind == "planet" else "void", loc.seed)

	var feats := []
	match loc.kind:
		"planet":
			for f in ["station", "ore", "obelisk", "spice"]:
				if loc[f]:
					feats.append(f)
		"gate":
			feats.append("gate")
		"anomaly":
			if loc.wormhole >= 0:
				feats.append("wormhole")
			feats.append("ore")
	# the things here sit kilometres apart: fly between them, or warp (F)
	var base_ang := rng.randf() * TAU
	for k in feats.size():
		var at := Vector3.ZERO
		if k > 0:
			var a := base_ang + k * TAU / feats.size()
			at = Vector3(cos(a) * FEATURE_SPACING, rng.randf_range(-900.0, 900.0), sin(a) * FEATURE_SPACING)
		_build_feature(feats[k], at, sys, loc, rng)
	if loc.wreck:
		_spawn_wreck(_ring_point(rng, 2500.0, 5000.0, 600.0), sys_id, loc_i)
	if loc.kind != "gate":
		for i in rng.randi_range(0, [1, 2, 3, 3][sys.cat]):
			var c := Crate.new()
			c.main = self
			c.position = _ring_point(rng, 400.0, 3000.0, 400.0)
			world.add_child(c)
	_spawn_traffic(sys, rng)

	# drop out of warp some way short of the main thing here, coming in along your heading and facing it
	var first: Dictionary = landmarks[0] if not landmarks.is_empty() else {"pos": Vector3.ZERO, "arrive": 800.0}
	var dir := Vector3.ZERO
	if spawn is Vector3 and spawn.length() > 0.01:
		dir = spawn.normalized()
	else:
		var a := randf() * TAU
		dir = Vector3(cos(a), -0.12, sin(a)).normalized()
	player.position = first.pos - dir * first.arrive
	aim = Basis.looking_at((first.pos - player.position).normalized(), Vector3.UP)
	if first.get("kind", "") == "station":
		# traffic control drops you into the station's approach lane, lined up on the docking bay
		player.position = first.bay.mouth + first.bay.out * BAY_LANE + Vector3(randf_range(-60, 60), randf_range(-20, 20), 0)
		aim = Basis.looking_at((first.bay.mouth - player.position).normalized(), Vector3.UP)
	elif first.get("kind", "") == "gate":
		# arriving by gate you come in from the system you left, off to one side of this end of the gate
		player.position += dir.cross(Vector3.UP).normalized() * 280.0
		aim = Basis.looking_at((first.pos - player.position).normalized(), Vector3.UP)
	_dock_armed = true
	player.basis = aim
	player.stop()
	camera.global_position = player.position + aim.y * 6.0 + aim.z * 18.0 * zoom
	snap_camera()
	_wormhole_armed = false

	if loc.pirates:
		_pirate_timer = 1.5
	if mode == "title":
		return
	if prev_sys != sys_id or hud._title == "":
		var sub := "%s System" % Game.CAT_NAMES[sys.cat]
		if sys.cat == Game.CAT_PURPLE:
			sub += "  -  DANGER: heavy pirate activity"
		hud.show_title(sys.name.to_upper(), Game.CAT_COLORS[sys.cat], sub)
		Game.event("visit", {"sys": sys_id, "new": new_sys})
		if sys_id == Game.route_target:
			Game.route_target = -1
			Game.say("You have reached your destination.", UI.GOLD)
		Game.save_game()


func _ring_point(rng: RandomNumberGenerator, rmin: float, rmax: float, h: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := rng.randf_range(rmin, rmax)
	return Vector3(cos(a) * r, rng.randf_range(-h, h), sin(a) * r)

## Sky tint, sun direction and colour for this system (the same every visit).
func _set_sky(sys: Dictionary, loc: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sys.id * 31 + 7
	var tint: Color = Game.CAT_COLORS[sys.cat]
	var a := rng.randf() * TAU
	var sun_dir := Vector3(cos(a), rng.randf_range(0.12, 0.55), sin(a)).normalized()
	var sun_col := Color("fff1dc").lerp(tint, 0.12)
	sun_dir_world = sun_dir
	sky_mat.set_shader_parameter("band_axis", Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.0), rng.randf_range(-1, 1)).normalized())
	sky_mat.set_shader_parameter("tint", tint)
	sky_mat.set_shader_parameter("tint2", tint.lerp(Color("ff7de9"), 0.55))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_color", sun_col)
	sky_mat.set_shader_parameter("nebula", 1.3 if loc.kind == "anomaly" else 1.0)
	sun.global_basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = sun_col
	env.ambient_light_color = Color(0.2, 0.22, 0.27).lerp(tint, 0.12)
	env.fog_light_color = Color(0.075, 0.068, 0.062).lerp(tint * 0.1, 0.25)


## A giant planet far off to the side of the action (tens of kilometres across, a hundred away), with an
## atmosphere glow, rings round most gas giants, and a moon or two.
func _make_planet(ptype: String, planet_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed
	var pal: Array = Pix.PLANET_PAL[ptype]
	var node := Node3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 128
	sm.rings = 64
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = _planet_mat(pal, ptype, rng.randf() * 100.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var atmo := MeshInstance3D.new()
	atmo.mesh = sm
	var am := ShaderMaterial.new()
	am.shader = ATMO_SHADER
	am.set_shader_parameter("color", Color(pal[3]).lerp(Color(0.7, 0.75, 0.8), 0.5))
	am.set_shader_parameter("sun_dir", sun_dir_world)
	atmo.material_override = am
	atmo.scale = Vector3.ONE * 1.04
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(atmo)
	var radius := rng.randf_range(28000.0, 60000.0)  # the sphere mesh is half a unit across
	var a := rng.randf() * TAU
	node.position = Vector3(cos(a), rng.randf_range(-0.45, -0.05), sin(a)).normalized() * rng.randf_range(90000.0, 150000.0)
	node.scale = Vector3.ONE * radius
	node.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
	backdrop.add_child(node)
	_planet_base = node.position
	if ptype != "void":
		var to_planet := node.position.normalized()
		fill.global_basis = Basis.looking_at(-to_planet, Vector3.UP if absf(to_planet.y) < 0.98 else Vector3.RIGHT)
		fill.light_color = Color(pal[2]).lerp(Color(0.6, 0.65, 0.7), 0.4)
		fill.light_energy = 0.14
	if (ptype == "gas" and rng.randf() < 0.75) or rng.randf() < 0.15:
		var ring := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		ring.mesh = pm
		var rm := ShaderMaterial.new()
		rm.shader = RING_SHADER
		rm.set_shader_parameter("c1", Color(pal[2]))
		rm.set_shader_parameter("c2", Color(pal[4]).lightened(0.2))
		rm.set_shader_parameter("seed", rng.randf() * 100.0)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.scale = Vector3.ONE * rng.randf_range(1.1, 1.5)
		ring.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		node.add_child(ring)
	for i in rng.randi_range(0, 2):
		var moon := MeshInstance3D.new()
		moon.mesh = sm
		var mtype: String = ["rocky", "ice", "desert", "lava"][rng.randi() % 4]
		moon.material_override = _planet_mat(Pix.PLANET_PAL[mtype], mtype, rng.randf() * 100.0)
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1)).normalized()
		moon.position = node.position + off * radius * rng.randf_range(1.6, 2.6)
		moon.scale = Vector3.ONE * radius * rng.randf_range(0.08, 0.2)
		backdrop.add_child(moon)


func _planet_mat(pal: Array, ptype: String, planet_seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PLANET_SHADER
	for i in 5:
		m.set_shader_parameter("c%d" % i, pal[i])
	m.set_shader_parameter("kind", {"gas": 1, "lava": 2, "ocean": 3}.get(ptype, 0))
	m.set_shader_parameter("seed", planet_seed)
	return m


## Records something notable here (for the overview, warping to it, markers). With an action it can also
## be used with E once you're within its range.
func _landmark(lm_name: String, kind: String, icon: String, pos: Vector3, action = null, label := "") -> Dictionary:
	var lm := {"name": lm_name, "kind": kind, "icon": icon, "pos": pos, "arrive": ARRIVE.get(kind, 800.0),
		"radius": USE_RANGE.get(kind, 0.0), "size": SIZE.get(kind, 50.0), "label": label}
	if action != null:
		lm["action"] = action
		interactables.append(lm)
	landmarks.append(lm)
	return lm


func _obstacle(type: String, data: Dictionary) -> void:
	data["type"] = type
	obstacles.append(data)


func _build_feature(kind: String, at: Vector3, sys: Dictionary, loc: Dictionary, rng: RandomNumberGenerator) -> void:
	match kind:
		"station":
			var st := Models.prop("station")
			st.position = at
			world.add_child(st)
			# the docking bay opens toward -Z: you fly in through the mouth and dock by reaching the pad
			var bay := {"mouth": at + BAY_MOUTH, "out": Vector3.FORWARD, "pad": at + BAY_PAD, "zone_c": at + BAY_ZONE_C,
				"zone_h": BAY_ZONE_H, "loc": loc, "right": Vector3.RIGHT, "hw": 120.0, "hh": 67.5, "clear": 850.0, "bore": 90.0}
			var lm := _landmark(loc.name, "station", "station", at, open_station.bind(loc), "")
			lm["bay"] = bay
			for z in [-320.0, -420.0, -515.0]:  # lamps along the bay roof (shadowed, so they don't shine through its walls)
				var bl := _light(at + Vector3(0, 45, z), Color("ffe9cc"), 190.0, 2.4)
				bl.shadow_enabled = true
				bl.distance_fade_enabled = true
				bl.distance_fade_begin = 2500.0
				bl.distance_fade_length = 600.0
			_light(at + Vector3(0, -40, -600), Color("ffe2b0"), 260.0, 1.2)  # floodlight spill out of the mouth
			# the citadel's main masses (built in tools/blender/props.py, shown 3x), so you fly round it
			_obstacle("capsule", {"a": at + Vector3(0, -375, 0), "b": at + Vector3(0, 360, 0), "r": 138.0})
			_obstacle("torus", {"c": at + Vector3(0, 135, 0), "n": Vector3.UP, "R": 390.0, "r": 57.0})
			_obstacle("torus", {"c": at + Vector3(0, -180, 0), "n": Vector3.UP, "R": 285.0, "r": 27.0})
			_obstacle("cyl", {"c": at, "R": 258.0, "h": 108.0})
			_obstacle("cyl", {"c": at + Vector3(0, 210, 0), "R": 186.0, "h": 72.0})
			_obstacle("cyl", {"c": at + Vector3(0, -240, 0), "R": 190.0, "h": 45.0})
			_obstacle("sphere", {"c": at + Vector3(0, -405, 0), "r": 110.0})
			# the docking bay: a hollow shell (walls to the inner faces of the ribs), the block joining it to the
			# hub, the frame round the mouth, and the ships parked down the sides
			_obstacle("box", {"c": at + Vector3(0, 0, -187.5), "h": Vector3(138, 85.5, 82.5)})
			for sx in [-1, 1]:
				_obstacle("box", {"c": at + Vector3(sx * 123.75, 0, -405), "h": Vector3(14.25, 85.5, 135)})
				_obstacle("box", {"c": at + Vector3(sx * 137.25, 0, -546), "h": Vector3(17.25, 85.5, 7.5)})
				for z in [-330.0, -420.0, -495.0]:
					_obstacle("box", {"c": at + Vector3(sx * 84, -54, z), "h": Vector3(17, 10, 38)})
			_obstacle("box", {"c": at + Vector3(0, 71.25, -405), "h": Vector3(138, 14.25, 135)})
			_obstacle("box", {"c": at + Vector3(0, -76.25, -405), "h": Vector3(138, 9.25, 135)})
			for sy in [-1, 1]:
				_obstacle("box", {"c": at + Vector3(0, sy * 76.5, -546), "h": Vector3(154.5, 8.0, 7.5)})
			for sx in [-1, 1]:
				_obstacle("box", {"c": at + Vector3(sx * 735, -90, 0), "h": Vector3(198, 9, 216)})
			for i in 4:  # docking arms on the diagonals, low down, each ending in a docking module
				var a := i * PI / 2.0 + PI / 4.0
				var d := Vector3(cos(a), 0.0, -sin(a))
				_obstacle("capsule", {"a": at + Vector3(0, -336, 0) + d * 75.0, "b": at + Vector3(0, -336, 0) + d * 585.0, "r": 18.0})
				_obstacle("sphere", {"c": at + Vector3(0, -336, 0) + d * 640.0, "r": 115.0})
		"ore":
			_spawn_field(at, sys, loc.kind == "anomaly", rng)
			_landmark("Anomaly Ore Field" if loc.kind == "anomaly" else "Asteroid Field", "ore", "ore", at)
		"obelisk":
			var ob := Models.prop("obelisk")
			ob.position = at
			world.add_child(ob)
			_light(at + Vector3(0, 50, 0), Color("d050ff"), 300.0, 3.0)
			_landmark("Offering Obelisk", "obelisk", "obelisk", at + Vector3(0, 40, 0), open_panel.bind("obelisk", loc),
				"[G]  Approach the Offering Obelisk")
			_obstacle("capsule", {"a": at, "b": at + Vector3(0, 88, 0), "r": 12.0})
			_obstacle("box", {"c": at + Vector3(0, -2, 0), "h": Vector3(18, 4, 18)})
		"spice":
			var sp := Models.prop("spice_stand")
			sp.position = at
			world.add_child(sp)
			_light(at + Vector3(0, 18, 0), Color("ffb03d"), 140.0, 2.5)
			_landmark("Spice Stand", "spice", "spice", at, open_panel.bind("spice", loc), "[G]  Browse the Spice Stand")
			_obstacle("sphere", {"c": at + Vector3(0, 12, 0), "r": 24.0})
		"gate":
			# a railgun: the barrel points at the system it leads to, and you fly in at the mouth to be fired
			# down it (see _update_travel)
			var dest_sys: Dictionary = Game.systems[loc.gate_to]
			var hv: Vector2 = dest_sys.pos - sys.pos
			var dir := Vector3(hv.x, 0.0, hv.y).normalized() if hv.length() > 0.001 else Vector3.FORWARD
			var side := dir.cross(Vector3.UP).normalized()
			var gate := GateField.new()
			gate.color = Game.CAT_COLORS[dest_sys.cat]
			gate.dest = dest_sys.name
			gate.position = at
			gate.basis = Basis.looking_at(dir, Vector3.UP)
			world.add_child(gate)
			var mouth := at - dir * GateField.MOUTH
			var lm := _landmark("Stargate to " + dest_sys.name, "gate", "gate", at, try_gate.bind(loc.gate_to), "")
			lm["bay"] = {"mouth": mouth, "out": -dir, "pad": mouth + dir * 160.0, "bore": GateField.BORE - 4.0, "gate": gate,
				"right": side, "hw": GateField.BORE, "hh": GateField.BORE, "clear": 380.0, "dest": dest_sys.name}
			# the coils (rings round the barrel), the mouth and its flare, the muzzle, the four rails and the
			# power plant alongside: fly down the bore, bump off the frame
			for y in GateField.COILS:
				_obstacle("torus", {"c": at + dir * y * GateField.SCALE, "n": dir, "R": 56.0, "r": 10.0})
			_obstacle("torus", {"c": at - dir * 280.0, "n": dir, "R": 77.5, "r": 12.0})
			_obstacle("torus", {"c": at - dir * 302.0, "n": dir, "R": 92.5, "r": 9.0})
			_obstacle("torus", {"c": at + dir * 280.0, "n": dir, "R": 65.0, "r": 13.0})
			for i in 4:
				var a := i * PI / 2.0 + PI / 4.0
				var off := (side * cos(a) + Vector3.UP * sin(a)) * 68.0
				_obstacle("capsule", {"a": at + off - dir * 270.0, "b": at + off + dir * 270.0, "r": 7.0})
			_obstacle("capsule", {"a": at + side * 125.0 - dir * 125.0, "b": at + side * 125.0 + dir * 25.0, "r": 32.0})
		"wormhole":
			_wormhole = Wormhole.new()
			_wormhole.position = at
			world.add_child(_wormhole)
			_landmark("Wormhole", "wormhole", "anomaly", at, enter_wormhole, "[G]  Enter the wormhole (or fly into it)")


func _light(pos: Vector3, color: Color, range_m: float, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = range_m
	l.light_energy = energy
	l.position = pos
	world.add_child(l)
	return l


## An ore field: dozens of huge mineable veins spread over a few kilometres, a couple of giant ones,
## a haze of smaller loose rocks between them and drifting dust clouds.
func _spawn_field(center: Vector3, sys: Dictionary, anomaly: bool, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(55, 75) if anomaly else rng.randi_range(40, 60)
	var spread := 3000.0 if anomaly else 2600.0
	fields.append({"c": center, "r": spread * 1.3 + 600.0})
	var placed := []
	var giants := rng.randi_range(1, 3)
	for i in count + giants:
		var giant := i >= count
		var amount := rng.randi_range(40, 100) if anomaly else rng.randi_range(15, 100)
		var size := lerpf(30.0, 110.0, (amount - 15) / 85.0) * (1.25 if anomaly else 1.0) * rng.randf_range(0.85, 1.15)
		if giant:  # a mountain of a rock with a lot of ore in it
			amount = rng.randi_range(220, 380)
			size = rng.randf_range(240.0, 420.0)
		var p := center
		for _t in 20:
			p = center + _ring_point(rng, 0.0 if giant else 60.0, spread * (0.6 if giant else 1.0), 450.0)
			if placed.all(func(q): return q[0].distance_to(p) > q[1] + size + 60.0):
				break
		placed.append([p, size])
		var roll := Game.roll_ore(sys, anomaly)
		var a := Asteroid.new()
		a.main = self
		a.position = p
		world.add_child(a)
		a.setup(roll[0], roll[1], amount, rng.randi(), size)
	_spawn_pebbles(center, spread, rng)
	_spawn_clouds(center, spread, Game.CAT_COLORS[sys.cat], rng)


## Hundreds of small loose rocks (not mineable) filling out the field.
func _spawn_pebbles(center: Vector3, spread: float, rng: RandomNumberGenerator) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.11)
	mat.roughness = 0.95
	for k in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.rock_mesh(k * 2 + 1)
		mm.instance_count = 320
		for i in mm.instance_count:
			var s := lerpf(0.8, 28.0, pow(rng.randf(), 3.5))
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(b, center + _ring_point(rng, 0.0, spread * 1.15, 500.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		world.add_child(mmi)


## Big soft clouds of dust hanging in the field, tinted a little by the system's colour.
func _spawn_clouds(center: Vector3, spread: float, tint: Color, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(8, 13):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.albedo_texture = Models.soft_texture()
		m.albedo_color = Color(Color(0.36, 0.32, 0.28).lerp(tint, 0.12), rng.randf_range(0.05, 0.1))
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 300.0
		var q := QuadMesh.new()
		q.size = Vector2.ONE * rng.randf_range(1500.0, 4000.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = center + _ring_point(rng, 0.0, spread, 250.0)
		world.add_child(mi)


func _spawn_wreck(at: Vector3, sys_id: int, loc_i: int) -> void:
	var w := Wreck.new()
	w.main = self
	w.position = at
	world.add_child(w)
	var it := _landmark("Derelict", "wreck", "wreck", at, null, "[G]  Salvage the derelict")
	it["action"] = salvage_wreck.bind(w, it, sys_id, loc_i)
	interactables.append(it)
	_obstacle("sphere", {"c": at, "r": 30.0})


## Civilian ships about their business: haulers running between the station and the far points of the
## location, miners working the ore field. Wild space has none (only pirates go there).
func _spawn_traffic(sys: Dictionary, rng: RandomNumberGenerator) -> void:
	if sys.cat == Game.CAT_PURPLE:
		return
	var station := {}
	var field := {}
	var route := []
	for lm in landmarks:
		if lm.kind == "station":
			station = lm
		elif lm.kind == "ore":
			field = lm
		route.append(lm.pos + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1)) * 600.0)
	for i in 3:
		route.append(_ring_point(rng, 4000.0, 12000.0, 2000.0))
	if not station.is_empty():
		for i in rng.randi_range(3, 6):
			var n := Npc.new()
			n.main = self
			n.home = station.bay.pad + Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))  # on the pad
			n.lane = station.bay.mouth + station.bay.out * 350.0  # lined up in front of the bay
			n.home_out = station.bay.out
			n.route = route
			n.position = route[rng.randi() % route.size()].lerp(n.lane, rng.randf())
			world.add_child(n)
			n.setup("hauler", ["mule", "ark", "leviathan", "halberd", "prospector", "aegis", "monarch"][rng.randi() % 7], rng)
	if not field.is_empty():
		for i in rng.randi_range(2, 4):
			var n := Npc.new()
			n.main = self
			n.home = field.pos
			n.position = field.pos + _ring_point(rng, 200.0, 1500.0, 200.0)
			world.add_child(n)
			n.setup("miner", ["prospector", "mule", "bastion"][rng.randi() % 3], rng)

func salvage_wreck(w, it: Dictionary, sys_id: int, loc_i: int) -> void:
	if w.salvaged:
		return
	w.mark_salvaged()
	interactables.erase(it)
	it.erase("action")
	Game.mark_salvaged(sys_id, loc_i)
	var txt := Game.salvage(Game.systems[sys_id])
	sparks(w.position, Color("ffd24a"), 30)
	Sfx.play("refine", -4.0)
	Game.say(txt, UI.GOOD)


## Pirate types for one wave; Wild space and anomalies send tougher mixes (and sometimes a Captain).
func _wave(cat: int, anomaly: bool) -> Array:
	var picks := []
	if anomaly:
		picks = ["sentinel", "sentinel"]
		if randf() < 0.5:
			picks.append(["raider", "gunner", "sniper"].pick_random())
		if randf() < 0.15:
			picks.append("captain")
	elif cat == Game.CAT_GREEN:
		for i in randi_range(1, 2):
			picks.append("raider")
	elif cat == Game.CAT_RED:
		for i in randi_range(2, 3):
			picks.append(["raider", "raider", "gunner", "sniper", "swarmer"].pick_random())
	else:
		for i in randi_range(3, 4):
			picks.append(["raider", "gunner", "sniper", "swarmer", "swarmer"].pick_random())
		if randf() < 0.18:
			picks.append("captain")
	var out := []
	for t in picks:
		out.append(t)
		if t == "swarmer":
			out.append_array(["swarmer", "swarmer"])  # swarmers hunt in packs
	return out


func _spawn_pirates() -> void:
	var sys := current_sys()
	var anomaly: bool = current_loc().kind == "anomaly"
	var wave := _wave(sys.cat, anomaly)
	var base := randf() * TAU
	for t in wave:
		var p := Pirate.new()
		p.main = self
		var a := base + randf_range(-0.8, 0.8)
		var r := randf_range(160.0, 210.0)
		p.position = player.position + Vector3(cos(a) * r, randf_range(-30.0, 30.0), sin(a) * r)
		world.add_child(p)
		p.setup(t, sys.cat)
	if wave.has("captain"):
		Sfx.play("alarm", -2.0)
		Game.toast.emit("WARNING", "A Pirate Captain has arrived!", "skull", UI.BAD)
	if anomaly:
		Game.say("!! Anomaly Sentinels are waking up! (%d)" % wave.size(), Color("d080ff"))
	else:
		Game.say("!! Pirates detected! (%d)" % wave.size(), UI.BAD)


# ---------------------------------------------------------------- photo mode

## F1: hide the UI, freeze the action and fly a free camera round it. F1 or ESC goes back.
func toggle_photo() -> void:
	if not photo and not mode in ["fly", "warp"]:
		return
	photo = not photo
	ui_layer.visible = not photo
	vignette_layer.visible = not photo
	Engine.time_scale = 0.0 if photo else 1.0
	if _photo_hint == null:
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		_photo_hint = Label.new()
		_photo_hint.add_theme_font_override("font", UI.body)
		_photo_hint.add_theme_font_size_override("font_size", 17)
		_photo_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		_photo_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_photo_hint.add_theme_constant_override("outline_size", 4)
		_photo_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_photo_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		_photo_hint.offset_top = -46
		_photo_hint.offset_bottom = -18
		layer.add_child(_photo_hint)
	_photo_hint.visible = photo
	_photo_hint.text = _photo_help()
	_photo_hint_t = 6.0
	_photo_us = Time.get_ticks_usec()
	_photo_fov = camera.fov
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	if photo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.fov = FOV


func _photo_help() -> String:
	return "PHOTO MODE    mouse look    WASD move    E / Q up and down    SHIFT fast    ALT slow    wheel zoom    P save picture    H hide this    F1 back"


## Free camera, driven by real time (the game clock is stopped).
func _update_photo() -> void:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _photo_us) / 1000000.0, 0.1)
	_photo_us = now
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		move.y -= 1.0
	var speed := 40.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 10.0
	if Input.is_physical_key_pressed(KEY_ALT):
		speed *= 0.15
	if move != Vector3.ZERO:
		camera.global_position += camera.global_basis * move.normalized() * speed * dt
	camera.fov = lerpf(camera.fov, _photo_fov, 1.0 - exp(-10.0 * dt))
	_photo_hint_t -= dt
	_photo_hint.modulate.a = clampf(_photo_hint_t, 0.0, 1.0)


## P: save the view (without the hint) to the screenshots folder.
func _photo_save() -> void:
	_photo_hint.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var folder := OS.get_user_data_dir().path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("driftlight_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	img.save_png(path)
	Sfx.play("click", -6.0)
	_photo_hint.visible = photo
	_photo_hint.text = "Saved  %s" % ProjectSettings.globalize_path(path)
	_photo_hint_t = 4.0
	await get_tree().create_timer(4.0, true, false, true).timeout
	if _photo_hint:
		_photo_hint.text = _photo_help()

# ---------------------------------------------------------------- targets, autopilot, collisions

## Pushes a sphere (centre p, radius r) out of the big structures here. Returns how far it was moved.
func push_out(p: Vector3, r: float) -> Vector3:
	var total := Vector3.ZERO
	for o in obstacles:
		var q := p + total
		var away := Vector3.ZERO
		var pen := 0.0
		match o.type:
			"sphere":
				away = q - o.c
				pen = o.r + r - away.length()
			"capsule":
				var ab: Vector3 = o.b - o.a
				var t := clampf((q - o.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				away = q - (o.a + ab * t)
				pen = o.r + r - away.length()
			"torus":
				var v: Vector3 = q - o.c
				var flat: Vector3 = v - o.n * v.dot(o.n)
				if flat.length_squared() < 0.01:
					continue
				away = q - (o.c + flat.normalized() * o.R)
				pen = o.r + r - away.length()
			"cyl":  # upright cylinder
				var v: Vector3 = q - o.c
				var radial := Vector2(v.x, v.z).length()
				var side: float = o.R + r - radial
				var cap: float = o.h + r - absf(v.y)
				if side > 0.0 and cap > 0.0:
					if side < cap:
						away = Vector3(v.x, 0.0, v.z)
						pen = side
					else:
						away = Vector3(0.0, signf(v.y), 0.0)
						pen = cap
			"box":
				var v: Vector3 = q - o.c
				var best := INF
				for i in 3:
					var d: float = o.h[i] + r - absf(v[i])
					if d <= 0.0:
						best = INF
						break
					if d < best:
						best = d
						away = Vector3.ZERO
						away[i] = signf(v[i]) if v[i] != 0.0 else 1.0
				pen = best if best != INF else 0.0
		if pen > 0.0 and away.length_squared() > 0.000001:
			total += away.normalized() * pen
	return total


func target_valid(t) -> bool:
	if t == null:
		return false
	if t is Dictionary:
		return landmarks.has(t)
	return is_instance_valid(t) and not t.is_queued_for_deletion() and t.visible


func is_selected(t) -> bool:
	return target_valid(selected) and ((t is Dictionary and selected is Dictionary and t == selected) or
		(not t is Dictionary and not selected is Dictionary and t == selected))


func target_pos(t) -> Vector3:
	return t.pos if t is Dictionary else t.global_position


func target_size(t) -> float:
	return t.size if t is Dictionary else t.radius


## Name, icon, colour, a line of detail and what E does, for the overview and the target panel.
func target_info(t) -> Dictionary:
	if not target_valid(t):
		return {"name": "", "icon": "radar", "color": Color.WHITE, "sub": "", "use": ""}
	if t is Dictionary:
		var uses := {"station": "Dock", "gate": "Jump", "wormhole": "Enter", "wreck": "Salvage", "obelisk": "Approach",
			"spice": "Browse"}
		var sub := {"station": "Station  -  dock to refine, trade, build and repair", "gate": "Stargate  -  jump to another system",
			"ore": "Asteroid field  -  huge ore veins to mine", "obelisk": "Offering Obelisk  -  make an offering for a blessing",
			"spice": "Spice Stand  -  a trader in the middle of nowhere", "wormhole": "Wormhole  -  leads deep into Wild space",
			"wreck": "Derelict  -  salvage it for parts" if t.has("action") else "Derelict  -  already salvaged"}
		return {"name": t.name, "icon": t.icon, "color": Color("ffe066"), "sub": sub.get(t.kind, ""),
			"use": uses.get(t.kind, "") if t.has("action") else ""}
	if t.is_in_group("asteroids"):
		var col: Color = Game.ORES[t.ore_id].color
		if t.scanned:
			return {"name": Game.ore_label(t.ore_id, t.quality, "vein"), "icon": "ore", "color": col,
				"sub": "%d ore left  -  %d m across" % [t.remaining, roundi(t.radius * 2.0)], "use": ""}
		return {"name": "Asteroid (unscanned)", "icon": "ore", "color": col.lerp(Color(0.6, 0.6, 0.6), 0.6),
			"sub": "%d m across  -  press V to survey what's in it" % roundi(t.radius * 2.0), "use": ""}
	if t.is_in_group("pirates"):
		return {"name": t.data.name, "icon": "skull", "color": Color("ff5a5a"), "sub": t.describe(), "use": ""}
	if t.is_in_group("npcs"):
		return {"name": t.overview_name(), "icon": "ship", "color": Color("9fd3ff"), "sub": "Civilian  -  minding its own business",
			"use": ""}
	if t.is_in_group("crates"):
		return {"name": "Cargo container", "icon": "cargo", "color": Color("c49a3c"), "sub": "Shoot it open for ore and credits",
			"use": ""}
	if t.is_in_group("chunks"):
		return {"name": "%s  x%d" % [Game.ore_label(t.ore_id, t.quality, "ore"), t.amount], "icon": "ore",
			"color": Game.ORES[t.ore_id].color.lightened(0.2), "sub": "Loose ore  -  fly into it to collect it (O collects it all)",
			"use": ""}
	return {"name": "?", "icon": "radar", "color": Color.WHITE, "sub": "", "use": ""}


## Everything worth listing here, nearest first: landmarks, ships, containers, ore veins and loose ore.
## `cat` narrows it to one kind (all, places, ships, ore, loot); `minq` hides ore below that quality (veins
## you haven't scanned yet count as unknown, so they only show with no quality filter).
func overview_entries(limit: int, cat := "all", minq := -1) -> Array:
	var pp: Vector3 = player.position
	var all := []
	if cat in ["all", "places", "loot"]:
		for lm in landmarks:
			if cat != "loot" or lm.kind == "wreck":
				all.append(lm)
	var groups := {"all": ["pirates", "npcs", "crates", "asteroids", "chunks"], "places": [], "ships": ["pirates", "npcs"],
		"ore": ["asteroids", "chunks"], "loot": ["crates"]}
	for group in groups[cat]:
		for n in get_tree().get_nodes_in_group(group):
			if not n.visible or (group in ["asteroids", "chunks"] and n.position.distance_to(pp) > 12000.0):
				continue
			if minq >= 0 and group == "asteroids" and (not n.scanned or n.quality < minq):
				continue
			if minq >= 0 and group == "chunks" and n.quality < minq:
				continue
			all.append(n)
	all.sort_custom(func(a, b): return pp.distance_squared_to(target_pos(a)) < pp.distance_squared_to(target_pos(b)))
	var out := []
	for t in all.slice(0, limit):
		var info := target_info(t)
		out.append({"t": t, "name": info.name, "icon": info.icon, "color": info.color})
	return out


## The thing on screen nearest the point `at` (screen pixels), if anything is close enough to it.
func pick_at(at: Vector2):
	var best = null
	var best_d := INF
	var cands := landmarks.duplicate()
	for group in ["pirates", "npcs", "crates", "asteroids"]:
		cands.append_array(get_tree().get_nodes_in_group(group).filter(func(n): return n.visible))
	for t in cands:
		var p := target_pos(t)
		if camera.is_position_behind(p):
			continue
		var sp := camera.unproject_position(p)
		var dist := camera.global_position.distance_to(p)
		var on_screen_r := target_size(t) / maxf(dist, 1.0) * get_viewport().get_visible_rect().size.y
		var d := sp.distance_to(at)
		if d < maxf(26.0, on_screen_r * 0.8) and d < best_d:
			best_d = d
			best = t
	return best


func select(t) -> void:
	if not target_valid(t):
		return
	if not is_selected(t):
		Sfx.play("hover", -6.0)
	selected = t


## Can this order be given to the selected target right now?
func order_ok(what: String) -> bool:
	if not target_valid(selected) or mode != "fly":
		return false
	var d: float = player.position.distance_to(target_pos(selected))
	match what:
		"warp":
			return d > LOCAL_WARP_MIN
		"cruise":
			return d > CRUISE_MIN + target_size(selected)
		"use":
			return selected is Dictionary and selected.has("action")
	return true


## Approach, orbit, warp to or use the selected target.
func order(what: String) -> void:
	if not target_valid(selected) or mode != "fly":
		return
	var t = selected
	var d: float = player.position.distance_to(target_pos(t))
	var size := target_size(t)
	match what:
		"approach":
			_start_autopilot("approach", t, size + player.radius + (60.0 if t is Dictionary else 25.0))
		"orbit":
			_start_autopilot("orbit", t, size + player.radius + (250.0 if t is Dictionary else 60.0))
		"cruise":
			var stop: float = size + player.radius + (250.0 if t is Dictionary else 80.0)
			if d <= stop + CRUISE_MIN:
				_start_autopilot("approach", t, stop)
				return
			_start_autopilot("cruise", t, stop)
			autopilot["t"] = 0.0
			Sfx.play("charge", -7.0, 2.2 / CRUISE_SPOOL)
		"use":
			if not (t is Dictionary and t.has("action")):
				return
			if t.has("bay"):
				_start_autopilot("dock", t, 0.0)  # stations: fly into the docking bay
				return
			if d <= t.radius:
				t.action.call()
			else:
				_start_autopilot("use", t, t.radius * 0.8)
		"warp":
			if d <= LOCAL_WARP_MIN:
				Game.say("Too close to warp - approaching instead.", UI.MUTED)
				_start_autopilot("approach", t, size + player.radius + 60.0)
				return
			warp_local(t)


func _start_autopilot(what: String, t, range_m: float) -> void:
	var to: Vector3 = target_pos(t) - player.position
	var axis := to.cross(player.forward())
	if axis.length() < 0.01:
		axis = Vector3.UP
	autopilot = {"mode": what, "target": t, "range": range_m, "axis": axis.normalized()}
	Sfx.play("click", -8.0)


func cancel_autopilot(why := "") -> void:
	if autopilot.is_empty():
		return
	autopilot = {}
	player.cruise_v = 0.0
	if why != "":
		Game.say(why + " - autopilot off.", UI.MUTED)


func autopilot_text() -> String:
	if autopilot.is_empty():
		return ""
	if autopilot.mode == "collect":
		return "Collecting loose ore  -  %d pieces in reach" % get_tree().get_nodes_in_group("chunks").filter(
			func(c): return c.position.distance_to(player.position) < COLLECT_RANGE).size()
	var d: float = player.position.distance_to(target_pos(autopilot.target))
	match autopilot.mode:
		"cruise": return ("Cruise drive spooling up..." if autopilot.t < CRUISE_SPOOL else "Cruising  -  %s to go" % UI.dist(
			maxf(0.0, d - autopilot.range)))
		"orbit": return "Orbiting at %s" % UI.dist(autopilot.range)
		"dock": return "Docking approach  -  %s to the pad" % UI.dist(player.position.distance_to(autopilot.target.bay.pad))
		"use": return "Approaching to %s  -  %s to go" % [target_info(autopilot.target).use.to_lower(), UI.dist(maxf(0.0, d - autopilot.range))]
	return "Approaching  -  %s to go" % UI.dist(maxf(0.0, d - autopilot.range))


## O: the autopilot flies you from one loose chunk of ore to the next, nearest first, collecting them,
## until there are none left in reach or the hold is full. O again (or taking the controls) stops it.
func toggle_collect() -> void:
	if autopilot.get("mode", "") == "collect":
		cancel_autopilot("Collecting stopped")
		return
	if _nearest_chunk() == null:
		Game.say("No loose ore within %s." % UI.dist(COLLECT_RANGE), UI.MUTED)
		return
	autopilot = {"mode": "collect"}
	Sfx.play("click", -8.0)
	Game.say("Collecting loose ore - O or any flight key to stop.", Color("8cd8ff"))


func _nearest_chunk():
	var best = null
	var bd := COLLECT_RANGE
	for c in get_tree().get_nodes_in_group("chunks"):
		if c.is_queued_for_deletion():
			continue
		var d: float = player.position.distance_to(c.position)
		if d < bd:
			bd = d
			best = c
	return best


func _update_collect(delta: float) -> void:
	if Game.cargo_used() >= player.st.cargo:
		cancel_autopilot("Cargo hold full")
		return
	var c = _nearest_chunk()
	if c == null:
		autopilot = {}
		Game.say("All the loose ore in reach is collected.", UI.GOOD)
		return
	var to: Vector3 = c.position - player.position
	var d := to.length()
	var dir := to / maxf(d, 0.01)
	# full ahead when far, easing off as it closes so it doesn't overshoot; turn first if it's off the nose
	player.throttle = clampf(d / (player.top_speed() * 3.0), 0.15, 1.0)
	if player.forward().dot(dir) < 0.6:
		player.throttle = minf(player.throttle, 0.15)
	var up := aim.y if absf(dir.dot(aim.y)) < 0.95 else Vector3.UP
	var want := Basis.looking_at(dir, up).get_rotation_quaternion()
	aim = Basis(aim.get_rotation_quaternion().slerp(want, minf(1.0, 3.0 * delta))).orthonormalized()


## Steers (by swinging the aim, which the ship follows) and works the throttle for approach / orbit / use.
func _update_autopilot(delta: float) -> void:
	if autopilot.mode == "collect":
		_update_collect(delta)
		return
	var t = autopilot.target
	if not target_valid(t):
		autopilot = {}
		return
	var to: Vector3 = target_pos(t) - player.position
	if autopilot.mode == "dock":
		to = _dock_goal(t) - player.position
	var d := to.length()
	var top: float = player.top_speed()
	var dir := to / maxf(d, 0.01)
	match autopilot.mode:
		"cruise":
			autopilot.t += delta
			var left: float = d - autopilot.range
			if left <= 0.0:
				player.cruise_v = 0.0
				player.throttle = 0.0
				autopilot = {}
				return
			if autopilot.t < CRUISE_SPOOL:
				# spooling up: swing round onto the line and creep forward
				player.cruise_v = 0.0
				player.throttle = 0.2
			else:
				# hold cruise speed, easing back down to normal flight speed over the last stretch
				player.cruise_v = clampf(left * 0.9, player.top_speed(), top * CRUISE_MULT + 60.0)
			dir = _avoid(dir, maxf(player.vel.length(), 60.0))
		"dock":
			# full ahead to the approach lane, then in under half throttle, easing off toward the pad
			var lined_up: bool = _dock_goal(t) == t.bay.pad
			player.throttle = clampf(d / (top * 5.0), 0.25, 0.5) if lined_up else 1.0
			# don't push on until the nose is roughly where we're going
			if player.forward().dot(dir) < 0.7:
				player.throttle = minf(player.throttle, 0.15)
		"approach", "use":
			var left: float = d - autopilot.range
			if left <= 0.0:
				player.throttle = 0.0
				var arrived = autopilot
				autopilot = {}
				if arrived.mode == "use" and t is Dictionary and t.has("action"):
					t.action.call()
				return
			# ease off near the end so you stop about where you meant to
			player.throttle = clampf(left / (top * 2.0), 0.12, 1.0)
		"orbit":
			var radial := -dir
			var tangent: Vector3 = (autopilot.axis as Vector3).cross(radial).normalized()
			dir = (tangent + radial * clampf((autopilot.range - d) / autopilot.range * 3.0, -1.5, 1.5)).normalized()
			player.throttle = 0.8
	var up := aim.y if absf(dir.dot(aim.y)) < 0.95 else Vector3.UP
	var want := Basis.looking_at(dir, up).get_rotation_quaternion()
	aim = Basis(aim.get_rotation_quaternion().slerp(want, minf(1.0, 2.5 * delta))).orthonormalized()


## Cruise steering: bend `dir` away from any rock (or ship) in the way ahead, harder the closer and more
## head-on it is, so a cruise threads through a field instead of ploughing into it.
func _avoid(dir: Vector3, speed: float) -> Vector3:
	var p: Vector3 = player.position
	var look := maxf(300.0, speed * 3.0)
	var push := Vector3.ZERO
	for g in ["asteroids", "npcs"]:
		for a in group(g):
			var rel: Vector3 = a.position - p
			var along := rel.dot(dir)
			if along < -a.radius or along > look + a.radius:
				continue
			var off: Vector3 = rel - dir * along
			var clear: float = a.radius + player.radius + 35.0
			var miss := off.length()
			if miss >= clear:
				continue
			var away: Vector3 = -off / miss if miss > 0.01 else dir.cross(Vector3.UP).normalized()
			push += away * (clear - miss) / clear * clampf(1.0 - along / (look + a.radius), 0.25, 1.0)
	return (dir + push * 2.5).normalized() if push != Vector3.ZERO else dir


## Admin: straight to any system through a short jump, arriving at its first planet.
func admin_jump(id: int) -> void:
	close_maps()
	if mode != "fly" or id == Game.current_system:
		return
	var sys: Dictionary = Game.systems[id]
	var loc_i := 0
	for i in sys.locs.size():
		if sys.locs[i].kind == "planet":
			loc_i = i
			break
	var heading: Vector2 = sys.pos - current_sys().pos
	_travel_to("jump", sys.name, 1.0, 4.0, enter_location.bind(id, loc_i, _arrival_spot(heading)), Game.CAT_COLORS[sys.cat], heading)


## Admin: a pirate wave, here and now.
func call_pirates() -> void:
	if mode == "fly":
		_spawn_pirates()


## A warp across the location to the target: align, a short charge, then a few seconds at warp with the
## world streaking past, dropping out a little short of it.
func warp_local(t) -> void:
	var tp := target_pos(t)
	var to: Vector3 = tp - player.position
	var d := to.length()
	var stop := target_size(t) + 300.0
	if t is Dictionary:
		# land within reach of a station or gate (EVE's "warp to 0"), or at the edge of an ore field
		stop = 3000.0 if t.kind == "ore" else maxf(t.radius * 0.6, t.size + 150.0)
	var dest := tp - to.normalized() * minf(stop, d * 0.5)
	if t is Dictionary and t.has("bay"):
		# a station: drop out in its approach lane, in front of the docking bay
		dest = t.bay.mouth + t.bay.out * BAY_LANE
		to = dest - player.position
		d = to.length()
	cancel_autopilot()
	_travel_to("local", target_info(t).name, 1.2, 2.5 + d / 3500.0, Callable(), Color(0.55, 0.8, 1.0), Vector2(to.x, to.z),
		{"heading3": to.normalized(), "from": player.position, "to": dest})


## V: a survey pulse that reveals what's in every asteroid within range (each one glints as it reaches it).
func survey_scan() -> void:
	if _scan_cd > 0.0:
		Game.say("Survey scanner recharging (%ds)." % ceili(_scan_cd), UI.MUTED)
		return
	_scan_cd = SCAN_COOLDOWN
	Sfx.play("charge", -6.0, 1.8)
	var n := 0
	var ore := 0
	for a in get_tree().get_nodes_in_group("asteroids"):
		var d: float = a.position.distance_to(player.position)
		if d < SCAN_RANGE:
			a.scanned = true
			a.ping(d / SCAN_RANGE * 1.5)  # the pulse reaches the far rocks last
			n += 1
			ore += a.remaining
	if n == 0:
		Game.say("Survey scan: no asteroids within %s." % UI.dist(SCAN_RANGE), UI.MUTED)
	else:
		Game.say("Survey scan: %d asteroids, %d ore in reach. Check the overview." % [n, ore], Color("8cd8ff"))

# ---------------------------------------------------------------- spawning helpers

const LASER_SHADER = preload("res://shaders/laser.gdshader")
var _laser_mats := {}


## A laser material per bolt colour.
func _laser_mat(color: Color) -> ShaderMaterial:
	if not _laser_mats.has(color):
		var m := ShaderMaterial.new()
		m.shader = LASER_SHADER
		m.set_shader_parameter("color", color)
		_laser_mats[color] = m
	return _laser_mats[color]


func spawn_bullet(pos: Vector3, dir: Vector3, s: Dictionary, friendly: bool) -> void:
	var b := Bullet.new()
	b.main = self
	# the beam: a white-hot core in a coloured glow, laid back from the bolt's head; it starts at nothing
	# and grows out of the muzzle as the bolt flies (bullet._stretch)
	var beam := MeshInstance3D.new()
	beam.mesh = Models.streak_mesh(1.0, 1.0)
	beam.material_override = _laser_mat(s.color)
	beam.rotation.x = -PI / 2.0  # the mesh's head end (+Y) points forward (-Z)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(beam)
	b.beam = beam
	b.beam_width = s.size.x * 0.4
	b.beam_len = s.size.y * (3.0 if friendly else 1.8)  # player bolts are fast: longer beams
	b.add_child(Models.glow_quad(Color(Color(s.color).lerp(Color.WHITE, 0.3), 0.5), s.size.x * 0.35))  # a tight hot spot at the head
	b.vel = dir * s.speed
	b.life = s.life * (player.st.bolt if friendly else 1.0)
	b.damage = s.damage
	b.mining = s.mining
	b.friendly = friendly
	b.color = s.color
	b.pierce = s.pierce
	b.homing = s.homing
	b.slow = s.slow
	world.add_child(b)
	b.global_position = pos
	b.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


func spawn_chunk(ore: String, q: int, amount: int, pos: Vector3, vel: Vector3) -> void:
	var c := OreChunk.new()
	c.main = self
	c.ore_id = ore
	c.quality = q
	c.amount = amount
	c.position = pos
	c.vel = vel
	world.add_child(c)


func sparks(pos: Vector3, color: Color, n: int) -> void:
	_fx(pos).sparks(color, n)


## A bolt chipping a rock: dust and grit thrown off along `normal`.
func rock_hit(pos: Vector3, color: Color, normal: Vector3) -> void:
	_fx(pos).rock_hit(color, normal)


## rocky: an asteroid breaking up (dust and rock chunks) rather than a ship blowing up.
func explosion(pos: Vector3, scale_f: float, color: Color, rocky := false) -> void:
	_fx(pos).explode(scale_f, color, rocky)
	Sfx.play("explode", -6.0, randf_range(0.8, 1.1))
	if player.alive and pos.distance_to(player.position) < 120.0:
		shake(0.25 * scale_f)


func cargo_full() -> void:
	if Time.get_ticks_msec() - _full_warned > 2500:
		_full_warned = Time.get_ticks_msec()
		Game.say("Cargo hold full! Refine at a station, or jettison something (I).", UI.BAD)


# ---------------------------------------------------------------- travel

## Damage is ignored while docked, or inside the warp tunnel (but not while turning or charging).
func invulnerable() -> bool:
	return mode == "docked" or (mode == "warp" and not travel.get("phase", "") in ["align", "charge"])


## Start a timed warp or jump: the ship turns to face the destination, the drive charges (you can still
## be shot; ESC or X cancels), then you fly the warp tunnel, then arrive gliding.
## extra: for a warp inside this location (kind "local") the 3D heading and the from / to points.
func _travel_to(kind: String, dest: String, charge: float, tunnel_time: float, arrive: Callable, color: Color, heading: Vector2,
		extra := {}) -> void:
	var speed: float = Game.stats_ship().warp
	var h3 := Vector3(heading.x, 0.0, heading.y)
	h3 = h3.normalized() if h3.length() > 0.001 else player.forward()
	if extra.has("heading3"):
		h3 = extra.heading3
	var want := Basis.looking_at(h3, Vector3.UP)
	travel = {"kind": kind, "dest": dest, "phase": "align", "t": 0.0, "charge": charge / speed,
		"travel": tunnel_time / speed, "arrive": arrive, "color": color, "heading": h3, "want": want,
		"align_total": maxf(0.05, player.forward().angle_to(h3))}
	travel.merge(extra)
	(tunnel.material as ShaderMaterial).set_shader_parameter("tint", color)
	mode = "warp"
	player.throttle = 0.0


func _update_travel(delta: float) -> void:
	travel.t += delta
	if travel.phase in ["align", "charge"] and (Input.is_action_just_pressed("cut_throttle") or Input.is_action_just_pressed("close")):
		travel = {}
		_scroll_speed = 0.0
		mode = "fly"
		Game.say("Warp cancelled.", UI.MUTED)
		return
	var fwd: Vector3 = player.forward()
	warp_scroll += fwd * _scroll_speed * delta
	match travel.phase:
		"align":
			# the ship swings round to face the destination (see ship._turn) before the drive can charge
			aim = travel.want
			player.vel = player.vel.move_toward(Vector3.ZERO, player.top_speed() * 0.6 * delta)
			if travel.has("gate"):
				player.vel -= _off_axis(travel.gate) * 1.5 * delta  # drift onto the gate's centre line
			if fwd.angle_to(travel.heading) < 0.02:
				travel.phase = "charge"
				travel.t = 0.0
				Sfx.play("charge", -6.0, 2.2 / travel.charge)
		"charge":
			var k: float = clampf(travel.t / travel.charge, 0.0, 1.0)
			shake(k * 0.12)
			if travel.has("gate"):
				# the railgun: accelerate hard down the barrel, held to its centre line, to leave the muzzle
				# just as the charge completes; the coils flare as the ship passes through them
				var g: Dictionary = travel.gate
				var into: Vector3 = -g.out
				if not travel.has("rail_a"):
					var left: float = GateField.MOUTH + GateField.MUZZLE + 20.0 - (player.position - g.mouth).dot(into)
					travel.rail_a = 2.0 * maxf(left, 60.0) / (travel.charge * travel.charge)
					g.gate.launch(travel.charge)
				player.vel = into * travel.rail_a * travel.t - _off_axis(g) * 4.0
				_scroll_speed = 220.0 * k * k * k
			else:
				# the ship starts rolling forward and the world begins to slide past
				player.vel = fwd * player.top_speed() * 0.5 * k
				_scroll_speed = 220.0 * k * k * k
			if travel.t >= travel.charge:
				travel.phase = "travel"
				travel.t = 0.0
				if travel.kind == "local":
					travel.from = player.position  # it crept forward while charging
				else:
					_rush = Vector3.ZERO
					_rush_v = 400.0 if travel.has("gate") else 150.0
				_flash(0.35)
				Sfx.play("warp", -6.0)
				var f := _fx(player.position)
				# punch forward: a jet of light blasts out behind the ship
				f.jet(70, Color(travel.color).lightened(0.4), -fwd, 160.0, 14.0, 0.8)
				f.jet(30, Color.WHITE, -fwd, 220.0, 6.0, 0.5)
				_fov_kick = 18.0
		"travel":
			if travel.kind == "local":
				# across this location with the world still there, streaking past (and the planet swinging by)
				var s := clampf(travel.t / travel.travel, 0.0, 1.0)
				var before: Vector3 = player.position
				player.position = (travel.from as Vector3).lerp(travel.to, s * s * (3.0 - 2.0 * s))
				player.vel = (player.position - before) / maxf(delta, 0.001) * 0.02
				warp_scroll += player.position - before
			else:
				# everything here - stations, rocks, the planet - streams away behind you faster and faster
				# until it's gone
				player.vel = Vector3.ZERO
				_scroll_speed = move_toward(_scroll_speed, WARP_SCROLL_MAX, 3000.0 * delta)
				_rush_v = minf(_rush_v * exp(3.0 * delta), 600000.0)
				_rush += travel.heading * _rush_v * delta
				world.position = -_rush
				world.visible = _rush.length() < 60000.0
			if travel.t >= travel.travel:
				travel.phase = "exit"
				travel.t = 0.0
				if travel.kind != "local":
					travel.arrive.call()
					# the new place rushes in from far ahead and settles round you
					_rush = -travel.heading * 30000.0
					world.position = -_rush
				world.visible = true
				_flash(0.25)
				Sfx.play("arrive", -6.0)
				fwd = player.forward()
				# drop out of warp still moving: light sprays out ahead and the ship glides forward
				var f := _fx(player.position)
				f.jet(50, Color(travel.color).lightened(0.5), fwd, 200.0, 20.0, 0.8)
				f.jet(25, Color.WHITE, fwd, 260.0, 8.0, 0.5)
				player.vel = fwd * player.top_speed() * 1.6
				_fov_kick = -12.0
				shake(0.3)
		"exit":
			_scroll_speed = move_toward(_scroll_speed, 0.0, 4000.0 * delta)
			_rush *= exp(-7.0 * delta)
			world.position = -_rush
			if travel.t >= (0.6 if travel.kind == "local" else 1.2):
				travel = {}
				_scroll_speed = 0.0
				_rush = Vector3.ZERO
				world.position = Vector3.ZERO
				mode = "fly"


## How far the ship is off a gate's centre line (sideways, as a vector).
func _off_axis(g: Dictionary) -> Vector3:
	var into: Vector3 = -g.out
	var rel: Vector3 = player.position - g.mouth
	return rel - into * rel.dot(into)


## The direction you arrive from (enter_location drops you out of warp short of the main thing there,
## coming in along your heading, so you glide in).
func _arrival_spot(heading: Vector2) -> Vector3:
	var h := Vector3(heading.x, -0.08, heading.y)
	return h.normalized() if Vector2(h.x, h.z).length() > 0.001 else Vector3.FORWARD


func _flash(a: float) -> void:
	fade.color.a = a
	create_tween().tween_property(fade, "color:a", 0.0, 0.45)


func start_warp(loc_i: int) -> void:
	if mode != "fly":
		return
	force_warp_menu = false
	warp_menu.hide()
	if loc_i >= 1000:  # somewhere in this location (see warp_menu)
		var lm: Dictionary = landmarks[loc_i - 1000]
		select(lm)
		order("warp")
		return
	var sys := current_sys()
	var from: Vector2 = sys.locs[Game.current_loc].map_pos
	var to: Vector2 = sys.locs[loc_i].map_pos
	_travel_to("warp", sys.locs[loc_i].name, WARP_CHARGE, WARP_BASE + from.distance_to(to) * WARP_PER_UNIT,
		enter_location.bind(Game.current_system, loc_i, _arrival_spot(to - from)), Game.CAT_COLORS[sys.cat], to - from)


func try_gate(dest: int) -> void:
	var d: Dictionary = Game.systems[dest]
	if d.cat == Game.CAT_PURPLE:
		ask("!!  WARNING  !!\n\n%s is a WILD system.\nPirates hold roughly 60%% of its planets, and you lose your cargo if you're destroyed.\nAnomalies hide in Wild space, though...\n\nJump anyway?" % d.name,
			"Jump", _gate_jump.bind(dest))
	else:
		_gate_jump(dest)


## Jump to another system. Flown into a stargate's mouth, the gate's coils fire you down its barrel (which
## points at that system) and out of the muzzle into the jump.
func _gate_jump(dest: int) -> void:
	var back := Game.gate_index(dest, Game.current_system)
	Game.event("jump")
	var heading: Vector2 = Game.systems[dest].pos - current_sys().pos
	var extra := {}
	if not _gate_bay.is_empty() and player.position.distance_to(_gate_bay.mouth) < 800.0:
		extra = {"gate": _gate_bay}
	_gate_bay = {}
	_travel_to("jump", Game.systems[dest].name, JUMP_CHARGE, JUMP_BASE + heading.length() * JUMP_PER_PX,
		enter_location.bind(dest, back, _arrival_spot(heading)), Game.CAT_COLORS[Game.systems[dest].cat], heading, extra)


func enter_wormhole() -> void:
	var loc := current_loc()
	if loc.wormhole < 0 or mode != "fly":
		return
	var other: Dictionary = Game.anomalies[loc.wormhole]
	ask("The wormhole churns violently. It leads somewhere very far away, deep in WILD space, where pirates rule.\n\nGo through?",
		"Enter", _wormhole_jump.bind(other.sys, other.loc))


func _wormhole_jump(sys_id: int, loc_i: int) -> void:
	Game.say("The wormhole spat you out in %s!" % Game.systems[sys_id].name, Color("e080ff"))
	Game.event("wormhole")
	var heading: Vector2 = Game.systems[sys_id].pos - current_sys().pos
	_travel_to("wormhole", Game.systems[sys_id].name, JUMP_CHARGE, WORMHOLE_TIME,
		enter_location.bind(sys_id, loc_i, _arrival_spot(heading)), Color("d050ff"), heading)


func ask(text: String, yes_text: String, on_yes: Callable) -> void:
	var prev := mode
	mode = "dialog"
	confirm.ask(text, yes_text, _confirm_yes.bind(prev, on_yes), _confirm_no.bind(prev))


func _confirm_yes(prev: String, on_yes: Callable) -> void:
	mode = prev
	on_yes.call()


func _confirm_no(prev: String) -> void:
	mode = prev


# ---------------------------------------------------------------- panels & maps

func open_station(loc: Dictionary) -> void:
	mode = "docked"
	player.stop()
	player.heal_full()
	Sfx.play("dock", -4.0)
	var key := "%d:%d" % [Game.current_system, Game.current_loc]
	var got := Game.collect(key)
	if not got.is_empty():
		var parts := []
		for id in got:
			parts.append("%d %s" % [got[id], Game.ORES[id].name])
		Game.say("Collected from the furnace: " + ", ".join(parts), UI.GOOD)
	station_ui.open("station", loc)
	Game.save_game()


func open_panel(kind: String, loc: Dictionary) -> void:
	mode = "panel"
	player.stop()
	station_ui.open(kind, loc)


func close_panel() -> void:
	station_ui.hide()
	var was_docked := mode == "docked"
	mode = "fly"
	if was_docked and not _docked_bay.is_empty():
		# undock: released from the pad, drifting gently out toward the mouth
		var bay := _docked_bay
		_docked_bay = {}
		player.position = bay.pad + Vector3(0, 4, 0)
		aim = Basis.looking_at(bay.out, Vector3.UP)
		player.basis = aim
		player.stop()
		player.vel = bay.out * 5.0
		_dock_armed = false
		snap_camera()


func close_inventory() -> void:
	inventory.hide()
	if mode == "inventory":
		mode = "fly"


func close_fitting() -> void:
	fitting.hide()
	if mode == "fitting":
		mode = "fly"


## The nodes in a group, fetched once a frame (every bolt asks for them every frame).
func group(g: String) -> Array:
	var f := Engine.get_process_frames()
	if f != _group_frame:
		_group_frame = f
		_group_cache.clear()
	if not _group_cache.has(g):
		_group_cache[g] = get_tree().get_nodes_in_group(g)
	return _group_cache[g]


## Is `p` in or near an ore field (where the rocks are)?
func near_field(p: Vector3) -> bool:
	for fl in fields:
		if p.distance_squared_to(fl.c) < fl.r * fl.r:
			return true
	return false


func close_maps() -> void:
	galaxy_map.hide()
	system_map.close()
	if mode == "map":
		mode = "fly"


func player_died() -> void:
	if mode == "dead":
		return
	mode = "dead"
	travel = {}
	_scroll_speed = 0.0
	_rush = Vector3.ZERO
	world.position = Vector3.ZERO
	world.visible = true
	explosion(player.position, 2.2, Color("ff7a45"))
	shake(0.6)
	player.set_dead(true)
	close_maps()
	station_ui.hide()
	inventory.hide()
	fitting.hide()
	confirm.hide()
	Game.cargo.clear()
	Game.event("death")
	Game.changed.emit()
	Game.say("Your ship was destroyed! Your cargo is lost.", UI.BAD)
	await get_tree().create_timer(3.0).timeout
	_flash(1.0)
	_respawn()


func _respawn() -> void:
	player.set_dead(false)
	player.heal_full()
	mode = "fly"
	enter_location(0, 0)
	Game.say("Your ship was rebuilt at Core Station.", Color("9fd3ff"))
	Game.save_game()
