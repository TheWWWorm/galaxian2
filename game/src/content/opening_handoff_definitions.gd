extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Bounded Mac state retained across the native Opening-to-rescue transition.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"fresh_opening_handoff","opening_cursor":0,"arrival_cursor":1,"center_cursor_upper_inclusive":44,"initial_other_score":0,"player_kill_weight":1,"pirate_kill_weight":2,"cursor_weight":1,"rank_thresholds":[0,7,21,42,70,105,147,196,252,315,385,462,546,637,735,840,952,1071,1197,1330,1650],"initial_companion_count":0,"initial_location_wrapper_id":-1,"initial_reputation":[30,0],"initial_reputation_override":-1,"pirate_reputation_change_maximum":2,"rescue_reputation_axis":1,"rescue_hostile_above":70,"rescue_hostile_override":2,"reputation_override_equipment_type":29}
const SPANS := {"cursor_predicate":[858140,16],"rank_calculation":[876028,136],"rank_thresholds":[1591610,84],"fresh_companions":[881087,16],"fresh_location_wrapper":[854382,28],"wrapper_defaults":[850809,14],"location_comparison":[853288,22],"reputation_initial":[806990,50],"fresh_reputation":[882961,33],"hostility":[807440,128],"pirate_reputation":[807862,168],"reputation_adjustment":[808046,168],"reputation_double_predicate":[873106,34],"reputation_mask_reset":[727691,54],"equipment_dispatch":[727786,42],"equipment_table":[728830,120],"equipment_override":[728429,66]}

const MAC_ALTERNATE := {"cursor_predicate":[858772,16],"rank_calculation":[876660,136],"rank_thresholds":[1566706,84],"fresh_companions":[881719,16],"fresh_location_wrapper":[855014,28],"wrapper_defaults":[851441,14],"location_comparison":[853920,22],"reputation_initial":[807622,50],"fresh_reputation":[883593,33],"hostility":[808072,128],"pirate_reputation":[808494,168],"reputation_adjustment":[808678,168],"reputation_double_predicate":[873738,34],"reputation_mask_reset":[728315,54],"equipment_dispatch":[728410,42],"equipment_table":[729454,120],"equipment_override":[729053,66]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, bytes: int, arch: String, arrival: Dictionary, actors: Dictionary, world: Dictionary) -> String:
	if not data is Dictionary:return "Missing Opening handoff capability"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported Opening handoff declarations"
	var npc: Dictionary=actors.get("npc_initialization",{})
	var hull: Dictionary=npc.get("hull",{})
	if world.is_empty() or npc.get("death_accounting",{}).is_empty() or actors.get("player_initialization",{}).get("flight_cache",{}).is_empty() or hull.get("rank")!=0 or hull.get("base_hull")!=20 or not hull.get("provenance",{}).has("rank_calculation"):return "Opening handoff lacks its retained-state dependencies"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],bytes):return "Opening handoff lacks its scene anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid Opening handoff provenance"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),bytes,layouts) else "Disconnected Opening handoff declaration"
