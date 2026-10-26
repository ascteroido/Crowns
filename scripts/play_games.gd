extends Node
## Google Play Games leaderboards. Only active on Android with the plugin
## built in and leaderboard IDs filled in; everywhere else every call is a no-op.

const SignInClient := preload("res://addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd")
const LeaderboardsClient := preload("res://addons/GodotPlayGameServices/scripts/leaderboards/leaderboards_client.gd")
const Variant_ := preload("res://addons/GodotPlayGameServices/scripts/leaderboards/leaderboard_variant.gd")

## Leaderboard IDs from the Play Console (Play Games Services > Leaderboards).
## Daily and weekly: Time format, smaller is better. The others: numeric, larger is better.
const DAILY_ID := "CgkIs_CWu6AOEAIQAg"
const WEEKLY_ID := "CgkIs_CWu6AOEAIQBQ"
const CLIMB_ID := "CgkIs_CWu6AOEAIQAw"
const SOLVED_ID := "CgkIs_CWu6AOEAIQAQ"

var _available := false
var _signed_in := false
var _sign_in: Node
var _leaderboards: Node
## Leaderboard to open once a sign-in started for it finishes: [id, time span].
var _pending_show := []


func _ready() -> void:
	if OS.get_name() != "Android" or DAILY_ID.is_empty():
		return
	var services: Node = get_node_or_null("/root/GodotPlayGameServices")
	if services == null or services.initialize() != OK:
		return
	_available = true
	_sign_in = SignInClient.new()
	_leaderboards = LeaderboardsClient.new()
	add_child(_sign_in)
	add_child(_leaderboards)
	_sign_in.user_authenticated.connect(_on_authenticated)
	_sign_in.is_authenticated()


func available() -> bool:
	return _available


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
	if not _available:
		return
	if not _signed_in:
		_pending_show = ["", Variant_.TimeSpan.TIME_SPAN_ALL_TIME]
		_sign_in.sign_in()
		return
	_leaderboards.show_all_leaderboards()


func show_daily() -> void:
	_show(DAILY_ID, Variant_.TimeSpan.TIME_SPAN_DAILY)


func show_weekly() -> void:
	_show(WEEKLY_ID, Variant_.TimeSpan.TIME_SPAN_WEEKLY)


func show_climb() -> void:
	_show(CLIMB_ID, Variant_.TimeSpan.TIME_SPAN_ALL_TIME)


func show_solved() -> void:
	_show(SOLVED_ID, Variant_.TimeSpan.TIME_SPAN_ALL_TIME)


func _submit(id: String, score: int) -> void:
	# Play Games keeps each player's best, so worse scores are simply ignored.
	if _available and _signed_in and not id.is_empty():
		_leaderboards.submit_score(id, score)


func _show(id: String, span: int) -> void:
	if not _available or id.is_empty():
		return
	if not _signed_in:
		_pending_show = [id, span]
		_sign_in.sign_in()
		return
	_leaderboards.show_leaderboard_for_time_span(id, span)


func _on_authenticated(is_authenticated: bool) -> void:
	_signed_in = is_authenticated
	if not is_authenticated or _pending_show.is_empty():
		return
	var request := _pending_show
	_pending_show = []
	if request[0].is_empty():
		show_all()
	else:
		_show(request[0], request[1])
