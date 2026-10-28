extends SceneTree
## Makes the Android app icon variants from the classic icon's layers in
## res://icons/, into the DailyReminder plugin's resources:
##   godot --headless --path . --script res://tools/make_icons.gd
## then rebuild the plugin with addons/DailyReminder/build.sh.
##
## Each variant keeps the gold crown and the classic icon's soft radial shading,
## on its own colour. The plugin's manifest has a launcher entry per variant,
## and scripts/app_icon.gd switches between them.

## Variant -> the background's colour at its centre. Names match the manifest's
## activity aliases and scripts/app_icon.gd.
const VARIANTS := {
	"dark": Color("34343a"),
	"midnight": Color("1f3357"),
	"forest": Color("4f8a48"),
	"contrast": Color("000000"),
}
## How much darker the classic background is in its corners than its centre.
const SHADE := 0.155
const ADAPTIVE := 432
const LEGACY := 192
## The classic legacy icon's crown is this much larger than the adaptive one's.
const LEGACY_CROWN_SCALE := 0.675
const OUT := "res://addons/DailyReminder/android/res/"


func _init() -> void:
	var foreground := _load("res://icons/adaptive_foreground.png")
	var monochrome := _load("res://icons/adaptive_monochrome.png")
	# The classic legacy icon's rounded square, to cut the variants to.
	var shape := _load("res://icons/icon_192.png")
	shape.convert(Image.FORMAT_RGBA8)
	_save(foreground, "drawable-nodpi/crowns_icon_foreground.png")
	_save(monochrome, "drawable-nodpi/crowns_icon_monochrome.png")

	var legacy_crown := foreground.duplicate()
	var crown_size := roundi(ADAPTIVE * LEGACY_CROWN_SCALE)
	legacy_crown.resize(crown_size, crown_size, Image.INTERPOLATE_LANCZOS)
	for variant: String in VARIANTS:
		var background := _shaded(ADAPTIVE, VARIANTS[variant])
		_save(background, "drawable-nodpi/crowns_icon_%s_background.png" % variant)

		# Android 7 has no adaptive icons, so it gets a finished square.
		var legacy := _shaded(LEGACY, VARIANTS[variant])
		var offset := (LEGACY - crown_size) / 2
		legacy.blend_rect(legacy_crown, Rect2i(Vector2i.ZERO, legacy_crown.get_size()), Vector2i(offset, offset))
		for y in LEGACY:
			for x in LEGACY:
				var pixel := legacy.get_pixel(x, y)
				pixel.a *= shape.get_pixel(x, y).a
				legacy.set_pixel(x, y, pixel)
		_save(legacy, "mipmap-nodpi/crowns_icon_%s.png" % variant)

		var xml_path := ProjectSettings.globalize_path(OUT + "mipmap-anydpi-v26/crowns_icon_%s.xml" % variant)
		DirAccess.make_dir_recursive_absolute(xml_path.get_base_dir())
		var xml := FileAccess.open(xml_path, FileAccess.WRITE)
		xml.store_string(("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
				+ "<!-- Made by tools/make_icons.gd. -->\n"
				+ "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
				+ "\t<background android:drawable=\"@drawable/crowns_icon_%s_background\" />\n"
				+ "\t<foreground android:drawable=\"@drawable/crowns_icon_foreground\" />\n"
				+ "\t<monochrome android:drawable=\"@drawable/crowns_icon_monochrome\" />\n"
				+ "</adaptive-icon>\n") % variant)
		xml.close()
	print("Wrote the icon variants to %s" % OUT)
	quit()


## A square of `color`, darkening towards the corners like the classic icon.
func _shaded(size: int, color: Color) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) / 2.0
	var corner := center.length()
	for y in size:
		for x in size:
			var t := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center) / corner
			image.set_pixel(x, y, color.lerp(color.darkened(SHADE), t))
	return image


func _load(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _save(image: Image, file: String) -> void:
	var path := ProjectSettings.globalize_path(OUT + file)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)
