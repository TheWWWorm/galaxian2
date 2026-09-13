extends RefCounted
## Fresh ordinary flight and primary input after the first cinematic handoff.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"ordinary_phase":4,"postcombat_after_event_finished":10,"initial_pitch_units":0,"initial_yaw_units":0,"initial_throttle":1.0,"primary_category":0,"primary_requires_living_hull":true,"primary_contacts_before_npc":true,"fire_after_camera":true,"response_after_camera":true}
const SPANS := {"x86_64":{"initial_angular":[429398,20],"ordinary_path":[456905,90],"controller_result":[255595,24],"input_block":[256619,39],"primary_input":[256713,54],"primary_route":[438223,72],"primary_call":[256759,23],"primary_permission":[420670,45],"steering_input":[256994,51],"input_release":[17845,5],"postcombat_gate":[17889,21],"player_equipment_before_field":[-165110,5],"initial_normal_modes":[428741,14],"weapon_groups":[-4221,100],"primary_group":[-55066,7],"npc_group":[-64431,7],"rotation_anchor":[442786,24],"response_anchor":[473793,16]},"armv7":{"constructor_zero":[384198,2],"initial_angular":[384804,8],"ordinary_path":[406570,30],"ordinary_call":[411028,40],"controller_result":[264322,26],"input_block":[265248,40],"primary_input":[265364,44],"primary_call":[265494,16],"primary_route":[392156,74],"primary_permission":[377892,36],"steering_input":[265716,44],"input_release":[51176,4],"postcombat_gate":[39860,34],"player_equipment_before_field":[-160366,4],"initial_normal_modes":[384532,8],"weapon_groups":[-3304,84],"primary_group":[-57418,4],"npc_group":[-65644,4],"rotation_anchor":[396128,12],"response_anchor":[419772,12]}}

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
	if not data is Dictionary: return "Invalid ordinary player flight capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported ordinary player flight"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes): return "Ordinary player flight lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid ordinary player flight provenance"
	for key in SPANS[architecture]:
		var rule: Array=SPANS[architecture][key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]): return "Disconnected ordinary player flight declaration"
	return ""
