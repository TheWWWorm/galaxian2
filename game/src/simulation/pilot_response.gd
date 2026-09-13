extends RefCounted
## Ordinary elapsed-time response. Commands are signed local pitch/yaw in [-1,1].
## Vehicle response and sensitivity must be supplied explicitly by the caller.
const Definitions = preload("res://src/content/motion_definitions.gd")
const Library = preload("res://src/content/library.gd")
var error := ""
var binding_id := ""
var base_content_id := ""
var _parameters := {}
var _factor := 0.0
var _sensitivity := 0.0

func configure(bindings: RefCounted, content_id: String, response_factor: float, sensitivity: float) -> bool:
	clear()
	if not Library.valid_hash(content_id) or bindings.base_content_id != content_id or not Library.valid_hash(bindings.binding_id):
		error = "Pilot response belongs to another or unavailable content identity"
		return false
	var parameters: Dictionary = bindings.pilot_response
	if not Definitions.valid_response_parameters(parameters):
		error = "This content has no supported elapsed-time pilot response"
		return false
	if not is_finite(sensitivity) or sensitivity < 0.0 or sensitivity >= float(parameters.ramp_bias):
		error = "Invalid pilot sensitivity"
		return false
	_parameters = parameters.duplicate(true)
	_sensitivity = sensitivity
	if not set_response_factor(response_factor):
		var reason := error
		clear()
		error = reason
		return false
	binding_id = bindings.binding_id
	base_content_id = content_id
	return true

func clear() -> void:
	error = ""
	binding_id = ""
	base_content_id = ""
	_parameters = {}
	_factor = 0.0
	_sensitivity = 0.0

func set_response_factor(value: float) -> bool:
	error = ""
	if _parameters.is_empty() or not is_finite(value) or value <= 0.0 \
			or value * float(_parameters.target_gain) > 2147483647.0:
		error = "Invalid vehicle response factor"
		return false
	_factor = value
	return true

func next_units(current: Vector2, commands: Vector2, seconds: float) -> Vector2:
	error = ""
	if binding_id.is_empty():
		error = "Configure pilot response before processing commands"
		return current
	if not current.is_finite() or not commands.is_finite() or absf(commands.x) > 1.0 or absf(commands.y) > 1.0 \
			or not is_finite(seconds) or seconds < 0.0:
		error = "Invalid pilot command, response state or elapsed time"
		return current
	if seconds == 0.0: return current
	var milliseconds := seconds * 1000.0
	var neutral := milliseconds * _factor / float(_parameters.neutral_divisor)
	var drive := milliseconds * _factor / ((float(_parameters.ramp_bias) - _sensitivity) * float(_parameters.ramp_scale))
	if not is_finite(neutral) or not is_finite(drive):
		error = "Pilot response exceeds supported time range"
		return current
	var result := current
	for axis in 2:
		var value := move_toward(current[axis], 0.0, neutral)
		var command := commands[axis]
		# Preserve the source's integer target quantization, including commands
		# too small to request a nonzero target. Do not accelerate away from a
		# nearer target after neutral return has already left it behind.
		var scaled := command * absf(command) * float(_parameters.target_gain) * _factor
		var target := float(int(float(int(scaled)) / float(_parameters.target_divisor)))
		if command > 0.0 and value < target: value = minf(value + drive, target)
		elif command < 0.0 and value > target: value = maxf(value - drive, target)
		result[axis] = value
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.base_content_id=base_content_id;copy.binding_id=binding_id
	copy._parameters=_parameters.duplicate(true);copy._factor=_factor;copy._sensitivity=_sensitivity
	return copy
