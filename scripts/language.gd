extends RefCounted
## Languages: each .po file in res://translations/ adds one, and the player picks
## from them in Settings. Without a choice the game follows the device's language,
## falling back to English, the language the game is written in.

const DIR := "res://translations/"
## The language of the strings in the code.
const SOURCE := "en"

static var _loaded := false


## Registers every translation file once; later calls do nothing.
static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for file in ResourceLoader.list_directory(DIR):
		if file.get_extension() == "po":
			var translation := load(DIR + file) as Translation
			if translation:
				TranslationServer.add_translation(translation)


## English first, then the translated languages in alphabetical order of locale.
static func locales() -> PackedStringArray:
	load_all()
	var found := TranslationServer.get_loaded_locales()
	found.sort()
	var result := PackedStringArray([SOURCE])
	for locale in found:
		if locale != SOURCE:
			result.append(locale)
	return result


## Switches to `locale`, or to the device's language when it is empty.
static func apply(locale: String) -> void:
	load_all()
	TranslationServer.set_locale(OS.get_locale() if locale.is_empty() else locale)


## A language's name in that language, as its translators wrote it.
static func native_name(locale: String) -> String:
	if locale == SOURCE:
		return "English"
	var translation := TranslationServer.get_translation_object(locale)
	if translation:
		var name := translation.get_message("English", "language name")
		if not name.is_empty():
			return name
	return TranslationServer.get_locale_name(locale)
