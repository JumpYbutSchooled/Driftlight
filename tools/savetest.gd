extends SceneTree
## Save-safety test: runs the real Game save code against a scratch folder (never the player's saves).
## godot --headless --path <project> --script <this> -- --root=<empty scratch dir> --save=<a real version-2 save>

var G
var dir_root := ""
var real := ""
var fails := 0
var _frames := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	G = root_node()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			dir_root = a.substr(7)
		elif a.begins_with("--save="):
			real = a.substr(7)
	if dir_root == "" or not dir_root.contains("scratchpad"):
		print("FAIL: refusing to run outside the scratchpad")
		return true
	G.no_save = false
	G.save_root = dir_root
	G.use_slot("pilot")
	print("save path: ", G.save_path)
	_run()
	print("RESULT: %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	return true


func root_node():
	return get_root().get_node("Game")


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func wipe() -> void:
	for d in [dir_root.path_join("backups"), dir_root]:
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d.path_join(f))
	G.in_game = false


func put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func names(why: String) -> Array:
	return G.backups(G.save_path).filter(func(p): return p.contains("_" + why))


func _run() -> void:
	# --save is a real save from an earlier version: as-is it's one this version resets, and marked with the
	# current save version it stands in for a good, current save
	var before_reset := FileAccess.get_file_as_string(real)
	var cur: Dictionary = JSON.parse_string(before_reset)
	cur.version = G.SAVE_VERSION
	var good := JSON.stringify(cur)
	var old_v3 := JSON.stringify({"version": 1, "credits": 0, "owned_ships": ["wren"], "ship_id": "wren", "playtime": 4.0})
	var main: String = G.save_path

	print("-- a normal start: the save loads and a session backup is kept")
	wipe()
	put(main, good)
	put(main + ".bak", good)
	G.migrate_saves()
	check(text(main) == good and text(main + ".bak") == good, "migrate leaves a good save alone")
	check(not G.reset_note, "no 'started over' note")
	check(G.has_save(), "Continue shows")
	check(G.load_game() and G.credits == 57730 and G.ship_id == "excavator", "loads: %d credits, %s" % [G.credits, G.ship_id])
	check(names("session").size() == 1, "a session backup was kept")

	print("-- on the title (no game loaded), nothing writes the save")
	wipe()
	put(main, good)
	G.new_game()  # what the title holds in memory: a blank pilot
	G.in_game = false
	G.save_game()
	G.end_session()
	check(text(main) == good, "the save is untouched by save_game / end_session on the title")
	check(G.backups(main).is_empty(), "and no backups are made from it")

	print("-- an old copy of the game (v3) wrote over the save and its .bak")
	wipe()
	put(main, good)
	G.load_game()  # a normal session: session backup
	G.in_game = true
	G.end_session()  # leaving: auto backup
	put(main, old_v3)
	put(main + ".bak", old_v3)
	G.in_game = false
	G.migrate_saves()
	check(not FileAccess.file_exists(main) and not FileAccess.file_exists(main + ".bak"), "the v3 files were moved out of the way")
	check(names("set_aside").size() == 2, "...into the backups folder, not deleted")
	check(not G.reset_note, "no 'started over' note (there's a good backup)")
	check(G.has_save(), "Continue still shows")
	check(G.load_game() and G.credits == 57730, "Continue restores the newest good backup: %d credits" % G.credits)
	check(G.loaded_backup.contains("_auto"), "from " + G.loaded_backup.get_file())
	G.in_game = true
	G.save_game()
	check(JSON.parse_string(text(main)).credits == 57730.0, "and the next save puts it back in place")

	print("-- an unreadable save")
	wipe()
	put(main, good)
	G.load_game()
	put(main, "{\"credits\": 5")
	G.in_game = false
	G.migrate_saves()
	check(G.load_game() and G.credits == 57730, "falls back to the backup")

	print("-- a save from a newer version of the game")
	wipe()
	var newer: Dictionary = JSON.parse_string(good)
	newer["game"] = 99
	put(main, JSON.stringify(newer))
	G.migrate_saves()
	check(G.has_save(), "Continue shows")
	check(not G.load_game() and G.save_too_new == 99, "won't load: " + G.load_error)
	G.save_game()
	check(JSON.parse_string(text(main)).game == 99.0, "and isn't written over")

	print("-- a pre-v4 save with nothing newer (the v4 reset)")
	wipe()
	put(main, old_v3)
	G.migrate_saves()
	check(G.reset_note, "the 'started over' note shows")
	check(not G.has_save(), "no Continue")
	check(names("set_aside").size() == 1, "the old save is kept in the backups folder")

	print("-- the reset: a save (and backups) from before this save version")
	wipe()
	put(main, before_reset)
	put(main + ".bak", before_reset)
	G.load_game()  # (refused: it's from before the reset)
	G.keep_before_new_game()  # stands in for v7's own backups of it
	G.migrate_saves()
	check(G.reset_note, "the 'started over' note shows")
	check(not G.has_save() and not G.load_game(), "no Continue, and its backups aren't loaded either")
	check(names("set_aside").size() == 2, "the save and .bak are kept in the backups folder")

	print("-- furnaces keep smelting while the game is closed")
	wipe()
	var fur: Dictionary = cur.duplicate(true)
	fur.refineries = {"0:0": {"name": "Test Station", "queue": [["corrite", 0, 100], ["ferrox", 3, 1000]], "progress": 0.0,
		"output": {}}}
	fur.saved_at = Time.get_unix_time_from_system() - 3600.0
	put(main, JSON.stringify(fur))
	check(G.load_game(), "loads")
	var r: Dictionary = G.refineries["0:0"]
	var ferrox_each: float = G.refine_time("ferrox", 3)
	var want_ferrox := floori((3600.0 - 100 * G.refine_time("corrite", 0)) / ferrox_each)
	check(r.output.get("corrite", 0) == 100 * G.Q_YIELD[0], "an hour away: all 100 corrite smelted (%d materials)" % r.output.get("corrite", 0))
	check(absi(r.output.get("ferrox", 0) - want_ferrox * G.Q_YIELD[3]) <= G.Q_YIELD[3],
		"...and about %d pristine ferrox (%d materials)" % [want_ferrox, r.output.get("ferrox", 0)])
	check(G.away_smelted == G.furnace_output() and absf(G.away_time - 3600.0) < 5.0,
		"reported: %d materials in %d s away" % [G.away_smelted, G.away_time])

	print("-- relics come back a week after they're decoded")
	var rl := [0, 0]
	for s in G.systems:
		for li in s.locs.size():
			if rl[0] == 0 and s.id > 0 and s.locs[li].kind == "planet":
				rl = [s.id, li]
	G.new_game()
	G.systems[rl[0]].locs[rl[1]].relic = true
	G.mark_relic(rl[0], rl[1])
	check(not G.systems[rl[0]].locs[rl[1]].relic, "decoded: the relic is gone")
	G.mark_relic(rl[0], rl[1])
	check(G.relics_done.size() == 1, "decoding it again doesn't add a second entry")
	check(G.refresh_relics() == 0 and not G.systems[rl[0]].locs[rl[1]].relic, "it stays gone through the week")
	G.relics_done[0][2] = Time.get_unix_time_from_system() - G.RELIC_RESPAWN + 3600.0
	check(G.refresh_relics() == 0 and not G.systems[rl[0]].locs[rl[1]].relic, "an hour before the week is up: still gone")
	G.relics_done[0][2] = Time.get_unix_time_from_system() - G.RELIC_RESPAWN - 60.0
	check(G.refresh_relics() == 1 and G.systems[rl[0]].locs[rl[1]].relic and G.relics_done.is_empty(), "a week and a minute on: it's back")
	var rs: Dictionary = G.systems[rl[0]]
	G.mark_relic(rl[0], rl[1])
	wipe()
	G.in_game = true
	G.save_game()  # (saved with the relic decoded just now)
	G.new_game()
	check(G.load_game() and not G.systems[rl[0]].locs[rl[1]].relic, "still gone after saving and loading")
	var old_save: Dictionary = JSON.parse_string(text(main))
	old_save.relics_done = [[rl[0], rl[1]]]  # (a save from before the weekly return: no time)
	put(main, JSON.stringify(old_save))
	check(G.load_game() and not G.systems[rl[0]].locs[rl[1]].relic and G.relics_done.size() == 1,
		"an older save's relics get a fresh week")
	G.in_game = false

	print("-- save codes: carry a save to another device")
	wipe()
	put(main, good)
	var code: String = G.save_code()
	check(code.begins_with("DLSAVE1-") and code.length() > 200 and not code.contains(" ") and not code.contains("\n"),
		"a code for the save: %d characters" % code.length())
	wipe()  # (the other device: no save there)
	check(not G.has_save(), "nothing saved on the other device")
	check(G.import_code(code) == "", "the code loads")
	check(text(main) == good and text(main + ".bak") == good, "the save is exactly the original")
	check(G.load_game() and G.credits == 57730 and G.ship_id == "excavator", "and plays: %d credits, %s" % [G.credits, G.ship_id])
	put(main, FileAccess.get_file_as_string(real))  # (an older pilot save sits there now)
	var wrapped := ""
	for i in range(0, code.length(), 60):
		wrapped += code.substr(i, 60) + ("\n" if i % 120 == 0 else " ")
	check(G.import_code("  " + wrapped + "\n") == "", "pasting with spaces and line breaks works too")
	check(names("before_code").size() >= 1, "the save it replaced was kept in the backups folder")
	check(G.import_code(code.substr(0, code.length() - 40)) != "", "a cut-off code is refused")
	var flipped := code.substr(0, code.length() - 5) + ("A" if code[code.length() - 5] != "A" else "B") + code.substr(code.length() - 4)
	check(G.import_code(flipped) != "", "a code with one character changed is refused")
	check(G.import_code("hello") != "" and G.import_code("") != "", "rubbish is refused")
	var old_json := JSON.stringify({"version": 1, "credits": 5})
	var old_code := "DLSAVE1-%d-%s-%s" % [old_json.length(), "x", "y"]
	check(G.import_code(old_code) != "", "a made-up code is refused")
	var newer2: Dictionary = JSON.parse_string(good)
	newer2["game"] = 99
	put(main, JSON.stringify(newer2))
	var newer_code: String = G.save_code()
	wipe()
	check(G.import_code(newer_code).contains("newer version"), "a save from a newer game version is refused")

	print("-- a fresh install")
	wipe()
	G.migrate_saves()
	check(not G.has_save() and not G.reset_note and not G.load_game(), "no save, no note, nothing to load")

	print("-- starting over, rolling backups, the cap")
	wipe()
	put(main, good)
	G.keep_before_new_game()
	check(names("before_new_game").size() == 1, "New Game keeps a copy of the save it replaces")
	G.load_game()
	G.in_game = true
	var n: int = G.backups(main).size()
	G.playtime += G.BACKUP_EVERY + 1.0
	G.save_game()
	check(G.backups(main).size() == n + 1, "a rolling backup after %d s of play" % int(G.BACKUP_EVERY))
	G.save_game()
	check(G.backups(main).size() == n + 1, "but not on every save")
	var sandbox: String = dir_root.path_join(G.SLOTS.sandbox)
	check(G.backups(sandbox).is_empty(), "the sandbox slot doesn't see the pilot's backups")
	var real_ones: int = G.backups(main).size()
	for i in 50:
		put(dir_root.path_join("backups").path_join("driftlight_save_2000-01-01T00-00-%02d_auto.json" % i), good)
	G.end_session()
	var all: Array = G.backups(main)
	check(all.size() == G.BACKUPS_KEPT, "kept to %d backups (%d)" % [G.BACKUPS_KEPT, all.size()])
	check(not all[0].contains("T00-00-00"), "the oldest went first")
	check(all.filter(func(p): return not p.contains("2000-01-01")).size() == real_ones + 1, "every real backup is still there")
	wipe()
