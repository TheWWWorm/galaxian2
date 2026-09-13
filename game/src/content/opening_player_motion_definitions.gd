extends RefCounted
## Scripted forward player motion through the first ordinary handoff.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"initial_scripted_flight":true,"scripted_ignores_throttle":true,"ordinary_motion_suppressed":true,"initial_update_enabled":true,"release_after_event_finished":8,"release_phase":4,"motion_before_controller":true}
const SPANS := {"x86_64":{"player_before_weapons":[244328,40],"controller_call":[255610,5],"player_delta":[449268,7],"initial_scripted":[65,18],"scripted_setter":[440389,13],"initial_update_enabled":[428577,4],"update_gate":[449205,11],"scripted_gate":[454099,68],"scripted_travel":[454167,23],"ordinary_suppression":[456905,13],"release":[17756,46],"speed":[429564,27],"forward_helper":[-844729,42]},"armv7":{"player_before_weapons":[253418,40],"controller_call":[264340,4],"player_delta":[400308,4],"initial_scripted":[26,16],"scripted_setter":[394182,6],"constructor_zero":[384198,2],"initial_update_enabled":[384452,4],"update_gate":[400264,10],"scripted_gate":[404284,60],"scripted_travel":[404344,36],"ordinary_suppression":[406570,6],"release":[51082,48],"speed":[384956,20],"forward_helper":[-1191394,36]}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in VALUES:
		var value: Variant=data.get(key)
		var expected: Variant=VALUES[key]
		if expected is int:
			if not Numbers.integer(value,expected,expected): return false
		elif expected is float:
			if not (value is float or value is int) or value!=expected: return false
		elif expected is Array:
			if not value is Array or value.size()!=expected.size(): return false
			for i in expected.size():
				if not Numbers.integer(value[i],expected[i],expected[i]): return false
		elif typeof(value)!=typeof(expected) or value!=expected: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, staging: Dictionary) -> String:
	if not data is Dictionary: return "Invalid scripted player motion capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported scripted player motion"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes): return "Scripted player motion lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid scripted player motion provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]): return "Disconnected scripted player motion declaration"
	return ""
