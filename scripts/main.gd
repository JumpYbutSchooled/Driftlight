extends Node3D
## Runs the 3D game: title screen, building each location, the mouse-aim camera, warping and gates,
## saving, and all the UI.
##
## Controls: W/S pitch, Q/E turn, A/D roll, R/F throttle, SHIFT boost, X brake. The mouse swings the
## camera round the ship (it never steers); the gun turrets swivel to whatever the crosshair in the middle
## of the screen is on, and left click fires (a turret whose shot would pass through your own hull won't).
## Right-click selects what's under the crosshair; with something selected 1 approaches, 2 orbits, 3 warps
## to it and G docks / jumps / uses it. C frees the cursor (or hold ALT), wheel zooms, middle-click
## puts the camera back behind the ship. T: auto-travel along the plotted route, gates and warps and all.
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
const STAR_SHADER = preload("res://shaders/star.gdshader")
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
const DockScreen = preload("res://scripts/ui/dock_screen.gd")
const DebugUI = preload("res://scripts/ui/debug_ui.gd")
const Confirm = preload("res://scripts/ui/confirm.gd")
const Title = preload("res://scripts/ui/title.gd")
const Pause = preload("res://scripts/ui/pause.gd")
const AdminPanel = preload("res://scripts/ui/admin_panel.gd")
const JumpMap = preload("res://scripts/ui/jump_map.gd")
const CodePanel = preload("res://scripts/ui/code_panel.gd")
const Updater = preload("res://scripts/updater.gd")
const AUTOSAVE_EVERY := 30.0  # save at least this often...
const SAVE_AFTER_CHANGE := 5.0  # ...and within this many seconds of anything changing
# warp timings (seconds, before Warp Core / ship bonuses): charge-up, then time in the warp tunnel
const WARP_CHARGE := 1.6
const WARP_BASE := 0.8
const WARP_PER_UNIT := 1.0  # per system-map unit travelled (a system is about 2.2 units across)
# jumping to another system always takes longer than any warp inside a system
const JUMP_CHARGE := 3.0
const JUMP_BASE := 4.0
const JUMP_PER_PX := 1.0 / 80.0  # per galaxy-map pixel between the two systems
const WORMHOLE_TIME := 6.0
const WARP_RUSH := 400000.0  # m/s the world streams away at once a jump's drive has charged: no build-up
const CHARGE_SPEED := 22.0  # times top speed: how fast the charging drive drags the ship before the burst
const LOCAL_WARP_SPEED := 12000.0  # m/s across a location: a steady, very fast run
const JUMP_DRIVE_CHARGE := 5.0  # capital ships: the jump drive winds up longer...
const JUMP_DRIVE_COOLDOWN := 20.0  # ...and needs a while to recharge
const CAPITAL_DOCK := 4000.0  # capital ships can't fit in a bay: they tether to a station from this close
const MOUSE_SENS := 0.0022  # radians of aim per pixel of mouse movement
const FOV := 72.0
const WARP_SCROLL_MAX := 1400.0  # m/s the background streams past inside the tunnel
const FEATURE_SPACING := 16000.0  # metres between the things at one location
const LOCAL_WARP_MIN := 2500.0  # anything further away than this can be warped to without leaving
const FLIGHT_MENUS := ["map", "inventory", "fitting"]  # menus opened in flight: the ship (and its autopilot) keeps flying under them
const ZOOM_MIN := 0.5
const ZOOM_MAX := 120.0
const SCAN_RANGE := 7000.0  # survey scanner reach (V)
const SCAN_COOLDOWN := 8.0
# how far from each kind of thing you drop out of warp, and how close you must be to use it
const ARRIVE := {"station": 5000.0, "gate": 1100.0, "ore": 3600.0, "obelisk": 700.0, "spice": 450.0, "wormhole": 1100.0,
	"wreck": 450.0, "relic": 900.0}
const USE_RANGE := {"obelisk": 280.0, "spice": 170.0, "wormhole": 500.0, "wreck": 260.0, "relic": 360.0}
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
const CRUISE_MULT := 14.0  # cruise speed: this many times the ship's normal top speed
# rough size of each thing (for picking it on screen and where "approach" stops)
const SIZE := {"station": 1000.0, "gate": 150.0, "ore": 2600.0, "obelisk": 60.0, "spice": 25.0, "wormhole": 160.0,
	"wreck": 35.0, "relic": 80.0}

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
var dock_screen  # the black screen and startup sequence round docking
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
var star_mat: ShaderMaterial  # the system's star (shaders/star.gdshader)
var _look := {}  # how this system looks (Game.system_look)
var _obs := Vector3.ZERO  # where you are relative to the system's star, in system-map units (y: below its plane)
var _atmo: ShaderMaterial  # the planet's atmosphere (lit from the star)
var _scan_cd := 0.0
var _cam_q := Quaternion.IDENTITY  # where the mouse has swung the camera to: it orbits the ship freely, any way up
var _cam_view := Quaternion.IDENTITY  # the camera's actual turn, easing after _cam_q
var _shake_t := 0.0
var _noise := FastNoiseLite.new()  # smooth camera shake
var ap_power := 1.0  # how hard the autopilot pushes (R/F while it flies)
var jump_map: Control  # the map that swoops between systems when a jump finishes
var code_panel: Control  # save codes: copy this save as text, or load one from another device
var auto_travel := false  # T: following the route on its own, warps and gates and all
var _jump_cd := 0.0  # jump drive recharge
var _prev_mode := "title"
var _from_dock := false  # the open map or menu was opened from the station: closing it goes back there
var ui_layer: CanvasLayer
var vignette_layer: CanvasLayer
var photo := false  # F1 photo mode
var _photo_running := false  # photo mode with time running again (T)
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
var _bay_warned := 0  # when we last said you can't warp in a docking bay (msec)
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
	dock_screen = _ui(root, DockScreen.new())  # under the station menus, over everything else
	station_ui = _ui(root, StationUI.new())
	inventory = _ui(root, InventoryUI.new())
	fitting = _ui(root, Fitting.new())
	title = _ui(root, Title.new())
	confirm = Confirm.new()
	root.add_child(confirm)
	jump_map = _ui(root, JumpMap.new())
	pause = _ui(root, Pause.new())
	code_panel = _ui(root, CodePanel.new())  # (over the ESC menu and the title)
	admin_panel = _ui(root, AdminPanel.new())
	updater = Updater.new()
	add_child(updater)
	fade = ColorRect.new()
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color(1, 1, 1, 0)
	root.add_child(fade)

	Game.notify.connect(hud.push_message)
	Game.jettisoned.connect(_on_jettison)
	_noise.frequency = 0.9
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
	# slightly hard colour
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
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
	# the system's star: a quad the shader holds far out along the star's direction from the camera
	var star := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	star.mesh = q
	star_mat = ShaderMaterial.new()
	star_mat.shader = STAR_SHADER
	star.material_override = star_mat
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.custom_aabb = AABB(Vector3.ONE * -1.0e7, Vector3.ONE * 2.0e7)  # it's wherever the camera is
	add_child(star)
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
		Game.end_session()
		Sfx.save_settings()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode != "title":
		Game.save_game()


# ---------------------------------------------------------------- game flow

func start_new_game() -> void:
	Game.keep_before_new_game()
	Game.new_game()
	if Game.sandbox:
		Game.sandbox_fill()
	_begin(0, 0)
	Game.say("Welcome aboard the Wren! You have nothing but your ship. Go mine some Corrite.", Color("9fd3ff"))
	Game.say("W/S pitch, Q/E turn, A/D roll, R/F throttle. The mouse looks around, click to fire. Hold SPACE to warp to the Core Belt.", Color("9fd3ff"))
	Game.say("Lost? Press H for the Guide.", Color("9fd3ff"))
	Game.save_game()


func continue_game() -> void:
	# a save that won't load is never replaced without asking (it stays in the backups folder either way)
	if not Game.load_game():
		if Game.save_too_new > 0:
			ask(Game.load_error, "OK", func(): pass)
		else:
			ask(Game.load_error + "\n\nNothing has been overwritten. Start a new game instead? (The old save is kept in the backups folder.)",
				"Start a new game", start_new_game)
		return
	_begin(Game.current_system, Game.current_loc)
	Game.say("Welcome back, pilot.", Color("9fd3ff"))
	if Game.away_smelted > 0:
		Game.say("While you were away (%s) your furnaces smelted %d materials. Dock there to collect them." % [
			UI.span(Game.away_time), Game.away_smelted], Color("e8a060"))
	if Game.loaded_backup != "":
		Game.say("Your save was missing or damaged, so it was restored from the backup %s." % Game.loaded_backup.get_file(),
			Color("ffd24a"))


func _begin(sys_id: int, loc_i: int) -> void:
	title.hide()
	player.set_dead(false)
	player.setup()
	mode = "fly"
	Game.in_game = true
	hud._title = ""
	enter_location(sys_id, loc_i)
	_since_save = 0.0


