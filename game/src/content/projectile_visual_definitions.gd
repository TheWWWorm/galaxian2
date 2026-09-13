extends RefCounted
## Fresh ordinary travelling projectile declarations; impact effects are separate.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"item_ids":[2,19],"model_ids":[6756,6795],"kinds":[0,1],"camera_facing_kind":1,"shrink_below_ms":1000,"shrink_divisor":1000.0,"hidden_position_x":50000.0,"reduced_billboard_scale":0.6000000238418579,"animation_speed":1.0,"animation_loop":true,"animation_shared_per_weapon":true,"render_type":2}
const SPANS := {"x86_64":{"player_model_table":[-57355,28],"player_wrapper":[-56975,27],"npc_model":[-65918,31],"npc_wrapper":[-63455,29],"wrapper_load":[353223,26],"orientation_kind":[353299,31],"reduced_scale":[353330,61],"model_tick":[354101,55],"live_position":[356328,44],"velocity":[356424,78],"camera_basis":[356564,269],"last_second":[356833,44],"new_shot_scale":[356882,33],"world_up":[357482,266],"flight_basis":[357748,193],"scale_preset":[358010,45],"draw":[358293,36],"loop_setup":[1040855,60],"loop_update":[946100,187],"animation_defaults":[942446,39],"model_2":[1454439,4],"model_19":[1454507,4],"shrink_constant":[1434903,4],"hidden_constant":[1423547,4],"unit_constant":[1422583,4]},"armv7":{"player_model_table":[-59732,18],"player_wrapper":[-58502,22],"npc_model":[-66740,22],"npc_wrapper":[-65584,22],"wrapper_load":[364900,24],"orientation_kind":[364942,42],"reduced_scale":[364984,44],"model_tick":[365996,38],"draw_constants":[367774,10],"live_position":[367876,22],"velocity":[367922,30],"camera_basis":[367978,134],"last_second":[368112,42],"new_shot_scale":[368398,34],"world_up":[368478,102],"flight_basis":[368580,124],"scale_preset":[368704,32],"draw":[368918,34],"loop_setup":[1790306,18],"loop_update":[1745310,184],"animation_defaults":[1743666,18],"model_2":[2342358,4],"model_19":[2342426,4],"shrink_constant":[368470,4],"hidden_constant":[368466,4]}}

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
	if not data is Dictionary: return "Invalid ordinary projectile visuals capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported ordinary projectile visuals"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes): return "Ordinary projectile visuals lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid ordinary projectile visuals provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]): return "Disconnected ordinary projectile visuals declaration"
	return ""
