extends Node
## Synthesized sound effects plus a slow ambient music bed, all generated in code.
## Also owns the player settings (volumes, control style), saved to user://settings.cfg.

const RATE := 22050
const MUSIC_RATE := 11025
const SETTINGS_PATH := "user://settings.cfg"
# chord roots (Hz) for the ambient pads; each chord is root, fifth, ninth
const CHORDS := [[110.0, 164.8, 246.9], [98.0, 146.8, 220.0], [130.8, 196.0, 293.7], [87.3, 130.8, 196.0]]
const PENTATONIC := [440.0, 493.9, 587.3, 659.3, 784.0, 880.0, 987.8]

var volumes := {"Master": 0.8, "Music": 0.55, "SFX": 0.8}
var hold_thrust := false  # false: W/S move a throttle lever. true: hold W to thrust, S to reverse.
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: Array[AudioStreamPlayer] = []
var _pads: Array = []
var _chord := 0
var _chord_t := 0.0
var _ping_t := 4.0
var _thread: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_load_settings()
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for i in 3:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		add_child(m)
		_music.append(m)
	_streams["laser"] = _tone(0.11, 1500.0, 320.0, "square", 0.3)
	_streams["hit"] = _noise(0.08, 0.5, 0.6)
	_streams["pickup"] = _tone(0.09, 700.0, 1500.0, "sine", 0.5)
	_streams["explode"] = _noise(0.7, 0.9, 0.12)
	_streams["beep"] = _tone(0.06, 1250.0, 1250.0, "sine", 0.55)
	_streams["warp"] = _tone(1.3, 80.0, 900.0, "saw", 0.28, true)
	_streams["charge"] = _tone(2.2, 55.0, 330.0, "saw", 0.16, true)
	_streams["arrive"] = _tone(0.6, 700.0, 120.0, "sine", 0.35)
	_streams["click"] = _tone(0.04, 900.0, 600.0, "square", 0.2)
	_streams["hover"] = _tone(0.025, 1400.0, 1400.0, "square", 0.08)
	_streams["dock"] = _tone(0.35, 300.0, 520.0, "sine", 0.45)
	_streams["boost"] = _noise(0.25, 0.35, 0.3)
	_streams["refine"] = _notes([523.0, 659.0, 784.0], 0.09)
	_streams["found"] = _notes([440.0, 660.0, 880.0, 1320.0], 0.1)
	_streams["alarm"] = _notes([880.0, 660.0, 880.0, 660.0], 0.09)
	_thread = Thread.new()
	_thread.start(_build_pads)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func play(sound: String, db := 0.0, pitch := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(volumes[bus], 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), volumes[bus] <= 0.001)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in volumes:
		cfg.set_value("audio", k, volumes[k])
	cfg.set_value("controls", "hold_thrust", hold_thrust)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in volumes:
			volumes[k] = cfg.get_value("audio", k, volumes[k])
		hold_thrust = cfg.get_value("controls", "hold_thrust", false)
	for k in volumes:
		set_volume(k, volumes[k])


# ---------------------------------------------------------------- music

func _process(delta: float) -> void:
	if _pads.size() < CHORDS.size():
		return
	_chord_t -= delta
	if _chord_t <= 0.0:
		# a new pad fades in over the tail of the last one
		_chord_t = 7.0
		var m := _music[_chord % 2]
		m.stream = _pads[_chord % CHORDS.size()]
		m.volume_db = -8.0
		m.play()
		_chord += 1
	_ping_t -= delta
	if _ping_t <= 0.0:
		_ping_t = randf_range(2.5, 6.0)
		var m := _music[2]
		m.stream = _streams["ping"]
		m.pitch_scale = PENTATONIC.pick_random() / 440.0
		m.volume_db = randf_range(-20.0, -14.0)
		m.play()


## Runs on a worker thread: slow-swelling chord pads (9 seconds each, so they overlap by 2).
func _build_pads() -> void:
	var pads := []
	for chord in CHORDS:
		var dur := 9.0
		var n := int(dur * MUSIC_RATE)
		var data := PackedByteArray()
		data.resize(n * 2)
		var phases := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for i in n:
			var t := float(i) / MUSIC_RATE
			var env := sin(PI * t / dur)
			env *= env
			var v := 0.0
			for k in 3:
				var f: float = chord[k]
				phases[k * 2] += f / MUSIC_RATE
				phases[k * 2 + 1] += f * 1.004 / MUSIC_RATE  # slight detune for a chorused shimmer
				v += sin(phases[k * 2] * TAU) + sin(phases[k * 2 + 1] * TAU) * 0.7
			v *= 0.09 * env * (0.85 + 0.15 * sin(t * 1.3))
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = MUSIC_RATE
		s.data = data
		pads.append(s)
	var ping := _tone(1.6, 440.0, 440.0, "sine", 0.35)
	call_deferred("_pads_ready", pads, ping)


func _pads_ready(pads: Array, ping: AudioStreamWAV) -> void:
	_streams["ping"] = ping
	_pads = pads


# ---------------------------------------------------------------- synthesis

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _tone(dur: float, f0: float, f1: float, wave: String, vol: float, swell := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var x := fmod(phase, 1.0)
		var v := 0.0
		match wave:
			"sine": v = sin(phase * TAU)
			"square": v = 1.0 if x < 0.5 else -1.0
			_: v = x * 2.0 - 1.0
		var env := sin(t * PI) if swell else minf(1.0, t * 40.0) * (1.0 - t)
		data.encode_s16(i * 2, int(clampf(v * env * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _noise(dur: float, vol: float, smooth: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += (randf_range(-1.0, 1.0) - y) * smooth
		var env := (1.0 - t) * (1.0 - t)
		data.encode_s16(i * 2, int(clampf(y * env * vol * 2.0, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _notes(freqs: Array, each: float) -> AudioStreamWAV:
	var per := int(each * RATE)
	var data := PackedByteArray()
	data.resize(per * freqs.size() * 2)
	for k in freqs.size():
		for i in per:
			var t := float(i) / per
			var v := sin(TAU * freqs[k] * i / RATE) * (1.0 - t) * 0.4
			data.encode_s16((k * per + i) * 2, int(v * 32767.0))
	return _wav(data)
