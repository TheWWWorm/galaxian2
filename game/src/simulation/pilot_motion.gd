extends RefCounted
## Ordinary pilot update: move with the established angular state, then prepare
## the response to current commands for the next step. Special flight modes are
## not selected here. Callers own pause/time policy and vehicle state.
const Flight = preload("res://src/simulation/flight_motion.gd")
const Vehicle = preload("res://src/simulation/vehicle_response.gd")
const Response = preload("res://src/simulation/pilot_response.gd")
var error := ""
var binding_id := ""
var base_content_id := ""
var angular_units := Vector2.ZERO
var _flight := Flight.new()
var _response := Response.new()

func configure(bindings: RefCounted, content_id: String, response_factor: float, sensitivity: float) -> bool:
	clear()
	if not _flight.configure(bindings, content_id) or not _response.configure(bindings, content_id, response_factor, sensitivity):
		var reason := _flight.error if not _flight.error.is_empty() else _response.error
		clear()
		error = reason
		return false
	binding_id = bindings.binding_id
	base_content_id = content_id
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
	_flight.clear()
	_response.clear()

func set_response_factor(value: float) -> bool:
	var result := _response.set_response_factor(value)
	error = _response.error
	return result

func advance(pose: Transform3D, commands: Vector2, throttle: float, seconds: float) -> Transform3D:
	error = ""
	if binding_id.is_empty():
		error = "Configure this content's pilot motion before advancing"
		return pose
	var next_response := _response.next_units(angular_units, commands, seconds)
	if not _response.error.is_empty():
		error = _response.error
		return pose
	var next_pose := _flight.advance(pose, angular_units, throttle, seconds)
	if not _flight.error.is_empty():
		error = _flight.error
		return pose
	angular_units = next_response
	return next_pose

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

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.base_content_id=base_content_id;copy.binding_id=binding_id;copy.angular_units=angular_units
	copy._flight=_flight.fork_for_frame();copy._response=_response.fork_for_frame()
	return copy
