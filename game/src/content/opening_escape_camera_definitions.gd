extends RefCounted
## Fixed-eye shake and refresh rules for the fresh opening escape camera.
## This capability does not establish support for the following mission scene.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"fresh_opening_escape_fixed_camera","look_shake_axes":[0,1,2],"random_bound_radius_multiplier":2,"look_shake_scale":1.0,"immediate_update_ms":1000,"ordinary_minimum_ms":1,"inherit_target_up":true,"transient_eye_shake":false,"extra_roll":0.0,"cockpit":false}
const SPANS := {"x86_64":{"defaults":[782030,68],"roll_defaults":[782172,27],"ordinary_gate":[783860,23],"fixed_target":[783883,468],"cockpit_gate":[786280,13],"transient_gate":[786506,10],"look_shake":[786712,282],"scale_constant":[1470095,8],"pan":[783223,87],"cockpit_select":[787309,84],"fixed_select":[787893,10],"random_bound":[999071,171],"random_bits":[998943,96]},"armv7":{"defaults":[722642,504],"ordinary_gate":[724596,18],"fixed_target":[724614,128],"fixed_target_store":[724908,84],"cockpit_gate":[726044,6],"transient_gate":[726130,8],"look_shake":[726310,228],"scale_literal":[726670,8],"pan":[724294,72],"cockpit_select":[726746,54],"fixed_select":[726990,6],"random_bound":[1768282,114],"random_bits":[1768154,128]}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not equal_value(data.get(key),VALUES[key]):return false
	return true

static func equal_value(value: Variant, expected: Variant) -> bool:
	if expected is int:return Numbers.integer(value,expected,expected)
	if expected is float:return (value is int or value is float) and value==expected
	if expected is Array:
		if not value is Array or value.size()!=expected.size():return false
		for i in expected.size():
			if not equal_value(value[i],expected[i]):return false
		return true
	return typeof(value)==typeof(expected) and value==expected

static func validate(data: Variant, executable_bytes: int, architecture: String, staging: Dictionary) -> String:
	if not data is Dictionary:return "Invalid opening escape camera capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(architecture):return "Unsupported opening escape camera declarations"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes):return "Opening escape lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size():return "Invalid opening escape camera provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]):return "Disconnected opening escape camera declaration"
	return ""
