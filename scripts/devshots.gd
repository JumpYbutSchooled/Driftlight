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
	_run()


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
	main._input(mm)
	await _secs(0.3)
	print("mouse look: camera yaw %.0f deg, ship turned %.1f deg" % [rad_to_deg(main._cam_yaw), rad_to_deg(nose.angle_to(p.forward()))])
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
	# fly on in to the pad: that docks
	p.throttle = 1.0
	p.vel = p.forward() * 30.0
	var t0 := Time.get_ticks_msec()
	while main.mode != "docked" and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	print("docking by flying in: mode %s after %.1f s" % [main.mode, (Time.get_ticks_msec() - t0) / 1000.0])
	await _secs(0.5)
	await _shot("02f_docked")
	main.close_panel()
	await _secs(1.5)
	print("undocked: mode %s, %.0f m from the pad, facing out %.2f, moving %.1f m/s" % [main.mode, p.position.distance_to(bay.pad),
		p.forward().dot(bay.out), p.vel.length()])
	await _shot("02g_undocked")
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
	if main.mode == "docked":
		main.close_panel()
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
	main._cam_yaw += 1.3
	main._cam_pitch -= 0.12
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
	main._cam_yaw += 0.5
	main._cam_pitch -= 0.25
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
		main._cam_yaw = atan2(-to_side.x, -to_side.z)
		main._cam_pitch = asin(clampf(to_side.y, -1.0, 1.0))
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
	# warp to a gate in The Core
	main.enter_location(0, 0)
	await _secs(0.5)
	var gate := -1
	for k in Game.systems[0].locs.size():
		if Game.systems[0].locs[k].kind == "gate":
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

	# photo mode: the UI hides, time stops, and a free camera looks back at the ship
	main.toggle_photo()
	main.camera.global_position = p.position + Vector3(p.radius * 3.0, p.radius * 1.2, p.radius * 2.0)
	main.camera.look_at(p.position, Vector3.UP)
	await _wait(6)
	await _shot("09_photo_mode")
	print("photo mode: on=%s  time_scale=%.1f  ui hidden=%s" % [main.photo, Engine.time_scale, not main.ui_layer.visible])
	main.toggle_photo()
	await _wait(2)
	# the admin slot (only on the admin device): everything free, fill up, jump straight to a far system
	Game.use_slot("admin")
	print("admin: allowed=%s admin=%s god=%s free titan=%s" % [Game.admin_allowed(), Game.admin, Game.god,
		Game.can_afford(Game.build_cost("ship", "titan"))])
	if Game.admin:
		Game.admin_fill()
		var far_sys: int = Game.systems.size() - 1
		main.admin_jump(far_sys)
		while main.mode != "fly" or not main.travel.is_empty():
			await get_tree().process_frame
		print("admin jump: now in system %d (wanted %d), credits %d, ships %d" % [Game.current_system, far_sys, Game.credits,
			Game.owned_ships.size()])
		await _shot("08b_admin_jump")
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
	print("audio peaks over the tour: music %.1f dB, sfx %.1f dB" % [_peaks.Music, _peaks.SFX])
	get_tree().quit()