func quit_to_title() -> void:
	dock_screen.reset()
	Game.docked = false
	_from_dock = false
	Game.end_session()
	Game.in_game = false  # (from here until Continue, nothing on the title can write a save)
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
		if _photo_running:
			_photo_world(delta)
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
		elif mode in ["fly", "warp", "dead", "docking", "launching"] and not cursor_free():
			want_mouse = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want_mouse:
		Input.mouse_mode = want_mouse
	set_cursor("arrow" if want_mouse == Input.MOUSE_MODE_VISIBLE else "dot")
	if mode == "title":
		_prev_mode = mode
		_update_camera(delta)
		return
	# the HUD flickers back on, piece by piece, when flight resumes after a warp, the docking screens or a respawn
	if mode == "fly" and _prev_mode in ["warp", "launching", "title", "dead", "docked", "docking"]:
		hud.flicker_in()
	_prev_mode = mode
	_jump_cd = maxf(0.0, _jump_cd - delta)
	if not travel.is_empty():
		_update_travel(delta)
	player.turn_input = Vector3.ZERO
	if mode == "fly":
		_steer()
	# the autopilot keeps flying with a map, the inventory or the fitting screen open (only a station, a dialog
	# or a warp take it over)
	if (mode == "fly" or mode in FLIGHT_MENUS) and not autopilot.is_empty():
		if mode == "fly":
			# R/F set how hard the autopilot pushes, without taking the controls back
			if Input.is_action_pressed("move_up"):
				ap_power = minf(1.0, ap_power + 0.8 * delta)
			elif Input.is_action_pressed("move_down"):
				ap_power = maxf(0.2, ap_power - 0.8 * delta)
		_update_autopilot(delta)
	elif mode == "fly" and auto_travel and travel.is_empty() and player.alive:
		_update_auto(delta)
	if selected != null and not target_valid(selected):
		selected = null
	_scan_cd = maxf(0.0, _scan_cd - delta)
	# the camera follows the ship once it has moved this frame (the ship runs first: see _ready), so the
	# two never step out of time with each other
	_update_camera(delta)
	_aim_raycast()

	var holding: bool = mode == "fly" and Input.is_action_pressed("warp_menu")
	if holding and in_bay():
		holding = false  # no warp menu inside a docking bay
		if Input.is_action_just_pressed("warp_menu"):
			_bay_blocks()
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
	if loc.pirates and not loc.station and mode != "dead" and not Game.peaceful:
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


## Keys turn the ship: Q/E yaw, W/S pitch, A/D roll. The ship spins up and down with momentum (see
## ship._turn); taking the controls hands them back from the autopilot.
func _steer() -> void:
	var yaw := Input.get_axis("yaw_right", "yaw_left")
	var pitch := Input.get_axis("pitch_down", "pitch_up")
	var roll := Input.get_axis("roll_left", "roll_right")
	player.turn_input = Vector3(pitch, yaw, roll)
	if yaw != 0.0 or pitch != 0.0 or roll != 0.0:
		cancel_autopilot("Manual control")
		stop_auto("Manual control")


## Is the cursor freed for clicking (C toggles it, holding ALT frees it for a moment)?
func cursor_free() -> bool:
	return command or (mode in ["fly", "warp"] and Input.is_key_pressed(KEY_ALT))


## Put the camera straight behind the ship, the ship's way up (on arrival at once; on a middle-click it
## swings round).
func snap_camera(instant := true) -> void:
	_cam_q = aim.orthonormalized().get_rotation_quaternion()
	if instant:
		_cam_view = _cam_q


## Swing the camera round the ship: `yaw` about its own up, `pitch` about its own right (radians). No limits:
## it can go right over the top.
func cam_turn(yaw: float, pitch: float) -> void:
	_cam_q = (_cam_q * Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)).normalized()


## Point the camera along `dir`, keeping roughly its current up.
func cam_look(dir: Vector3, instant := false) -> void:
	var up: Vector3 = Basis(_cam_q).y
	if absf(dir.normalized().dot(up)) > 0.98:
		up = Basis(_cam_q).z
	_cam_q = Basis.looking_at(dir.normalized(), up).get_rotation_quaternion()
	if instant:
		_cam_view = _cam_q


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
	var r: float = player.radius
	camera.near = clampf(zoom * 0.12 * maxf(1.0, r / 20.0), 0.3, 40.0)
	# the turn eases in (no stepping from one mouse report to the next) and the camera follows the ship with a
	# little give - bounded, so a fast ship never leaves it behind
	_cam_view = _cam_view.slerp(_cam_q, 1.0 - exp(-24.0 * delta)).normalized()
	var view := Basis(_cam_view)
	var target: Vector3 = player.position + (view.y * (r * 0.75 + 2.0) + view.z * (r * 2.4 + 7.0)) * zoom
	if not player.alive:
		target = camera.global_position
	var lag: Vector3 = (camera.global_position - target) * exp(-14.0 * delta)
	camera.global_position = target + lag.limit_length(r * 0.5 + 2.0)
	camera.global_basis = view
	# shake: smooth noise, not a fresh random jolt every frame
	_shake_t += delta
	camera.h_offset = _noise.get_noise_2d(_shake_t * 40.0, 0.0) * _shake * 1.8
	camera.v_offset = _noise.get_noise_2d(0.0, _shake_t * 40.0 + 100.0) * _shake * 1.8
	_shake = move_toward(_shake, 0.0, 2.5 * delta)
	var speed_fov: float = 6.0 if player.boosting else (20.0 if player.cruise_v > 0.0 else 0.0)
	var warp_fov := 0.0
	match travel.get("phase", ""):
		"charge": warp_fov = -4.0 * clampf(travel.t / travel.charge, 0.0, 1.0)
		"travel": warp_fov = 40.0
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
	for g in ["pirates", "crates", "asteroids", "npcs"]:
		for n in group(g):
			if not is_instance_valid(n) or not n.visible:
				continue
			var t := _ray_sphere(o, d, n.position, n.radius)
			if t > 0.0 and t < best:
				best = t
				aim_target = n
			if t > 0.0 and t < shoot and g != "npcs":
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
		cam_turn(-event.relative.x * MOUSE_SENS, -event.relative.y * MOUSE_SENS)


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
				KEY_T: _photo_toggle_time()
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
				snap_camera(false)
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
		if event.is_action_pressed("cut_throttle"):
			cancel_autopilot("Brakes")
			stop_auto("Brakes")
		if event.is_action_pressed("auto_travel"):
			toggle_auto()
			return
		if event.is_action_pressed("guide"):
			open_menu("guide")
			return
	if mode == "docked":
		# at a station the maps and menus open over it, and close back to it
		for pair in [["galaxy_map", "galaxy"], ["system_map", "system"], ["inventory", "inventory"], ["fitting", "fitting"],
				["guide", "guide"]]:
			if event.is_action_pressed(pair[0]):
				open_menu(pair[1])
				return
	if event.is_action_pressed("admin") and Game.sandbox:
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
		var port := near_port(3500.0 + (CAPITAL_DOCK if player.st.capital else 0.0))
		if near:
			near.action.call()
		elif not port.is_empty():
			select(port)
			order("use")  # near a station or gate: the autopilot flies you into its bay or mouth
	elif event.is_action_pressed("galaxy_map"):
		if galaxy_map.visible:
			close_maps()
		elif system_map.visible:
			system_map.close()
			galaxy_map.open()
		elif mode == "fly":
			open_menu("galaxy")
	elif event.is_action_pressed("system_map"):
		if system_map.visible:
			close_maps()
		elif galaxy_map.visible:
			galaxy_map.hide()
			system_map.open()
		elif mode == "fly":
			open_menu("system")
	elif event.is_action_pressed("inventory"):
		if mode == "inventory":
			close_inventory()
		elif mode == "fly":
			open_menu("inventory")
	elif event.is_action_pressed("fitting"):
		if mode == "fitting":
			close_fitting()
		elif mode == "fly":
			open_menu("fitting")
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
	var cruising: bool = player.cruise_v > 0.0 and player.vel.length() > player.top_speed() * 3.0 and autopilot.get("mode", "") != "dock"
	match phase:
		"charge":
			var k: float = clampf(travel.t / travel.charge, 0.0, 1.0)
			glow = Color(travel.color, k * 0.6)
			want = 0.3 * k * k  # the speed lines start streaming as the drive winds up
		"travel":
			want = 1.0
			glow = Color(travel.color, 0.45)
			shake(0.14)  # the whole ship shudders in the tunnel
	if cruising and phase == "":
		want = 0.5
		glow = Color(0.55, 0.8, 1.0, 0.16)
		shake(0.05)
	var tm := tunnel.material as ShaderMaterial
	var cur: float = tm.get_shader_parameter("intensity")
	var now_i := move_toward(cur, want * 0.85, delta * (3.0 if want > cur else 6.0))
	tm.set_shader_parameter("intensity", now_i)
	tunnel.visible = now_i > 0.0  # (at 0 it's all see-through: don't run it over the whole screen for nothing)
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
	# the lens fringes harder the faster you go
	var fv = vm.get_shader_parameter("fringe")
	var fr: float = fv if fv != null else 0.0016
	vm.set_shader_parameter("fringe", move_toward(fr, 0.0016 + 0.012 * want, delta * 0.02))
	dust.stretch = 1.0 if phase == "travel" else (0.9 if player.cruise_v > 0.0 else 0.0)
	dust.dir = player.forward()
	dust.zoom = zoom
	dust.size_k = maxf(1.0, player.radius / 5.0)
	dust.offset = warp_scroll
	if backdrop.get_child_count() > 0:
		# the planet is far away and barely moves, until you warp: then it's left behind fast
		backdrop.position = -(warp_scroll - _scroll_base) * 3.0 - _rush
	_update_star()


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


## Is the ship inside a station's docking bay? You can't warp or cruise from in there: fly out first.
func in_bay() -> bool:
	for lm in landmarks:
		if lm.kind == "station" and in_box(player.position, lm.bay.inner_c, lm.bay.inner_h):
			return true
	return false


