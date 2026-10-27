extends Node
## Keeps the game up to date from the GitHub releases, and restarts itself into the new version.
##
## The title screen asks (at start, and every time you come back to it) whether a newer release exists. That
## question is one plain web request that needs no API (and so has no rate limit): GitHub redirects
## ".../releases/latest" to ".../releases/tag/v<number>". A higher number than Game.VERSION is downloaded
## (retrying if it drops), unpacked into a staging folder and checked; then, at the title, the game saves its
## settings and quits while a small hidden PowerShell helper waits for it to exit, swaps the new files in
## (retrying, since antivirus or Windows can still hold a file for a few seconds; leaving files that haven't
## changed alone; logging everything to update_log.txt) and starts the game again. While an update is being
## fetched or installed the title won't let you join a game. If an install fails the staged update is kept and
## tried again at the next start (up to three times, then it is downloaded afresh). Only runs in exported
## builds, never from the editor; offline it just stays quiet.

const REPO_PAGE := "https://github.com/%s/releases/latest"
const ASSET_URL := "https://github.com/%s/releases/latest/download/Driftlight-windows.zip"
const API := "https://api.github.com/repos/%s/releases/latest"  # (only if the plain request fails)
const DOWNLOAD_TRIES := 3
const INSTALL_TRIES := 3  # failed installs at start-up before the staged update is thrown away and downloaded again

# where everything lives (the tests point these at a scratch folder)
var zip_path := "user://update.zip"
var stage_dir := "user://update_stage"
var ready_path := "user://update_ready.json"  # the staged update's version and how many installs were tried
var log_path := "user://update_log.txt"
var installer_path := "user://install_update.ps1"
var game_dir := ""  # where the game's files are ("" : next to the running exe)

var status := ""  # shown on the title screen
var state := "idle"  # idle, checking, downloading, staged (ready, waiting for the title), installing
var version := 0  # the update's version, once known
var progress := 0.0  # how much of it has downloaded, 0..1
var no_restart := false  # tests: install, but don't start the game again
var current := Game.VERSION  # the version this game is (tests pretend to be older)
var latest_seen := 0  # the newest release the last check found
var auto_install := true  # install as soon as the title is up (tests turn it off)
var force_enabled := false  # tests: run outside an exported build
var wait_pid := -1  # tests: the process the installer waits for (-1: this game)
var _enabled := false
var _http: HTTPRequest
var _try := 0
var _launched := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_enabled = (OS.has_feature("template") and not OS.has_feature("editor")) or force_enabled
	no_restart = no_restart or "--update-no-restart" in args
	if not _enabled:
		return
	# dev test: "-- --update-from=<zip>" stages that zip as if it were release v999, then quits
	for a in args:
		if a.begins_with("--update-from="):
			zip_path = OS.get_user_data_dir().path_join("update.zip")
			DirAccess.copy_absolute(a.substr(14), zip_path)
			version = 999
			var err := _unpack()
			print("UPDATE TEST staged=%s status=%s" % [err == "", err])
			get_tree().quit()
			return
	if _resume_staged():
		return
	check()


## Does the title have to wait? (An update is being downloaded, or installed: don't let anyone join a game.)
func blocking() -> bool:
	return state in ["downloading", "staged", "installing"]


## Ask whether a newer release exists (and fetch it if so). Safe to call whenever: it does nothing while busy.
func check() -> void:
	if not _enabled or state != "idle":
		return
	state = "checking"
	status = "checking for updates..."
	_try = 0
	if not _ask(REPO_PAGE % Game.REPO, 0, "", 20.0, _on_page):
		_idle("")


func _headers(extra: Array) -> PackedStringArray:
	return PackedStringArray(["User-Agent: Driftlight/%d" % Game.VERSION] + extra)


## One web request (its own node, so nothing carries over from the last one).
func _ask(url: String, redirects: int, to_file: String, timeout: float, done: Callable, extra := []) -> bool:
	if _http != null:
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.max_redirects = redirects
	_http.timeout = timeout
	if to_file != "":
		_http.download_file = to_file
	add_child(_http)
	_http.request_completed.connect(done)
	return _http.request(url, _headers(extra)) == OK


