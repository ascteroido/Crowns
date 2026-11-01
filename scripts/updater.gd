extends Node
## Checks GitHub for a newer release on start. The APK published outside Google
## Play downloads it and hands it to Android's installer (the Updater library in
## addons/DailyReminder, only in that build); desktop builds point to the release
## page. Play updates its own build, and the editor, tests and web build never check.

signal update_found(version: String)
signal download_progress(fraction: float)
## `path` is the downloaded APK, or "" when the download failed.
signal download_finished(path: String)

const RELEASES := "https://api.github.com/repos/ascteroido/Crowns/releases?per_page=20"
const CLASS := "com.ascathelstan.crowns.updater.Updater"
const DOWNLOADS := "user://updates"

## The newer release found: {"version", "page", "apk"}, or {} for none.
var release := {}
var _updater: JavaClass
var _context: JavaObject
var _request: HTTPRequest
var _download: HTTPRequest


func _ready() -> void:
	if OS.get_name() == "Android" and OS.has_feature("no_google"):
		var runtime: Object = Engine.get_singleton("AndroidRuntime")
		_updater = JavaClassWrapper.wrap(CLASS)
		if runtime == null or _updater == null:
			_updater = null
		else:
			_context = runtime.getApplicationContext()
	# Downloads from before the last update are done with.
	if DirAccess.dir_exists_absolute(DOWNLOADS):
		for file in DirAccess.get_files_at(DOWNLOADS):
			DirAccess.remove_absolute(DOWNLOADS.path_join(file))


func _process(_delta: float) -> void:
	if _download and _download.get_body_size() > 0:
		download_progress.emit(float(_download.get_downloaded_bytes()) / _download.get_body_size())


## Whether this build checks for updates: the APK from outside Google Play, or
## an exported desktop build.
func available() -> bool:
	return _updater != null or (OS.has_feature("pc") and not OS.has_feature("editor"))


## Whether this build can install an update itself, rather than open its page.
func installs() -> bool:
	return _updater != null


## Asks GitHub for its releases; update_found follows if one is newer.
func check() -> void:
	if not available() or _request:
		return
	_request = HTTPRequest.new()
	add_child(_request)
	_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		_request.queue_free()
		_request = null
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		release = newest(JSON.parse_string(body.get_string_from_utf8()), ProjectSettings.get_setting("application/config/version"),
				installs())
		if not release.is_empty():
			update_found.emit(release.version))
	_request.request(RELEASES, PackedStringArray(["User-Agent: Crowns", "Accept: application/vnd.github+json"]))


## Downloads the release's APK; download_progress, then download_finished, follow.
func download() -> void:
	if release.is_empty() or release.apk.is_empty() or _download:
		return
	DirAccess.make_dir_recursive_absolute(DOWNLOADS)
	var path := DOWNLOADS.path_join("Crowns-%s.apk" % release.version)
	_download = HTTPRequest.new()
	_download.download_file = path
	add_child(_download)
	_download.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_download.queue_free()
		_download = null
		var done := result == HTTPRequest.RESULT_SUCCESS and code == 200
		if not done:
			DirAccess.remove_absolute(path)
		download_finished.emit(ProjectSettings.globalize_path(path) if done else ""))
	if _download.request(release.apk, PackedStringArray(["User-Agent: Crowns"])) != OK:
		_download.queue_free()
		_download = null
		download_finished.emit("")


## Whether Android lets the game install apps; if not, open_install_settings() asks.
func can_install() -> bool:
	return _updater != null and _updater.canInstall(_context)


func open_install_settings() -> void:
	if _updater:
		_updater.openInstallSettings(_context)


## Hands a downloaded APK to Android's installer, which asks the player to
## confirm. Returns "" once handed over, or what went wrong.
func install(path: String) -> String:
	if not _updater:
		return "no installer"
	return _updater.install(_context, path)


## The newest of GitHub's `releases` (its API's list) that's newer than `current`,
## as {"version", "page", "apk"}, or {} when there's none. Drafts are skipped,
## prereleases count; with `need_apk`, so are releases without an Android APK.
static func newest(releases: Variant, current: String, need_apk: bool) -> Dictionary:
	var best := {}
	if not releases is Array:
		return best
	for entry: Variant in releases:
		if not entry is Dictionary or entry.get("draft", false):
			continue
		var version: String = str(entry.get("tag_name", "")).trim_prefix("v")
		if not is_newer(version, current) or (not best.is_empty() and not is_newer(version, best.version)):
			continue
		var apk := ""
		for asset: Variant in entry.get("assets", []):
			if asset is Dictionary and str(asset.get("name", "")).ends_with("-android.apk"):
				apk = str(asset.get("browser_download_url", ""))
		if need_apk and apk.is_empty():
			continue
		best = {"version": version, "page": str(entry.get("html_url", "")), "apk": apk}
	return best


## Whether version `a` ("1.2", "1.10") is newer than `b`, part by part.
static func is_newer(a: String, b: String) -> bool:
	var left := a.split(".")
	var right := b.split(".")
	for i in maxi(left.size(), right.size()):
		var x := left[i].to_int() if i < left.size() else 0
		var y := right[i].to_int() if i < right.size() else 0
		if x != y:
			return x > y
	return false
