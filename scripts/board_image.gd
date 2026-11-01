extends RefCounted
## A puzzle's empty board as an image, drawn like the board on a dark page: the
## regions' tiles, rounded, on the dark tray. For the Android widget, which
## can't run the game; plain Image calls, so it can be drawn off the main thread.

const BoardView := preload("res://scripts/board_view.gd")

## The image's width and height in pixels.
const SIDE := 288


static func render(size: int, regions: PackedInt32Array) -> Image:
	var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	var cell := float(SIDE) / size
	_rounded_rect(image, Rect2i(0, 0, SIDE, SIDE), roundi(cell * BoardView.RADIUS * 1.3), BoardView.TRAY_DARK)
	var gap := maxi(2, roundi(cell * BoardView.GAP))
	var radius := roundi(cell * BoardView.RADIUS)
	for row in size:
		for col in size:
			var left := roundi(col * cell) + gap / 2 + 1
			var top := roundi(row * cell) + gap / 2 + 1
			var tile := Rect2i(left, top, roundi((col + 1) * cell) - gap / 2 - 1 - left,
					roundi((row + 1) * cell) - gap / 2 - 1 - top)
			var region := regions[row * size + col]
			# Dimmed as on a dark page, so they don't glare.
			var fill := BoardView.REGION_COLORS[region % BoardView.REGION_COLORS.size()].darkened(0.18)
			_rounded_rect(image, tile, radius, fill)
	return image


## Fills `rect` with `color`, its corners rounded to `radius`.
static func _rounded_rect(image: Image, rect: Rect2i, radius: int, color: Color) -> void:
	radius = mini(radius, mini(rect.size.x, rect.size.y) / 2)
	image.fill_rect(Rect2i(rect.position.x + radius, rect.position.y, rect.size.x - 2 * radius, rect.size.y), color)
	image.fill_rect(Rect2i(rect.position.x, rect.position.y + radius, rect.size.x, rect.size.y - 2 * radius), color)
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		# The corner circle's centre, and the square of pixels it rounds.
		var centre := Vector2(rect.position.x + radius + corner.x * (rect.size.x - 2 * radius),
				rect.position.y + radius + corner.y * (rect.size.y - 2 * radius))
		var from := Vector2i(rect.position.x + corner.x * (rect.size.x - radius), rect.position.y + corner.y * (rect.size.y - radius))
		for y in range(from.y, from.y + radius):
			for x in range(from.x, from.x + radius):
				var reach := Vector2(x + 0.5, y + 0.5).distance_to(centre)
				if reach <= radius:
					image.set_pixel(x, y, color)
				elif reach < radius + 1.0:
					# Soften the edge over one pixel.
					image.set_pixel(x, y, image.get_pixel(x, y).blend(Color(color, color.a * (radius + 1.0 - reach))))
