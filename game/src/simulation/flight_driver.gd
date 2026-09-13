extends RefCounted
## Native flight wiring for an explicitly supplied scenario. This does not create
## mission state or choose a loadout/location. Non-pause actions remain requests.
const Motion = preload("res://src/simulation/pilot_motion.gd")
const Clock = preload("res://src/simulation/frame_clock.gd")
const Controls = preload("res://src/input/flight_controls.gd")
const PAUSE_REASONS := ["user", "focus", "modal", "cinematic"]
var error := ""
var binding_id := ""
var base_content_id := ""
var controls := Controls.new()
var _motion := Motion.new()
var _clock := Clock.new()
var _pose := Transform3D.IDENTITY
var _pauses := {}
var _focused := true

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String, ship_id: int, upgrades: Array, equipment: Array, sensitivity: float, initial_pose: Transform3D) -> bool:
	clear()
	if not _motion.configure_vehicle(bindings, catalogues, content_id, ship_id, upgrades, equipment, sensitivity):
		error = _motion.error
		return false
	if not _clock.configure(bindings, content_id):
		var reason := _clock.error
		clear()
		error = reason
		return false
	_motion.advance(initial_pose, Vector2.ZERO, 0, 0)
	if not _motion.error.is_empty():
		var reason := _motion.error
		clear()
		error = reason
		return false
	_pose = initial_pose
	binding_id = bindings.binding_id
	base_content_id = content_id
	return true

func clear() -> void:
	error = ""
	binding_id = ""
	base_content_id = ""
	_motion.clear()
	_clock.clear()
	controls.clear()
	controls.set_enabled(true)
	_pose = Transform3D.IDENTITY
	_pauses.clear()
	_focused = true

func pose() -> Transform3D:
	return _pose

func angular_units() -> Vector2:
	return _motion.angular_units

func is_paused() -> bool:
	return not _pauses.is_empty()

func set_pause(reason: String, paused: bool, now_microseconds: int) -> bool:
	error = ""
	if binding_id.is_empty() or reason not in PAUSE_REASONS or now_microseconds < 0:
		error = "Invalid flight pause context, reason or timestamp"
		return false
	if _pauses.has(reason) == paused: return true
	if not _clock.rebase(now_microseconds):
		error = _clock.error
		return false
	if paused: _pauses[reason] = true
	else: _pauses.erase(reason)
	# Acknowledging a modal must not also fire or steer the ship.
	controls.clear()
	return true

func set_focused(focused: bool, now_microseconds: int) -> bool:
	if not set_pause("focus", not focused, now_microseconds): return false
	_focused = focused
	controls.set_enabled(focused)
	return true

func accept(event: InputEvent) -> bool:
	if binding_id.is_empty() or not _focused: return false
	return controls.accept(event)

func step(now_microseconds: int, throttle: float) -> Dictionary:
	error = ""
	if binding_id.is_empty() or now_microseconds < 0 or not is_finite(throttle) or throttle < 0 or throttle > 1:
		error = "Invalid flight driver context, timestamp or throttle"
		return {}
	var pressed := controls.take_pressed()
	if "pause" in pressed:
		set_pause("user", not _pauses.has("user"), now_microseconds)
		pressed.clear()
	var seconds := _clock.sample(now_microseconds, is_paused())
	if not _clock.error.is_empty():
		error = _clock.error
		return {}
	var input := controls.snapshot()
	var candidate := _motion.advance(_pose, input.command, throttle, seconds)
	if not _motion.error.is_empty():
		error = _motion.error
		return {}
	_pose = candidate
	# Requests are observable but cannot complete an unsupported action. Callers
	# must dispatch them to implemented systems; blocked simulation exposes none.
	return {"pose": _pose, "seconds": seconds, "paused": is_paused(),
		"requested_actions": [] if is_paused() else pressed,
		"held_actions": {} if is_paused() else input.held}
