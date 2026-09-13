extends RefCounted
## Ordinary NPC steering tuning, independent of target and speed selection.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=12 or not data.get("provenance") is Dictionary: return false
	if not Numbers.integer(data.get("turn_numerator"),1,127) or not Numbers.integer(data.get("bank_samples"),5,5): return false
	for key in ["turn_scale","heading_snap_l1","bank_sign_angle","bank_limit","bank_gain","bank_slew_numerator","bank_slew_divisor","bank_angle_scale","pi"]:
		var value: Variant = data.get(key)
		if (not value is float and not value is int) or not is_finite(float(value)) or value<=0 or value>100000: return false
	for key in ["turn_scale","heading_snap_l1","bank_angle_scale"]:
		if data[key]>1: return false
	return data.pi==3.1415927410125732 and data.bank_sign_angle==1.5707963705062866

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing NPC flight declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid NPC flight parameters"
	var sizes := {"actor_wrapper":14,"virtual_update":8,"bank":24,"turn":19,"snap":13,"sign":13,"history":222,"reset":30,"slew":21,"radians":16,"travel":28,"slew_numerator":4,"history_divisor":4,"sign_mask":16} if architecture=="x86_64" else {"actor_wrapper":60,"virtual_update":4,"bank":52,"turn":28,"snap":32,"sign":22,"history":198,"reset":14,"slew":32,"radians":42,"travel":40} if architecture=="armv7" else {}
	if sizes.is_empty(): return "Unsupported NPC flight architecture"
	for key in ["turn_scale","heading_snap_l1","bank_sign_angle","bank_slew_divisor","bank_angle_scale","pi"]: sizes[key]=4
	if data.provenance.size()!=sizes.size(): return "Invalid NPC flight provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid NPC flight extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping NPC flight extents"
		spans.append(span)
	return ""
