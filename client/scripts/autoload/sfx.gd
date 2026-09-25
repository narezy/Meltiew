extends Node
## Tiny procedural sound kit, so the build ships without audio assets.

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams.click = _tone(880.0, 1320.0, 0.05, 0.25, "sine")
	_streams.pop = _tone(520.0, 980.0, 0.09, 0.3, "sine")
	_streams.jump = _tone(300.0, 620.0, 0.14, 0.28, "triangle")
	_streams.boing = _tone(180.0, 760.0, 0.28, 0.35, "sine", 18.0)
	_streams.land = _tone(140.0, 70.0, 0.08, 0.3, "noise")
	_streams.join = _chord([523.25, 659.25, 783.99], 0.35, 0.22)
	_streams.error = _tone(220.0, 150.0, 0.2, 0.3, "square")
	_streams.coin = _chord([987.77, 1318.51], 0.25, 0.22)
	_streams["break"] = _tone(420.0, 90.0, 0.35, 0.4, "noise")
	_streams.hurt = _tone(330.0, 180.0, 0.16, 0.3, "square")


func play(name: String, pitch := 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()


func click() -> void:
	play("click", randf_range(0.95, 1.05))


func _tone(f0: float, f1: float, dur: float, vol: float, wave: String, vibrato := 0.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t) + sin(t * TAU * vibrato) * 30.0 * float(vibrato > 0.0)
		phase += f / RATE
		var s := 0.0
		match wave:
			"sine":
				s = sin(phase * TAU)
			"triangle":
				s = 1.0 - 4.0 * absf(fposmod(phase, 1.0) - 0.5)
			"square":
				s = 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
				s *= 0.5
			"noise":
				s = randf_range(-1.0, 1.0) * 0.7 + sin(phase * TAU) * 0.3
		var env := minf(t * 30.0, 1.0) * pow(1.0 - t, 2.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _chord(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / n
		var s := 0.0
		for k in freqs.size():
			var start := float(k) * 0.12
			if t >= start:
				var local := (t - start) / (1.0 - start)
				s += sin(float(i) / RATE * TAU * freqs[k]) * pow(1.0 - local, 2.0)
		var env := minf(t * 40.0, 1.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol / freqs.size() * 1.6, -1.0, 1.0) * 32767.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