## Says why a warp or cruise didn't start, if it was the docking bay (not more than every couple of seconds).
func _bay_blocks() -> bool:
	if not in_bay():
		return false
	if Time.get_ticks_msec() - _bay_warned > 2000:
		_bay_warned = Time.get_ticks_msec()
		Game.say("You can't warp inside a docking bay - fly out of it first.", UI.MUTED)
	return true


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
				# the clamps take the ship as the view fades to black; then the station opens
				_docked_bay = lm.bay
				mode = "docking"
				player.throttle = 0.0
				dock_screen.dock(lm.name, lm.action)
			else:
				_gate_bay = lm.bay
				lm.action.call()
			return
	if not inside:
		_dock_armed = true
	var big: bool = player.st.capital
	var lm := near_port(3500.0 + (CAPITAL_DOCK if big else 0.0))
	if hud.prompt == "" and not lm.is_empty() and not inside:
		var station: bool = lm.kind == "station"
		if big:
			hud.prompt = ("Too big for the bay: G to dock by tether" if station else "G: jump through the gate to %s" % lm.bay.dest) \
				if autopilot.is_empty() else autopilot_text()
		elif autopilot.get("mode", "") == "dock":
			hud.prompt = "Docking autopilot engaged" if station else "Autopilot: lining up on the gate"
		else:
			hud.prompt = "Fly into the docking bay to dock   -   G: docking autopilot" if station \
				else "Fly into the gate to jump to %s   -   G: autopilot" % lm.bay.dest


## The docking (or gate) approach goes in stages, so it never circles or wanders off:
##   "out"   - inside the station's (or gate's) keep-out sphere but not in its lane: straight away from it first;
##   "lane"  - round it to the lane point out in front of the mouth, and stop there;
##   "align" - turn to face straight in, holding still;
##   "in"    - straight in along the axis to the pad (a gate: into the bore at cruising speed).
## Picks the stage to start in from where the ship is: already in the bay or lined up in front of it, it goes on
## from there.
func _dock_stage(lm: Dictionary) -> String:
	var bay: Dictionary = lm.bay
	var p: Vector3 = player.position
	var rel: Vector3 = p - bay.mouth
	var along: float = rel.dot(bay.out)  # metres out in front of the mouth (negative: inside the bay or bore)
	var lateral: float = (rel - bay.out * along).length()
	if bay.has("inner_c") and in_box(p, bay.inner_c, bay.inner_h):
		return "in"
	if along < 0.0 and lateral < bay.bore:
		return "in"
	if along >= 0.0 and along < _lane_dist(lm) * 1.3 and lateral < 30.0 + along * 0.08:
		return "align"
	if p.distance_to(lm.pos) < bay.clear + player.radius:
		return "out"
	return "lane"


## How far out in front of the mouth the lane point is (clear of everything round the mouth).
func _lane_dist(lm: Dictionary) -> float:
	return BAY_LANE if lm.kind == "station" else 520.0


## Where the docking autopilot is heading at this stage (see _dock_stage).
func _dock_goal(lm: Dictionary) -> Vector3:
	var bay: Dictionary = lm.bay
	match autopilot.get("stage", "lane"):
		"out":
			var away: Vector3 = player.position - lm.pos
			if away.length() < 1.0:
				away = bay.out
			return lm.pos + away.normalized() * (bay.clear + player.radius + 250.0)
		"lane", "align":
			return bay.mouth + bay.out * _lane_dist(lm)
	return bay.pad if lm.kind == "station" else bay.mouth - bay.out * 200.0

# ---------------------------------------------------------------- locations

func enter_location(sys_id: int, loc_i: int, spawn = null) -> void:
	var _warp_aim := aim  # (the heading the ship had: kept when it arrives out of a warp)
	Game.refresh_relics()  # (relics decoded a week ago or more are back)
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
	if loc.get("relic", false):
		feats.append("relic")
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
	var warped_in: bool = spawn is Vector3 and spawn.length() > 0.01
	if first.get("kind", "") == "station":
		# traffic control drops you into the station's approach lane, in front of the docking bay. Out of a
		# warp you keep the heading you warped along (and glide on), rather than snapping round to the station.
		player.position = first.bay.mouth + first.bay.out * (BAY_LANE * 1.3 + _big_clear()) + Vector3(randf_range(-80, 80), randf_range(-20, 20), 0)
		var face: Vector3 = dir if warped_in else (first.bay.mouth - player.position).normalized()
		aim = Basis.looking_at(face, Vector3.UP if absf(face.y) < 0.98 else Vector3.RIGHT)
	elif first.get("kind", "") == "gate":
		# arriving by gate you come in from the system you left, off to one side of this end of the gate
		player.position += dir.cross(Vector3.UP).normalized() * (280.0 + _big_clear()) - dir * _big_clear()
		aim = Basis.looking_at(dir if warped_in else (first.pos - player.position).normalized(), Vector3.UP)
	_dock_armed = true
	if warped_in and mode != "title":
		# out of a warp the ship keeps its heading and the camera keeps its view: nothing snaps or swings round on arrival
		aim = _warp_aim
		player.basis = aim
		player.stop()
		var view := Basis(_cam_view)
		camera.global_position = player.position + (view.y * (player.radius * 0.75 + 2.0) + view.z * (player.radius * 2.4 + 7.0)) * zoom
		camera.global_basis = view
	else:
		player.basis = aim
		player.stop()
		camera.global_position = player.position + aim.y * 6.0 + aim.z * 18.0 * zoom
		snap_camera()
	_wormhole_armed = false

	if loc.pirates and not loc.station:
		_pirate_timer = 1.5
	if mode == "title":
		return
	Game.note_loc(sys_id, loc_i)
	if prev_sys != sys_id or hud._title == "":
		var sub := "%s System  -  %s" % [Game.CAT_NAMES[sys.cat], Game.REGIONS[sys.region].name]
		if sys.cat == Game.CAT_PURPLE:
			sub += "  -  DANGER: heavy pirate activity"
		hud.show_title(sys.name.to_upper(), Game.CAT_COLORS[sys.cat], sub)
		Game.event("visit", {"sys": sys_id, "new": new_sys})
		if sys.cat == Game.CAT_PURPLE and player.st.sense > 0.0:
			_sense_anomalies(sys)
		if sys_id == Game.route_target:
			if Game.next_stop():
				Game.say("Stop reached: %s. Next stop %s." % [sys.name, Game.systems[Game.route_target].name], UI.GOLD)
			else:
				Game.say("You have reached your destination.", UI.GOLD)
				stop_auto()
		Game.save_game()


## Anomaly Sense: arriving in a Wild system, it pings any hidden anomalies there.
func _sense_anomalies(sys: Dictionary) -> void:
	var n := 0
	for l in sys.locs:
		if l.kind == "anomaly" and not l.found:
			l.found = true
			n += 1
			Game.event("anomaly")
	if n > 0:
		Sfx.play("found", -4.0)
		Game.say("Anomaly Sense: %d hidden anomal%s here - check the warp menu." % [n, "y" if n == 1 else "ies"], Color("e080ff"))


## How much further out a capital ship has to sit from things to clear them (0 for anything that fits a bay).
func _big_clear() -> float:
	return player.radius * 2.5 if player.st.get("capital", false) else 0.0


