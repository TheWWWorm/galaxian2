extends RefCounted
## Native remake bindings. Feed unhandled events only while flight owns input.
## Controller ownership adapts the maintained GoF3D input component (Apache-2.0).
const KEY_ACTIONS := {KEY_SPACE: "fire", KEY_R: "missiles", KEY_F: "dock", KEY_W: "boost", KEY_TAB: "time",
	KEY_P: "pause", KEY_ESCAPE: "pause", KEY_E: "action_menu", KEY_T: "change_view", KEY_Q: "autopilot",
	KEY_K: "jump", KEY_C: "cloak", KEY_V: "wingmen", KEY_BRACKETRIGHT: "throttle_up",
	KEY_SLASH: "throttle_down", KEY_S: "brake", KEY_G: "secondary_menu", KEY_M: "mouse_mode",
	KEY_1: "roll_left", KEY_3: "roll_right"}
const BUTTON_ACTIONS := {JOY_BUTTON_A: "boost", JOY_BUTTON_B: "missiles", JOY_BUTTON_X: "dock",
	JOY_BUTTON_Y: "autopilot", JOY_BUTTON_START: "pause", JOY_BUTTON_BACK: "time",
	JOY_BUTTON_DPAD_UP: "throttle_up", JOY_BUTTON_DPAD_DOWN: "throttle_down", JOY_BUTTON_DPAD_RIGHT: "secondary_menu",
	JOY_BUTTON_LEFT_SHOULDER: "map", JOY_BUTTON_RIGHT_SHOULDER: "jump"}
const AXIS_ACTIONS := {JOY_AXIS_TRIGGER_RIGHT: "fire", JOY_AXIS_TRIGGER_LEFT: "missiles"}
const ACTIONS := ["fire", "missiles", "secondary_next", "secondary_menu", "boost", "brake", "pause", "time", "autopilot", "dock", "map", "jump", "throttle_up", "throttle_down", "action_menu", "change_view", "cloak", "wingmen", "mouse_mode", "roll_left", "roll_right"]
const TURN_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
const STRAFE_KEYS := [KEY_A, KEY_D]
const DIRECTIONS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]
const HELD_ONLY_ACTIONS := ["brake", "roll_left", "roll_right"]
var error := ""
var device := -1
var deadzone := 0.18
var invert_pitch := false
var touch_controls := OS.has_feature("mobile")
var enabled := true
var mouse_sensitivity := 1.0
var _mouse_active := false
var _mouse_delta := Vector2.ZERO
var _mouse_command := Vector2.ZERO
var _mouse_fire := false
var _keys := {}
var _axes := {}
var _buttons := {}
var _touch := {}
var _touch_command := Vector2.ZERO
var _touch_active := false
var _pressed: Array[String] = []
var _touch_pressed: Array[String] = []
var _events: Array[Dictionary] = []
# A held analog trigger must return to neutral after a modal boundary. These
# release guards intentionally survive clear(), unlike queued flight actions.
var _blocked_triggers := {}

func clear() -> void:
	for axis in AXIS_ACTIONS:
		if float(_axes.get(axis,0.0))>0.25:_blocked_triggers[Vector2i(device,axis)]=true
	_keys.clear()
	_axes.clear()
	_buttons.clear()
	_touch.clear()
	_touch_command = Vector2.ZERO
	_touch_active = false
	_pressed.clear()
	_touch_pressed.clear()
	_events.clear()
	device = -1
	_mouse_delta=Vector2.ZERO;_mouse_command=Vector2.ZERO;_mouse_fire=false

func set_enabled(value: bool) -> void:
	enabled = value
	if not value: clear()

func set_touch_controls(value: bool) -> void:
	touch_controls = value
	if not value:
		_touch_pressed.clear()
		_events=_events.filter(func(event):return not event.touch)
		for action in _touch:
			if _touch[action]:_release(action,true)
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

func discard_modal_event(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion or not AXIS_ACTIONS.has(event.axis) or not is_finite(event.axis_value) or absf(event.axis_value)>1.0:return
	var handle:=Vector2i(event.device,event.axis)
	if event.axis_value>0.25:_blocked_triggers[handle]=true
	else:_blocked_triggers.erase(handle)

func disconnect_controller(identifier: int) -> void:
	for handle in _blocked_triggers.keys():
		if handle.x==identifier:_blocked_triggers.erase(handle)
	if device != identifier: return
	_release_controller_actions()
	device = -1
	_axes.clear()
	_buttons.clear()

func accept(event: InputEvent) -> bool:
	if not enabled: return false
	if event is InputEventMouseMotion:
		if not _mouse_active or not event.screen_relative.is_finite():return false
		_mouse_delta+=event.screen_relative
		return true
	if event is InputEventMouseButton:
		if not _mouse_active or event.button_index!=MOUSE_BUTTON_LEFT:return false
		if event.pressed and not _mouse_fire:_edge("fire")
		if not event.pressed and _mouse_fire:_release("fire")
		_mouse_fire=event.pressed
		return true
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key not in DIRECTIONS and not KEY_ACTIONS.has(key): return false
		if event.echo: return true
		var was_pressed: bool = _keys.get(key, false)
		_keys[key] = event.pressed
		if KEY_ACTIONS.has(key) and KEY_ACTIONS[key] not in HELD_ONLY_ACTIONS:
			if event.pressed and not was_pressed: _edge(KEY_ACTIONS[key])
			if not event.pressed and was_pressed: _release(KEY_ACTIONS[key])
		return true
	if not (event is InputEventJoypadMotion or event is InputEventJoypadButton): return false
	if event is InputEventJoypadMotion:
		if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] \
				or not is_finite(event.axis_value) or absf(event.axis_value) > 1.0: return false
	else:
		if not BUTTON_ACTIONS.has(event.button_index): return false
	if event is InputEventJoypadMotion and _blocked_triggers.has(Vector2i(event.device,event.axis)):
		if event.axis_value<=0.25:_blocked_triggers.erase(Vector2i(event.device,event.axis))
		return true
	if event.device != device:
		if event is InputEventJoypadMotion:
			var activity: float = event.axis_value if AXIS_ACTIONS.has(event.axis) else absf(event.axis_value)
			if activity <= deadzone: return false
		if event is InputEventJoypadButton and not event.pressed: return false
		_release_controller_actions()
		_axes.clear()
		_buttons.clear()
		device = event.device
	if event is InputEventJoypadMotion:
		var previous: float = _axes.get(event.axis, 0.0)
		_axes[event.axis] = event.axis_value
		if AXIS_ACTIONS.has(event.axis) and previous <= 0.25 and event.axis_value > 0.25: _edge(AXIS_ACTIONS[event.axis])
		if AXIS_ACTIONS.has(event.axis) and previous > 0.25 and event.axis_value <= 0.25: _release(AXIS_ACTIONS[event.axis])
	else:
		var previous: bool = _buttons.get(event.button_index, false)
		_buttons[event.button_index] = event.pressed
		if event.pressed and not previous: _edge(BUTTON_ACTIONS[event.button_index])
		if not event.pressed and previous: _release(BUTTON_ACTIONS[event.button_index])
	return true

