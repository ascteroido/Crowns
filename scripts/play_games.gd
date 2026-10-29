extends Node
## Google Play Games: leaderboards, achievements and the cloud save. Only active
## on Android with the plugin built in; everywhere else every call is a no-op.

## Emitted once the player is signed in, whether silently at start or after a prompt.
signal signed_in
## The cloud save's contents after load_cloud(); empty when there is none yet.
signal cloud_loaded(data: PackedByteArray)

const SignInClient := preload("res://addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd")
const LeaderboardsClient := preload("res://addons/GodotPlayGameServices/scripts/leaderboards/leaderboards_client.gd")
const AchievementsClient := preload("res://addons/GodotPlayGameServices/scripts/achievements/achievements_client.gd")
const SnapshotsClient := preload("res://addons/GodotPlayGameServices/scripts/snapshots/snapshots_client.gd")
const Variant_ := preload("res://addons/GodotPlayGameServices/scripts/leaderboards/leaderboard_variant.gd")

## Leaderboard IDs from the Play Console (Play Games Services > Leaderboards).
## Daily and weekly: Time format, smaller is better. The others: numeric, larger is better.
const DAILY_ID := "CgkIs_CWu6AOEAIQAg"
const WEEKLY_ID := "CgkIs_CWu6AOEAIQBQ"
const CLIMB_ID := "CgkIs_CWu6AOEAIQAw"
const SOLVED_ID := "CgkIs_CWu6AOEAIQAQ"
## Achievement IDs from the Play Console (Play Games Services > Achievements), by
## the names main.gd uses. Empty ones are skipped. See store/achievements/README.md.
const ACHIEVEMENTS := {
	"first_crown": "CgkIs_CWu6AOEAIQBg",
	"unaided": "CgkIs_CWu6AOEAIQBw",
	"hard": "CgkIs_CWu6AOEAIQCA",
	"big_board": "CgkIs_CWu6AOEAIQCQ",
	"weekly": "CgkIs_CWu6AOEAIQCg",
	"streak_7": "CgkIs_CWu6AOEAIQCw",
	"streak_30": "CgkIs_CWu6AOEAIQDA",
	"climb_10": "CgkIs_CWu6AOEAIQDQ",
	"climb_25": "CgkIs_CWu6AOEAIQDg",
	"quick": "CgkIs_CWu6AOEAIQDw",
	"century": "CgkIs_CWu6AOEAIQEA",
	"tutorial": "CgkIs_CWu6AOEAIQEQ",
	"custom": "CgkIs_CWu6AOEAIQEg",
	"speed_run": "CgkIs_CWu6AOEAIQEw",
	"weekly_10": "CgkIs_CWu6AOEAIQFA",
	"hard_plus": "CgkIs_CWu6AOEAIQFQ",
	"giant": "CgkIs_CWu6AOEAIQFg",
	"every_size": "CgkIs_CWu6AOEAIQFw",
	"perfect_month": "CgkIs_CWu6AOEAIQGA",
	"streak_100": "CgkIs_CWu6AOEAIQGQ",
	"thousand": "CgkIs_CWu6AOEAIQGg",
}
## The saved game's name in the player's cloud storage.
const SAVE_NAME := "progress"

var _available := false
var _signed_in := false
var _sign_in: Node
var _leaderboards: Node
var _achievements: Node
var _snapshots: Node
## What to open once a sign-in started for it finishes.
var _after_sign_in := Callable()
## Achievements unlocked this session, so each is sent only once.
var _sent := {}


func _ready() -> void:
	# The Android build for outside Google Play ("no_google") has no Play Games.
	if OS.get_name() != "Android" or OS.has_feature("no_google") or DAILY_ID.is_empty():
		return
	var services: Node = get_node_or_null("/root/GodotPlayGameServices")
	if services == null or services.initialize() != OK:
		return
	_available = true
	_sign_in = SignInClient.new()
	_leaderboards = LeaderboardsClient.new()
	_achievements = AchievementsClient.new()
	_snapshots = SnapshotsClient.new()
	for client in [_sign_in, _leaderboards, _achievements, _snapshots]:
		add_child(client)
	_sign_in.user_authenticated.connect(_on_authenticated)
	_snapshots.game_loaded.connect(func(snapshot: RefCounted) -> void:
		cloud_loaded.emit(snapshot.content if snapshot else PackedByteArray()))
	_sign_in.is_authenticated()


func available() -> bool:
	return _available


func is_signed_in() -> bool:
	return _signed_in


## Whether the weekly challenge has a leaderboard to submit to and show.
func has_weekly() -> bool:
	return _available and not WEEKLY_ID.is_empty()


func submit_daily_time(seconds: float) -> void:
	_submit(DAILY_ID, roundi(seconds * 1000.0))


func submit_weekly_time(seconds: float) -> void:
	_submit(WEEKLY_ID, roundi(seconds * 1000.0))


func submit_climb(cleared: int) -> void:
	_submit(CLIMB_ID, cleared)


func submit_solved(count: int) -> void:
	_submit(SOLVED_ID, count)


func show_all() -> void:
	_when_signed_in(func() -> void: _leaderboards.show_all_leaderboards())


func show_daily() -> void:
	_show(DAILY_ID, Variant_.TimeSpan.TIME_SPAN_DAILY)


func show_weekly() -> void:
	_show(WEEKLY_ID, Variant_.TimeSpan.TIME_SPAN_WEEKLY)


func show_climb() -> void:
	_show(CLIMB_ID, Variant_.TimeSpan.TIME_SPAN_ALL_TIME)


func show_solved() -> void:
	_show(SOLVED_ID, Variant_.TimeSpan.TIME_SPAN_ALL_TIME)


func show_achievements() -> void:
	_when_signed_in(func() -> void: _achievements.show_achievements())


## Unlocks the achievement `name` (a key of ACHIEVEMENTS); Play Games ignores repeats.
func unlock(name: String) -> void:
	var id: String = ACHIEVEMENTS.get(name, "")
	if _available and _signed_in and not id.is_empty() and not _sent.has(name):
		_sent[name] = true
		_achievements.unlock_achievement(id)


## Fetches the cloud save; cloud_loaded follows. Nothing follows if it can't be
## reached, so a failed load never looks like an empty save.
func load_cloud() -> void:
	if _available and _signed_in:
		_snapshots.load_game(SAVE_NAME, false)


## Uploads `data`. When two devices' saves conflict, Play Games keeps the one
## with the higher `progress`.
func save_cloud(data: PackedByteArray, description: String, progress: int) -> void:
	if _available and _signed_in:
		_snapshots.save_game(SAVE_NAME, description, data, 0, progress)


func _submit(id: String, score: int) -> void:
	# Play Games keeps each player's best, so worse scores are simply ignored.
	if _available and _signed_in and not id.is_empty():
		_leaderboards.submit_score(id, score)


func _show(id: String, span: int) -> void:
	if not id.is_empty():
		_when_signed_in(func() -> void: _leaderboards.show_leaderboard_for_time_span(id, span))


## Runs `action` now if signed in, otherwise after the sign-in prompt succeeds.
func _when_signed_in(action: Callable) -> void:
	if not _available:
		return
	if _signed_in:
		action.call()
		return
	_after_sign_in = action
	_sign_in.sign_in()


func _on_authenticated(is_authenticated: bool) -> void:
	var newly := is_authenticated and not _signed_in
	_signed_in = is_authenticated
	if newly:
		signed_in.emit()
	if is_authenticated and _after_sign_in.is_valid():
		var action := _after_sign_in
		_after_sign_in = Callable()
		action.call()
