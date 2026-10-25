extends Node
## Synthesized sound effects, an engine rumble and the music, all generated in code.
## Also owns the player settings (volumes), saved to user://settings.cfg.
##
## Sounds are round and low: sine tones with a touch of their octave for body, and low rumbles, never
## buzzy saw or square waves.
##
## The music is a slow church-organ score in the spirit of a space-epic soundtrack: sustained organ chords
## over a deep pedal note, a clock ticking every 1.25 s, and a repeating two-note figure that builds and
## falls away again. One organ tone and one short pipe note are synthesized once (on a worker thread) and
## played at different pitches; a big reverb on the Music bus turns them into a cathedral.

const RATE := 22050
const VOICES := 32  # short effects share these
const LONG := ["warp", "charge", "arrive", "dock", "explode", "boost", "found", "alarm", "refine"]  # get their own players
const MIN_GAP := 0.03  # seconds: the same sound again sooner than this just tops up the one playing
const SETTINGS_PATH := "user://settings.cfg"
const TICK := 1.25  # seconds between clock ticks
const CHORD_TICKS := 8  # ticks per chord (10 s)
const ORGAN_BASE := 110.0  # pitch of the synthesized organ loop
const PIPE_BASE := 220.0  # and of the short pipe note
# the progression, as MIDI notes: pedal note, the chord held on the manuals, the two notes the figure
# alternates between, and how full the music is during that chord (0 pads only ... 3 everything)
const SCORE := [
	{"bass": 45, "pad": [57, 60, 64, 71], "fig": [76, 81], "level": 0},
	{"bass": 41, "pad": [53, 57, 60, 64], "fig": [76, 77], "level": 1},
	{"bass": 40, "pad": [55, 60, 64, 67], "fig": [76, 79], "level": 1},
	{"bass": 43, "pad": [55, 59, 62, 64], "fig": [74, 79], "level": 2},
	{"bass": 45, "pad": [57, 60, 64, 69], "fig": [76, 81], "level": 2},
	{"bass": 38, "pad": [50, 53, 57, 64], "fig": [77, 81], "level": 3},
	{"bass": 41, "pad": [53, 57, 60, 71], "fig": [76, 84], "level": 3},
	{"bass": 40, "pad": [52, 57, 59, 64], "fig": [76, 83], "level": 1},
]

var volumes := {"Master": 0.8, "Music": 0.55, "SFX": 0.8}
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer
var _engine_level := 0.0
var _beam: AudioStreamPlayer  # the mining beam's hum
var _beam_level := 0.0
var _long := {}  # sound -> its own player
var _last := {}  # sound -> when it last started (msec)
var _thread: Thread
# music
var _organ: AudioStreamWAV
var _pipe: AudioStreamWAV
var _tick_snd: AudioStreamWAV
var _voices := []  # organ voices: {"p": player, "a": amplitude now, "to": amplitude wanted, "rate": per second}
var _one_shots: Array[AudioStreamPlayer] = []
var _next_shot := 0
var _music_t := 0.0
var _beat := -1  # half-ticks since the music started
var _chord := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_setup_reverb()
	_load_settings()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for s in LONG:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_long[s] = p
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	_engine.volume_db = -80.0
	add_child(_engine)
	_beam = AudioStreamPlayer.new()
	_beam.bus = "SFX"
	_beam.volume_db = -80.0
	add_child(_beam)
	for i in 14:
		var v := AudioStreamPlayer.new()
		v.bus = "Music"
		add_child(v)
		_voices.append({"p": v, "a": 0.0, "to": 0.0, "rate": 0.5})
	for i in 4:
		var s := AudioStreamPlayer.new()
		s.bus = "Music"
		add_child(s)
		_one_shots.append(s)
	_streams["laser"] = _tone(0.22, 230.0, 72.0, 0.5, 18.0)
	_streams["hit"] = _mix([_tone(0.3, 110.0, 38.0, 0.6, 10.0), _rumble(0.25, 0.35, 0.08)])
	_streams["pickup"] = _tone(0.16, 300.0, 470.0, 0.4, -6.0)
	_streams["explode"] = _mix([_tone(1.3, 62.0, 24.0, 0.7, 3.0), _rumble(1.6, 0.8, 0.035)])
	_streams["beep"] = _tone(0.1, 440.0, 440.0, 0.35, 0.0)
	_streams["warp"] = _mix([_tone(1.6, 42.0, 150.0, 0.45, -1.5, true), _rumble(1.6, 0.35, 0.03, true)])
	_streams["charge"] = _mix([_tone(2.2, 30.0, 96.0, 0.4, -1.0, true), _tone(2.2, 60.0, 192.0, 0.12, -1.0, true)])
	_streams["arrive"] = _tone(0.9, 190.0, 46.0, 0.45, 4.0)
	_streams["click"] = _tone(0.06, 260.0, 190.0, 0.25, 0.0)
	_streams["hover"] = _tone(0.04, 360.0, 360.0, 0.12, 0.0)
	_streams["dock"] = _mix([_tone(0.5, 95.0, 55.0, 0.6, 6.0), _rumble(0.3, 0.45, 0.1), _tone(0.9, 196.0, 196.0, 0.18, 0.0)])
	_streams["boost"] = _mix([_rumble(0.6, 0.5, 0.05), _tone(0.6, 48.0, 70.0, 0.35, -2.0)])
	_streams["refine"] = _notes([262.0, 330.0, 392.0], 0.12)
	_streams["found"] = _notes([220.0, 330.0, 440.0, 660.0], 0.12)
	_streams["alarm"] = _notes([440.0, 330.0, 440.0, 330.0], 0.12)
	_engine.stream = _engine_loop()
	_beam.stream = _beam_loop()
	_thread = Thread.new()
	_thread.start(_build_music)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


