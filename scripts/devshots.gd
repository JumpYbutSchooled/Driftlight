extends Node
## Dev-only: run with `-- --autoshot --shotdir=<folder>` to tour the game, save screenshots and quit.
## Never touches the player's real save: saving is off while it runs.

const Pirate = preload("res://scripts/pirate.gd")

var main
var dir := ""
var _peaks := {"Music": -200.0, "SFX": -200.0}  # loudest each audio bus got during the tour, dB


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	if dir == "":
		dir = OS.get_user_data_dir()
	if "--gallery" in OS.get_cmdline_user_args():
		_gallery()
	else:
		_run()


## `-- --autoshot --gallery`: every ship model close up under the game's own lighting: three-quarter front
## and rear, and from the sun's side. (Photo mode: the UI is hidden and time is stopped.)
func _gallery() -> void:
	await _secs(1.0)
	main.start_new_game()
	await _secs(1.5)
	var p = main.player
	main.toggle_photo()
	main._photo_hint.visible = false
	p.visible = false
	var at: Vector3 = p.position
	var ids: Array = Game.SHIPS.keys() + Game.ENEMIES.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):  # just these models
			ids = Array(a.substr(7).split(","))
	var sheet: Image = null
	if "--sheet" in OS.get_cmdline_user_args():  # every ship on one contact sheet, from the front quarter
		sheet = Image.create(480 * 6, 300 * ceili(ids.size() / 6.0), false, Image.FORMAT_RGBA8)
	for id in ids:
		var m: Node3D = Models.ship(id)
		main.world.add_child(m)
		m.global_position = at
		var guns = load("res://scripts/turrets.gd").new(m)
		for tu in guns.list:  # swing them a little, as if tracking something off the nose
			tu.yaw.rotation.y = 0.5
			tu.pitch.rotation.x = 0.3
		var s: Vector3 = Models.size(id)
		var r := maxf(s.x, s.z) if Models.scale_of(id) == 1.0 else maxf(s.x, s.z) * 0.9
		var sun: Vector3 = main.sun_dir_world
		var views := [["front", Vector3(0.8, 0.45, -1.0)], ["rear", Vector3(-0.9, 0.35, 1.0)], ["sunside", sun + Vector3(0.3, 0.3, 0.0)]]
		if sheet != null:
			views = [["sun", (sun + Vector3(0.0, 0.35, 0.0)).normalized() + Vector3(0.25, 0.0, -0.35)]]
		for view in views:
			main.camera.global_position = at + (view[1] as Vector3).normalized() * r * (0.95 if sheet != null else 1.4)
			main.camera.look_at(at, Vector3.UP)
			main.camera.far = r * 20.0 + 2000.0
			await _wait(6)
			if sheet != null:
				# one tile per ship on a contact sheet
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(480, 300, Image.INTERPOLATE_LANCZOS)
				var k: int = ids.find(id)
				sheet.blit_rect(img, Rect2i(0, 0, 480, 300), Vector2i((k % 6) * 480, floori(k / 6.0) * 300))
			else:
				await _shot("g_%s_%s" % [id, view[0]])
		m.queue_free()
		await _wait(2)
	if sheet != null:
		sheet.save_png(dir.path_join("ship_sheet.png"))
		print("SHEET ship_sheet")
	get_tree().quit()


func _process(_delta: float) -> void:
	for bus in _peaks:
		var i := AudioServer.get_bus_index(bus)
		_peaks[bus] = maxf(_peaks[bus], maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0)))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	print("SHOT ", shot_name)


## A click of the fire button (press, a frame, release): mining beams toggle on a click.
func _click() -> void:
	Input.action_release("fire")
	await get_tree().process_frame
	Input.action_press("fire")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("fire")


## Order the docking autopilot and wait (fast) until docked, noting the stages it went through.
func _autodock(st: Dictionary, limit_ms: int) -> Array:
	main.select(st)
	main.order("use")
	Engine.time_scale = 8.0
	var t0 := Time.get_ticks_msec()
	var stages := []
	while main.mode != "docked" and Time.get_ticks_msec() - t0 < limit_ms:
		var s: String = main.autopilot.get("stage", "")
		if s != "" and (stages.is_empty() or stages[-1] != s):
			stages.append(s)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	return [stages, (Time.get_ticks_msec() - t0) / 1000.0]


func _find(test: Callable) -> Array:
	for s in Game.systems:
		for i in s.locs.size():
			if test.call(s, s.locs[i]):
				return [s.id, i]
	return [-1, -1]


