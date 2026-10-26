extends Node
## The daily puzzle reminder, an Android notification at a chosen time each day.
## The DailyReminder plugin (addons/DailyReminder) shows it and keeps it going
## while the game is closed; everywhere else every call is a no-op.

## Emitted after the player answers the notification permission prompt.
signal permission_answered(granted: bool)

const CLASS := "com.ascathelstan.crowns.reminder.Reminder"
const PERMISSION := "android.permission.POST_NOTIFICATIONS"

var _reminder: JavaClass
var _context: JavaObject


func _ready() -> void:
	if OS.get_name() != "Android":
		return
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	_reminder = JavaClassWrapper.wrap(CLASS)
	if runtime == null or _reminder == null:
		_reminder = null
		return
	_context = runtime.getApplicationContext()
	get_tree().on_request_permissions_result.connect(_on_permission_result)


func available() -> bool:
	return _reminder != null


## Reminds every day at hour:minute local time, from the first such time at or
## after the unix time `not_before`: the next daily once today's is solved.
func schedule(hour: int, minute: int, not_before: int, channel_name: String, title: String, text: String) -> void:
	if _reminder:
		_reminder.schedule(_context, hour, minute, not_before * 1000, channel_name, title, text)


func cancel() -> void:
	if _reminder:
		_reminder.cancel(_context)


## Asks for permission to notify where Android needs it (13 and up). Returns true
## when it's already granted; otherwise permission_answered follows the prompt.
func request_permission() -> bool:
	if not _reminder or PERMISSION in OS.get_granted_permissions():
		return true
	return OS.request_permission(PERMISSION)


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission == PERMISSION:
		permission_answered.emit(granted)