## Play a sound effect. The long ones (warps, docking, explosions...) each have their own player, so a burst
## of gunfire never cuts them off; short ones take a free voice (or the oldest). The same sound asked for again
## within a couple of frames doesn't stack up into one loud click.
func play(sound: String, db := 0.0, pitch := 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last.get(sound, -1000) < MIN_GAP * 1000.0 and not _long.has(sound):
		return
	_last[sound] = now
	var p: AudioStreamPlayer = _long.get(sound, null)
	if p == null:
		p = _players[_next]
		for k in _players.size():  # a voice that's finished, if there is one
			var q := _players[(_next + k) % _players.size()]
			if not q.playing:
				p = q
				_next = (_next + k) % _players.size()
				break
		_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## The mining beam's hum (0: off, 1: a beam cutting).
func set_beam(level: float) -> void:
	_beam_level = move_toward(_beam_level, level, 0.12)
	if _beam_level < 0.01:
		if _beam.playing:
			_beam.stop()
		return
	if not _beam.playing:
		_beam.play()
	_beam.volume_db = linear_to_db(_beam_level * 0.5) - 8.0
	_beam.pitch_scale = 0.9 + 0.1 * _beam_level


## The engine rumble follows the throttle (0..1); `hot` (boost / warp) pitches it up a little.
func set_engine(level: float, hot := false) -> void:
	_engine_level = lerpf(_engine_level, level, 0.08)
	if _engine_level < 0.01:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.volume_db = linear_to_db(_engine_level * 0.6) - 4.0
	_engine.pitch_scale = 0.8 + 0.3 * _engine_level + (0.15 if hot else 0.0)


func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(volumes[bus], 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), volumes[bus] <= 0.001)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in volumes:
		cfg.set_value("audio", k, volumes[k])
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in volumes:
			volumes[k] = cfg.get_value("audio", k, volumes[k])
	for k in volumes:
		set_volume(k, volumes[k])


## A large, dark hall on the Music bus.
func _setup_reverb() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(bus) > 0:
		return
	var r := AudioEffectReverb.new()
	r.room_size = 0.95
	r.damping = 0.45
	r.spread = 1.0
	r.hipass = 0.08
	r.predelay_msec = 60.0
	r.predelay_feedback = 0.3
	r.dry = 0.7
	r.wet = 0.5
	AudioServer.add_bus_effect(bus, r)


# ---------------------------------------------------------------- music

static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