## ".../releases/latest" answers with a redirect to ".../releases/tag/v15": the newest version is in it.
func _on_page(_result: int, _code: int, hdrs: PackedStringArray, _body: PackedByteArray) -> void:
	var v := 0
	for h in hdrs:
		if h.to_lower().begins_with("location:"):
			v = h.substr(9).strip_edges().get_file().trim_prefix("v").to_int()
	if v > 0:
		_found(v)
	elif not _ask(API % Game.REPO, 10, "", 20.0, _on_api, ["Accept: application/vnd.github+json"]):
		_idle("")


func _on_api(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	var v := 0
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			v = str(data.get("tag_name", "")).trim_prefix("v").to_int()
	if v > 0:
		_found(v)
	else:
		_idle("")  # (offline: stay quiet)


func _found(v: int) -> void:
	latest_seen = v
	if v <= current:
		_idle("up to date  -  v%d" % current)
		return
	version = v
	_try = 0
	_download()


func _idle(text: String) -> void:
	state = "idle"
	status = text


func _download() -> void:
	_try += 1
	state = "downloading"
	progress = 0.0
	status = "downloading v%d..." % version
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path))
	if not _ask(ASSET_URL % Game.REPO, 10, ProjectSettings.globalize_path(zip_path), 900.0, _on_zip):
		_download_failed("couldn't start the download")


func _process(_delta: float) -> void:
	if not _enabled:
		return
	if state == "downloading" and _http != null and _http.get_body_size() > 0:
		progress = clampf(float(_http.get_downloaded_bytes()) / _http.get_body_size(), 0.0, 1.0)
		status = "downloading v%d...  %d%%" % [version, roundi(100.0 * progress)]
	elif state == "staged" and auto_install and _at_title():
		_install_now()


func _at_title() -> bool:
	var m := get_parent()
	return m == null or m.get("mode") == "title"


func _on_zip(result: int, code: int, _hdrs: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_download_failed("download failed (%d / %d)" % [result, code])
		return
	var err := _unpack()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path))
	if err != "":
		_download_failed(err)
		return
	_log("v%d downloaded and unpacked" % version)
	var f := FileAccess.open(ready_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"v": version, "tries": 0}))
		f.close()
	state = "staged"
	status = "installing v%d..." % version
	if get_parent() != null and get_parent().has_method("note_update_ready"):
		get_parent().note_update_ready(version)


## A failed download: try again a few times, then give up quietly until the next check.
func _download_failed(why: String) -> void:
	_log("download of v%d failed: %s (try %d)" % [version, why, _try])
	if _try < DOWNLOAD_TRIES:
		status = "download failed - trying again (%d/%d)..." % [_try + 1, DOWNLOAD_TRIES]
		await get_tree().create_timer(3.0).timeout
		_download()
	else:
		_idle("couldn't download v%d - it'll try again next time" % version)


## Unpack the zip's files (flattened) into the staging folder and check them. Returns "" or what went wrong.
func _unpack() -> String:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return "the download is damaged"
	var stage := ProjectSettings.globalize_path(stage_dir)
	_clear_stage()
	DirAccess.make_dir_recursive_absolute(stage)
	var got_pack := false
	for path in zr.get_files():
		var fname := path.get_file()
		if fname == "":
			continue  # a folder entry
		var data := zr.read_file(path)
		var f := FileAccess.open(stage.path_join(fname), FileAccess.WRITE)
		if f == null:
			zr.close()
			return "can't write the update"
		f.store_buffer(data)
		f.close()
		if FileAccess.get_file_as_bytes(stage.path_join(fname)).size() != data.size():
			zr.close()
			return "the update didn't unpack completely"
		got_pack = got_pack or fname.to_lower().ends_with(".pck")
	zr.close()
	return "" if got_pack else "no game data in the download"


func _clear_stage() -> void:
	var stage := ProjectSettings.globalize_path(stage_dir)
	if DirAccess.dir_exists_absolute(stage):
		for f in DirAccess.get_files_at(stage):
			DirAccess.remove_absolute(stage.path_join(f))
		DirAccess.remove_absolute(stage)


func _resume_staged_for_test() -> bool:
	return _resume_staged()


