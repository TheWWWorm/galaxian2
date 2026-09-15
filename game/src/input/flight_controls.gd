extends RefCounted
## Native remake bindings. Feed unhandled events only while flight owns input.
## Controller ownership adapts the maintained GoF3D input component (Apache-2.0).
const KEY_ACTIONS := {KEY_SPACE: "fire", KEY_R: "missiles", KEY_SHIFT: "boost", KEY_ESCAPE: "pause",
	KEY_T: "time", KEY_P: "autopilot", KEY_E: "dock", KEY_M: "map", KEY_J: "jump", KEY_EQUAL: "throttle_up", KEY_MINUS: "throttle_down"}
const BUTTON_ACTIONS := {JOY_BUTTON_A: "boost", JOY_BUTTON_B: "missiles", JOY_BUTTON_X: "dock",
	JOY_BUTTON_Y: "autopilot", JOY_BUTTON_START: "pause", JOY_BUTTON_BACK: "time",
	JOY_BUTTON_DPAD_UP: "throttle_up", JOY_BUTTON_DPAD_DOWN: "throttle_down",
	JOY_BUTTON_LEFT_SHOULDER: "map", JOY_BUTTON_RIGHT_SHOULDER: "jump"}
const AXIS_ACTIONS := {JOY_AXIS_TRIGGER_RIGHT: "fire", JOY_AXIS_TRIGGER_LEFT: "missiles"}
const ACTIONS := ["fire", "missiles", "boost", "pause", "time", "autopilot", "dock", "map", "jump", "throttle_up", "throttle_down"]
const DIRECTIONS := [KEY_W, KEY_S, KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
var error := ""
var device := -1
var deadzone := 0.18
var invert_pitch := false
var touch_controls := OS.has_feature("mobile")
var enabled := true
var _keys := {}
var _axes := {}
var _buttons := {}
var _touch := {}
var _touch_command := Vector2.ZERO
var _touch_active := false
var _pressed: Array[String] = []
var _touch_pressed: Array[String] = []

func clear() -> void:
	_keys.clear()
	_axes.clear()
	_buttons.clear()
	_touch.clear()
	_touch_command = Vector2.ZERO
	_touch_active = false
	_pressed.clear()
	_touch_pressed.clear()
	device = -1

func set_enabled(value: bool) -> void:
	enabled = value
	if not value: clear()

func set_touch_controls(value: bool) -> void:
	touch_controls = value
	if not value:
		_touch_pressed.clear()
		_touch.clear()
		_touch_command = Vector2.ZERO
		_touch_active = false

func configure_preferences(zone: float, inverted: bool, show_touch: bool) -> bool:
	error = ""
	if not is_finite(zone) or zone < 0.0 or zone >= 1.0:
		error = "Controller deadzone must be between zero and one"
		return false
	deadzone = zone
	invert_pitch = inverted
	set_touch_controls(show_touch)
	return true

func disconnect_controller(identifier: int) -> void:
	if device != identifier: return
	device = -1
	_axes.clear()
	_buttons.clear()

func accept(event: InputEvent) -> bool:
	if not enabled: return false
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key not in DIRECTIONS and not KEY_ACTIONS.has(key): return false
		if event.echo: return true
		var was_pressed: bool = _keys.get(key, false)
		_keys[key] = event.pressed
		if event.pressed and not was_pressed and KEY_ACTIONS.has(key): _edge(KEY_ACTIONS[key])
		return true
	if not (event is InputEventJoypadMotion or event is InputEventJoypadButton): return false
	if event is InputEventJoypadMotion:
		if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] \
				or not is_finite(event.axis_value) or absf(event.axis_value) > 1.0: return false
	else:
		if not BUTTON_ACTIONS.has(event.button_index): return false
	if event.device != device:
		if event is InputEventJoypadMotion:
			var activity: float = event.axis_value if AXIS_ACTIONS.has(event.axis) else absf(event.axis_value)
			if activity <= deadzone: return false
		if event is InputEventJoypadButton and not event.pressed: return false
		_axes.clear()
		_buttons.clear()
		device = event.device
	if event is InputEventJoypadMotion:
		var previous: float = _axes.get(event.axis, 0.0)
		_axes[event.axis] = event.axis_value
		if AXIS_ACTIONS.has(event.axis) and previous <= 0.25 and event.axis_value > 0.25: _edge(AXIS_ACTIONS[event.axis])
	else:
		var previous: bool = _buttons.get(event.button_index, false)
		_buttons[event.button_index] = event.pressed
		if event.pressed and not previous: _edge(BUTTON_ACTIONS[event.button_index])
	return true

func set_touch_command(command: Vector2, active: bool) -> bool:
	if not enabled or not touch_controls: return false
	if not command.is_finite() or absf(command.x) > 1.0 or absf(command.y) > 1.0: return false
	_touch_command = command if active else Vector2.ZERO
	_touch_active = active
	return true

func set_touch_action(action: String, down: bool) -> bool:
	if not enabled or not touch_controls or action not in ACTIONS: return false
	var previous: bool = _touch.get(action, false)
	_touch[action] = down
	if down and not previous: _edge(action, true)
	return true

func snapshot() -> Dictionary:
	var held := {}
	for action in ACTIONS: held[action] = false
	if not enabled: return {"command": Vector2.ZERO, "held": held, "pressed": []}
	var pitch := float(_key(KEY_S, KEY_DOWN)) - float(_key(KEY_W, KEY_UP))
	var yaw := float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT))
	var command := Vector2(pitch if pitch != 0 else _axis(JOY_AXIS_LEFT_Y), yaw if yaw != 0 else _axis(JOY_AXIS_LEFT_X))
	if _touch_active: command = _touch_command
	if invert_pitch: command.x = -command.x
	for key in KEY_ACTIONS:
		if _keys.get(key, false): held[KEY_ACTIONS[key]] = true
	for button in BUTTON_ACTIONS:
		if _buttons.get(button, false): held[BUTTON_ACTIONS[button]] = true
	for axis in AXIS_ACTIONS:
		if float(_axes.get(axis, 0.0)) > 0.25: held[AXIS_ACTIONS[axis]] = true
	for action in _touch:
		if _touch[action]: held[action] = true
	return {"command": command, "held": held, "pressed": pressed_actions()}

func take_pressed() -> Array[String]:
	var result := pressed_actions()
	_pressed.clear()
	_touch_pressed.clear()
	return result

func pressed_actions() -> Array[String]:
	var result := _pressed.duplicate()
	for action in _touch_pressed:
		if action not in result: result.append(action)
	return result

func _edge(action: String, from_touch := false) -> void:
	var target := _touch_pressed if from_touch else _pressed
	if action not in target: target.append(action)

func _key(first: int, second: int) -> bool:
	return _keys.get(first, false) or _keys.get(second, false)

func _axis(index: int) -> float:
	var value := float(_axes.get(index, 0.0))
	return signf(value) * maxf(0.0, absf(value) - deadzone) / (1.0 - deadzone)
