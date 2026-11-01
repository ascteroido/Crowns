@tool
extends EditorPlugin
## Adds the reminder library to Android exports, and the updater library to the
## one published outside Google Play. Rebuild them with build.sh after changing
## anything in android/ or updater/.

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "DailyReminder"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var libraries := PackedStringArray(["DailyReminder/bin/DailyReminder.aar"])
		# The updater only goes in the APK published outside Google Play, whose
		# policy doesn't allow apps to update themselves.
		if "no_google" in get_export_preset().get_custom_features().split(",", false):
			libraries.append("DailyReminder/bin/Updater.aar")
		return libraries