## At start: an update staged by an earlier run that never got installed is installed now. Returns true if so.
func _resume_staged() -> bool:
	if not FileAccess.file_exists(ready_path):
		_clear_stage()  # (leftovers of something that never finished)
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(ready_path))
	var stage := ProjectSettings.globalize_path(stage_dir)
	var has_pack := false
	if DirAccess.dir_exists_absolute(stage):
		for f in DirAccess.get_files_at(stage):
			has_pack = has_pack or f.to_lower().ends_with(".pck")
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) <= current or not has_pack:
		_clear_stage()  # (already installed, or nothing left of it)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ready_path))
		return false
	var tries := int(d.get("tries", 0)) + 1
	if tries > INSTALL_TRIES:
		_log("v%d couldn't be installed %d times: starting over" % [int(d.v), INSTALL_TRIES])
		_clear_stage()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ready_path))
		return false
	d["tries"] = tries
	var f := FileAccess.open(ready_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()
	version = int(d.v)
	state = "staged"
	status = "installing v%d..." % version
	_log("an update (v%d) was waiting: installing it (try %d)" % [version, tries])
	return true


## Hand over to the helper: it swaps the files in once this process has exited, then starts the game again.
func _install_now() -> void:
	if state != "staged":
		return
	state = "installing"
	status = "installing v%d - restarting..." % version
	Sfx.save_settings()
	_launch_installer(not no_restart)
	get_tree().quit()


func _launch_installer(run_after: bool) -> void:
	if _launched or version <= 0:
		return
	_launched = true
	var ps := ProjectSettings.globalize_path(installer_path)
	var f := FileAccess.open(ps, FileAccess.WRITE)
	if f == null:
		_log("couldn't write the installer")
		return
	f.store_string(INSTALLER)
	f.close()
	var gdir := game_dir if game_dir != "" else OS.get_executable_path().get_base_dir()
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", ps,
		"-ProcId", str(wait_pid if wait_pid > 0 else OS.get_process_id()), "-Game", gdir, "-Stage", ProjectSettings.globalize_path(stage_dir),
		"-Run", "1" if run_after else "0", "-Log", ProjectSettings.globalize_path(log_path),
		"-Ready", ProjectSettings.globalize_path(ready_path)])


func _exit_tree() -> void:
	if _enabled and state in ["staged", "installing"]:
		_launch_installer(false)  # closing the game installs a waiting update for next time


func _log(text: String) -> void:
	var path := ProjectSettings.globalize_path(log_path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%s  %s" % [Time.get_datetime_string_from_system(false, true), text])
		f.close()


## The helper (PowerShell). Waits for the game to exit, then for each staged file: unchanged ones are left alone;
## changed ones are copied beside the old one and moved over it, retrying for up to Tries x 0.75 s when something
## still holds the file. On success the staging folder and ready file go; on failure they stay so the next
## start tries again, and the old game is started anyway. Everything is written to the log.
const INSTALLER := """param($ProcId, $Game, $Stage, $Run, $Log, $Ready, $Tries = 40)
function Say($m) { Add-Content -LiteralPath $Log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m) }
Say ('installer: waiting for process ' + $ProcId + ', game folder ' + $Game)
$until = (Get-Date).AddSeconds(90)
while ((Get-Process -Id $ProcId -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $until)) { Start-Sleep -Milliseconds 300 }
Start-Sleep -Milliseconds 700
$ok = $true
foreach ($f in (Get-ChildItem -LiteralPath $Stage -File)) {
	$dest = Join-Path $Game $f.Name
	try {
		if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -eq $f.Length) -and ((Get-FileHash -LiteralPath $dest -ErrorAction Stop).Hash -eq (Get-FileHash -LiteralPath $f.FullName -ErrorAction Stop).Hash)) {
			Say ($f.Name + ': unchanged')
			continue
		}
	} catch { }
	$done = $false
	for ($i = 1; ($i -le $Tries) -and (-not $done); $i++) {
		try {
			$tmp = $dest + '.new'
			Copy-Item -LiteralPath $f.FullName -Destination $tmp -Force -ErrorAction Stop
			Move-Item -LiteralPath $tmp -Destination $dest -Force -ErrorAction Stop
			$done = $true
			Say ($f.Name + ': installed')
		} catch {
			Say ($f.Name + ': try ' + $i + ' failed: ' + $_.Exception.Message)
			Remove-Item -LiteralPath ($dest + '.new') -Force -ErrorAction SilentlyContinue
			Start-Sleep -Milliseconds 750
		}
	}
	if (-not $done) { $ok = $false }
}
if ($ok) {
	Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $Ready -Force -ErrorAction SilentlyContinue
	Say 'installer: done'
} else {
	Say 'installer: FAILED, the update is kept for the next start'
}
if ($Run -eq '1') { Start-Process -FilePath (Join-Path $Game 'Driftlight.exe') -WorkingDirectory $Game }
"""