func _process(delta: float) -> void:
	for v in _voices:
		if v.a != v.to:
			v.a = move_toward(v.a, v.to, v.rate * delta)
			v.p.volume_db = linear_to_db(maxf(v.a, 0.0001))
			if v.a <= 0.0 and v.to <= 0.0:
				v.p.stop()
	if _organ == null:
		return
	_music_t += delta
	var beat := floori(_music_t / (TICK * 0.5))
	if beat == _beat:
		return
	_beat = beat
	var chord_i := floori(beat / (CHORD_TICKS * 2.0))
	var c: Dictionary = SCORE[chord_i % SCORE.size()]
	if chord_i != _chord:
		_chord = chord_i
		_change_chord(c)
	var level: int = c.level
	var in_chord := beat % (CHORD_TICKS * 2)
	if beat % 2 == 0 and level >= 1:
		_shot(_tick_snd, 1.0, -24.0 + level * 1.5)
	if level >= 2:
		# the figure: two notes back and forth on every half tick, a little louder at the top of the build
		var n: int = c.fig[in_chord % 2]
		_shot(_pipe, _hz(n) / PIPE_BASE, (-15.0 if level == 2 else -11.0) + (in_chord / 16.0) * 3.0)


## Fade the last chord out and the next one in, slowly, over a few seconds.
func _change_chord(c: Dictionary) -> void:
	for v in _voices:
		if v.to > 0.0:
			v.to = 0.0
			v.rate = 1.0 / 3.5
	var notes := []
	for n in c.pad:
		notes.append([n, 0.16])
	if c.level >= 1:
		notes.append([c.bass, 0.3])  # the pedal note
		notes.append([c.bass - 12, 0.22 if c.level >= 2 else 0.12])  # and its 16-foot octave below
	if c.level >= 3:
		notes.append([c.pad[c.pad.size() - 1] + 12, 0.08])  # a high octave on top at the peak
	for nv in notes:
		var v = _free_voice()
		if v == null:
			break
		v.p.stream = _organ
		v.p.pitch_scale = _hz(nv[0]) / ORGAN_BASE
		v.a = 0.0
		v.to = nv[1]
		v.rate = nv[1] / 2.8
		v.p.volume_db = -80.0
		v.p.play(randf() * 0.9)


func _free_voice():
	for v in _voices:
		if not v.p.playing:
			return v
	return null


func _shot(stream: AudioStreamWAV, pitch: float, db: float) -> void:
	var p := _one_shots[_next_shot]
	_next_shot = (_next_shot + 1) % _one_shots.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()


## Runs on a worker thread: the organ tone (a seamless 1 s loop of two slightly detuned ranks of pipes,
## so it slowly beats), the short pipe note for the figure and the clock tick.
func _build_music() -> void:
	var partials := [[1, 1.0], [2, 0.55], [3, 0.3], [4, 0.26], [5, 0.07], [6, 0.11], [8, 0.07]]
	var n := RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * ORGAN_BASE * p[0] * t) * p[1]
			v += sin(TAU * (ORGAN_BASE + 1.0) * p[0] * t + 0.7) * p[1] * 0.6
		data.encode_s16(i * 2, int(clampf(v * 0.11, -1.0, 1.0) * 32767.0))
	var organ := _wav(data)
	organ.loop_mode = AudioStreamWAV.LOOP_FORWARD
	organ.loop_begin = 0
	organ.loop_end = n
	# the pipe note: a quick breath in, a short hold, then a long fade into the reverb
	var pn := int(1.6 * RATE)
	var pd := PackedByteArray()
	pd.resize(pn * 2)
	for i in pn:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.015) * (1.0 if t < 0.2 else exp(-(t - 0.2) * 3.2))
		var v := sin(TAU * PIPE_BASE * t) + sin(TAU * PIPE_BASE * 2.0 * t) * 0.4 + sin(TAU * PIPE_BASE * 3.0 * t) * 0.15
		pd.encode_s16(i * 2, int(clampf(v * env * 0.3, -1.0, 1.0) * 32767.0))
	var pipe := _wav(pd)
	# a soft wooden tick
	var tn := int(0.08 * RATE)
	var td := PackedByteArray()
	td.resize(tn * 2)
	for i in tn:
		var t := float(i) / RATE
		var v := sin(TAU * 820.0 * t) * exp(-t * 90.0) * 0.5 + sin(TAU * 140.0 * t) * exp(-t * 40.0) * 0.6
		td.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 32767.0))
	var tick := _wav(td)
	call_deferred("_music_ready", organ, pipe, tick)


