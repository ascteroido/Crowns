extends Control
## A gold crown that hops when it first appears, for titles and the win panel.

const CrownArt := preload("res://scripts/crown_art.gd")
const HOP_MS := 450.0

var _shown_at := -1


func _ready() -> void:
	visibility_changed.connect(hop)
	hop()


func hop() -> void:
	_shown_at = Time.get_ticks_msec()
	queue_redraw()


func _process(_delta: float) -> void:
	if _shown_at >= 0:
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	var t := (Time.get_ticks_msec() - _shown_at) / HOP_MS if _shown_at >= 0 else 1.0
	if t >= 1.0:
		_shown_at = -1
	else:
		rect.position.y -= sin(PI * t) * side * 0.15
	CrownArt.draw(self, rect)
