extends RefCounted
## Languages: each .po file in res://translations/ adds one, and the player picks
## from them in Settings. Without a choice the game follows the device's language,
## falling back to English, the language the game is written in.

const DIR := "res://translations/"
## The language of the strings in the code.
const SOURCE := "en"
## Every string there is to translate; translations are measured against it.
const TEMPLATE := DIR + "crowns.pot"

static var _loaded := false
static var _template_keys := PackedStringArray()


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


## How much of `locale` is translated, 0 to 1: the share of the template's
## strings it has a finished translation for. Fuzzy and empty entries don't count.
static func completion(locale: String) -> float:
	if locale == SOURCE:
		return 1.0
	var translation := TranslationServer.get_translation_object(locale)
	var keys := template_keys()
	if translation == null or keys.is_empty():
		return 0.0
	var translated := translation.get_message_list()
	var done := 0
	for key in keys:
		if key in translated:
			done += 1
	return float(done) / keys.size()


## The template's strings, in the form Translation.get_message_list() uses:
## "context\u0004text" for strings with a context, otherwise just the text.
static func template_keys() -> PackedStringArray:
	if _template_keys.is_empty():
		_template_keys = parse_keys(FileAccess.get_file_as_string(TEMPLATE))
	return _template_keys


static func parse_keys(po: String) -> PackedStringArray:
	var keys := PackedStringArray()
	var context := ""
	var id := ""
	var field := ""
	for line in po.split("\n"):
		line = line.strip_edges()
		if line.begins_with("\""):
			if field == "msgctxt":
				context += line.substr(1, line.length() - 2).c_unescape()
			elif field == "msgid":
				id += line.substr(1, line.length() - 2).c_unescape()
			continue
		if line.begins_with("msgctxt ") or line.begins_with("msgid "):
			if line.begins_with("msgctxt "):
				context = ""
				id = ""
			field = line.get_slice(" ", 0)
			var text := line.substr(field.length() + 2, line.length() - field.length() - 3).c_unescape()
			if field == "msgctxt":
				context = text
			else:
				id = text
		elif line.begins_with("msgid_plural") or line.begins_with("msgstr"):
			if field == "msgid" and not id.is_empty():
				keys.append(context + char(4) + id if not context.is_empty() else id)
			field = ""
			context = ""
			id = ""
	return keys
