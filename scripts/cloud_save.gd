extends RefCounted
## Progress kept in Google Play Games' saved games, so it follows the player
## between devices, or copied out as a backup code on devices without them.
## Devices merge rather than overwrite each other: solves and records from
## either side are kept. Settings stay with each device.

## Sections that belong to the device, not the player.
const LOCAL_ONLY := ["settings"]
## Recent solves kept per size for the solve history graph.
const HISTORY_LENGTH := 30
## Starts every backup code, with a version in case the format ever changes.
const BACKUP_PREFIX := "CROWNS1:"


## The progress to upload: everything but the device's settings.
static func pack(progress: ConfigFile) -> PackedByteArray:
	var copy := ConfigFile.new()
	for section in progress.get_sections():
		if section in LOCAL_ONLY:
			continue
		for key in progress.get_section_keys(section):
			copy.set_value(section, key, progress.get_value(section, key))
	# Base64 keeps the bytes plain ASCII on their way through the plugin's JSON.
	return Marshalls.utf8_to_base64(copy.encode_to_text()).to_ascii_buffer()


## The progress in `data`, or null when it is empty or unreadable.
static func unpack(data: PackedByteArray) -> ConfigFile:
	if data.is_empty():
		return null
	var progress := ConfigFile.new()
	if progress.parse(Marshalls.base64_to_utf8(data.get_string_from_ascii())) != OK:
		return null
	return progress


## Progress as a code to copy somewhere safe, for devices without cloud save:
## everything pack() would upload, compressed, as letters and digits.
static func backup_code(progress: ConfigFile) -> String:
	var copy := ConfigFile.new()
	for section in progress.get_sections():
		if section in LOCAL_ONLY:
			continue
		for key in progress.get_section_keys(section):
			copy.set_value(section, key, progress.get_value(section, key))
	var text := copy.encode_to_text().to_utf8_buffer()
	return BACKUP_PREFIX + str(text.size()) + ":" + Marshalls.raw_to_base64(text.compress(FileAccess.COMPRESSION_GZIP))


## The progress in a backup code, or null if it isn't one. Spaces and line
## breaks a messaging app might add are ignored.
static func from_backup_code(code: String) -> ConfigFile:
	var compact := "".join(code.split(" ", false)).replace("\n", "").replace("\r", "").replace("\t", "")
	if not compact.begins_with(BACKUP_PREFIX):
		return null
	var parts := compact.trim_prefix(BACKUP_PREFIX).split(":", true, 1)
	if parts.size() != 2 or not parts[0].is_valid_int():
		return null
	var packed := Marshalls.base64_to_raw(parts[1])
	if packed.is_empty():
		return null
	var text := packed.decompress(parts[0].to_int(), FileAccess.COMPRESSION_GZIP)
	if text.size() != parts[0].to_int():
		return null
	var progress := ConfigFile.new()
	if progress.parse(text.get_string_from_utf8()) != OK:
		return null
	return progress


## Puzzles solved, for Play Games to keep the furthest save when two devices conflict.
static func solved_count(progress: ConfigFile) -> int:
	var count := 0
	if progress.has_section("solved"):
		count = progress.get_section_keys("solved").size()
	return count + progress.get_value("stats", "climb_solved", 0)


## Folds `remote` into `local`, keeping the better of the two for each record.
static func merge(local: ConfigFile, remote: ConfigFile) -> void:
	for key in _keys(remote, "solved"):
		if remote.get_value("solved", key):
			local.set_value("solved", key, true)
	for key in _keys(remote, "best"):
		_keep_lower(local, remote, "best", key)
	# The first solve's date is the earlier of the two.
	for key in _keys(remote, "solved_on"):
		if not local.has_section_key("solved_on", key) or remote.get_value("solved_on", key) < local.get_value("solved_on", key):
			local.set_value("solved_on", key, remote.get_value("solved_on", key))
	_merge_stats(local, remote)
	_merge_history(local, remote)
	# Days played: the more solves of the two, so merging twice doesn't count twice.
	for key in _keys(remote, "calendar"):
		_keep_higher(local, remote, "calendar", key)

	_keep_higher(local, remote, "challenge", "best")
	if remote.has_section_key("speed", "best"):
		_keep_lower(local, remote, "speed", "best")
	# A run in progress here stays; otherwise pick up the one from the other device.
	if not local.has_section_key("challenge", "run") and remote.has_section_key("challenge", "run"):
		local.set_value("challenge", "run", remote.get_value("challenge", "run"))

	# Boards in progress: this device's stay, others are added unless already solved.
	for key in _keys(remote, "in_progress"):
		if not local.has_section_key("in_progress", key) and not local.get_value("solved", key, false):
			local.set_value("in_progress", key, remote.get_value("in_progress", key))
	if not local.has_section("last"):
		for key in _keys(remote, "last"):
			local.set_value("last", key, remote.get_value("last", key))


static func _merge_stats(local: ConfigFile, remote: ConfigFile) -> void:
	for key: String in _keys(remote, "stats"):
		if key.begins_with("best_"):
			_keep_lower(local, remote, "stats", key)
		elif key.begins_with("timed_"):
			# A size's total time goes with its count of timed solves.
			var time_key := "time_" + key.trim_prefix("timed_")
			if remote.get_value("stats", key) > local.get_value("stats", key, 0):
				local.set_value("stats", key, remote.get_value("stats", key))
				local.set_value("stats", time_key, remote.get_value("stats", time_key, 0.0))
		elif key.begins_with("time_"):
			continue
		elif key in ["streak", "last_daily"]:
			continue
		else:
			_keep_higher(local, remote, "stats", key)
	# The streak comes from whichever device solved a daily most recently.
	var remote_last: String = remote.get_value("stats", "last_daily", "")
	var local_last: String = local.get_value("stats", "last_daily", "")
	if remote_last > local_last or (remote_last == local_last
			and remote.get_value("stats", "streak", 0) > local.get_value("stats", "streak", 0)):
		local.set_value("stats", "last_daily", remote_last)
		local.set_value("stats", "streak", remote.get_value("stats", "streak", 0))


## Each size's recent solves from both devices, in order, without the ones
## both already share, trimmed to the most recent.
static func _merge_history(local: ConfigFile, remote: ConfigFile) -> void:
	for key in _keys(remote, "history"):
		var merged: Array = local.get_value("history", key, []).duplicate()
		for entry: Array in remote.get_value("history", key):
			if not merged.has(entry):
				merged.append(entry)
		merged.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		local.set_value("history", key, merged.slice(-HISTORY_LENGTH))


static func _keys(progress: ConfigFile, section: String) -> PackedStringArray:
	return progress.get_section_keys(section) if progress.has_section(section) else PackedStringArray()


static func _keep_lower(local: ConfigFile, remote: ConfigFile, section: String, key: String) -> void:
	if remote.get_value(section, key) < local.get_value(section, key, INF):
		local.set_value(section, key, remote.get_value(section, key))


static func _keep_higher(local: ConfigFile, remote: ConfigFile, section: String, key: String) -> void:
	if remote.has_section_key(section, key) and remote.get_value(section, key) > local.get_value(section, key, 0):
		local.set_value(section, key, remote.get_value(section, key))
