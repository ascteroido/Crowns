extends Node
## Online leaderboards through SilentWolf (silentwolf.com), for desktop, web and
## the Android build outside Google Play. Talks to its REST API directly.
##
## Boards are made on first use: "daily-YYYY-MM-DD" and "weekly-YYYY-MM-DD" (the
## week's Sunday) hold times, "climb" holds best runs and "solved" puzzles solved.
## SilentWolf ranks higher scores first, so times are sent as negative milliseconds.
## Every save is kept, so reads collapse each player to their best entry, and
## players are told apart by a random id in the metadata rather than by name.

## Emitted when the scores waiting to be sent change, so they can be saved.
signal pending_changed(pending: Array)

const KEY_SCRIPT := "res://scripts/silent_wolf_key.gd"
const API := "https://api.silentwolf.com/"
## The plugin version whose request format this follows.
const PLUGIN_VERSION := "0.9.9"
const NAME_LENGTH := 16

## Tests set this: the key file is ignored, so boards are off until a test sets
## api_key, and requests are recorded in `sent` instead of going out.
static var offline := false

var game_id := ""
var api_key := ""
## Scores that couldn't be sent yet, as [board, player_id, name, score].
var pending: Array = []
## Requests made while offline, as [method, board, ...].
var sent: Array = []
## Answers for fetch() while offline: board -> raw score entries.
var fake_scores := {}
## Set while retry() works through `pending`, so a second call doesn't send twice.
var _sending := false


func _ready() -> void:
	# The Google Play build uses Play Games instead, and ships without the key too.
	if ResourceLoader.exists(KEY_SCRIPT) and not offline and not OS.has_feature("play_store"):
		var key: Script = load(KEY_SCRIPT)
		game_id = key.GAME_ID
		api_key = key.API_KEY


func available() -> bool:
	return not api_key.is_empty()


static func daily_board(date: String) -> String:
	return "daily-" + date


static func weekly_board(week_start: String) -> String:
	return "weekly-" + week_start


static func time_score(seconds: float) -> int:
	return -roundi(seconds * 1000.0)


## A name as the boards accept it: trimmed, one line, at most NAME_LENGTH long.
static func clean_name(text: String) -> String:
	return text.replace("\n", " ").strip_edges().left(NAME_LENGTH).strip_edges()


## Sends `score` to `board`. Anything that fails is kept in `pending` and sent
## with the next score or retry().
func submit(board: String, player_id: String, player_name: String, score: int) -> void:
	pending.append([board, player_id, player_name, score])
	pending_changed.emit(pending)
	await retry()


## Sends the scores still waiting, oldest first; stops at the first failure.
func retry() -> void:
	if _sending:
		return
	_sending = true
	while not pending.is_empty() and available():
		var entry: Array = pending[0]
		if not await _save(entry[0], entry[1], entry[2], entry[3]):
			break
		pending.remove_at(0)
		pending_changed.emit(pending)
	_sending = false


## The board's best entry per player, best first: [{"name", "score", "id"}].
## Empty when the board has no scores; null when it can't be reached.
func fetch(board: String, count := 25) -> Variant:
	var raw: Array
	if offline:
		sent.append(["fetch", board])
		raw = fake_scores.get(board, [])
	else:
		var url := API + "get_scores/%s?max=100&ldboard_name=%s&period_offset=0" % [game_id, board]
		var data: Variant = await _request(url, HTTPClient.METHOD_GET, _headers())
		if data == null:
			return null
		raw = data.get("top_scores", [])
	return best_per_player(raw).slice(0, count)


## Collapses raw SilentWolf entries ({"pn", "s", "t", "md"}) to each player's
## best score, under the name they used most recently, sorted best first.
static func best_per_player(raw: Array) -> Array:
	var best := {}
	var latest := {}
	for entry: Dictionary in raw:
		var metadata: Variant = entry.get("md", {})
		var id: String = metadata.get("id", "") if metadata is Dictionary else ""
		var key := id if not id.is_empty() else "name:" + str(entry.get("pn", ""))
		if not best.has(key) or entry.s > best[key].score:
			best[key] = {"name": str(entry.get("pn", "")), "score": int(entry.s), "id": id}
		if not latest.has(key) or entry.get("t", 0.0) > latest[key][0]:
			latest[key] = [entry.get("t", 0.0), str(entry.get("pn", ""))]
	var result := []
	for key: String in best:
		best[key].name = latest[key][1]
		result.append(best[key])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return result


func _save(board: String, player_id: String, player_name: String, score: int) -> bool:
	if offline:
		sent.append(["save", board, player_id, player_name, score])
		return true
	var payload := {"score_id": _uuid(), "player_name": player_name, "game_id": game_id, "score": score,
			"ldboard_name": board, "metadata": {"id": player_id}}
	# SilentWolf's anti-tamper check: an MD5 of the name, score and a timestamp,
	# where the timestamp is only the current time's milliseconds part (0-999).
	var now := Time.get_unix_time_from_system()
	var stamp := roundi((now - floorf(now)) * 1000.0)
	var headers := _headers()
	headers.append_array(["Content-Type: application/json", "x-sw-act-tmst: %d" % stamp,
			"x-sw-act-dig: " + (player_name + str(score) + str(stamp)).md5_text()])
	return await _request(API + "save_score", HTTPClient.METHOD_POST, headers, JSON.stringify(payload)) != null


func _headers() -> PackedStringArray:
	return PackedStringArray(["x-api-key: " + api_key, "x-sw-game-id: " + game_id,
			"x-sw-plugin-version: " + PLUGIN_VERSION, "x-sw-godot-version: " + Engine.get_version_info().string])


## The response's JSON when it reports success, otherwise null.
func _request(url: String, method: int, headers: PackedStringArray, body := "") -> Variant:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	if http.request(url, headers, method, body) != OK:
		http.queue_free()
		return null
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return null
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return data if data is Dictionary and data.get("success", false) else null


static func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]
