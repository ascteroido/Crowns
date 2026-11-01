extends Control
## A year of days played, as on a wall calendar turned on its side: a column
## per week, Sunday at the top, today's week on the right, each day shaded by
## how many puzzles were solved. Takes its colours from the theme.

const WEEKS := 53
## Gap between days, as a fraction of a day's square.
const GAP := 0.22
const FONT_SIZE := 12
## Solves a day needs for each shade after the first.
const LEVELS := [1, 2, 4, 7]

## "YYYY-MM-DD" -> puzzles solved that day.
var days := {}:
	set(value):
		days = value
		queue_redraw()
## Today, "YYYY-MM-DD", the grid's last day.
var today := "":
	set(value):
		today = value
		queue_redraw()
## Short month names, January first, for the labels along the top.
var month_names: Array = []
## Turns a date and its count into a tooltip, e.g. "Oct 23 · 3 puzzles".
var describe := func(_date: String, count: int) -> String: return str(count)


func _ready() -> void:
	resized.connect(_fit_height)
	_fit_height()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_fit_height()
		queue_redraw()


func _fit_height() -> void:
	custom_minimum_size.y = _label_height() + _cell() * 7


## The shade for `count` solves: 0 for none, up to LEVELS.size().
static func level(count: int) -> int:
	var shade := 0
	for least: int in LEVELS:
		if count >= least:
			shade += 1
	return shade


## The colour of shade `shade`, from the theme's text and button colours.
func shade_color(shade: int) -> Color:
	var text := get_theme_color("font_color", "Label")
	if shade == 0:
		return Color(text, 0.09)
	var fill := text
	var button := get_theme_stylebox("normal", "Button")
	if button is StyleBoxFlat:
		fill = button.bg_color.lerp(text, 0.1)
		# On a dark page (light text), brightened so it shows, keeping its hue.
		if text.get_luminance() > 0.5:
			var bright: Color = button.bg_color
			fill = Color.from_hsv(bright.h, bright.s * 0.75, maxf(bright.v, 0.85))
	return Color(fill, [0.3, 0.55, 0.8, 1.0][shade - 1])


func _cell() -> float:
	return size.x / WEEKS


func _label_height() -> float:
	return TextSize.scaled(FONT_SIZE) * 1.6


## The date of the grid's first square, the Sunday 52 weeks before today's.
func _start() -> int:
	var now := Time.get_unix_time_from_datetime_string(today)
	return now - (52 * 7 + Time.get_datetime_dict_from_unix_time(now).weekday) * 86400


func _draw() -> void:
	if today.is_empty() or size.x <= 0.0:
		return
	var cell := _cell()
	var top := _label_height()
	var font := get_theme_default_font()
	var font_size := TextSize.scaled(FONT_SIZE)
	var text := get_theme_color("font_color", "Label")
	var start := _start()
	var end := Time.get_unix_time_from_datetime_string(today)
	var rtl := is_layout_rtl()
	var last_month := -1
	for week in WEEKS:
		var x := (WEEKS - 1 - week if rtl else week) * cell
		# A month's name over the first week that starts in it, if there's room before the next.
		var sunday := Time.get_date_dict_from_unix_time(start + week * 7 * 86400)
		if sunday.month != last_month and not month_names.is_empty():
			if last_month >= 0 and week < WEEKS - 2:
				var name: String = month_names[sunday.month - 1]
				var label_x := x - font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + cell if rtl else x
				draw_string(font, Vector2(label_x, font_size), name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
						Color(text, 0.6))
			last_month = sunday.month
		for day in 7:
			var unix := start + (week * 7 + day) * 86400
			if unix > end:
				break
			var count: int = days.get(Time.get_date_string_from_unix_time(unix), 0)
			var square := Rect2(x + cell * GAP / 2.0, top + day * cell + cell * GAP / 2.0,
					cell * (1.0 - GAP), cell * (1.0 - GAP))
			draw_rect(square, shade_color(level(count)))


func _get_tooltip(at_position: Vector2) -> String:
	if today.is_empty():
		return ""
	var cell := _cell()
	var week := floori(at_position.x / cell)
	var day := floori((at_position.y - _label_height()) / cell)
	if is_layout_rtl():
		week = WEEKS - 1 - week
	if week < 0 or week >= WEEKS or day < 0 or day >= 7:
		return ""
	var unix := _start() + (week * 7 + day) * 86400
	if unix > Time.get_unix_time_from_datetime_string(today):
		return ""
	var date := Time.get_date_string_from_unix_time(unix)
	return describe.call(date, days.get(date, 0))
