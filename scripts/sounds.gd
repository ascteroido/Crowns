extends Node
## Sound effects, synthesised at startup so the game ships no audio files.
## Bubble pops for crosses, an eraser smudge for erasing, wooden ticks for
## buttons and marimba notes for crowns and wins.

## Plenty for soft percussion, and half the startup work of 44.1 kHz.
const RATE := 22050
const VOICES := 8
## A cross sound at most this often, so fast drags patter instead of buzzing.
const CROSS_GAP_MS := 35

var enabled := true

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_cross := -CROSS_GAP_MS


func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_streams.click = _render(0.05, func(t: float) -> float: return _knock(t, 1700.0, 0.006) * 0.22)
	_streams.cross = _render(0.1, func(t: float) -> float: return _bubble(t, 280.0, 850.0, 0.03) * 0.5)
	_streams.erase = _render(0.16, _smudge(0.16, 0.55))
	# Two rising notes, a fifth apart.
	_streams.crown = _render(0.8, func(t: float) -> float:
		return ((_marimba(t, _note(72), 0.18) * 0.8 + _marimba(t - 0.08, _note(79), 0.34)) * 0.45
				+ _knock(t, 600.0, 0.01) * 0.15))
	_streams.conflict = _render(0.4, func(t: float) -> float:
		return (_marimba(t, _note(52), 0.16) + _marimba(t, _note(53), 0.16)) * 0.24)
	_streams.hint = _render(0.6, func(t: float) -> float:
		return (_marimba(t, _note(79), 0.22) + _marimba(t - 0.09, _note(84), 0.28)) * 0.3)
	# A rising arpeggio that settles on a chord.
	_streams.win = _render(1.6, func(t: float) -> float:
		var notes := [[0.0, 72], [0.09, 76], [0.18, 79], [0.3, 84]]
		var sum := 0.0
		for n: Array in notes:
			sum += _marimba(t - n[0], _note(n[1]), 0.5)
		return sum * 0.28)
	_streams.fail = _render(1.0, func(t: float) -> float:
		var notes := [[0.0, 67], [0.16, 63], [0.32, 60]]
		var sum := 0.0
		for n: Array in notes:
			sum += _marimba(t - n[0], _note(n[1]), 0.35)
		return sum * 0.3)


func play(sound: String) -> void:
	if not enabled or not _streams.has(sound):
		return
	if sound == "cross":
		var now := Time.get_ticks_msec()
		if now - _last_cross < CROSS_GAP_MS:
			return
		_last_cross = now
	var player := _players[_next]
	_next = (_next + 1) % VOICES
	player.stream = _streams[sound]
	# A little variation keeps repeated taps from sounding mechanical.
	player.pitch_scale = randf_range(0.96, 1.04) if sound in ["click", "cross", "erase"] else 1.0
	player.play()


## Frequency of a MIDI note number (60 is middle C).
func _note(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## A struck wooden bar: a few inharmonic partials that die away quickly.
func _knock(t: float, freq: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	var attack := minf(1.0, t / 0.001)
	return attack * (sin(TAU * freq * t) * exp(-t / decay)
			+ 0.5 * sin(TAU * freq * 2.76 * t) * exp(-t / (decay * 0.6))
			+ 0.25 * sin(TAU * freq * 5.4 * t) * exp(-t / (decay * 0.35)))


## A bubble pop: a pure tone that sweeps quickly upward as it dies away.
func _bubble(t: float, from_freq: float, to_freq: float, sweep: float) -> float:
	if t < 0.0:
		return 0.0
	# Phase of an exponential sweep from `from_freq` to `to_freq` over `sweep` seconds, then held.
	var ratio := to_freq / from_freq
	var k := log(ratio) / sweep
	var phase := from_freq * (exp(k * minf(t, sweep)) - 1.0) / k + to_freq * maxf(0.0, t - sweep)
	var attack := minf(1.0, t / 0.002)
	return attack * sin(TAU * phase) * exp(-t / 0.022)


## An eraser rubbing: noise through a band-pass filter whose centre slides down
## as it swells and fades. Returns a wave for _render, which keeps the filter state.
func _smudge(seconds: float, gain: float) -> Callable:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var filter := {"fast": 0.0, "slow": 0.0}
	var slow_coefficient := 1.0 - exp(-TAU * 300.0 / RATE)
	return func(t: float) -> float:
		var u := clampf(t / seconds, 0.0, 1.0)
		var fast_coefficient := 1.0 - exp(-TAU * lerpf(2400.0, 900.0, u) / RATE)
		filter.fast += fast_coefficient * (rng.randf_range(-1.0, 1.0) - filter.fast)
		filter.slow += slow_coefficient * (filter.fast - filter.slow)
		return (filter.fast - filter.slow) * pow(sin(PI * u), 1.5) * gain


## A marimba note: the fundamental plus the bar's bright fourth harmonic, which fades first.
func _marimba(t: float, freq: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	var attack := minf(1.0, t / 0.003)
	return attack * (sin(TAU * freq * t) * exp(-t / decay)
			+ 0.3 * sin(TAU * freq * 4.0 * t) * exp(-t / (decay * 0.18)))


func _render(seconds: float, wave: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		# Fade the last few milliseconds so nothing clicks when it ends.
		var tail := minf(1.0, (seconds - t) / 0.01)
		data.encode_s16(i * 2, int(clampf(wave.call(t) * tail, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
