extends Node
## The Android app icon: the classic purple one or a variant to match a theme.
## The DailyReminder plugin (addons/DailyReminder) carries the icons, each a
## launcher entry that opens the game without tying it to that entry, so the
## icon can change while the game runs. Everywhere but Android it's a no-op.

const CLASS := "com.ascathelstan.crowns.icon.AppIcon"
## Icons in the order Settings lists them; all but "classic" are plugin variants.
const ICONS := ["classic", "dark", "midnight", "forest", "contrast"]

var _app_icon: JavaClass
var _context: JavaObject


func _ready() -> void:
	if OS.get_name() != "Android":
		return
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	_app_icon = JavaClassWrapper.wrap(CLASS)
	if runtime == null or _app_icon == null:
		_app_icon = null
		return
	_context = runtime.getApplicationContext()


func available() -> bool:
	return _app_icon != null


## Shows `icon` (one of ICONS; anything else means the classic one). Only
## launcher entries in the wrong state change, so calling it again is cheap.
func set_icon(icon: String) -> void:
	if _app_icon:
		_app_icon.setIcon(_context, icon if icon in ICONS else "classic")
