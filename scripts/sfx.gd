extends Node
## All sound is synthesised at startup into AudioStreamWAV buffers:
## engine loop, effects and two short chiptune music loops.

const RATE := 22050
var streams := {}
var players: Array[AudioStreamPlayer] = []
var engine: AudioStreamPlayer
var music: AudioStreamPlayer
var _next := 0
var muted := false
var music_track := ""

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	engine = AudioStreamPlayer.new()
	add_child(engine)
	music = AudioStreamPlayer.new()
	music.volume_db = -9.0
	add_child(music)
	_build()

func _wav(samples: PackedFloat32Array, loop: bool = false, rate: int = RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

## tone: freq sweep f0->f1, wave 0 sine 1 square 2 saw 3 noise, envelope decay
func _tone(dur: float, f0: float, f1: float, wave: int, vol: float = 0.5, attack: float = 0.005) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var noise := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		ph += f / RATE
		var v := 0.0
		match wave:
			0: v = sin(ph * TAU)
			1: v = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			2: v = fmod(ph, 1.0) * 2.0 - 1.0
			3:
				if i % 2 == 0:
					noise = randf() * 2.0 - 1.0
				v = noise
		var env := minf(1.0, float(i) / (attack * RATE + 1.0)) * pow(1.0 - t, 1.6)
		out[i] = v * env * vol
	return out

func _seq(notes: Array, dur: float, wave: int, vol: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for nt in notes:
		out.append_array(_tone(dur, nt, nt, wave, vol))
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out

func _build() -> void:
	var eng := PackedFloat32Array()
	var n := int(RATE * 0.5)
	eng.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := fmod(t * 60.0, 1.0)
		var b := fmod(t * 120.0, 1.0)
		eng[i] = ((1.0 if a < 0.4 else -1.0) * 0.18 + (b * 2.0 - 1.0) * 0.12) * (0.8 + 0.2 * sin(t * TAU * 8.0))
	streams["engine"] = _wav(eng, true)
	streams["click"] = _wav(_tone(0.06, 900, 1300, 1, 0.25))
	streams["select"] = _wav(_seq([660, 990], 0.07, 1, 0.25))
	streams["count"] = _wav(_tone(0.25, 440, 440, 1, 0.3))
	streams["go"] = _wav(_tone(0.6, 880, 880, 1, 0.3))
	streams["box"] = _wav(_seq([523, 659, 784, 1046], 0.05, 1, 0.22))
	streams["tick"] = _wav(_tone(0.03, 1500, 1500, 1, 0.12))
	streams["item_get"] = _wav(_seq([784, 1046, 1318], 0.07, 0, 0.4))
	streams["boost"] = _wav(_mix(_tone(0.6, 200, 900, 2, 0.25), _tone(0.6, 0, 0, 3, 0.12)))
	streams["drift1"] = _wav(_tone(0.12, 600, 900, 1, 0.15))
	streams["drift2"] = _wav(_tone(0.12, 800, 1200, 1, 0.15))
	streams["drift3"] = _wav(_tone(0.12, 1000, 1600, 1, 0.15))
	streams["hit"] = _wav(_mix(_tone(0.5, 600, 80, 1, 0.3), _tone(0.3, 0, 0, 3, 0.25)))
	streams["bump"] = _wav(_tone(0.12, 160, 60, 0, 0.6))
	streams["shoot"] = _wav(_tone(0.25, 300, 900, 1, 0.22))
	streams["splat"] = _wav(_mix(_tone(0.3, 200, 60, 0, 0.5), _tone(0.2, 0, 0, 3, 0.15)))
	streams["shield"] = _wav(_tone(0.5, 400, 1400, 0, 0.35))
	streams["pop"] = _wav(_tone(0.15, 1400, 300, 0, 0.4))
	streams["lap"] = _wav(_seq([784, 784, 1046], 0.09, 1, 0.25))
	streams["final"] = _wav(_seq([659, 784, 988, 1318], 0.1, 1, 0.25))
	streams["finish"] = _wav(_mix(_seq([523, 659, 784, 1046, 784, 1046], 0.12, 1, 0.22), _seq([262, 330, 392, 523, 392, 523], 0.12, 2, 0.15)))
	streams["lose"] = _wav(_seq([392, 370, 349, 330], 0.18, 2, 0.25))
	streams["record"] = _wav(_seq([1046, 1318, 1568, 2093], 0.08, 0, 0.35))
	engine.stream = streams["engine"]
	engine.volume_db = -14.0
	streams["music_menu"] = _wav(_music(false), true, 16000)
	streams["music_race"] = _wav(_music(true), true, 16000)

func _music(fast: bool) -> PackedFloat32Array:
	var rate := 16000
	var bpm := 150.0 if fast else 112.0
	var step := 60.0 / bpm / 2.0
	var steps := 32
	var n := int(step * steps * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var roots := [0, 0, 5, 7] if fast else [0, 9, 5, 7]
	var mel := [0, 4, 7, 12, 7, 4, 9, 7, 0, 4, 7, 11, 12, 11, 7, 4] if fast else [7, -1, 4, -1, 2, 4, 7, -1, 9, -1, 7, 4, 2, -1, 0, -1]
	var base := 196.0 if fast else 174.6
	var spn := int(step * rate)
	for s in steps:
		var root: int = roots[(s / 8) % 4]
		var bass_f := base * 0.5 * pow(2.0, root / 12.0)
		var mi: int = mel[s % 16]
		var mel_f := 0.0 if mi < 0 else base * 2.0 * pow(2.0, (mi + root) / 12.0)
		for j in spn:
			var i := s * spn + j
			if i >= n:
				break
			var t := float(j) / rate
			var e := exp(-t * 9.0)
			var v := 0.0
			var bp := fmod(t * bass_f, 1.0)
			v += (1.0 if bp < 0.5 else -1.0) * 0.09 * (0.6 + 0.4 * e)
			if mel_f > 0.0:
				var mp := fmod(t * mel_f, 1.0)
				v += (1.0 if mp < 0.25 else -1.0) * 0.07 * e
			if fast and s % 2 == 0:
				v += (randf() * 2.0 - 1.0) * 0.08 * exp(-t * 40.0)
			if s % 4 == 0:
				v += sin(t * TAU * lerpf(120.0, 40.0, minf(1.0, t * 12.0))) * 0.3 * exp(-t * 14.0)
			out[i] = v
	return out

func play(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if muted or not streams.has(name):
		return
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = streams[name]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()

func set_music(which: String) -> void:
	if which == music_track and (music.playing or muted):
		return
	music_track = which
	if muted or which == "":
		music.stop()
		return
	music.stream = streams["music_" + which]
	music.play()

func set_engine(on: bool, speed_ratio: float, boost: bool) -> void:
	if muted or not on:
		if engine.playing:
			engine.stop()
		return
	if not engine.playing:
		engine.play()
	engine.pitch_scale = clampf(0.7 + speed_ratio * 1.5 + (0.25 if boost else 0.0), 0.5, 2.6)

func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)
	if m:
		engine.stop()
		music.stop()
	else:
		var w := music_track
		music_track = ""
		set_music(w)
