class_name ISSInput
extends RefCounted
## Controllers for the match: keyboard and joypads turned into the game's
## logical buttons (tbl_button_layouts maps the Mega Drive's B, C, A and Z
## onto pass, shoot, lofted pass / sliding tackle and dash; Y switches
## player). The d-pad is read as 8 directions, like the Mega Drive pad.
##
##   Player 1: arrows, Z pass, X shoot, A lofted / slide, Left Shift dash,
##             S switch, Enter start; or the first joypad.
##   Player 2: I J K L, U pass, O shoot, Y lofted / slide, H dash, N switch,
##             Backspace start; or the second joypad.

const KEYS := [
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "pass": KEY_Z,
		"shoot": KEY_X, "loft": KEY_A, "dash": KEY_SHIFT, "switch": KEY_S, "start": KEY_ENTER},
	{"up": KEY_I, "down": KEY_K, "left": KEY_J, "right": KEY_L, "pass": KEY_U,
		"shoot": KEY_O, "loft": KEY_Y, "dash": KEY_H, "switch": KEY_N, "start": KEY_BACKSPACE},
]
const PAD_BUTTONS := {"pass": JOY_BUTTON_A, "shoot": JOY_BUTTON_B, "loft": JOY_BUTTON_X,
	"switch": JOY_BUTTON_Y, "dash": JOY_BUTTON_RIGHT_SHOULDER, "start": JOY_BUTTON_START,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT,
	"right": JOY_BUTTON_DPAD_RIGHT}
const BITS := {"pass": ISSFootballer.PASS, "shoot": ISSFootballer.SHOOT, "loft": ISSFootballer.LOFT,
	"dash": ISSFootballer.DASH, "switch": ISSFootballer.SWITCH}


static func action(player: int, name: String) -> StringName:
	return StringName("iss_p%d_%s" % [player + 1, name])


## Register the input actions once.
static func ensure_actions() -> void:
	if InputMap.has_action(action(0, "pass")):
		return
	for p in 2:
		for name: String in KEYS[p]:
			var act := action(p, name)
			InputMap.add_action(act, 0.4)
			var k := InputEventKey.new()
			k.physical_keycode = KEYS[p][name]
			InputMap.action_add_event(act, k)
			var b := InputEventJoypadButton.new()
			b.device = p
			b.button_index = PAD_BUTTONS[name]
			InputMap.action_add_event(act, b)
		for axis in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0],
				["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
			var m := InputEventJoypadMotion.new()
			m.device = p
			m.axis = axis[1]
			m.axis_value = axis[2]
			InputMap.action_add_event(action(p, axis[0]), m)
	# The trigger also dashes.
	for p in 2:
		var t := InputEventJoypadMotion.new()
		t.device = p
		t.axis = JOY_AXIS_TRIGGER_RIGHT
		t.axis_value = 1.0
		InputMap.action_add_event(action(p, "dash"), t)


## The pad state for the engine: {"dir": -1 or 0-63, "press": bits, "held": bits}.
static func read(player: int) -> Dictionary:
	var v := Vector2(
		Input.get_action_strength(action(player, "right")) - Input.get_action_strength(action(player, "left")),
		Input.get_action_strength(action(player, "down")) - Input.get_action_strength(action(player, "up")))
	var dir := -1
	if v.length() > 0.3:
		# 8 directions, 0 = up (-y), 16 = right.
		dir = (roundi(atan2(v.x, -v.y) / TAU * 8.0) * 8) & 63
	var press := 0
	var held := 0
	for name: String in BITS:
		if Input.is_action_just_pressed(action(player, name)):
			press |= BITS[name]
		if Input.is_action_pressed(action(player, name)):
			held |= BITS[name]
	return {"dir": dir, "press": press, "held": held}


static func start_pressed(player: int) -> bool:
	return Input.is_action_just_pressed(action(player, "start"))
