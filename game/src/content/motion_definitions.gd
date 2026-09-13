extends RefCounted
## Source declarations for ordinary cruise; boost and steering are separate.

static func valid_rate(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value > 0.0 and value <= 1000.0

static func valid_forward_axis(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for i in 3:
		if not (value[i] is int or value[i] is float) or value[i] != (1 if i == 2 else 0):
			return false
	return true

static func validate_cruise(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary:
		return "Invalid cruise definitions"
	if data.is_empty(): return ""
	if not valid_rate(data.get("speed_units_per_millisecond")) or not valid_forward_axis(data.get("forward_axis")):
		return "Unsupported cruise rate or forward axis"
	if not data.get("provenance") is Array or data.provenance.size() != 5:
		return "Missing cruise source provenance"
	var sizes := [20, 30, 36, 32, 38] if architecture == "armv7" else [27, 23, 40, 42, 27]
	var seen := {}
	for i in sizes.size():
		var record: Variant = data.provenance[i]
		if not record is Dictionary or record.get("bytes") != sizes[i]:
			return "Unsupported cruise reader layout"
		var offset: Variant = record.get("offset")
		if not (offset is int or offset is float) or not is_finite(offset) or offset != floor(offset) \
				or offset < 0 or offset > executable_bytes - sizes[i] or seen.has(offset):
			return "Invalid cruise source extent"
		seen[offset] = true
	return ""

static func valid_rotation_parameters(data: Dictionary) -> bool:
	if data.get("rotation_order") != "local_x_y": return false
	for key in ["angle_unit_scale", "radians_per_turn", "time_scale"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(value) or value <= 0.0 \
				or value > (10.0 if key == "radians_per_turn" else 1.0):
			return false
	return true

static func validate_manual_rotation(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Invalid manual rotation definitions"
	if data.is_empty(): return ""
	if not valid_rotation_parameters(data): return "Unsupported manual rotation parameters"
	var sizes := [90, 4, 4, 4, 28] if architecture == "armv7" else [24, 61, 4, 4, 4, 45]
	if not data.get("provenance") is Array or data.provenance.size() != sizes.size():
		return "Missing manual rotation provenance"
	for i in sizes.size():
		var row: Variant = data.provenance[i]
		if not row is Dictionary or row.get("bytes") != sizes[i]:
			return "Unsupported manual rotation reader layout"
		var offset: Variant = row.get("offset")
		if not (offset is int or offset is float) or not is_finite(offset) or offset != floor(offset) \
				or offset < 0 or offset > executable_bytes - sizes[i]:
			return "Invalid manual rotation source extent"
	return ""

static func valid_response_parameters(data: Dictionary) -> bool:
	if data.get("mode") != "elapsed" or data.get("command_curve") != "signed_square" or data.get("target_divisor") != 63:
		return false
	for key in ["target_gain", "ramp_bias", "ramp_scale", "neutral_divisor"]:
		var value: Variant = data.get(key)
		var maximum := 1000000.0 if key == "target_gain" else (10.0 if key == "ramp_bias" else 10000.0)
		if not (value is float or value is int) or not is_finite(value) or value <= 0.0 or value > maximum:
			return false
	return true

static func validate_pilot_response(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Invalid pilot response definitions"
	if data.is_empty(): return ""
	if not valid_response_parameters(data): return "Unsupported pilot response parameters"
	var sizes := [54, 58, 28, 28, 28, 28] if architecture == "armv7" else [54, 33, 33, 32, 32, 32, 32]
	for i in (7 if architecture == "armv7" else 9): sizes.append(4)
	if not data.get("provenance") is Array or data.provenance.size() != sizes.size():
		return "Missing pilot response provenance"
	for i in sizes.size():
		var row: Variant = data.provenance[i]
		if not row is Dictionary or row.get("bytes") != sizes[i]: return "Unsupported pilot response reader layout"
		var offset: Variant = row.get("offset")
		if not (offset is int or offset is float) or not is_finite(offset) or offset != floor(offset) \
				or offset < 0 or offset > executable_bytes - sizes[i]: return "Invalid pilot response source extent"
	return ""
