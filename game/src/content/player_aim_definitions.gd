extends RefCounted
## Ordinary projected-forward aiming and original reticle declarations.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"mode":"projected_forward","distance":22000.0,"new_weight":0.20000000298023224,"previous_weight":0.800000011920929,"initial_aim":[0,0,0],"initial_contact":false,"initial_contact_ms":0,"contact_limit_ms":201,"reticle_phase":4,"image_ids":[1216,1230],"texture_id":10062,"image_regions":[115,129],"motion_before_aim":true,"aim_before_camera":true,"draw_before_contact_expiry":true}
const SPANS := {"x86_64":{"initial_aim":[428166,22],"initial_timer":[428859,10],"initial_world_contact":[-168052,4],"body_vectors":[460729,96],"projected_mode":[460979,263],"smoothing":[462008,165],"retain_aim":[462265,19],"image_loads":[430949,57],"idle_alias":[-650759,64],"contact_alias":[-650439,64],"player_contact_enable":[-57001,13],"contact_setter":[-309853,14],"npc_contact":[-304564,24],"draw_gate":[481324,203],"draw_feedback":[481770,143],"player_before_world":[244328,40],"controller_later":[255610,5],"distance_constant":[1465855,4],"new_weight_constant":[1423555,4],"previous_weight_constant":[1423951,4]},"armv7":{"initial_aim":[384182,100],"initial_timer":[384570,4],"initial_world_contact":[-163182,238],"body_vectors":[409376,34],"projected_mode":[409498,54],"projection_smoothing":[409900,204],"retain_aim":[410516,34],"image_loads":[386034,40],"idle_alias":[-945118,98],"contact_alias":[-944598,98],"player_contact_enable":[-58526,10],"contact_setter":[-292770,6],"npc_contact":[-288898,350],"draw_gate":[424998,164],"draw_feedback":[425328,210],"player_before_world":[253418,40],"controller_later":[264340,4]}}

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
	if not data is Dictionary: return "Invalid player aim capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported player aim"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes): return "Player aim lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid player aim provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]): return "Disconnected player aim declaration"
	return ""
