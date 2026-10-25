extends Node
## Dev-only: run with `-- --autoshot --shotdir=<folder>` to tour the game, save screenshots and quit.
## Never touches the player's real save: saving is off while it runs.

const Pirate = preload("res://scripts/pirate.gd")

var main
var dir := ""


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	if dir == "":
		dir = OS.get_user_data_dir()
	_run()


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


func _run() -> void:
	await _secs(1.5)
	await _shot("01_title")
	main.start_new_game()
	await _secs(1.0)
	var p = main.player
	print("ship model: muzzles %d engines %d radius %.1f hull %s" % [p.muzzles.size(), p.engines.size(), p.radius, str(p.hull_box)])
	# turn with the keys (A for two seconds); the reticle sits mid-screen
	Input.warp_mouse(get_viewport().get_visible_rect().size / 2.0)
	var before: Vector3 = p.forward()
	Input.action_press("yaw_left")
	await _secs(1.5)
	Input.action_release("yaw_left")
	await _secs(0.5)
	print("keyboard turn: nose swung %.0f deg, %.1f deg off the heading" % [rad_to_deg(before.angle_to(p.forward())),
		rad_to_deg(p.forward().angle_to(-main.aim.z))])
	p.throttle = 0.6
	await _secs(1.0)
	await _shot("02_station")
	p.throttle = 0.0
	# in front of the citadel's hangar, looking up at it
	p.position = Vector3(780, 180, -1860)
	main.aim = Basis.looking_at((Vector3(0, 60, 0) - p.position).normalized(), Vector3.UP)
	p.basis = main.aim
	await _secs(0.8)
	await _shot("02b_station_close")
	# zoomed right out
	main._zoom_to = 60.0
	await _secs(1.5)
	await _shot("02d_zoomed_out")
	main._zoom_to = 1.0
	main.zoom = 1.0
	await _secs(0.4)
	# engine plumes at full throttle, seen from the side
	p.throttle = 1.0
	await _secs(0.8)
	main.aim = main.aim.rotated(Vector3.UP, 1.2)
	await _secs(0.25)
	await _shot("02c_plumes")
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
	await _secs(0.4)
	Input.action_press("fire")
	await _secs(1.6)
	Input.action_release("fire")
	print("rock after 1.6s of fire: %d / %d ore, chunks %d" % [rock.remaining, rock.total, get_tree().get_nodes_in_group("chunks").size()])
	await _shot("03_mining")
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
	get_tree().quit()