func set_mouse_active(active: bool) -> void:
	if _mouse_active==active:return
	if _mouse_fire:_release("fire")
	_mouse_active=active
	_mouse_delta=Vector2.ZERO;_mouse_command=Vector2.ZERO;_mouse_fire=false

func advance_mouse(seconds: float) -> void:
	# Convert physical mouse speed to the existing bounded ship controls. A
	# fixed distance over a fixed time has the same response at 60 or 240 FPS.
	_mouse_command=Vector2.ZERO
	if _mouse_active and is_finite(seconds) and seconds>0:
		var velocity:=_mouse_delta*mouse_sensitivity/(600.0*seconds)
		_mouse_command=Vector2(clampf(velocity.y,-1,1),clampf(velocity.x,-1,1))
	_mouse_delta=Vector2.ZERO

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
	if not down and previous:_release(action,true)
	return true

func snapshot() -> Dictionary:
	var held := {}
	for action in ACTIONS: held[action] = false
	if not enabled: return {"command": Vector2.ZERO, "strafe": 0.0, "held": held, "pressed": []}
	var pitch := float(_keys.get(KEY_DOWN, false)) - float(_keys.get(KEY_UP, false))
	var yaw := float(_keys.get(KEY_RIGHT, false)) - float(_keys.get(KEY_LEFT, false))
	var strafe := float(_keys.get(KEY_D, false)) - float(_keys.get(KEY_A, false))
	var command := Vector2(pitch if pitch != 0 else _axis(JOY_AXIS_LEFT_Y), yaw if yaw != 0 else _axis(JOY_AXIS_LEFT_X))
	if command.x==0:command.x=_mouse_command.x
	if command.y==0:command.y=_mouse_command.y
	if _touch_active: command = _touch_command
	# The ship flies along +Z; the following camera's screen-right is local -X.
	command.y=-command.y
	if invert_pitch: command.x = -command.x
	for key in KEY_ACTIONS:
		if _keys.get(key, false): held[KEY_ACTIONS[key]] = true
	for button in BUTTON_ACTIONS:
		if _buttons.get(button, false): held[BUTTON_ACTIONS[button]] = true
	for axis in AXIS_ACTIONS:
		if float(_axes.get(axis, 0.0)) > 0.25: held[AXIS_ACTIONS[axis]] = true
	for action in _touch:
		if _touch[action]: held[action] = true
	if _mouse_fire:held.fire=true
	return {"command": command, "strafe": strafe, "held": held, "pressed": pressed_actions()}

func take_pressed() -> Array[String]:
	var result := pressed_actions()
	_pressed.clear()
	_touch_pressed.clear()
	_events.clear()
	return result

## Preserve down/up order when several controls change before the next frame.
## Steering directions never travel through the flight action-button callbacks.
func take_events() -> Array[Dictionary]:
	var result:=_events
	_events=[];_pressed.clear();_touch_pressed.clear()
	return result

static func pointer_command(flight_command: Vector2) -> Vector2:
	# Drilling uses screen X/Y; flight uses local pitch/yaw.
	return Vector2(-flight_command.y,flight_command.x)

func pressed_actions() -> Array[String]:
	var result := _pressed.duplicate()
	for action in _touch_pressed:
		if action not in result: result.append(action)
	return result

func _edge(action: String, from_touch := false) -> void:
	var target := _touch_pressed if from_touch else _pressed
	if action not in target: target.append(action)
	_events.append({"action":action,"pressed":true,"touch":from_touch})

func _release(action: String,from_touch:=false) -> void:
	_events.append({"action":action,"pressed":false,"touch":from_touch})

func _release_controller_actions() -> void:
	for button in _buttons:
		if _buttons[button] and BUTTON_ACTIONS.has(button):_release(BUTTON_ACTIONS[button])
	for axis in AXIS_ACTIONS:
		if float(_axes.get(axis,0.0))>0.25:_release(AXIS_ACTIONS[axis])

func _axis(index: int) -> float:
	var value := float(_axes.get(index, 0.0))
	return signf(value) * maxf(0.0, absf(value) - deadzone) / (1.0 - deadzone)
