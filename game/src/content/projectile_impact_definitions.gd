extends RefCounted
## Fresh ordinary impact declarations; clocks retain pre-contact model samples.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Layouts = preload("res://src/content/declaration_layouts.gd")
const VALUES := {"item_ids":[2,19],"model_ids":[14600,14605],"kinds":[0,1],"initial_playing":false,"animation_speed":1.0,"animation_loop":false,"camera_basis_copy":true,"position_is_projectile":true,"sample_before_contacts":true,"restart_preserves_sample":true,"render_type":2}
const SPANS := {"x86_64":{"player_setter":[-57023,35],"effect_table":[-310645,27],"allocation":[-310618,42],"initial_disabled":[-310469,32],"update_before_contacts":[-302299,113],"contact_restart":[-304271,84],"contact_position":[-304187,165],"position_load":[-303620,48],"draw":[-301683,394],"wrapper_draw":[355864,9],"restart_mode":[945503,112],"end_sample":[946259,59],"npc_setter":[-65918,31],"model_2":[1450823,4],"model_19":[1450891,4]},"armv7":{"player_setter":[-58548,32],"effect_table":[-293460,22],"allocation":[-293438,44],"initial_disabled":[-293274,28],"update_before_contacts":[-287508,92],"contact_restart":[-288462,52],"contact_position":[-288410,118],"position_load":[-289392,28],"draw":[-287042,276],"wrapper_draw":[367462,8],"restart_mode":[1745034,82],"end_sample":[1745468,48],"npc_setter":[-66740,22],"model_2":[2339938,4],"model_19":[2340006,4]}}

const MAC_ALTERNATE := {"player_setter":[-57023,35],"effect_table":[-311137,27],"allocation":[-311110,42],"initial_disabled":[-310961,32],"update_before_contacts":[-302791,113],"contact_restart":[-304763,84],"contact_position":[-304679,165],"position_load":[-304112,48],"draw":[-302175,394],"wrapper_draw":[356390,9],"restart_mode":[946231,112],"end_sample":[946987,59],"npc_setter":[-65918,31],"model_2":[1425887,4],"model_19":[1425955,4]}

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
	if not data is Dictionary: return "Invalid ordinary projectile impacts capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported ordinary projectile impacts"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes): return "Ordinary projectile visuals lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid ordinary projectile impacts provenance"
	var layouts: Array=[SPANS[architecture]]
	if architecture=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(initial.offset),executable_bytes,layouts) else "Disconnected ordinary projectile impacts declaration"
