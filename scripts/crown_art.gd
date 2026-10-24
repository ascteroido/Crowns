extends RefCounted
## The crown drawn on the board, above the menu title and on the win panel:
## gold with a dark outline so it reads on every region colour.

const GOLD := Color("f4c542")
const GOLD_BAND := Color("d9a521")
const INK := Color("1e1e1e")

# In units of the square the crown is drawn in.
const OUTLINE: Array[Vector2] = [
	Vector2(0.22, 0.70), Vector2(0.17, 0.32), Vector2(0.36, 0.50), Vector2(0.50, 0.24),
	Vector2(0.64, 0.50), Vector2(0.83, 0.32), Vector2(0.78, 0.70),
]
const TIPS: Array[Vector2] = [Vector2(0.17, 0.30), Vector2(0.50, 0.21), Vector2(0.83, 0.30)]


static func draw(canvas: CanvasItem, rect: Rect2, fill := GOLD, band := GOLD_BAND, ink := INK) -> void:
	var s := rect.size.x
	var p := rect.position
	var points := PackedVector2Array()
	for v in OUTLINE:
		points.append(p + v * s)
	var band_rect := Rect2(p + Vector2(0.22, 0.74) * s, Vector2(0.56, 0.08) * s)
	var tip_radius := s * 0.045
	var w := maxf(1.0, s * 0.035)

	# The outline is the same shapes drawn a little larger in ink underneath;
	# circles at the corners round off the thick polyline's joints.
	var closed := points.duplicate()
	closed.append(points[0])
	canvas.draw_polyline(closed, ink, w * 2.0, true)
	for point in points:
		canvas.draw_circle(point, w, ink, true, -1.0, true)
	canvas.draw_rect(band_rect.grow(w), ink)
	for tip in TIPS:
		canvas.draw_circle(p + tip * s, tip_radius + w, ink, true, -1.0, true)

	canvas.draw_colored_polygon(points, fill)
	canvas.draw_rect(band_rect, band)
	for tip in TIPS:
		canvas.draw_circle(p + tip * s, tip_radius, fill, true, -1.0, true)
