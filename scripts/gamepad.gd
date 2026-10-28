extends RefCounted
## Gamepad controls, added to the input map when the game starts. Godot's own
## UI actions already move between buttons with the D-pad and left stick; these
## add A to press and B to go back, and the board's own buttons:
##   A: cross out or clear (hold and move to keep crossing out or clearing)
##   Y: crown, X: empty the cell, LB/RB: undo/redo, Select: hint,
##   Start: move to the buttons around the board and back.

## Board actions; also the editor's, where A paints and LB/RB change colour.
const CROSS := "board_cross"
const CROWN := "board_crown"
const CLEAR := "board_clear"
const UNDO := "board_undo"
const REDO := "board_redo"
const HINT := "board_hint"
const CONTROLS := "board_controls"

const BUTTONS := {
	"ui_accept": JOY_BUTTON_A,
	"ui_cancel": JOY_BUTTON_B,
	CROSS: JOY_BUTTON_A,
	CROWN: JOY_BUTTON_Y,
	CLEAR: JOY_BUTTON_X,
	UNDO: JOY_BUTTON_LEFT_SHOULDER,
	REDO: JOY_BUTTON_RIGHT_SHOULDER,
	HINT: JOY_BUTTON_BACK,
	CONTROLS: JOY_BUTTON_START,
}


## Adds the gamepad buttons to the input map, once.
static func setup() -> void:
	for action: String in BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventJoypadButton.new()
		event.button_index = BUTTONS[action]
		# Any connected gamepad.
		event.device = -1
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


## Whether a gamepad is plugged in, for showing its controls.
static func connected() -> bool:
	return not Input.get_connected_joypads().is_empty()