func _music_ready(organ: AudioStreamWAV, pipe: AudioStreamWAV, tick: AudioStreamWAV) -> void:
	_pipe = pipe
	_tick_snd = tick
	_organ = organ


# ---------------------------------------------------------------- synthesis

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## A sine tone gliding from f0 to f1 (exponentially when `curve` > 0: most of the drop at the start, like a
## thump; < 0 eases in instead), with a little of its octave for body. Plain sounds start quickly and die
## away; `swell` ones rise and fall.
func _tone(dur: float, f0: float, f1: float, vol: float, curve: float, swell := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var k := t
		if curve > 0.0:
			k = 1.0 - exp(-t * curve)
		elif curve < 0.0:
			k = pow(t, -curve * 0.5 + 1.0)
		phase += lerpf(f0, f1, k) / RATE
		var v := sin(phase * TAU) + sin(phase * TAU * 2.0) * 0.18
		var env := sin(t * PI) if swell else minf(1.0, t * dur / 0.004) * pow(1.0 - t, 1.6)
		data.encode_s16(i * 2, int(clampf(v * env * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Low rumbling noise: random values smoothed hard (smaller `smooth` = deeper).
func _rumble(dur: float, vol: float, smooth: float, swell := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / n
		y += (randf_range(-1.0, 1.0) - y) * smooth
		y2 += (y - y2) * smooth * 2.0
		var env := sin(t * PI) if swell else minf(1.0, t * dur / 0.01) * (1.0 - t) * (1.0 - t)
		data.encode_s16(i * 2, int(clampf(y2 * env * vol * 6.0, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Several sounds layered into one.
func _mix(parts: Array) -> AudioStreamWAV:
	var n := 0
	for p in parts:
		n = maxi(n, p.data.size())
	var out := PackedByteArray()
	out.resize(n)
	for i in range(0, n, 2):
		var v := 0
		for p in parts:
			if i < p.data.size():
				v += p.data.decode_s16(i)
		out.encode_s16(i, clampi(v, -32767, 32767))
	return _wav(out)


func _notes(freqs: Array, each: float) -> AudioStreamWAV:
	var per := int(each * RATE)
	var data := PackedByteArray()
	data.resize(per * freqs.size() * 2)
	for k in freqs.size():
		for i in per:
			var t := float(i) / per
			var env := minf(1.0, t * each / 0.006) * pow(1.0 - t, 1.5)
			var v := (sin(TAU * freqs[k] * i / RATE) + sin(TAU * freqs[k] * 2.0 * i / RATE) * 0.15) * env * 0.35
			data.encode_s16((k * per + i) * 2, int(v * 32767.0))
	return _wav(data)


## A seamless 1 s loop for the mining beam: a steady low hum with a soft shimmer over it.
func _beam_loop() -> AudioStreamWAV:
	var n := RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 220.0 * t) * 0.25 + sin(TAU * 333.0 * t) * 0.1 * (0.5 + 0.5 * sin(TAU * 6.0 * t))
		data.encode_s16(i * 2, int(clampf(v * 0.3, -1.0, 1.0) * 32767.0))
	var s := _wav(data)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s


## A seamless 2 s loop of engine rumble: a deep hum plus a bed of low random partials (all whole numbers
## of cycles in the loop, so there's no seam).
func _engine_loop() -> AudioStreamWAV:
	var n := RATE * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var parts := []
	for k in 24:
		parts.append([rng.randi_range(40, 260) * 0.5, rng.randf() * TAU, rng.randf_range(0.3, 1.0)])
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 41.0 * t) * 0.9 + sin(TAU * 82.0 * t) * 0.25
		for p in parts:
			v += sin(TAU * p[0] * t + p[1]) * p[2] * 0.12
		data.encode_s16(i * 2, int(clampf(v * 0.28, -1.0, 1.0) * 32767.0))
	var s := _wav(data)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s
