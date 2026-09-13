extends RefCounted
## Verified fresh NPC scanner and original marker/animation declarations.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"x86_64":{"scope":"fresh_opening_npcs","equipment_type":17,"duration_property":29,"cargo_property":31,"default_duration_ms":8000,"near_half_extent":24000.0,"initial_selected":-1,"initial_candidate":-1,"initial_elapsed_ms":0,"acquisition_sound_id":26,"empty_cargo_message_id":22,"animation_image_id":1110,"animation_texture_id":10062,"animation_region":10,"image_ids":[1224,1225,1226,1227,1228,1229,1234,1243,1244,1235,1236,1237,1238,1241,1242],"marker_before_acquisition":true,"completion_strict":true,"architecture":"x86_64","window_divisor":18,"marker_texture_id":10063},"armv7":{"scope":"fresh_opening_npcs","equipment_type":17,"duration_property":29,"cargo_property":31,"default_duration_ms":8000,"near_half_extent":24000.0,"initial_selected":-1,"initial_candidate":-1,"initial_elapsed_ms":0,"acquisition_sound_id":26,"empty_cargo_message_id":22,"animation_image_id":1110,"animation_texture_id":10062,"animation_region":10,"image_ids":[1224,1225,1226,1227,1228,1229,1234,1243,1244,1235,1236,1237,1238,1241,1242],"marker_before_acquisition":true,"completion_strict":true,"architecture":"armv7","window_divisor":16,"marker_texture_id":10062}}
const SPANS := {"x86_64":{"initial_selection":[535235,88],"initial_timer":[535563,34],"images":[535647,3060],"equipment":[538707,200],"ordinary_permission":[539017,16],"window":[539102,39],"population":[545563,135],"order":[546071,111],"eligibility":[546190,177],"markers_candidates":[546474,2245],"clock_permissions":[548719,290],"acquisition":[549110,477],"animation_reset":[549587,349],"animation_alias":[-656135,64],"animation_constructor":[683895,118],"animation_frame":[684013,90],"near_constant":[1453067,4],"negative_near_constant":[1467011,4]},"armv7":{"initial_selection":[471206,304],"images":[471510,2468],"equipment":[473978,136],"ordinary_permission":[474198,20],"window":[474252,18],"population_markers_candidates":[479528,2162],"clock_permissions":[481690,392],"acquisition":[482210,810],"animation_reset":[483020,274],"animation_alias":[-953790,92],"animation_constructor":[631534,194]}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or not VALUES.has(data.get("architecture")) or not data.get("provenance") is Dictionary: return false
	var expected_values: Dictionary=VALUES[data.architecture]
	if data.size()!=expected_values.size()+1: return false
	for key in expected_values:
		var value: Variant=data.get(key)
		var expected: Variant=expected_values[key]
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
	if not data is Dictionary: return "Invalid NPC scanner capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture) or data.architecture!=architecture: return "Unsupported NPC scanner"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes): return "NPC scanner lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid NPC scanner provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]): return "Disconnected NPC scanner declaration"
	return ""
