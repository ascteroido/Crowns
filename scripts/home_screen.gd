extends Node
## The game on Android's home screen: the app icon's long-press shortcuts, the
## daily puzzle widget, and what a shortcut, the widget or the reminder asked
## the game to open. The DailyReminder plugin (addons/DailyReminder) carries
## them; everywhere but Android every call is a no-op.

const SHORTCUTS_CLASS := "com.ascathelstan.crowns.icon.Shortcuts"
const WIDGET_CLASS := "com.ascathelstan.crowns.widget.Widget"

var _shortcuts: JavaClass
var _widget: JavaClass
var _context: JavaObject


func _ready() -> void:
	if OS.get_name() != "Android":
		return
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	_shortcuts = JavaClassWrapper.wrap(SHORTCUTS_CLASS)
	_widget = JavaClassWrapper.wrap(WIDGET_CLASS)
	if runtime == null or _shortcuts == null or _widget == null:
		_shortcuts = null
		_widget = null
		return
	_context = runtime.getApplicationContext()


func available() -> bool:
	return _shortcuts != null


## Labels the shortcuts to today's daily, this week's weekly and the numbered puzzles.
func set_shortcuts(daily: String, weekly: String, resume: String) -> void:
	if _shortcuts:
		_shortcuts.setShortcuts(_context, daily, weekly, resume)


## What the player tapped to open the game, once: "daily", "weekly", "continue",
## or "" for nothing in particular.
func take_open() -> String:
	if not _shortcuts:
		return ""
	return _shortcuts.takeOpen(_context)


## The widget shows `solved_text` while `solved_date` is today's daily, else
## `ready_text`, and `streak_text` while the streak's last daily, `streak_date`,
## is today's or yesterday's. Dates are on the daily calendar, which turns over
## at midnight `offset` seconds from UTC. `board_folder` (a system path) holds
## each day's board as daily-YYYY-MM-DD.png, with its size and difficulty in
## daily-YYYY-MM-DD.txt.
func update_widget(title: String, ready_text: String, solved_date: String, solved_text: String,
		streak_date: String, streak_text: String, offset: int, board_folder: String) -> void:
	if _widget:
		_widget.update(_context, title, ready_text, solved_date, solved_text, streak_date, streak_text, offset,
				board_folder)