func _ring_point(rng: RandomNumberGenerator, rmin: float, rmax: float, h: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := rng.randf_range(rmin, rmax)
	return Vector3(cos(a) * r, rng.randf_range(-h, h), sin(a) * r)

## This system's sky (Game.system_look: the same every visit): its nebulae and galactic band, its star's
## colour and light, and the ambient light and dust colours that go with them.
func _set_sky(sys: Dictionary, loc: Dictionary) -> void:
	_look = Game.system_look(sys)
	for k in ["c1", "c2", "c3", "neb_dir", "neb_size", "neb_dir2", "neb_size2", "band_axis", "band", "turb", "lanes", "seed"]:
		sky_mat.set_shader_parameter(k, _look[k])
	sky_mat.set_shader_parameter("nebula", _look.nebula * (1.3 if loc.kind == "anomaly" else 1.0))
	sky_mat.set_shader_parameter("star_density", _look.stars)
	var axis: Vector3 = _look.band_axis
	var yaw: float = _look.yaw
	sky_mat.set_shader_parameter("core_dir", axis.cross(Vector3(cos(yaw), 0.0, sin(yaw))).normalized())
	var sc: Color = _look.star_color
	star_mat.set_shader_parameter("star_color", sc)
	star_mat.set_shader_parameter("comp_color", _look.get("companion_color", sc))
	sun.light_color = sc.lerp(Color.WHITE, 0.4)
	var neb: Color = (_look.c1 as Color).lerp(_look.c2, 0.5)
	env.ambient_light_color = Color(0.2, 0.22, 0.27).lerp(neb, 0.3).lerp(sc, 0.15)
	env.fog_light_color = Color(0.07, 0.065, 0.06).lerp(neb * 0.25, 0.4)
	dust.set_colors(sc, _look.c3)
	var p: Vector2 = loc.map_pos
	_obs = Vector3(p.x, -_star_height(), p.y)
	_update_star()


## How far below the plane of its star's system you see it from (system-map units): it stands that high
## in your sky.
func _star_height() -> float:
	var tilt: float = _look.get("tilt", 0.2)
	return 0.08 + tilt * 0.5


## Where you are relative to the system's star, in system-map units (it sits at the centre of the system
## map; `_obs` is where you are now): partway across in a warp; in a jump, carried off into the dark, then
## sweeping in toward the new star as you arrive.
func _star_obs() -> Vector3:
	if travel.is_empty():
		return _obs
	var hd: Vector3 = travel.heading
	match travel.kind:
		"warp":
			if travel.phase == "travel" and travel.has("obs_to"):
				var s: float = smoothstep(0.0, 1.0, travel.t / travel.travel)
				return _obs.lerp(travel.obs_to, s)
		"jump", "wormhole":
			if travel.phase == "travel":
				var s: float = clampf(travel.t / travel.travel, 0.0, 1.0)
				return _obs + hd * s * s * 6.0
			if travel.phase == "exit":
				return _obs - hd * _rush.length() / 30000.0 * 2.0
	return _obs


## Put the star where it is from here (see _star_obs): its direction and size in the sky, and the light
## falling from it.
func _update_star() -> void:
	if _look.is_empty():
		return
	var o := _star_obs()
	var dist := maxf(o.length(), 0.05)
	var dir := -o / dist
	sun_dir_world = dir
	var size: float = _look.star_size
	var rad := clampf(0.011 * size / (dist + 0.12), 0.0012, 0.2)
	star_mat.set_shader_parameter("star_dir", dir)
	star_mat.set_shader_parameter("star_rad", rad)
	if _look.binary:
		# the companion circles a little way off the star, in the system's plane
		var a: float = _look.yaw * 3.0
		var c := Vector3(cos(a), 0.0, sin(a)) * (0.03 + size * 0.012) - o
		var cd := c.length()
		var csize: float = _look.companion_size
		star_mat.set_shader_parameter("comp_dir", c / cd)
		star_mat.set_shader_parameter("comp_rad", clampf(0.011 * csize / (cd + 0.12), 0.001, 0.15))
	else:
		star_mat.set_shader_parameter("comp_rad", 0.0)
	sun.global_basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	var light: float = _look.star_light
	sun.light_energy = light * clampf(sqrt(0.55 / dist), 0.85, 1.25)
	sun.light_angular_distance = clampf(rad_to_deg(rad) * 0.8, 0.15, 1.5)
	if _atmo:
		_atmo.set_shader_parameter("sun_dir", dir)


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
	_atmo = am
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
				"zone_h": BAY_ZONE_H, "loc": loc, "right": Vector3.RIGHT, "hw": 120.0, "hh": 67.5, "clear": 1000.0, "bore": 90.0,
				"inner_c": at + Vector3(0, 0, -420), "inner_h": Vector3(125, 72, 165)}  # the whole bay (no warping in here)
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
		"relic":
			# an ancient relic: a broken alien structure round a slowly turning glowing crystal
			var ruin := Models.prop("wreck")
			ruin.scale *= 3.0
			ruin.position = at
			world.add_child(ruin)
			var crystal := MeshInstance3D.new()
			crystal.mesh = Models.crystal_mesh()
			crystal.material_override = Models.bright_mat(Color("7fd8ff"), 3.0)
			crystal.scale = Vector3.ONE * 22.0
			crystal.position = at + Vector3(0, 70, 0)
			world.add_child(crystal)
			var tw := crystal.create_tween().set_loops()
			tw.tween_property(crystal, "rotation:y", TAU, 9.0).from(0.0)
			_light(at + Vector3(0, 70, 0), Color("7fd8ff"), 420.0, 3.0)
			var lm := _landmark("Ancient Relic", "relic", "star", at + Vector3(0, 40, 0), null, "[G]  Decode the ancient relic")
			lm["action"] = _decode_relic.bind(lm, Game.current_system, Game.current_loc)
			interactables.append(lm)
			_obstacle("sphere", {"c": at, "r": 110.0})


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
func _spawn_field(center: Vector3, sys: Dictionary, anomaly: bool, rng: RandomNumberGenerator, only_ore := "") -> void:
	# anomalies hold enormous fields: hundreds of veins of every ore, with mountains among them
	var count := rng.randi_range(170, 230) if anomaly else rng.randi_range(40, 60)
	var spread := 7500.0 if anomaly else 2600.0
	fields.append({"c": center, "r": spread * 1.3 + 600.0})
	var giants := rng.randi_range(5, 9) if anomaly else rng.randi_range(1, 3)
	var rocks := []  # [amount, size, giant]
	for i in count + giants:
		var giant := i >= count
		var amount := rng.randi_range(40, 100) if anomaly else rng.randi_range(15, 100)
		var size := lerpf(30.0, 110.0, (amount - 15) / 85.0) * (1.25 if anomaly else 1.0) * rng.randf_range(0.85, 1.15)
		if giant:  # a mountain of a rock with a lot of ore in it
			amount = rng.randi_range(220, 380)
			size = rng.randf_range(240.0, 420.0)
		rocks.append([amount, size, giant])
	# biggest first, so the smaller ones find room round them; a rock with nowhere clear to go is left out
	# rather than buried inside another (where it could never be mined)
	rocks.sort_custom(func(a, b): return a[1] > b[1])
	var placed := []  # [position, size]
	for r in rocks:
		var amount: int = r[0]
		var size: float = r[1]
		var giant: bool = r[2]
		var p := center
		var clear := false
		for _t in 60:
			p = center + _ring_point(rng, 0.0 if giant else 60.0, spread * (0.6 if giant else 1.0), 450.0 + size)
			if placed.all(func(q): return q[0].distance_to(p) > (q[1] + size) * 1.05 + 60.0):
				clear = true
				break
		if not clear:
			continue
		placed.append([p, size])
		var roll := Game.roll_ore(sys, anomaly) if only_ore == "" else [only_ore, rng.randi_range(1, 3)]
		var a := Asteroid.new()
		a.main = self
		a.position = p
		world.add_child(a)
		a.setup(roll[0], roll[1], amount, rng.randi(), size)
	_spawn_pebbles(center, spread, rng, 3 if not anomaly else 6)
	_spawn_clouds(center, spread, rng, 1 if not anomaly else 3)


