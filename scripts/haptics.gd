extends Node
## Vibration on Android: a light tick for each cross or crown placed or
## removed, and a pattern that follows the win sound's beats. Elsewhere
## every call is a no-op.

## [start ms, length ms, strength 0-1] pulses matching complete_puzzle.wav: a
## light tap at 0.1 s, then the big hit at 0.3 s fading out by 0.6 s.
const WIN_PATTERN := [[85, 60, 0.5], [300, 90, 1.0], [390, 110, 0.55], [500, 110, 0.25]]
## A cross tick at most this often, like the cross sound, so fast drags don't buzz.
const CROSS_GAP_MS := 35

var enabled := true

var _available := OS.get_name() == "Android"
var _last_cross := -CROSS_GAP_MS


func available() -> bool:
	return _available


func cross() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cross < CROSS_GAP_MS:
		return
	_last_cross = now
	_buzz(12, 0.35)


## A softer tick for a cross or crown removed, sharing the cross's limit so a
## drag that clears crosses doesn't buzz on every cell either.
func erase() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cross < CROSS_GAP_MS:
		return
	_last_cross = now
	_buzz(8, 0.25)


func crown() -> void:
	_buzz(22, 0.7)


## Starts the win pattern; call it as the win sound starts.
func win() -> void:
	if not (_available and enabled):
		return
	# The sound reaches the speaker a little after play(); start the pulses with it.
	var delay := AudioServer.get_output_latency()
	for pulse: Array in WIN_PATTERN:
		get_tree().create_timer(delay + pulse[0] / 1000.0).timeout.connect(_buzz.bind(pulse[1], pulse[2]))


func _buzz(ms: int, strength: float) -> void:
	if _available and enabled:
		Input.vibrate_handheld(ms, strength)
