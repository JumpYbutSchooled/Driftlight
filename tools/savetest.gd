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
	var good := FileAccess.get_file_as_string(real)
	var old_v3 := JSON.stringify({"version": 1, "credits": 0, "owned_ships": ["wren"], "ship_id": "wren", "playtime": 4.0})
	var main: String = G.save_path

	print("-- a normal start: the save loads and a session backup is kept")
	wipe()
	put(main, good)
	put(main + ".bak", good)
	G.migrate_saves()
	check(text(main) == good and text(main + ".bak") == good, "migrate leaves a good save alone")
	check(not G.reset_note, "no 'v4 started over' note")
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
	check(not G.reset_note, "no 'v4 started over' note (there's a good backup)")
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
	check(G.reset_note, "the 'v4 started over' note shows")
	check(not G.has_save(), "no Continue")
	check(names("set_aside").size() == 1, "the old save is kept in the backups folder")

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
