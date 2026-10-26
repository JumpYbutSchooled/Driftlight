extends Node
## Keeps a downloaded copy of the game up to date from the GitHub releases. At start it asks GitHub for
## the latest release; if its tag (v<number>) is higher than Game.VERSION it downloads the release zip and
## unpacks it into a staging folder. The running game holds its files open, so the swap happens once it
## closes: a small hidden PowerShell helper waits for the game to exit, copies the new files over the old
## ones and (after "Restart to update") starts it again. Only runs in exported builds, never from the
## editor; offline it just stays quiet.

const API := "https://api.github.com/repos/%s/releases/latest"
const ASSET := "Driftlight-windows.zip"
const STAGE := "user://update_stage"

var status := ""  # shown on the title screen
var ready_version := 0  # an update unpacked and waiting to be swapped in
var _http: HTTPRequest
var _zip_path := ""
var _downloading := 0  # the version being downloaded
var _launched := false  # the installer has already been started


func _ready() -> void:
	if not OS.has_feature("template") or OS.has_feature("editor"):
		return
	# dev test: "-- --update-from=<zip>" installs that zip as if it were release v999, then quits
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-from="):
			_zip_path = OS.get_user_data_dir().path_join("update.zip")
			DirAccess.copy_absolute(a.substr(14), _zip_path)
			_on_zip(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray(), 999)
			print("UPDATE TEST ready=%d status=%s" % [ready_version, status])
			get_tree().quit()
			return
	_http = HTTPRequest.new()
	_http.timeout = 900.0  # (the release zip is ~90 MB: 60 s was too close on a slower connection)
	_http.use_threads = true
	_http.max_redirects = 10
	add_child(_http)
	_http.request_completed.connect(_on_release)
	if _http.request(API % Game.REPO, _headers(["Accept: application/vnd.github+json"])) == OK:
		status = "checking for updates..."


func _headers(extra: Array) -> PackedStringArray:
	return PackedStringArray(["User-Agent: Driftlight/%d" % Game.VERSION] + extra)


func _process(_delta: float) -> void:
	if _downloading > 0 and _http.get_body_size() > 0:
		status = "downloading v%d...  %d%%" % [_downloading, roundi(100.0 * _http.get_downloaded_bytes() / _http.get_body_size())]


func _on_release(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_release)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status = ""
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		status = ""
		return
	var v := str(data.get("tag_name", "")).trim_prefix("v").to_int()
	if v <= Game.VERSION:
		status = "up to date  -  v%d" % Game.VERSION
		return
	var url := ""
	for a in data.get("assets", []):
		if a.get("name", "") == ASSET:
			url = a.get("browser_download_url", "")
	if url == "":
		status = ""
		return
	_zip_path = OS.get_user_data_dir().path_join("update.zip")
	_http.download_file = _zip_path
	_http.request_completed.connect(_on_zip.bind(v))
	if _http.request(url, _headers([])) == OK:
		_downloading = v
		status = "downloading v%d..." % v


func _on_zip(result: int, code: int, _headers_in: PackedStringArray, _body: PackedByteArray, v: int) -> void:
	_downloading = 0
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status = "update download failed - it'll try again next time"
		return
	var err := _unpack()
	DirAccess.remove_absolute(_zip_path)
	if err != "":
		status = "couldn't unpack the update (%s)" % err
		return
	ready_version = v
	status = "v%d downloaded - it installs when you close the game" % v
	Game.toast.emit("UPDATE READY", "Driftlight v%d is downloaded. It installs when you close the game (or restart from the title screen)." % v,
		"star", Color("8ee0a0"))


## Unpack the zip's files (flattened) into the staging folder. Returns "" or what went wrong.
func _unpack() -> String:
	var zr := ZIPReader.new()
	if zr.open(_zip_path) != OK:
		return "bad download"
	var stage := ProjectSettings.globalize_path(STAGE)
	DirAccess.make_dir_recursive_absolute(stage)
	var got_pack := false
	for path in zr.get_files():
		var fname := path.get_file()
		if fname == "":
			continue  # a folder entry
		var f := FileAccess.open(stage.path_join(fname), FileAccess.WRITE)
		if f == null:
			zr.close()
			return "can't write the update"
		f.store_buffer(zr.read_file(path))
		f.close()
		got_pack = got_pack or fname.to_lower().ends_with(".pck")
	zr.close()
	return "" if got_pack else "no game data in the download"


## Start the hidden helper that swaps the staged files in once this process has exited.
func _launch_installer(run_after: bool) -> void:
	if _launched or ready_version <= 0:
		return
	_launched = true
	var ps := ProjectSettings.globalize_path("user://install_update.ps1")
	var script := """param($ProcId, $Game, $Stage, $Run)
while (Get-Process -Id $ProcId -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }
Start-Sleep -Milliseconds 500
Get-ChildItem -LiteralPath $Stage -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Game $_.Name) -Force }
Remove-Item -LiteralPath $Stage -Recurse -Force
if ($Run -eq '1') { Start-Process -FilePath (Join-Path $Game 'Driftlight.exe') -WorkingDirectory $Game }
"""
	var f := FileAccess.open(ps, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(script)
	f.close()
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", ps,
		"-ProcId", str(OS.get_process_id()), "-Game", OS.get_executable_path().get_base_dir(),
		"-Stage", ProjectSettings.globalize_path(STAGE), "-Run", "1" if run_after else "0"])


## Install the downloaded update now and start the new version (the caller saves first).
func restart() -> void:
	_launch_installer(true)
	get_tree().quit()


func _exit_tree() -> void:
	_launch_installer(false)  # closing the game installs a waiting update for next time
