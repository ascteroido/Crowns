extends SceneTree
## Rebuilds translations/crowns.pot, the template translators start each language from,
## out of the tr() and tr_n() calls in scripts/:
##   godot --headless --path . --script res://tools/update_pot.gd
## A "# TRANSLATORS:" comment just above a call becomes a note for translators.

const SCRIPTS := "res://scripts/"
const OUTPUT := "res://translations/crowns.pot"
const STRING := "\"((?:[^\"\\\\]|\\\\.)*)\""


func _init() -> void:
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(build())
	file.close()
	print("Wrote ", OUTPUT)
	quit()


## The template's text.
static func build() -> String:
	# Keyed by context + "\u0004" + msgid, in order of first use.
	var entries := {}
	# Not in the code: each language's own name, shown in the Settings picker.
	_add(entries, "English", "", "language name", "Your language's name, written in your language (e.g. Deutsch, Français).", "")
	var call := RegEx.create_from_string("\\btr\\(\\s*" + STRING + "(?:\\s*,\\s*" + STRING + ")?\\s*\\)")
	var plural_call := RegEx.create_from_string("\\btr_n\\(\\s*" + STRING + "\\s*,\\s*" + STRING)
	var files := Array(DirAccess.get_files_at(SCRIPTS))
	files.sort()
	for name: String in files:
		if name.get_extension() != "gd":
			continue
		var lines := FileAccess.get_file_as_string(SCRIPTS + name).split("\n")
		for i in lines.size():
			var note := _note_above(lines, i)
			var where := "scripts/%s:%d" % [name, i + 1]
			for found in call.search_all(lines[i]):
				_add(entries, found.get_string(1), "", found.get_string(2), note, where)
			for found in plural_call.search_all(lines[i]):
				_add(entries, found.get_string(1), found.get_string(2), "", note, where)

	var out := PackedStringArray([
		"# Translation template for Crowns. See translations/README.md.",
		"msgid \"\"",
		"msgstr \"\"",
		"\"Project-Id-Version: Crowns\\n\"",
		"\"MIME-Version: 1.0\\n\"",
		"\"Content-Type: text/plain; charset=UTF-8\\n\"",
		"\"Content-Transfer-Encoding: 8bit\\n\"",
		"",
	])
	for entry: Dictionary in entries.values():
		for note: String in entry.notes:
			out.append("#. " + note)
		if not entry.where.is_empty():
			out.append("#: " + " ".join(entry.where))
		if not entry.context.is_empty():
			out.append("msgctxt \"%s\"" % entry.context)
		out.append("msgid \"%s\"" % entry.id)
		if entry.plural.is_empty():
			out.append("msgstr \"\"")
		else:
			out.append("msgid_plural \"%s\"" % entry.plural)
			out.append("msgstr[0] \"\"")
			out.append("msgstr[1] \"\"")
		out.append("")
	return "\n".join(out)


static func _add(entries: Dictionary, id: String, plural: String, context: String, note: String, where: String) -> void:
	var key := context + "\u0004" + id
	if not entries.has(key):
		entries[key] = {"id": id, "plural": plural, "context": context, "notes": PackedStringArray(),
				"where": PackedStringArray()}
	var entry: Dictionary = entries[key]
	if not note.is_empty() and note not in entry.notes:
		entry.notes.append(note)
	if not where.is_empty():
		entry.where.append(where)


## The "# TRANSLATORS:" comment in the block of comment lines directly above line `index`.
static func _note_above(lines: PackedStringArray, index: int) -> String:
	var comments := PackedStringArray()
	var i := index - 1
	while i >= 0 and lines[i].strip_edges().begins_with("#"):
		comments.insert(0, lines[i].strip_edges().trim_prefix("#").strip_edges())
		i -= 1
	var text := " ".join(comments)
	var start := text.find("TRANSLATORS:")
	return "" if start < 0 else text.substr(start + "TRANSLATORS:".length()).strip_edges()