## Over 90 frames (holding `action`, if any): the frame-to-frame change in the ship's on-screen position,
## minus its average drift, so only the jumps are left. Also the frame time.
func _jitter(p, action: String) -> String:
	if action != "":
		Input.action_press(action)
	await _secs(1.2)
	var pts := []
	var t0 := Time.get_ticks_usec()
	for i in 91:
		await get_tree().process_frame
		pts.append(main.camera.unproject_position(p.global_position))
	var ms := (Time.get_ticks_usec() - t0) / 91000.0
	if action != "":
		Input.action_release(action)
	var steps := []
	var mean := Vector2.ZERO
	for i in 90:
		steps.append(pts[i + 1] - pts[i])
		mean += pts[i + 1] - pts[i]
	mean /= 90.0
	var dev := []
	for s in steps:
		dev.append((s - mean).length())
	dev.sort()
	return "median %.2f px, worst %.2f px per frame (%.1f ms frames)" % [dev[45], dev[89], ms]


func _run() -> void:
	await _secs(1.5)
	await _shot("01_title")
	main.start_new_game()
	await _secs(1.0)
	var p = main.player
	print("ship model: muzzles %d engines %d radius %.1f hull %s" % [p.muzzles.size(), p.engines.size(), p.radius, str(p.hull_box)])
	print("turrets %d" % p.turrets.size())
	# turn with the keys: the ship spins up while A is held and spins down after it's let go; the camera
	# stays put, since only the mouse moves it
	var cam_before: Basis = main.camera.global_basis
	var before: Vector3 = p.forward()
	Input.action_press("yaw_left")
	await _secs(1.5)
	var held: Vector3 = p.forward()
	var rate_held: float = p.ang_vel.length()
	Input.action_release("yaw_left")
	await _secs(1.5)
	print("keyboard turn: %.0f deg while held (spinning %.2f of %.2f rad/s), %.0f deg more coasting after, now %.3f rad/s, camera turned %.1f deg" % [
		rad_to_deg(before.angle_to(held)), rate_held, p.turn_rate(), rad_to_deg(held.angle_to(p.forward())), p.ang_vel.length(),
		rad_to_deg((-cam_before.z).angle_to(-main.camera.global_basis.z))])
	# the mouse swings the camera, not the ship
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(-300, 0)
	var nose: Vector3 = p.forward()
	var look0: Vector3 = -main.camera.global_basis.z
	main._input(mm)
	await _secs(0.3)
	print("mouse look: camera turned %.0f deg, ship turned %.1f deg" % [rad_to_deg(look0.angle_to(-main.camera.global_basis.z)),
		rad_to_deg(nose.angle_to(p.forward()))])
	# and right over the top: no limit on looking up
	mm.relative = Vector2(0, -900)
	main._input(mm)
	await _secs(0.4)
	print("mouse look over the top: camera up is now %.2f (negative: upside down, past the vertical)" % main.camera.global_basis.y.y)
	main.snap_camera()
	main.snap_camera()
	p.throttle = 1.0
	await _secs(3.0)
	print("throttle: %.1f m/s after 3 s at full throttle (top %.1f), engine rumble playing %s at %.1f dB" % [p.vel.length(),
		p.top_speed(), Sfx._engine.playing, Sfx._engine.volume_db])
	var voices: int = Sfx._voices.filter(func(v): return v.p.playing).size()
	print("music: organ ready %s, %d organ voices sounding, chord %d" % [Sfx._organ != null, voices, Sfx._chord])
	# smoothness: how far the ship jumps about on screen from one frame to the next while cruising, and
	# while turning (the chase camera should hold it steady: well under a pixel)
	print("screen jitter cruising: %s" % await _jitter(p, ""))
	print("screen jitter turning: %s" % await _jitter(p, "yaw_left"))
	await _shot("02_station")
	p.throttle = 0.0
	# out in front of the docking bay, lined up on it
	var st: Dictionary = main.station_lm()
	var bay: Dictionary = st.bay
	p.position = bay.mouth + bay.out * 380.0 + Vector3(60, 30, 0)
	main.aim = Basis.looking_at((bay.pad - p.position).normalized(), Vector3.UP)
	p.basis = main.aim
	p.stop()
	main.snap_camera()
	await _secs(1.0)
	print("turrets lined up on the bay: %s" % str(p.turret_why))
	await _secs(0.8)
	print("  and a moment later: %s" % str(p.turret_why))
	if "--quick" in OS.get_cmdline_user_args():  # (just the start of the tour, for quick checks)
		get_tree().quit()
		return
	await _shot("02b_bay_approach")
	# inside the bay
	p.position = bay.mouth - bay.out * 60.0 + Vector3(0, -10, 0)
	main.aim = Basis.looking_at((bay.pad - p.position).normalized(), Vector3.UP)
	p.basis = main.aim
	main.snap_camera()
	await _secs(0.8)
	await _shot("02e_bay_inside")
	# fly on in to the pad: that docks (and puts what the ship carries into station storage)
	Game.cargo["corrite:1"] = 12
	Game.materials["ferrox"] = 7
	Game.changed.emit()
	p.throttle = 1.0
	p.vel = p.forward() * 30.0
	var t0 := Time.get_ticks_msec()
	while main.mode != "docking" and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	await _secs(0.9)
	await _shot("02e2_docking_fade")
	while main.mode != "docked" and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	print("docking by flying in: mode %s after %.1f s" % [main.mode, (Time.get_ticks_msec() - t0) / 1000.0])
	print("storage on docking: carried ore %d ferrox %d, stored ore %d ferrox %d" % [Game.cargo_used(), Game.carried("ferrox"),
		Game.storage.cargo.get("corrite:1", 0), Game.stored("ferrox")])
	await _secs(0.5)
	await _shot("02f_docked")
	main.station_ui._set_tab("storage")
	await _secs(0.4)
	await _shot("02f3_storage")
	# the maps and menus open over the station, and close back to it
	main.open_menu("galaxy")
	await _secs(0.6)
	await _shot("02f4_map_from_dock")
	main.close_maps()
	print("map from the dock: back to %s, station menu showing %s" % [main.mode, main.station_ui.visible])
	# what the ship carries is lost with it; storage is safe
	Game.materials["ferrox"] = 5
	var lost := Game.lose_carried()
	print("lose carried: '%s', ferrox carried %d, stored %d" % [lost, Game.carried("ferrox"), Game.stored("ferrox")])
	main.close_panel()
	await _secs(1.2)
	await _shot("02f2_startup")
	t0 = Time.get_ticks_msec()
	while main.mode != "fly" and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	print("undocked: mode %s after %.1f s of startup, %.0f m from the pad, facing out %.2f" % [main.mode,
		(Time.get_ticks_msec() - t0) / 1000.0 + 1.2, p.position.distance_to(bay.pad), p.forward().dot(bay.out)])
	# launched out of the bay at cruising speed until clear of the mouth
	var fastest_out := 0.0
	t0 = Time.get_ticks_msec()
	while main.autopilot.get("mode", "") == "launch" and Time.get_ticks_msec() - t0 < 8000:
		fastest_out = maxf(fastest_out, p.vel.length())
		await get_tree().process_frame
	print("launch: %.0f m/s at most (cruise %.0f), done after %.1f s, %.0f m out of the mouth" % [fastest_out,
		p.top_speed() * main.CRUISE_MULT, (Time.get_ticks_msec() - t0) / 1000.0, (p.position - bay.mouth).dot(bay.out)])
	await _shot("02g_undocked")
	# the docking autopilot from just off to one side of the bay, close in: no circling
	p.position = bay.mouth + bay.out * 160.0 + bay.right * 280.0 + Vector3(0, 70, 0)
	main.aim = Basis.looking_at(bay.right, Vector3.UP)
	p.basis = main.aim
	p.stop()
	var side_dock: Array = await _autodock(st, 60000)
	print("docking autopilot from beside the bay: mode %s, stages %s, %.1f s real (x8)" % [main.mode, str(side_dock[0]), side_dock[1]])
	if main.mode == "docked":
		main.close_panel()
		t0 = Time.get_ticks_msec()
		while main.mode != "fly" and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
	# the docking autopilot from behind the station: it has to go round, line up and fly in
	p.position = st.pos - bay.out * 1500.0 + Vector3(0, 100, 0)
	main.aim = Basis.looking_at((st.pos - p.position).normalized(), Vector3.UP)
	p.basis = main.aim
	p.stop()
	main.select(st)
	main.order("use")
	Engine.time_scale = 8.0
	t0 = Time.get_ticks_msec()
	var mid_shot := false
	while main.mode != "docked" and Time.get_ticks_msec() - t0 < 90000:
		if not mid_shot and p.position.distance_to(bay.mouth) < 500.0:
			mid_shot = true
			Engine.time_scale = 1.0
			await _secs(0.3)
			await _shot("02h_autopilot_lineup")
			Engine.time_scale = 8.0
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("docking autopilot from behind: mode %s after %.1f s real (x8), %.0f m from the pad" % [main.mode,
		(Time.get_ticks_msec() - t0) / 1000.0, p.position.distance_to(bay.pad)])
	# and from underneath the station, inside its keep-out sphere
	if main.mode == "docked":
		main.close_panel()
		t0 = Time.get_ticks_msec()
		while main.mode != "fly" and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
	p.position = st.pos + Vector3(150, -700, 200)
	p.stop()
	var under: Array = await _autodock(st, 90000)
	print("docking autopilot from under the station: mode %s, stages %s, %.1f s real (x8)" % [main.mode, str(under[0]), under[1]])
	if main.mode == "docked":
		main.close_panel()
		t0 = Time.get_ticks_msec()
		while main.mode != "fly" and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
	await _secs(0.5)
	# zoomed right out
	main._zoom_to = 60.0
	await _secs(1.5)
	await _shot("02d_zoomed_out")
	main._zoom_to = 1.0
	main.zoom = 1.0
	await _secs(0.4)
	# engine plumes at full throttle, seen from the side and from behind
	p.throttle = 1.0
	await _secs(1.5)
	main.cam_turn(1.3, -0.12)
	await _secs(0.4)
	await _shot("02c_plumes")
	main.snap_camera()
	main._zoom_to = 0.6
	main.zoom = 0.6
	await _secs(0.4)
	print("turrets leaving the bay: %s" % str(p.turret_why))
	await _shot("02i_plumes_behind")
	main._zoom_to = 1.0
	main.zoom = 1.0
	p.throttle = 0.0

	# the Core Belt: survey it, pick a vein on the overview and approach it
	main.enter_location(0, 1)
	await _secs(0.6)
	main.survey_scan()
	await _secs(0.5)
	await _shot("03a_field_scan")
	# 5: cruise right across the field to its far side, threading between the rocks
	var far_rock = null
	for a in get_tree().get_nodes_in_group("asteroids"):
		var dd: float = a.position.distance_to(p.position)
		if dd < 5500.0 and (far_rock == null or dd > far_rock.position.distance_to(p.position)):
			far_rock = a
	main.select(far_rock)
	main.order("cruise")
	var fastest := 0.0
	var closest := INF
	var shot_taken := false
	Engine.time_scale = 4.0
	var tc := Time.get_ticks_msec()
	while main.autopilot.get("mode", "") == "cruise" and Time.get_ticks_msec() - tc < 40000:
		await get_tree().process_frame
		fastest = maxf(fastest, p.vel.length())
		for a in get_tree().get_nodes_in_group("asteroids"):
			closest = minf(closest, a.position.distance_to(p.position) - a.radius - p.radius)
		if not shot_taken and p.vel.length() > p.top_speed() * 6.0:
			shot_taken = true
			Engine.time_scale = 1.0
			await _shot("03g_cruise")
			Engine.time_scale = 4.0
	Engine.time_scale = 1.0
	print("cruise: %.0f m/s top (normal %.0f), closest a rock came %.0f m, ended %.0f m from the target after %.1f s real (x4), autopilot %s" % [
		fastest, p.top_speed(), closest, p.position.distance_to(far_rock.position) - far_rock.radius, (Time.get_ticks_msec() - tc) / 1000.0,
		main.autopilot.get("mode", "off")])
	await _secs(2.0)
	print("after cruise: %.0f m/s" % p.vel.length())
	# a hard turn at cruise speed: the dust streaks bend round with the ship
	p.cruise_v = p.top_speed() * 10.0
	await _secs(1.0)
	Input.action_press("yaw_left")
	await _secs(0.7)
	await _shot("03j_dust_curve")
	Input.action_release("yaw_left")
	p.cruise_v = 0.0
	await _secs(1.5)
	var vein = main.overview_entries(20).filter(func(r): return not r.t is Dictionary and r.t.is_in_group("asteroids"))[0].t
	main.select(vein)
	main.order("approach")
	await _secs(2.0)
	print("approach: autopilot %s, %.0f m to go" % [main.autopilot.get("mode", "-"), p.position.distance_to(vein.position)])
	await _shot("03c_approach")
	main.cancel_autopilot()
	main._zoom_to = 25.0
	await _secs(1.2)
	await _shot("03d_field_zoomed")
	main._zoom_to = 1.0
	main.zoom = 1.0
	var rock = get_tree().get_nodes_in_group("asteroids")[0]
	p.position = rock.position + Vector3(0, 4, rock.radius + 22.0)
	main.aim = Basis.looking_at((rock.position - p.position).normalized(), Vector3.UP)
	p.basis = main.aim
	main.snap_camera()
	await _secs(0.6)
	Input.action_press("fire")
	await _secs(1.6)
	print("rock after 1.6s of fire: %d / %d ore, chunks %d, turrets ready %s" % [rock.remaining, rock.total,
		get_tree().get_nodes_in_group("chunks").size(), str(p.guns_ready)])
	await _shot("03_mining")
	# close in on the guns while they fire: each beam should start at its barrel
	main._zoom_to = 0.55
	main.zoom = 0.55
	main.cam_turn(0.5, -0.25)
	await _secs(0.5)
	await _shot("03e_turrets_firing")
	Input.action_release("fire")
	main._zoom_to = 1.0
	main.zoom = 1.0
	main.snap_camera()
	if is_instance_valid(rock):
		rock.hit(99999.0, -p.forward())
	await _secs(0.35)
	await _shot("03b_rock_burst")
	# the overview filtered to ore of Normal quality or better
	main.overview.cat = "ore"
	main.overview.minq = 1
	main.overview._refresh = 0.0
	await _secs(0.4)
	await _shot("03f_overview_filter")
	print("overview filtered to ore, Normal+: %d rows" % main.overview._rows.size())
	main.overview.cat = "veins"
	main.overview.minq = -1
	main.overview.sort = "ore"
	main.overview._refresh = 0.0
	await _secs(0.4)
	await _shot("03f2_overview_veins_by_ore")
	print("overview veins by ore: %d rows, first %s" % [main.overview._rows.size(),
		main.overview._rows[0].name if not main.overview._rows.is_empty() else "-"])
	main.overview.cat = "all"
	main.overview.sort = "dist"
	# O: auto-collect flies round the loose ore, picking it all up
	var cargo0 := Game.cargo_used()
	var reach: int = get_tree().get_nodes_in_group("chunks").filter(
		func(c): return c.position.distance_to(p.position) < main.COLLECT_RANGE).size()
	main.toggle_collect()
	Engine.time_scale = 6.0
	t0 = Time.get_ticks_msec()
	while main.autopilot.get("mode", "") == "collect" and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("auto-collect: %d pieces in reach, cargo %d -> %d in %.1f s real (x6), autopilot now %s" % [reach, cargo0,
		Game.cargo_used(), (Time.get_ticks_msec() - t0) / 1000.0, main.autopilot.get("mode", "off")])

	# mining beams: Mk III lasers on both turrets lock on to a rock and cut ore straight into the hold
	Game.weapon_stock["mining_lasers_mk3"] = 2
	Game.mount_all("mining_lasers_mk3")
	await _wait(2)
	print("turret models after the swap: %s" % str(p.turrets.map(func(tu): return tu.kind)))
	var beam_rock = null
	for a in get_tree().get_nodes_in_group("asteroids"):
		if beam_rock == null or a.position.distance_to(p.position) < beam_rock.position.distance_to(p.position):
			beam_rock = a
	p.position = beam_rock.position + Vector3(0, 30, beam_rock.radius + 120.0)
	main.aim = Basis.looking_at((beam_rock.position - p.position).normalized(), Vector3.UP)
	p.basis = main.aim
	p.stop()
	main.snap_camera()
	await _secs(0.6)
	var held0 := Game.cargo_used()
	var chunks0 := get_tree().get_nodes_in_group("chunks").size()
	var left0: int = beam_rock.remaining
	await _click()  # one click: the beams lock on and keep cutting
	await _secs(0.4)
	main.cam_turn(0.6, 0.3)  # the beams stay locked whatever the crosshair does
	await _secs(2.6)
	await _shot("03h_mining_beam")
	print("mining beam: locked %s (no button held), rock %d -> %d, hold %d -> %d, new loose chunks %d" % [p.beam_lock == beam_rock,
		left0, beam_rock.remaining if is_instance_valid(beam_rock) else 0, held0, Game.cargo_used(),
		get_tree().get_nodes_in_group("chunks").size() - chunks0])
	main.snap_camera()
	await _secs(0.3)
	await _click()  # another click stops them
	await _secs(0.2)
	print("mining beam after a second click: locked %s" % [p.beam_lock != null])
	main.snap_camera()
	await _secs(1.5)
	print("tractor beam: reach %.0f m, %d chunks being pulled" % [p.tractor_range(),
		get_tree().get_nodes_in_group("chunks").filter(func(c): return c.tractored).size()])
	# jettison: a cargo stack thrown out the back as loose ore, which can't be scooped straight back up
	Game.cargo["corrite:1"] = 30
	Game.changed.emit()
	var c0 := get_tree().get_nodes_in_group("chunks").size()
	Game.jettison("corrite:1")
	await _secs(0.8)
	print("jettison: %d chunks out the back, hold has corrite: %s" % [get_tree().get_nodes_in_group("chunks").size() - c0,
		Game.cargo.has("corrite:1")])
	main.cam_turn(PI, -0.2)
	await _secs(0.4)
	await _shot("03i_jettison")
	main.snap_camera()
	Game.mount_all(Game.BLASTER)

	# a fight in Wild space with every pirate type
	var wild := _find(func(s, l): return s.cat == Game.CAT_PURPLE and l.kind == "planet" and l.ore)
	main.enter_location(wild[0], wild[1])
	main._pirate_timer = -1.0  # only the test's own pirates, so the ship survives the tour
	await _secs(0.3)
	var i := 0
	for t in ["raider", "gunner", "sniper", "swarmer", "captain", "sentinel"]:
		var e := Pirate.new()
		e.main = main
		e.position = p.position + p.forward() * 70.0 + main.aim.x * (-45.0 + i * 18.0) + Vector3(0, randf_range(-6, 6), 0)
		main.world.add_child(e)
		e.setup(t, Game.CAT_PURPLE)
		e.shot.damage = 0.2  # they still shoot (for the shield shots) but can't kill the starter ship
		i += 1
	await _secs(1.0)
	Input.action_press("fire")
	await _secs(0.8)
	Input.action_release("fire")
	await _shot("04_combat")
	print("pirates %d  hull %.0f  shield %.0f" % [get_tree().get_nodes_in_group("pirates").size(), p.hull, p.shield])
	var foes := get_tree().get_nodes_in_group("pirates")
	if foes.size() >= 2:
		foes[0].take_damage(foes[0].hp * 0.7)  # badly damaged: should smoke
		foes[1].position = p.position + p.forward() * 45.0
		foes[1].take_damage(99999.0)
	p.heal_full()
	p.take_damage(1.0, p.position + p.forward() * 5.0 + Vector3.UP * 2.0)
	await _secs(0.3)
	await _shot("04b_explosion")
	await _secs(0.8)
	await _shot("04c_aftermath")
	for e in get_tree().get_nodes_in_group("pirates"):
		e.queue_free()
	# look off to the side at a target there: the turrets swing round to it while the ship flies straight on
	var side := Pirate.new()
	side.main = main
	side.position = p.position + main.aim.x * 80.0 + p.forward() * 10.0
	main.world.add_child(side)
	side.setup("raider", Game.CAT_PURPLE)
	side.shot.damage = 0.0
	side.speed = 0.0
	for k in 2:  # twice: the camera moves round the ship as it turns, so aim again from where it ends up
		var to_side: Vector3 = (side.position - main.camera.global_position).normalized()
		main.cam_look(to_side, true)
		await _secs(0.6)
	Input.action_press("fire")
	await _secs(0.5)
	print("side target: on it %s, turrets ready %s, ship turned %.1f deg" % [main.aim_target == side, str(p.guns_ready),
		rad_to_deg(p.forward().angle_to(-main.aim.z))])
	await _shot("04d_turrets_side")
	Input.action_release("fire")
	if is_instance_valid(side):
		side.queue_free()
	main.snap_camera()

	# warp across a location with a station and an ore field, kilometres apart
	p.heal_full()
	var both := _find(func(s, l): return s.cat != Game.CAT_PURPLE and l.kind == "planet" and l.station and l.ore)
	main.enter_location(both[0], both[1])
	await _secs(0.5)
	var far = null
	for lm in main.landmarks:
		if p.position.distance_to(lm.pos) > main.LOCAL_WARP_MIN:
			far = lm
	if far != null:
		main.select(far)
		main.order("warp")
		while main.travel.get("phase", "") != "travel" and main.mode == "warp":
			await get_tree().process_frame
		await _secs(0.8)
		await _shot("05a_local_warp")
		while main.mode != "fly":
			await get_tree().process_frame
		print("local warp: landed %.0f m from %s" % [p.position.distance_to(far.pos), far.name])
		await _secs(0.5)
		await _shot("05b_local_arrival")
	else:
		print("local warp: nothing far enough away")
	# an anomaly's huge field: hundreds of veins, the common ores among them
	var anom := _find(func(s, l): return l.kind == "anomaly")
	Game.peaceful = true
	main.enter_location(anom[0], anom[1])
	main._pirate_timer = -1.0
	await _secs(0.8)
	var kinds := {}
	for a in get_tree().get_nodes_in_group("asteroids"):
		kinds[a.ore_id] = kinds.get(a.ore_id, 0) + 1
	print("anomaly field: %d veins, by ore %s" % [get_tree().get_nodes_in_group("asteroids").size(), str(kinds)])
	main._zoom_to = 40.0
	await _secs(1.5)
	await _shot("05c_anomaly_field")
	main._zoom_to = 1.0
	main.zoom = 1.0
	# an ancient relic: decode it
	var rel := _find(func(s, l): return l.get("relic", false) and l.kind == "planet")
	main.enter_location(rel[0], rel[1])
	main._pirate_timer = -1.0
	await _secs(0.6)
	for lm in main.landmarks:
		if lm.kind == "relic":
			p.position = lm.pos + Vector3(0, 60, 260)
			main.aim = Basis.looking_at((lm.pos - p.position).normalized(), Vector3.UP)
			p.basis = main.aim
			main.snap_camera()
			await _secs(0.6)
			await _shot("05d_relic")
			var cr0 := Game.credits
			lm.action.call()
			print("relic: decoded, credits %d -> %d, portals %d" % [cr0, Game.credits, Game.portals])
	Game.peaceful = false
	print("notebook: %d places, %d with a refinery" % [Game.notebook.size(), Game.notes_with("refinery").size()])
	# warp to a gate in The Core
	main.enter_location(0, 0)
	await _secs(0.5)
	var gate := -1
	for k in Game.systems[0].locs.size():
		var l: Dictionary = Game.systems[0].locs[k]
		if l.kind == "gate" and Game.systems[l.gate_to].cat != Game.CAT_PURPLE:  # (Wild gates ask first)
			gate = k
			break
	main.start_warp(gate)
	while main.travel.get("phase", "") == "align":
		await get_tree().process_frame
	print("aligned; charging")
	await _secs(1.4)
	await _shot("05_warp_charge")
	while main.travel.get("phase", "") != "travel":
		await get_tree().process_frame
	await _secs(1.0)
	await _shot("06_warp_tunnel")
	while main.mode != "fly":
		await get_tree().process_frame
	await _secs(1.0)
	await _shot("07_stargate")
	# the gate is a railgun: the autopilot lines up on its mouth and flies in, the coils fire the ship down
	# the barrel (which points at the next system) and out into the jump
	var gate_lm = null
	for lm in main.landmarks:
		if lm.kind == "gate":
			gate_lm = lm
	var dest_id: int = Game.systems[0].locs[gate].gate_to
	var gate_dir: Vector3 = -gate_lm.bay.out
	main.select(gate_lm)
	main.order("use")
	Engine.time_scale = 8.0
	t0 = Time.get_ticks_msec()
	while main.mode == "fly" and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("gate autopilot: mode %s after %.1f s real (x8), launched by the gate %s, heading %.1f deg off the barrel" % [
		main.mode, (Time.get_ticks_msec() - t0) / 1000.0, main.travel.has("gate"),
		rad_to_deg(main.travel.get("heading", Vector3.ZERO).angle_to(gate_dir))])
	if main.mode == "dialog":
		print("gate leads to Wild space: the warning is up")
	while main.travel.get("phase", "") != "charge" and main.mode == "warp":
		await get_tree().process_frame
	await _secs(main.travel.get("charge", 1.0) * 0.6)
	await _shot("07b_gate_launch")
	while main.travel.get("phase", "") != "travel" and main.mode == "warp":
		await get_tree().process_frame
	print("left the muzzle at %.0f m/s, %.0f m off the barrel's line" % [p.vel.length(), main._off_axis(gate_lm.bay).length()])
	await _secs(1.4)
	await _shot("07c_jump_rush")
	print("jump rush: world %.0f km behind, visible %s" % [main._rush.length() / 1000.0, main.world.visible])
	while main.mode != "fly":
		await get_tree().process_frame
	print("arrived in system %d (wanted %d)" % [Game.current_system, dest_id])
	await _secs(0.3)
	await _shot("07d_gate_arrival")
	# auto-travel: a route of a few jumps (through safe space), with a stop on the way, flown on its own
	var far_safe := -1
	for id in Game.systems_within(Game.current_system, 3, 3):
		if Game.find_path(Game.current_system, id).all(func(s): return Game.systems[s].cat < Game.CAT_PURPLE):
			far_safe = id
			break
	if far_safe >= 0:
		var path := Game.find_path(Game.current_system, far_safe)
		Game.clear_route()
		Game.route_target = path[0]
		Game.add_stop(far_safe)
		main.toggle_auto()
		Engine.time_scale = 6.0
		t0 = Time.get_ticks_msec()
		var warps := 0
		var was_warp := false
		while main.auto_travel and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
			if main.mode == "dialog":
				main.confirm._answer(true)
			if main.mode == "warp" and not was_warp:
				warps += 1
			was_warp = main.mode == "warp"
		Engine.time_scale = 1.0
		print("auto-travel: now in %d (wanted %d) after %.1f s real (x6), %d warps and jumps, route left %d" % [Game.current_system,
			far_safe, (Time.get_ticks_msec() - t0) / 1000.0, warps, Game.route_target])
		await _secs(0.4)
		await _shot("07e_auto_arrival")
	else:
		print("auto-travel: no safe system three jumps out")

	while main.mode != "fly" or not main.travel.is_empty():
		await get_tree().process_frame
	# photo mode: the UI hides, time stops, and a free camera looks back at the ship
	main.toggle_photo()
	main.camera.global_position = p.position + Vector3(p.radius * 3.0, p.radius * 1.2, p.radius * 2.0)
	main.camera.look_at(p.position, Vector3.UP)
	await _wait(6)
	await _shot("09_photo_mode")
	print("photo mode: on=%s  time_scale=%.1f  ui hidden=%s" % [main.photo, Engine.time_scale, not main.ui_layer.visible])
	main.toggle_photo()
	await _wait(2)
	# the sandbox slot (anyone can play it): everything free, fill up, jump straight to a far system
	Game.use_slot("sandbox")
	print("sandbox: on=%s god=%s free aeon=%s" % [Game.sandbox, Game.god, Game.can_afford(Game.build_cost("ship", "aeon"))])
	if Game.sandbox:
		Game.sandbox_fill()
		var far_sys: int = Game.systems.size() - 1
		main.admin_jump(far_sys)
		while main.mode != "fly" or not main.travel.is_empty():
			await get_tree().process_frame
		print("sandbox jump: now in system %d (wanted %d), credits %d, ships %d" % [Game.current_system, far_sys, Game.credits,
			Game.owned_ships.size()])
		await _shot("08b_sandbox_jump")
		# a capital ship: hundreds of metres long, too big for a bay, with its own jump drive
		Game.board_ship("sovereign")
		main.enter_location(0, 0)
		Game.peaceful = true
		await _secs(1.2)
		print("capital: %s radius %.0f m, %d turrets, jump reach %.0f" % [Game.SHIPS[Game.ship_id].name, p.radius, p.turrets.size(),
			p.st.jump])
		main._zoom_to = 1.0
		await _secs(0.5)
		await _shot("11_capital")
		main.cam_turn(2.4, -0.3)
		main._zoom_to = 1.6
		await _secs(1.2)
		await _shot("11b_capital_side")
		main._zoom_to = 1.0
		var hop: int = main._jump_hop(Game.systems.size() - 1)
		main.jump_drive(hop)
		t0 = Time.get_ticks_msec()
		var dshot := false
		while (main.mode != "fly" or not main.travel.is_empty()) and Time.get_ticks_msec() - t0 < 60000:
			await get_tree().process_frame
			if main.mode == "dialog":
				main.confirm._answer(true)
			if not dshot and main.travel.get("phase", "") == "charge" and main.travel.t > 2.0:
				dshot = true
				await _shot("11c_jump_drive_charge")
		print("jump drive: now in system %d (wanted %d), %.0f map units, cooldown %.0f s" % [Game.current_system, hop,
			Game.systems[0].pos.distance_to(Game.systems[hop].pos), main._jump_cd])
		await _secs(0.5)
		await _shot("11d_jump_drive_arrival")
		Game.peaceful = false
		Game.board_ship("wren")
	Game.peaceful = false
	Game.use_slot("pilot")
	# F3 in the Titan
	Game.owned_ships.append("titan")
	Game.board_ship("titan")
	main.enter_location(0, 0)
	await _secs(1.0)
	main.debug = true
	main.debug_ui.visible = true
	await _secs(0.3)
	await _shot("08_titan_f3")
	main.debug = false
	main.debug_ui.visible = false
	main.mode = "fitting"
	main.fitting.open()
	main.fitting._pick_slot(2)
	await _secs(1.2)
	await _shot("10_fitting_titan")
	print("fitting: %d turret rows for the %s" % [Game.loadout().size(), Game.SHIPS[Game.ship_id].name])
	main.close_fitting()
	# the menus: galaxy map with its regions, the guide and planner, the notebook, the fabricator
	main.mode = "map"
	main.galaxy_map.open()
	main.galaxy_map.zoom = 0.22
	await _secs(0.8)
	await _shot("12_galaxy_regions")
	main.close_maps()
	Game.toggle_pin("ship", "falcon")
	main.mode = "inventory"
	main.inventory.open("guide")
	await _secs(0.8)
	await _shot("13_guide")
	main.inventory.open("notebook")
	await _secs(0.6)
	await _shot("14_notebook")
	main.close_inventory()
	await _secs(0.4)
	await _shot("15_hud_pinned")
	main.mode = "docked"
	main.station_ui.open("station", main.current_loc())
	main.station_ui.fab_tab = "modules"
	main.station_ui._set_tab("fabricator")
	await _secs(0.6)
	await _shot("16_fab_modules")
	main.station_ui._set_fab_tab("ships")
	await _secs(0.4)
	await _shot("16b_fab_ships")
	main.station_ui.hide()
	main.mode = "fly"
	print("content: %d ships, %d weapons, %d modules, %d ores, %d achievements" % [Game.SHIPS.size(), Game.WEAPONS.size(),
		Game.MODULES.size(), Game.ORES.size(), Game.ACHIEVEMENTS.size()])
	print("audio peaks over the tour: music %.1f dB, sfx %.1f dB" % [_peaks.Music, _peaks.SFX])
	get_tree().quit()
