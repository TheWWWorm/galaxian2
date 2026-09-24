extends RefCounted
## Ordinary pilot update: move with the established angular state, then prepare
## the response to current commands for the next step. Special flight modes are
## not selected here. Callers own pause/time policy and vehicle state.
const Flight = preload("res://src/simulation/flight_motion.gd")
const Vehicle = preload("res://src/simulation/vehicle_response.gd")
const Response = preload("res://src/simulation/pilot_response.gd")
# Both supported Mac executables use these lateral-control scalars. The current
# ship's source response factor supplies the variable rate; no cruise speed is
# substituted for sideways travel.
const LATERAL_GAIN_PER_FACTOR := 0.06
const LATERAL_RATE_CAP := 2.0
const LATERAL_GAIN_START := 0.1
const LATERAL_GAIN_RAMP := 1.5
const LATERAL_RELEASE_RETENTION := 0.7
const LATERAL_SETTLE_RATE := 0.01
var error := ""
var binding_id := ""
var base_content_id := ""
var angular_units := Vector2.ZERO
var lateral_units_per_millisecond := 0.0
var _flight := Flight.new()
var _response := Response.new()
var _response_factor := 0.0
var _lateral_gain := LATERAL_GAIN_START

func configure(bindings: RefCounted, content_id: String, response_factor: float, sensitivity: float) -> bool:
	clear()
	if not _flight.configure(bindings, content_id) or not _response.configure(bindings, content_id, response_factor, sensitivity):
		var reason := _flight.error if not _flight.error.is_empty() else _response.error
		clear()
		error = reason
		return false
	binding_id = bindings.binding_id
	base_content_id = content_id
	_response_factor = response_factor
	return true

func configure_vehicle(bindings: RefCounted, catalogues: RefCounted, content_id: String, ship_id: int, upgrade_tags: Array, equipment_ids: Array, sensitivity: float) -> bool:
	clear()
	var vehicle := Vehicle.new()
	if not vehicle.configure(bindings, catalogues, content_id):
		error = vehicle.error
		return false
	var resolved := vehicle.resolve(ship_id, upgrade_tags, equipment_ids)
	if resolved.is_empty():
		error = vehicle.error
		return false
	return configure(bindings, content_id, resolved.response_factor, sensitivity)

func set_vehicle(bindings: RefCounted, catalogues: RefCounted, ship_id: int, upgrade_tags: Array, equipment_ids: Array) -> bool:
	error = ""
	if binding_id.is_empty() or binding_id != bindings.binding_id or base_content_id != bindings.base_content_id:
		error = "Vehicle change belongs to another motion context"
		return false
	var vehicle := Vehicle.new()
	if not vehicle.configure(bindings, catalogues, base_content_id):
		error = vehicle.error
		return false
	var resolved := vehicle.resolve(ship_id, upgrade_tags, equipment_ids)
	if resolved.is_empty():
		error = vehicle.error
		return false
	return set_response_factor(resolved.response_factor)

func clear() -> void:
	error = ""
	binding_id = ""
	base_content_id = ""
	angular_units = Vector2.ZERO
	lateral_units_per_millisecond = 0.0
	_response_factor = 0.0
	_lateral_gain = LATERAL_GAIN_START
	_flight.clear()
	_response.clear()

func set_response_factor(value: float) -> bool:
	var result := _response.set_response_factor(value)
	error = _response.error
	if result: _response_factor = value
	return result

func advance(pose: Transform3D, commands: Vector2, throttle: float, seconds: float, strafe_command:=0.0) -> Transform3D:
	error = ""
	if binding_id.is_empty():
		error = "Configure this content's pilot motion before advancing"
		return pose
	var next_response := _response.next_units(angular_units, commands, seconds)
	if not _response.error.is_empty():
		error = _response.error
		return pose
	var next_pose := advance_prepared(pose, throttle, seconds, strafe_command)
	if not error.is_empty(): return pose
	angular_units = next_response
	return next_pose

## Move with the response prepared by a preceding frame. Cinematic release
## samples current commands later, after its camera pass.
func advance_prepared(pose: Transform3D, throttle: float, seconds: float, strafe_command:=0.0) -> Transform3D:
	error = ""
	if binding_id.is_empty():
		error = "Configure this content's pilot motion before advancing"
		return pose
	if not is_finite(strafe_command) or strafe_command not in [-1.0, 0.0, 1.0]:
		error = "Manual strafe input must be left, neutral or right"
		return pose
	var rate := lateral_units_per_millisecond
	var gain := _lateral_gain
	if seconds > 0.0 and strafe_command != 0.0:
		# Positive local X is screen-left in the following flight camera.
		rate = -strafe_command * minf(LATERAL_RATE_CAP, _response_factor * LATERAL_GAIN_PER_FACTOR) * gain
		gain = minf(1.0, gain * LATERAL_GAIN_RAMP)
	if absf(rate) <= LATERAL_SETTLE_RATE:
		rate = 0.0
		gain = LATERAL_GAIN_START
	var next_pose := _flight.advance(pose, angular_units, throttle, seconds, rate)
	if not _flight.error.is_empty():
		error = _flight.error
		return pose
	if seconds > 0.0:
		lateral_units_per_millisecond = rate * LATERAL_RELEASE_RETENTION
		_lateral_gain = gain
	return next_pose

func sample_commands(commands: Vector2, seconds: float) -> bool:
	error = ""
	var next := _response.next_units(angular_units, commands, seconds)
	if not _response.error.is_empty():
		error = _response.error
		return false
	angular_units = next
	return true

func accept_visual_response(sample: Vector2, seconds: float, preceding_commands:=Vector2.ZERO) -> bool:
	# Settle the rendered angular sample before late input. A preceding input
	# flag can hold neutral return on the first guided frame. Callers can also
	# use this when opening a modal instruction bypasses late input.
	error=""
	if binding_id.is_empty() or not preceding_commands.is_finite() or absf(preceding_commands.x)>1 or absf(preceding_commands.y)>1:
		error="Visual response requires a configured pilot and valid preceding commands";return false
	var next:=_response.next_units(sample,Vector2.ZERO,seconds)
	if not _response.error.is_empty():error=_response.error;return false
	for axis in 2:
		if preceding_commands[axis]!=0:next[axis]=sample[axis]
	angular_units=next
	return true

func coast(pose: Transform3D, throttle: float, seconds: float) -> Transform3D:
	# Scripted flight retains its root heading and speed without preparing
	# steering input. Recharge and other player work belong to the caller.
	var rate:=lateral_units_per_millisecond if absf(lateral_units_per_millisecond)>LATERAL_SETTLE_RATE else 0.0
	var next:=_flight.advance(pose,Vector2.ZERO,throttle,seconds,rate)
	error=_flight.error
	if error.is_empty() and seconds>0.0:
		lateral_units_per_millisecond=rate*LATERAL_RELEASE_RETENTION
		if rate==0.0:_lateral_gain=LATERAL_GAIN_START
	return next

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.base_content_id=base_content_id;copy.binding_id=binding_id;copy.angular_units=angular_units
	copy.lateral_units_per_millisecond=lateral_units_per_millisecond
	copy._response_factor=_response_factor;copy._lateral_gain=_lateral_gain
	copy._flight=_flight.fork_for_frame();copy._response=_response.fork_for_frame()
	return copy
