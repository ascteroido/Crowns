extends Node
## Sound effects. Crosses, erasing and the win play recordings from sounds/;
## the rest are synthesised at startup: wooden ticks for buttons and marimba
## notes for crowns, hints and conflicts.

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
	_streams.cross = load("res://sounds/create_X.ogg")
	_streams.erase = load("res://sounds/remove_x.mp3")
	_streams.win = load("res://sounds/complete_puzzle.wav")
	# Two rising notes, a fifth apart.
	_streams.crown = _render(0.8, func(t: float) -> float:
		return ((_marimba(t, _note(72), 0.18) * 0.8 + _marimba(t - 0.08, _note(79), 0.34)) * 0.45
				+ _knock(t, 600.0, 0.01) * 0.15))
	_streams.conflict = _render(0.4, func(t: float) -> float:
		return (_marimba(t, _note(52), 0.16) + _marimba(t, _note(53), 0.16)) * 0.24)
	_streams.hint = _render(0.6, func(t: float) -> float:
		return (_marimba(t, _note(79), 0.22) + _marimba(t - 0.09, _note(84), 0.28)) * 0.3)
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
