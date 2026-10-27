extends Node
## The updater end to end, in a scratch folder (never the real game or its saves): the version check against GitHub
## (up to date, and a newer one found), the real download, unpack and checks, the staged update installed into a
## fake game folder by the real helper, a leftover staged update resumed at start-up, and a damaged download.
## Run inside the game (so the autoloads exist), through the dev tests:
##   godot --headless --path <project> -- --autoshot --updatetest --root=<empty dir under a scratchpad>

const Updater = preload("res://scripts/updater.gd")

var dir_root := ""
var fails := 0


func start(path: String) -> void:
	dir_root = path
	if dir_root == "" or not dir_root.contains("scratchpad"):
		print("UPDTEST FAIL: refusing to run outside the scratchpad")
		get_tree().quit()
		return
	_run()


func check(ok: bool, what: String) -> void:
	print("UPDTEST " + ("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func fresh(name: String, current: int) -> Node:
	var d := dir_root.path_join(name)
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	var u: Node = Updater.new()
	u.force_enabled = true
	u.current = current
	u.auto_install = false
	u.no_restart = true
	u.zip_path = d.path_join("update.zip")
	u.stage_dir = d.path_join("stage")
	u.ready_path = d.path_join("ready.json")
	u.log_path = d.path_join("log.txt")
	u.installer_path = d.path_join("install_update.ps1")
	u.game_dir = d.path_join("game")
	return u


func wait_for(u: Node, states: Array, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not u.state in states and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().create_timer(0.25).timeout


func _run() -> void:
	print("UPDTEST -- the version check (one plain web request, no API)")
	var u := fresh("t1", 999)
	add_child(u)
	await wait_for(u, ["idle"], 30.0)
	check(u.state == "idle" and u.latest_seen >= 15, "found the latest release: v%d (status: %s)" % [u.latest_seen, u.status])
	check(not u.blocking(), "an up-to-date game isn't blocked")
	u.queue_free()

	print("UPDTEST -- a newer release: download, unpack, check")
	var d := dir_root.path_join("t2")
	u = fresh("t2", 1)
	add_child(u)
	await wait_for(u, ["downloading", "staged"], 30.0)
	check(u.state == "downloading" or u.state == "staged", "found v%d, downloading" % u.latest_seen)
	check(u.blocking(), "the title is blocked while it downloads")
	var t0 := Time.get_ticks_msec()
	var best := 0.0
	while u.state == "downloading" and Time.get_ticks_msec() - t0 < 300000:
		best = maxf(best, u.progress)
		await get_tree().create_timer(0.5).timeout
	check(u.state == "staged", "downloaded and unpacked (%d s, progress reached %.0f%%)" % [(Time.get_ticks_msec() - t0) / 1000, best * 100.0])
	var staged := DirAccess.get_files_at(d.path_join("stage"))
	check(staged.has("Driftlight.pck") and staged.has("Driftlight.exe"), "the staged folder has the game: %s" % str(staged))
	check(FileAccess.file_exists(d.path_join("ready.json")), "the ready file is written")
	check(not FileAccess.file_exists(d.path_join("update.zip")), "the zip is cleaned up")
	check(u.blocking(), "still blocked once staged (it installs next)")

	print("UPDTEST -- the install, by the real helper, into a fake game folder")
	var gd := d.path_join("game")
	DirAccess.make_dir_recursive_absolute(gd)
	for fname in ["Driftlight.exe", "Driftlight.pck", "README.txt"]:
		var f := FileAccess.open(gd.path_join(fname), FileAccess.WRITE)
		f.store_string("old " + fname)
		f.close()
	var want := {}
	for fname in staged:
		want[fname] = FileAccess.get_file_as_bytes(d.path_join("stage").path_join(fname)).size()
	u.wait_pid = 999999  # (the game this test stands in for has already exited)
	u._launch_installer(false)
	var t1 := Time.get_ticks_msec()
	while DirAccess.dir_exists_absolute(d.path_join("stage")) and Time.get_ticks_msec() - t1 < 90000:
		await get_tree().create_timer(0.5).timeout
	check(not DirAccess.dir_exists_absolute(d.path_join("stage")) and not FileAccess.file_exists(d.path_join("ready.json")),
		"the helper installed it and cleaned up (%d s)" % ((Time.get_ticks_msec() - t1) / 1000))
	var same := true
	for fname in want:
		same = same and FileAccess.file_exists(gd.path_join(fname)) and FileAccess.get_file_as_bytes(gd.path_join(fname)).size() == want[fname]
	check(same, "every file in the game folder is the new one, byte for byte in size: %s" % str(want))
	check(Array(DirAccess.get_files_at(gd)).filter(func(f): return f.ends_with(".new")).is_empty(), "no leftover .new files")
	print(FileAccess.get_file_as_string(d.path_join("log.txt")))
	u.queue_free()

	print("UPDTEST -- a staged update left over from an earlier run is installed at the next start (and gives up after 3 tries)")
	u = fresh("t3", 1)
	var d3 := dir_root.path_join("t3")
	DirAccess.make_dir_recursive_absolute(d3.path_join("stage"))
	var sf := FileAccess.open(d3.path_join("stage").path_join("Driftlight.pck"), FileAccess.WRITE)
	sf.store_string("pck")
	sf.close()
	var rf := FileAccess.open(d3.path_join("ready.json"), FileAccess.WRITE)
	rf.store_string(JSON.stringify({"v": 99, "tries": 0}))
	rf.close()
	u._resume_staged_for_test()
	check(u.state == "staged" and u.version == 99, "picked up: v%d, state %s" % [u.version, u.state])
	check(JSON.parse_string(FileAccess.get_file_as_string(d3.path_join("ready.json"))).tries == 1, "that was try 1")
	u.state = "idle"
	u._resume_staged_for_test()
	u.state = "idle"
	u._resume_staged_for_test()
	check(u.state == "staged", "try 3 still goes ahead")
	u.state = "idle"
	check(not u._resume_staged_for_test() and not DirAccess.dir_exists_absolute(d3.path_join("stage")),
		"a 4th try is refused: the stage is thrown away, the next check downloads afresh")
	u.queue_free()

	print("UPDTEST -- already installed: leftovers are cleared, nothing blocks")
	u = fresh("t4", 100)
	var d4 := dir_root.path_join("t4")
	DirAccess.make_dir_recursive_absolute(d4.path_join("stage"))
	var sf4 := FileAccess.open(d4.path_join("stage").path_join("Driftlight.pck"), FileAccess.WRITE)
	sf4.store_string("pck")
	sf4.close()
	var rf4 := FileAccess.open(d4.path_join("ready.json"), FileAccess.WRITE)
	rf4.store_string(JSON.stringify({"v": 99, "tries": 0}))
	rf4.close()
	check(not u._resume_staged_for_test() and not DirAccess.dir_exists_absolute(d4.path_join("stage")) and not u.blocking(),
		"an update that's already in (v99 vs v100) is dropped")
	u.queue_free()

	print("UPDTEST -- a damaged download is refused")
	u = fresh("t5", 1)
	var d5 := dir_root.path_join("t5")
	var bad := FileAccess.open(d5.path_join("update.zip"), FileAccess.WRITE)
	bad.store_string("this is not a zip file")
	bad.close()
	var why: String = u._unpack()
	check(why != "", "a file that isn't a zip: %s" % why)
	u.queue_free()
	print("UPDTEST RESULT: %s" % ("all passed" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit()