## Hundreds of small loose rocks (not mineable) filling out the field.
func _spawn_pebbles(center: Vector3, spread: float, rng: RandomNumberGenerator, sets := 3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.11)
	mat.roughness = 0.95
	for k in sets:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.rock_mesh(k * 2 + 1 + floori(k / 3.0))
		mm.instance_count = 320
		for i in mm.instance_count:
			var s := lerpf(0.8, 28.0, pow(rng.randf(), 3.5))
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(b, center + _ring_point(rng, 0.0, spread * 1.15, 500.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		world.add_child(mmi)


## Big soft clouds of dust hanging in the field, glowing faintly in the colours of the system's nebulae.
func _spawn_clouds(center: Vector3, spread: float, rng: RandomNumberGenerator, mult := 1) -> void:
	var tints := [_look.c1, _look.c2, _look.c3]
	for i in rng.randi_range(8, 13) * mult:
		var tint: Color = tints[i % 3]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.albedo_texture = Models.soft_texture()
		m.albedo_color = Color(Color(0.36, 0.32, 0.28).lerp(tint, 0.45), rng.randf_range(0.05, 0.1))
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

func _decode_relic(lm: Dictionary, sys_id: int, loc_i: int) -> void:
	if not lm.has("action"):
		return
	interactables.erase(lm)
	lm.erase("action")
	Game.mark_relic(sys_id, loc_i)
	var txt := Game.decode_relic(Game.systems[sys_id])
	sparks(lm.pos, Color("7fd8ff"), 40)
	_flash(0.25)
	Sfx.play("found", -2.0)
	Game.toast.emit("ANCIENT RELIC", txt.replace("Decoded the relic: ", ""), "star", Color("7fd8ff"))
	Game.say(txt, Color("7fd8ff"))
	Game.note_loc(sys_id, loc_i)


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
	_photo_running = false  # (photo mode starts frozen; T runs time again)
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
	return "PHOTO MODE  (time %s)    mouse look    WASD move    E / Q up and down    SHIFT fast    ALT slow    wheel zoom    T %s time    P save picture    H hide this    F1 back" % [
		"running" if _photo_running else "paused", "pause" if _photo_running else "resume"]


## T: let the action run again while you stay in photo mode (and T again to freeze it). Your ship's controls stay
## off, so the free camera is the only thing you steer.
func _photo_toggle_time() -> void:
	_photo_running = not _photo_running
	Engine.time_scale = 1.0 if _photo_running else 0.0
	player.control = false
	player.turn_input = Vector3.ZERO
	Sfx.play("click", -8.0)
	_photo_hint.text = _photo_help()
	_photo_hint_t = 4.0


## While time runs in photo mode: the parts of the normal frame that keep the world going (a warp in progress,
## the autopilot, the warp visuals), but none of the ship's own controls.
func _photo_world(delta: float) -> void:
	player.control = false
	player.turn_input = Vector3.ZERO
	_update_screen_fx(delta)
	if not travel.is_empty():
		_update_travel(delta)
	elif not autopilot.is_empty() and mode == "fly":
		_update_autopilot(delta)


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
			"spice": "Browse", "relic": "Decode"}
		var sub := {"station": "Station  -  dock to refine, trade, build and repair", "gate": "Stargate  -  jump to another system",
			"ore": "Asteroid field  -  huge ore veins to mine", "obelisk": "Offering Obelisk  -  make an offering for a blessing",
			"spice": "Spice Stand  -  a trader in the middle of nowhere", "wormhole": "Wormhole  -  leads deep into Wild space",
			"wreck": "Derelict  -  salvage it for parts" if t.has("action") else "Derelict  -  already salvaged",
			"relic": "Ancient relic  -  decode it for whatever it remembers" if t.has("action") else "Ancient relic  -  decoded"}
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


## Everything worth listing on the overview: landmarks, ships, containers, ore veins and loose ore. `cat` narrows
## it to one kind (all, places, ships, veins, loose, loot), `minq` hides ore below that quality and `ore` keeps
## only that ore (veins you haven't scanned are unknown, so they only show unfiltered). `sort`: dist, name, ore
## (rarest first), quality or size. Rows: {t, name, icon, color, dist, ore, q, size}.
func overview_rows(cat := "all", minq := -1, ore := "", sort := "dist", reverse := false) -> Array:
	var pp: Vector3 = player.position
	var all := []
	if cat in ["all", "places", "loot"] and ore == "" and minq < 0:
		for lm in landmarks:
			if cat != "loot" or lm.kind in ["wreck", "relic"]:
				all.append(lm)
	var groups: Array = {"all": ["pirates", "npcs", "crates", "asteroids", "chunks"], "places": [], "ships": ["pirates", "npcs"],
		"veins": ["asteroids"], "loose": ["chunks"], "ore": ["asteroids", "chunks"], "loot": ["crates"]}.get(cat, [])
	var reach: float = 15000.0 + player.radius * 4.0
	for group in groups:
		var is_ore: bool = group in ["asteroids", "chunks"]
		if (ore != "" or minq >= 0) and not is_ore:
			continue
		for n in group_nodes(group):
			if not n.visible or (is_ore and n.position.distance_to(pp) > reach):
				continue
			if group == "asteroids" and (ore != "" or minq >= 0) and not n.scanned:
				continue
			if is_ore and ((minq >= 0 and n.quality < minq) or (ore != "" and n.ore_id != ore)):
				continue
			all.append(n)
	var out := []
	for t in all:
		var info := target_info(t)
		var row := {"t": t, "name": info.name, "icon": info.icon, "color": info.color, "dist": pp.distance_to(target_pos(t)),
			"ore": "", "q": -1, "size": target_size(t)}
		if not t is Dictionary and (t.is_in_group("chunks") or (t.is_in_group("asteroids") and t.scanned)):
			row.ore = t.ore_id
			row.q = t.quality
			row.size = t.amount if t.is_in_group("chunks") else t.remaining
		out.append(row)
	match sort:
		"name": out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
		"ore": out.sort_custom(func(a, b): return _ore_rank(a) > _ore_rank(b) or (_ore_rank(a) == _ore_rank(b) and a.dist < b.dist))
		"quality": out.sort_custom(func(a, b): return a.q > b.q or (a.q == b.q and a.dist < b.dist))
		"size": out.sort_custom(func(a, b): return a.size > b.size or (a.size == b.size and a.dist < b.dist))
		_: out.sort_custom(func(a, b): return a.dist < b.dist)
	if reverse:
		out.reverse()
	return out


## Rarer ore first (then better quality); things without ore last.
func _ore_rank(row: Dictionary) -> float:
	if row.ore == "":
		return -1.0
	return Game.ORES[row.ore].tier * 10.0 + float(Game.ORES[row.ore].has("region")) * 5.0 + row.q


## The nodes in a group (all of them, this frame).
func group_nodes(g: String) -> Array:
	return get_tree().get_nodes_in_group(g)


## Everything worth listing here, nearest first (the first `limit`): see overview_rows.
func overview_entries(limit: int, cat := "all", minq := -1) -> Array:
	return overview_rows(cat, minq).slice(0, limit)

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
			return d > LOCAL_WARP_MIN and not in_bay()
		"cruise":
			return d > CRUISE_MIN + target_size(selected) and not in_bay()
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
	var r: float = player.radius
	match what:
		"approach":
			_start_autopilot("approach", t, size + r + (60.0 if t is Dictionary else 25.0))
		"orbit":
			_start_autopilot("orbit", t, size + r + (250.0 if t is Dictionary else 60.0))
		"cruise":
			if _bay_blocks():
				return
			_start_autopilot("cruise", t, size + r + (250.0 if t is Dictionary else 80.0))
		"use":
			if not (t is Dictionary and t.has("action")):
				return
			if t.has("bay"):
				if player.st.capital:
					# too big for a bay or a gate's bore: tether to the station, or jump from near the gate
					var reach: float = CAPITAL_DOCK + r
					if d <= reach:
						_use_port(t)
					else:
						_start_autopilot("use", t, reach * 0.8)
					return
				_start_autopilot("dock", t, 0.0)  # fly into the docking bay / the gate's mouth
				return
			if d <= t.radius + r:
				t.action.call()
			else:
				_start_autopilot("use", t, t.radius * 0.8 + r)
		"warp":
			if _bay_blocks():
				return
			if d <= LOCAL_WARP_MIN:
				Game.say("Too close to warp - approaching instead.", UI.MUTED)
				_start_autopilot("approach", t, size + r + 60.0)
				return
			warp_local(t)


## A capital ship docks by tether (the view fades as the station takes it), or jumps straight from near a gate.
func _use_port(lm: Dictionary) -> void:
	cancel_autopilot()
	if lm.kind == "station":
		_docked_bay = lm.bay
		mode = "docking"
		player.throttle = 0.0
		player.cruise_v = 0.0
		dock_screen.dock(lm.name, lm.action)
	else:
		lm.action.call()


func _start_autopilot(what: String, t, range_m: float) -> void:
	var to: Vector3 = target_pos(t) - player.position
	var axis := to.cross(player.forward())
	if axis.length() < 0.01:
		axis = Vector3.UP
	autopilot = {"mode": what, "target": t, "range": range_m, "axis": axis.normalized(), "t": 0.0}
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
	if autopilot.mode == "launch":
		return "Launching"
	var pw := "" if ap_power >= 0.999 else "   (power %d%%)" % roundi(ap_power * 100.0)
	if autopilot.mode == "collect":
		return "Collecting loose ore  -  %d pieces in reach%s" % [get_tree().get_nodes_in_group("chunks").filter(
			func(c): return c.position.distance_to(player.position) < COLLECT_RANGE).size(), pw]
	var d: float = player.position.distance_to(target_pos(autopilot.target))
	var left := UI.dist(maxf(0.0, d - autopilot.range))
	var drive := ""
	if autopilot.get("engaged", false):
		drive = "Cruising  -  "
	elif autopilot.get("spool", 0.0) > 0.0:
		drive = "Cruise drive spooling...  -  "
	match autopilot.mode:
		"orbit": return "Orbiting at %s%s" % [UI.dist(autopilot.range), pw]
		"dock":
			var goal := _dock_goal(autopilot.target)
			var what: String = {"out": "backing away to go round", "lane": "to the approach lane", "align": "lining up",
				"in": "going in"}.get(autopilot.get("stage", "lane"), "")
			return "%s%s  -  %s  -  %s%s" % [drive, "Docking" if autopilot.target.kind == "station" else "Gate", what,
				UI.dist(player.position.distance_to(goal)), pw]
		"use": return "%sApproaching to %s  -  %s to go%s" % [drive, target_info(autopilot.target).use.to_lower(), left, pw]
	return "%sApproaching  -  %s to go%s" % [drive, left, pw]


## O: the autopilot flies you from one loose chunk of ore to the next, nearest first, collecting them,
## until there are none left in reach or the hold is full. O again (or taking the controls) stops it.
func toggle_collect() -> void:
	if autopilot.get("mode", "") == "collect":
		cancel_autopilot("Collecting stopped")
		return
	if _nearest_chunk() == null:
		if _nearest_chunk(false) != null:
			cargo_full()
		else:
			Game.say("No loose ore within %s." % UI.dist(COLLECT_RANGE), UI.MUTED)
		return
	autopilot = {"mode": "collect", "t": 0.0}
	Sfx.play("click", -8.0)
	Game.say("Collecting loose ore - O or any flight key to stop.", Color("8cd8ff"))


## The nearest loose chunk O would go for: not jettisoned and (`fits`) with room for it in the hold.
func _nearest_chunk(fits := true):
	var best = null
	var bd := COLLECT_RANGE
	for c in get_tree().get_nodes_in_group("chunks"):
		if c.is_queued_for_deletion() or c.pick_cd > 0.0 or c.jettisoned or (fits and not c.fits(player)):
			continue
		var d: float = player.position.distance_to(c.position)
		if d < bd:
			bd = d
			best = c
	return best


## Steers (by swinging the aim, which the ship follows) and works the throttle and cruise drive.
func _update_autopilot(delta: float) -> void:
	if autopilot.mode == "launch":
		var bay: Dictionary = station_lm().get("bay", {})
		autopilot.t += delta
		player.throttle = 0.0
		player.cruise_v = player.top_speed() * CRUISE_MULT * clampf(autopilot.t / 0.35, 0.15, 1.0)
		_steer_to(autopilot.out, delta)
		if bay.is_empty() or (player.position - bay.mouth).dot(bay.out) > 150.0 + player.radius or autopilot.t > 6.0:
			autopilot = {}
			player.cruise_v = 0.0  # (out of cruise the extra speed bleeds off over a couple of seconds)
		return
	if autopilot.mode == "collect":
		if Game.cargo_used() >= player.st.cargo:
			cancel_autopilot("Cargo hold full")
			return
		var c = _nearest_chunk()
		if c == null:
			if _nearest_chunk(false) != null:
				cancel_autopilot("Cargo hold full")  # (what's left won't fit: it stays where it is)
				return
			autopilot = {}
			player.cruise_v = 0.0
			Game.say("All the loose ore in reach is collected.", UI.GOOD)
			return
		# near enough and the tractor beam does the rest
		_drive(c.position, minf(player.tractor_range() * 0.4, 400.0), delta, true, true)
		return
	var t = autopilot.target
	if not target_valid(t):
		autopilot = {}
		player.cruise_v = 0.0
		return
	var top: float = player.top_speed()
	match autopilot.mode:
		"approach", "use", "cruise":
			if _drive(target_pos(t), autopilot.range, delta) <= 0.0:
				player.throttle = 0.0
				player.cruise_v = 0.0
				if mode != "fly":
					return  # arrived while a menu's open: wait there, the arrival happens once it closes
				var arrived = autopilot
				autopilot = {}
				if arrived.mode == "use" and t is Dictionary and t.has("action"):
					if t.has("bay"):
						_use_port(t)
					else:
						t.action.call()
		"dock":
			_update_dock(t, delta)
		"orbit":
			var to: Vector3 = target_pos(t) - player.position
			var d := to.length()
			var radial := -to / maxf(d, 0.01)
			var tangent: Vector3 = (autopilot.axis as Vector3).cross(radial).normalized()
			var dir := (tangent + radial * clampf((autopilot.range - d) / autopilot.range * 3.0, -1.5, 1.5)).normalized()
			player.throttle = 0.8 * ap_power
			player.cruise_v = 0.0
			_steer_to(dir, delta)


## Docking (or flying into a gate) by stages: see _dock_stage.
func _update_dock(lm: Dictionary, delta: float) -> void:
	var bay: Dictionary = lm.bay
	var top: float = player.top_speed()
	if not autopilot.has("stage"):
		autopilot["stage"] = _dock_stage(lm)
	var p: Vector3 = player.position
	var rel: Vector3 = p - bay.mouth
	var along: float = rel.dot(bay.out)
	var lateral: float = (rel - bay.out * along).length()
	var into: Vector3 = -bay.out
	match autopilot.stage:
		"out":
			var goal := _dock_goal(lm)
			player.cruise_v = 0.0
			if _drive(goal, 0.0, delta, false, true) < 60.0 or p.distance_to(lm.pos) > bay.clear + player.radius + 150.0:
				autopilot.stage = "lane"
		"lane":
			var goal := _dock_goal(lm)
			var left := _drive(goal, 0.0, delta)
			if left < maxf(40.0, top * 1.2):
				autopilot.stage = "align"
				autopilot["engaged"] = false
				player.cruise_v = 0.0
		"align":
			# hold still, nose round to face straight in; drift back onto the lane point if pushed off it
			player.cruise_v = 0.0
			var hold: Vector3 = _dock_goal(lm) - p
			player.throttle = 0.0
			player.vel = player.vel.move_toward(hold.limit_length(top * 0.5), top * 0.8 * delta)
			_steer_to(into, delta * 1.5)
			if player.forward().dot(into) > 0.996 and player.vel.length() < top * 0.6:
				autopilot.stage = "in"
		"in":
			# straight down the axis: aim at a point on it a little ahead, so any sideways error closes smoothly
			var station: bool = lm.kind == "station"
			var goal := _dock_goal(lm)
			var end_along: float = (goal - bay.mouth).dot(bay.out)
			var ahead: float = maxf(end_along, along - 120.0 - player.radius) if station else along - 150.0
			var aim_pt: Vector3 = bay.mouth + bay.out * ahead
			var to: Vector3 = aim_pt - p
			var d := p.distance_to(goal)
			player.throttle = 0.0
			player.cruise_v = clampf(d * (0.7 if station else 1.0), top * (0.6 if station else 2.0),
				top * (4.0 if station else CRUISE_MULT) * ap_power)
			if player.forward().dot(to.normalized()) < 0.9:
				player.cruise_v = maxf(top * 0.4, player.cruise_v * 0.4)  # get the nose on it first
			_steer_to(to.normalized(), delta)
			if lateral > 220.0 or along > _lane_dist(lm) * 2.0:
				autopilot.stage = _dock_stage(lm)  # knocked well off the line: start the approach again


## The autopilot's one way of getting somewhere. It turns onto the line, opening the throttle as the nose
## comes round; on a long run it spools the cruise drive once lined up and races there at many times top
## speed - round stations and gates, threading between the rocks, slowing for anything dead ahead - and
## eases off to stop `stop` metres short (or, with `through`, arrives still moving). R/F scale how hard it
## pushes. Returns how far there is left to go.
func _drive(goal: Vector3, stop: float, delta: float, cruise := true, through := false) -> float:
	var p: Vector3 = player.position
	var to := goal - p
	var d := to.length()
	var left := d - stop
	var top: float = player.top_speed()
	var fast: float = top * CRUISE_MULT * ap_power
	var dir := _detour(p, goal, to / maxf(d, 0.01))
	var speed: float = player.vel.length()
	dir = _avoid(dir, maxf(speed, 60.0))
	var aligned: float = player.forward().dot(dir)
	var cruising: bool = autopilot.get("engaged", false)
	if cruising:
		var clear := _clear_ahead(dir, maxf(speed * 2.0, 400.0))
		player.throttle = 0.0
		player.cruise_v = clampf(minf(left * 0.9 + (top * 3.0 if through else 0.0), clear * 0.7), top, fast)
		if aligned < 0.6:
			player.cruise_v = maxf(top, player.cruise_v * 0.5)  # a hard turn: ease off through it
		if left < top * 1.5 or left <= 0.0:
			autopilot["engaged"] = false
			player.cruise_v = 0.0
	elif cruise and left > CRUISE_MIN and not in_bay():
		# spool the cruise drive while lined up, creeping forward
		player.cruise_v = 0.0
		player.throttle = clampf((aligned - 0.3) / 0.6, 0.15, 1.0) * ap_power
		if aligned > 0.92:
			if autopilot.get("spool", 0.0) <= 0.0:
				Sfx.play("charge", -8.0, 2.2 / CRUISE_SPOOL)
			autopilot["spool"] = autopilot.get("spool", 0.0) + delta
			shake(minf(autopilot.spool / CRUISE_SPOOL, 1.0) * 0.15)
			if autopilot.spool >= CRUISE_SPOOL:
				autopilot["engaged"] = true
				autopilot["spool"] = 0.0
				_flash(0.15)
				_fov_kick = 16.0
				shake(0.35)
				Sfx.play("warp", -5.0, 1.5)
				player.cruise_v = maxf(speed, top * 3.0)
		else:
			autopilot["spool"] = 0.0
	else:
		player.cruise_v = 0.0
		var want := 1.0 if through else clampf(left / (top * 1.8), 0.12, 1.0)
		player.throttle = want * clampf((aligned - 0.2) / 0.6, 0.15, 1.0) * ap_power
	_steer_to(dir, delta)
	return left


## Swing the aim (which the ship turns to follow, at its own pace) toward `dir`.
func _steer_to(dir: Vector3, delta: float) -> void:
	var up := aim.y if absf(dir.dot(aim.y)) < 0.95 else Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var want := Basis.looking_at(dir, up).get_rotation_quaternion()
	aim = Basis(aim.get_rotation_quaternion().slerp(want, minf(1.0, 8.0 * delta))).orthonormalized()


## Round the stations and gates rather than through them: if the line to `goal` passes too close to one,
## head for a point out to the side of it instead.
func _detour(p: Vector3, goal: Vector3, dir: Vector3) -> Vector3:
	var seg := goal - p
	var l2 := maxf(seg.length_squared(), 1.0)
	for lm in landmarks:
		if not lm.has("bay"):
			continue
		var c: Vector3 = lm.pos
		var clear: float = lm.bay.clear + player.radius
		if p.distance_to(c) < clear or goal.distance_to(c) < clear:
			continue  # already close (docking) or going there: the docking approach handles it
		var k := clampf((c - p).dot(seg) / l2, 0.0, 1.0)
		var closest := p + seg * k
		if closest.distance_to(c) >= clear:
			continue
		var side := closest - c
		if side.length() < 1.0:
			side = seg.cross(Vector3.UP)
			if side.length() < 1.0:
				side = Vector3.RIGHT
		var way := c + side.normalized() * (clear + 250.0)
		return (way - p).normalized()
	return dir


## How far ahead along `dir` the way is clear of rocks and ships (INF if it is, as far as `look`): the cruise
## drive slows for anything it can't steer round in time.
func _clear_ahead(dir: Vector3, look: float) -> float:
	var p: Vector3 = player.position
	var best := INF
	for g in ["asteroids", "npcs"]:
		for a in group(g):
			var rel: Vector3 = a.position - p
			var along := rel.dot(dir)
			if along < 0.0 or along > look + a.radius:
				continue
			var miss := (rel - dir * along).length()
			if miss < a.radius + player.radius + 10.0:
				best = minf(best, along - a.radius)
	return maxf(best, 0.0)


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


# ---------------------------------------------------------------- auto-travel, jump drive, portable wormholes

## T: fly the plotted route on its own - warp to each gate, fly in, jump, on to the next (straight there by
## jump drive, if the ship has one). Asks once, up front, if the route goes through Wild space.
func toggle_auto() -> void:
	if auto_travel:
		stop_auto("Auto-travel off")
		return
	if Game.route_target < 0 or Game.route_target == Game.current_system:
		Game.say("Plot a route on the galaxy map (M) first, then press T.", UI.MUTED)
		return
	var wild := 0
	var at := Game.current_system
	for stop_id in [Game.route_target] + Game.route_stops:
		for id in Game.find_path(at, stop_id):
			if Game.systems[id].cat == Game.CAT_PURPLE:
				wild += 1
		at = stop_id
	if wild > 0:
		ask_wild("Your route goes through %d Wild system%s: pirates everywhere, and you lose your cargo if you're destroyed.\n\nAuto-travel the whole way?" % [
			wild, "" if wild == 1 else "s"], "Go", _start_auto)
	else:
		_start_auto()


func _start_auto() -> void:
	auto_travel = true
	Sfx.play("charge", -8.0, 1.6)
	Game.say("Auto-travel: %d jumps to %s. T, X or any flight key stops it." % [Game.route_jumps(), Game.systems[Game.route_target].name],
		Color("8cd8ff"))


func stop_auto(why := "") -> void:
	if not auto_travel:
		return
	auto_travel = false
	if why != "":
		Game.say(why + ".", UI.MUTED)


## One step of auto-travel, whenever the ship is free: pick the next warp, gate or jump.
func _update_auto(_delta: float) -> void:
	if Game.route_target < 0 or Game.route_target == Game.current_system:
		stop_auto()
		return
	if in_bay():
		# out of the docking bay first
		var st_lm := station_lm()
		player.throttle = 1.0
		_steer_to(st_lm.bay.out if not st_lm.is_empty() else player.forward(), get_process_delta_time())
		return
	if player.st.jump > 0.0:
		var hop := _jump_hop(Game.route_target)
		if hop >= 0:
			if _jump_cd <= 0.0:
				jump_drive(hop)
			return
	var path := Game.route_path()
	if path.is_empty():
		stop_auto("No route from here")
		return
	var next: int = path[0]
	var loc := current_loc()
	if loc.kind == "gate" and loc.gate_to == next:
		for lm in landmarks:
			if lm.kind == "gate":
				select(lm)
				order("use")
				return
	start_warp(Game.gate_index(Game.current_system, next))


## The best jump drive hop toward `target`: straight there if it's in reach, else the system in reach that
## gets closest to it (-1 if none gets any closer).
func _jump_hop(target: int) -> int:
	var here: Vector2 = current_sys().pos
	var goal: Vector2 = Game.systems[target].pos
	var reach: float = player.st.jump
	if here.distance_to(goal) <= reach:
		return target
	var best := -1
	var bd := here.distance_to(goal) - 1.0
	for s in Game.systems:
		if s.id != Game.current_system and here.distance_to(s.pos) <= reach and s.pos.distance_to(goal) < bd:
			bd = s.pos.distance_to(goal)
			best = s.id
	return best


## Can the jump drive reach system `id` from here?
func can_jump_drive(id: int) -> bool:
	return player.st.jump > 0.0 and id != Game.current_system and \
		current_sys().pos.distance_to(Game.systems[id].pos) <= player.st.jump


## Capital ships: straight to another system, no stargates. A long wind-up, then the jump; a while to recharge.
func jump_drive(id: int) -> void:
	close_maps()
	if mode != "fly" or _bay_blocks() or not can_jump_drive(id):
		return
	if _jump_cd > 0.0:
		Game.say("Jump drive recharging (%ds)." % ceili(_jump_cd), UI.MUTED)
		return
	var sys: Dictionary = Game.systems[id]
	if sys.cat == Game.CAT_PURPLE and not auto_travel and not Game.sandbox:
		ask_wild("%s is a WILD system: pirates everywhere, and you lose your cargo if you're destroyed.\n\nJump anyway?" % sys.name, "Jump",
			_jump_drive_go.bind(id))
	else:
		_jump_drive_go(id)


func _jump_drive_go(id: int) -> void:
	var sys: Dictionary = Game.systems[id]
	var heading: Vector2 = sys.pos - current_sys().pos
	_jump_cd = JUMP_DRIVE_COOLDOWN
	Game.bump("jumpdrives")
	Game.say("Jump drive spooling: %s." % sys.name, Color("c080ff"))
	_travel_to("jumpdrive", sys.name, JUMP_DRIVE_CHARGE, JUMP_BASE + heading.length() * JUMP_PER_PX * 0.6,
		enter_location.bind(id, _arrival_loc(id), _arrival_spot(heading)), Game.CAT_COLORS[sys.cat], heading)


## Open a portable wormhole: straight to any system at all. Used up.
func open_portal(id: int) -> void:
	close_maps()
	if mode != "fly" or Game.portals <= 0 or id == Game.current_system or _bay_blocks():
		return
	Game.portals -= 1
	Game.bump("portals")
	Game.changed.emit()
	var sys: Dictionary = Game.systems[id]
	var heading: Vector2 = sys.pos - current_sys().pos
	Game.say("The portable wormhole tears open toward %s..." % sys.name, Color("e080ff"))
	_travel_to("wormhole", sys.name, JUMP_CHARGE, WORMHOLE_TIME, enter_location.bind(id, _arrival_loc(id), _arrival_spot(heading)),
		Color("d050ff"), heading)


## Where you come out arriving in a system any way but its gates: at its station if it has one, else its first
## planet.
func _arrival_loc(id: int) -> int:
	var sys: Dictionary = Game.systems[id]
	var first := -1
	for i in sys.locs.size():
		if sys.locs[i].kind == "planet":
			if sys.locs[i].station:
				return i
			if first < 0:
				first = i
	return maxi(first, 0)


## Jettisoned cargo tumbles out of the back of the ship as loose chunks (which can't be picked up for a moment).
func _on_jettison(ore: String, q: int, n: int) -> void:
	if not mode in ["fly", "warp", "inventory", "fitting", "map"]:
		return
	var back: Vector3 = -player.forward()
	var per := maxi(10, ceili(n / 40.0))
	var left := n
	while left > 0:
		var a := mini(left, per)
		left -= a
		var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		var c = spawn_chunk(ore, q, a, player.position + back * (player.radius + 4.0) + off * player.radius * 0.3,
			player.vel + back * randf_range(8.0, 18.0) + off * 4.0)
		c.pick_cd = 3.0
		c.jettisoned = true

## Sandbox: straight to any system through a short jump, arriving at its station or first planet.
func admin_jump(id: int) -> void:
	close_maps()
	if mode != "fly" or id == Game.current_system:
		return
	var sys: Dictionary = Game.systems[id]
	var heading: Vector2 = sys.pos - current_sys().pos
	_travel_to("jump", sys.name, 1.0, 2.0, enter_location.bind(id, _arrival_loc(id), _arrival_spot(heading)), Game.CAT_COLORS[sys.cat],
		heading)


## Sandbox: pirates here and now - a wave of the usual mix, or `count` of one type.
func call_pirates(type := "", count := 1) -> void:
	if mode != "fly":
		return
	if type == "":
		_spawn_pirates()
		return
	var base := randf() * TAU
	for i in count:
		var p := Pirate.new()
		p.main = self
		var a := base + randf_range(-0.8, 0.8)
		var r: float = randf_range(160.0, 220.0) + player.radius
		p.position = player.position + Vector3(cos(a) * r, randf_range(-30.0, 30.0), sin(a) * r)
		world.add_child(p)
		p.setup(type, current_sys().cat)


## Sandbox: a fresh ore field right ahead of the ship (`ore` "" for the usual mix here).
func spawn_field_here(ore := "") -> void:
	if mode != "fly":
		return
	var at: Vector3 = player.position + player.forward() * 3500.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_spawn_field(at, current_sys(), false, rng, ore)
	_landmark("Sandbox Field", "ore", "ore", at)


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
		dest = t.bay.mouth + t.bay.out * (BAY_LANE + _big_clear())
		to = dest - player.position
		d = to.length()
	cancel_autopilot()
	_travel_to("local", target_info(t).name, 1.0, 0.4 + d / LOCAL_WARP_SPEED, Callable(), Color(0.55, 0.8, 1.0), Vector2(to.x, to.z),
		{"heading3": to.normalized(), "from": player.position, "to": dest})


## V: a survey pulse that reveals what's in every asteroid within range (each one glints as it reaches it).
func survey_scan() -> void:
	if _scan_cd > 0.0:
		Game.say("Survey scanner recharging (%ds)." % ceili(_scan_cd), UI.MUTED)
		return
	var k: float = player.st.scan
	var reach: float = SCAN_RANGE * k + player.radius
	_scan_cd = SCAN_COOLDOWN / k
	Sfx.play("charge", -6.0, 1.8)
	var n := 0
	var ore := 0
	var kinds := []
	for a in get_tree().get_nodes_in_group("asteroids"):
		var d: float = a.position.distance_to(player.position)
		if d < reach:
			a.scanned = true
			a.ping(d / reach * 1.5)  # the pulse reaches the far rocks last
			n += 1
			ore += a.remaining
			if not kinds.has(a.ore_id):
				kinds.append(a.ore_id)
	if n == 0:
		Game.say("Survey scan: no asteroids within %s." % UI.dist(reach), UI.MUTED)
	else:
		Game.note_loc(Game.current_system, Game.current_loc, kinds)  # the notebook remembers what's here
		Game.say("Survey scan: %d asteroids, %d ore in reach (%s). Check the overview." % [n, ore,
			", ".join(kinds.map(func(o): return Game.ORES[o].name))], Color("8cd8ff"))

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


## `k`: how big the gun is (Ship.gun_scale): the bolt is drawn to match it.
func spawn_bullet(pos: Vector3, dir: Vector3, s: Dictionary, friendly: bool, k := 1.0) -> void:
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
	b.beam_width = s.size.x * 0.4 * k
	b.beam_len = s.size.y * (3.0 if friendly else 1.8) * k  # player bolts are fast: longer beams
	b.add_child(Models.glow_quad(Color(Color(s.color).lerp(Color.WHITE, 0.3), 0.5), s.size.x * 0.35 * k))  # a tight hot spot at the head
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


func spawn_chunk(ore: String, q: int, amount: int, pos: Vector3, vel: Vector3) -> Node3D:
	var c := OreChunk.new()
	c.main = self
	c.ore_id = ore
	c.quality = q
	c.amount = amount
	c.position = pos
	c.vel = vel
	world.add_child(c)
	return c


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
	return mode in ["docked", "docking", "launching"] or (mode == "warp" and not travel.get("phase", "") in ["align", "charge"])


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
			shake(k * 0.35)
			if travel.has("gate"):
				# the railgun: accelerate hard down the barrel, held to its centre line, to leave the muzzle
				# just as the charge completes; the coils flare as the ship passes through them
				var g: Dictionary = travel.gate
				var into: Vector3 = -g.out
				if not travel.has("rail_a"):
					# keep the speed you came in with (the autopilot flies in at cruising speed) and add to it, so
					# the ship leaves the muzzle just as the charge completes
					var left: float = maxf(GateField.MOUTH + GateField.MUZZLE + 20.0 - (player.position - g.mouth).dot(into), 60.0)
					var v0: float = maxf(0.0, player.vel.dot(into))
					if v0 * travel.charge > left * 0.8:
						travel.charge = maxf(0.4, left * 0.8 / maxf(v0, 1.0))  # coming in fast: a shorter, harder shot
					travel.rail_v0 = v0
					travel.rail_a = maxf(0.0, 2.0 * (left - v0 * travel.charge) / (travel.charge * travel.charge))
					g.gate.launch(travel.charge)
				player.vel = into * (travel.rail_v0 + travel.rail_a * travel.t) - _off_axis(g) * 4.0
				_scroll_speed = WARP_SCROLL_MAX * 0.4 * k * k
			else:
				# the charge is the acceleration: the drive drags the ship forward harder and harder and the world
				# starts to slide past - then, charged, it's at full warp at once (see "travel")
				player.vel = fwd * player.top_speed() * CHARGE_SPEED * k * k
				_scroll_speed = WARP_SCROLL_MAX * 0.4 * k * k
			if travel.t >= travel.charge:
				travel.phase = "travel"
				travel.t = 0.0
				if travel.kind == "local":
					travel.from = player.position  # it rolled forward while charging
				else:
					_rush = Vector3.ZERO
					_rush_v = WARP_RUSH  # no build-up: the drive has charged, and you're gone
				_scroll_speed = WARP_SCROLL_MAX
				_flash(0.55)
				Sfx.play("warp", -1.0)
				var f := _fx(player.position)
				# punch forward: a jet of light blasts out behind the ship
				f.jet(70, Color(travel.color).lightened(0.4), -fwd, 160.0, 14.0, 0.8)
				f.jet(30, Color.WHITE, -fwd, 220.0, 6.0, 0.5)
				_fov_kick = 18.0
		"travel":
			if travel.kind == "local":
				# across this location at one steady, enormous speed, the world streaking past (and the planet
				# swinging by)
				var s := clampf(travel.t / travel.travel, 0.0, 1.0)
				var before: Vector3 = player.position
				player.position = (travel.from as Vector3).lerp(travel.to, s)
				player.vel = (player.position - before) / maxf(delta, 0.001) * 0.02
				warp_scroll += player.position - before
			else:
				# everything here - stations, rocks, the planet - streams away behind you faster and faster
				# until it's gone
				player.vel = Vector3.ZERO
				_scroll_speed = WARP_SCROLL_MAX
				_rush += travel.heading * _rush_v * delta
				world.position = -_rush
				world.visible = _rush.length() < 60000.0
			if travel.t >= travel.travel:
				if _jump_to_system(travel) >= 0:
					# a jump to another system: the map swoops over to it before you arrive
					travel.phase = "chart"
					travel.t = 0.0
					jump_map.play(Game.current_system, _jump_to_system(travel))
				else:
					_arrive(travel)
		"chart":
			# still streaming away under the map; the new system loads behind it at the end
			player.vel = Vector3.ZERO
			_rush += travel.heading * _rush_v * delta
			world.position = -_rush
			world.visible = _rush.length() < 60000.0
			if travel.t >= JumpMap.DURATION:
				_arrive(travel)
				jump_map.finish()
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


## The system a finished warp lands in, if that isn't the one you're in (a jump), else -1.
func _jump_to_system(trip: Dictionary) -> int:
	if trip.kind == "local" or not trip.arrive.is_valid():
		return -1
	var args: Array = (trip.arrive as Callable).get_bound_arguments()
	if args.is_empty() or int(args[0]) == Game.current_system:
		return -1
	return int(args[0])


## The warp is over: arrive (the new place rushes in from far ahead and settles round you) and drop out of warp
## still moving, light spraying out ahead. The camera is left exactly as it was: no snap, kick or shake.
func _arrive(trip: Dictionary) -> void:
	trip.phase = "exit"
	trip.t = 0.0
	if trip.kind != "local":
		trip.arrive.call()
		_rush = -trip.heading * 30000.0
		world.position = -_rush
	world.visible = true
	_flash(0.4)
	Sfx.play("arrive", -2.0)
	var fwd: Vector3 = player.forward()
	var f := _fx(player.position)
	f.jet(50, Color(trip.color).lightened(0.5), fwd, 200.0, 20.0, 0.8)
	f.jet(25, Color.WHITE, fwd, 260.0, 8.0, 0.5)
	player.vel = fwd * player.top_speed() * 1.6


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
	if mode != "fly" or _bay_blocks():
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
	# (the system map's x and y are the world's x and z, so the star swings round as you cross the system)
	_travel_to("warp", sys.locs[loc_i].name, WARP_CHARGE, WARP_BASE + from.distance_to(to) * WARP_PER_UNIT,
		enter_location.bind(Game.current_system, loc_i, _arrival_spot(to - from)), Game.CAT_COLORS[sys.cat], to - from,
		{"obs_to": Vector3(to.x, -_star_height(), to.y)})


func try_gate(dest: int) -> void:
	var d: Dictionary = Game.systems[dest]
	if d.cat == Game.CAT_PURPLE and not auto_travel and not Game.sandbox:  # (auto-travel asked once, up front)
		ask_wild("!!  WARNING  !!\n\n%s is a WILD system.\nPirates hold roughly 60%% of its planets, and you lose your cargo if you're destroyed.\nAnomalies hide in Wild space, though...\n\nJump anyway?" % d.name,
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
	ask_wild("The wormhole churns violently. It leads somewhere very far away, deep in WILD space, where pirates rule.\n\nGo through?",
		"Enter", _wormhole_jump.bind(other.sys, other.loc))


func _wormhole_jump(sys_id: int, loc_i: int) -> void:
	Game.say("The wormhole spat you out in %s!" % Game.systems[sys_id].name, Color("e080ff"))
	Game.event("wormhole")
	var heading: Vector2 = Game.systems[sys_id].pos - current_sys().pos
	_travel_to("wormhole", Game.systems[sys_id].name, JUMP_CHARGE, WORMHOLE_TIME,
		enter_location.bind(sys_id, loc_i, _arrival_spot(heading)), Color("d050ff"), heading)


## The Wild space warnings: skipped altogether once "don't show this again" has been ticked (the ESC menu turns
## them back on).
func ask_wild(text: String, yes_text: String, on_yes: Callable) -> void:
	if Game.skip_wild_warning:
		on_yes.call()
		return
	var prev := mode
	mode = "dialog"
	confirm.ask(text, yes_text, _confirm_yes.bind(prev, on_yes), _confirm_no.bind(prev), "Don't show this warning again",
		func(on: bool):
			if on:
				Game.skip_wild_warning = true
				Sfx.save_settings())


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
	Game.home = [Game.current_system, Game.current_loc]
	Game.docked = true
	if Game.auto_store and Game.store_all() > 0:
		Game.say("Everything you were carrying went into station storage (it's safe there).", Color("8cd8ff"))
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
	Game.docked = false
	_from_dock = false
	var was_docked := mode == "docked"
	mode = "fly"
	if was_docked and not _docked_bay.is_empty():
		# undock: the ship sits on the pad facing out while its systems start up on the black screen, then
		# the view fades in and the clamps let it drift out toward the mouth
		var bay := _docked_bay
		_docked_bay = {}
		player.position = bay.pad + Vector3(0, 4, 0)
		if player.st.capital:  # (tethered out in front of the station, not in the bay)
			player.position = bay.mouth + bay.out * (BAY_LANE + _big_clear())
		aim = Basis.looking_at(bay.out, Vector3.UP)
		player.basis = aim
		player.stop()
		_dock_armed = false
		snap_camera()
		mode = "launching"
		dock_screen.launch(_launched.bind(bay.out))
	elif was_docked:
		dock_screen.reset()


func _launched(out: Vector3) -> void:
	if mode == "launching":
		mode = "fly"
		player.vel = out * 5.0
		# the clamps let go and the ship is fired out of the bay at cruising speed until it's clear of the mouth
		autopilot = {"mode": "launch", "out": out, "t": 0.0}
		Sfx.play("warp", -8.0, 1.6)


## Open a map or menu: in flight, or over the station when docked (closing it then goes back to the station).
func open_menu(which: String) -> void:
	if not mode in ["fly", "docked"]:
		return
	_from_dock = mode == "docked"
	if _from_dock:
		station_ui.hide()
	match which:
		"galaxy":
			mode = "map"
			galaxy_map.open()
		"system":
			mode = "map"
			system_map.open()
		"inventory", "guide":
			mode = "inventory"
			inventory.open("guide" if which == "guide" else "")
		"fitting":
			mode = "fitting"
			fitting.open()


## A menu opened at the station has closed: back to the station's own menus.
func _back_to_dock() -> bool:
	if not _from_dock:
		return false
	_from_dock = false
	mode = "docked"
	station_ui.reshow()
	return true


func close_inventory() -> void:
	inventory.hide()
	if mode == "inventory" and not _back_to_dock():
		mode = "fly"


func close_fitting() -> void:
	fitting.hide()
	if mode == "fitting" and not _back_to_dock():
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
	if mode == "map" and not _back_to_dock():
		mode = "fly"


func player_died() -> void:
	if mode == "dead":
		return
	mode = "dead"
	Game.docked = false
	_from_dock = false
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
	dock_screen.reset()
	cancel_autopilot()
	stop_auto()
	Game.event("death")
	# everything the ship carried goes with it; only what's in station storage is safe
	var lost := Game.lose_carried()
	Game.say("Your ship was destroyed!%s" % ("" if lost == "" else " Lost: %s. Only what's in station storage is safe." % lost),
		UI.BAD)
	await get_tree().create_timer(3.0).timeout
	_flash(1.0)
	_respawn()


func _respawn() -> void:
	player.set_dead(false)
	player.heal_full()
	mode = "fly"
	Game.home = [0, 0]  # a lost ship is always rebuilt at the Core's station, wherever it died
	enter_location(0, 0)
	Game.say("Your ship was rebuilt at the Core, at %s." % current_loc().name, Color("9fd3ff"))
	Game.save_game()
