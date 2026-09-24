extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Combat-training construction only. Mission activation, combat and rewards
## require their own verified owners before this flight can be offered.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Equipment=preload("res://src/content/station_equipment_definitions.gd")
const Construction=preload("res://src/content/npc_construction_definitions.gd")
const Routes=preload("res://src/content/npc_route_definitions.gd")
const World=preload("res://src/content/opening_world_initialization_definitions.gd")
const VALUES := {"scope":"combat_training_encounter_construction","campaign_cursor":7,"mission_kind":4,"station_id":78,"system_id":15,"actor_count":4,"waypoints":[[-4000,-3000,80000],[10000,7000,160000]],"authored_route_initial_index":0,"authored_route_loop":false,"pirate_count":3,"pirate_actor_kind":8,"pirate_hull_catalogue_id":2,"pirate_waypoint_index":1,"pirate_mode":5,"pirate_active":false,"pirate_targeting_blocked":true,"companion_actor_id":3,"companion_actor_kind":3,"companion_hull_catalogue_id":30,"companion_position_offset":[700.0,50.0,6000.0],"companion_friendly":true,"companion_current_hull_override":9999999,"companion_name_text_id":1580,"subtype":0,"retains_generated_cargo":true,"companion_replaces_generated_route":true,"weapon_item_sequence":[0,19],"weapon_effect_sequence":[14600,14605],"companion_weapon_item_sequence":[0,25],"companion_weapon_effect_sequence":[14600,14606],"weapon_effect_capacity":4,"weapon_effect_random_bound":2,"zero_means_flipped":true}
const SPANS := {"actor_dispatch":[571,611],"waypoints":[1579386,24],"companion_x":[1546006,4],"companion_y":[1557078,4],"companion_z":[1575334,4],"route_constructor":[721210,378],"route_wrapper":[721200,10],"route_copy":[723224,472],"route_point":[722434,150],"route_replace":[-77698,104],"route_advance":[722824,302],"friendly":[535652,28],"hull_override":[537014,30],"weapon_effect_0":[1572842,4],"weapon_effect_19":[1572918,4],"weapon_effect_25":[1572942,4],"factory":[77944,3478],"route_and_cargo":[605172,2070],"inactive_mode":[-78898,44],"activity":[-78836,36],"activity_field":[540910,14],"hostile":[535624,28],"position_setter":[609228,176],"world_order":[-44096,2458],"weapons":[54772,4266],"extra_story":[51826,1046]}

const MAC_ALTERNATE := {"actor_dispatch":[571,611],"waypoints":[1554450,24],"companion_x":[1520990,4],"companion_y":[1532078,4],"companion_z":[1550398,4],"route_constructor":[721834,378],"route_wrapper":[721824,10],"route_copy":[723848,472],"route_point":[723058,150],"route_replace":[-77698,104],"route_advance":[723448,302],"friendly":[536188,28],"hull_override":[537550,30],"weapon_effect_0":[1547906,4],"weapon_effect_19":[1547982,4],"weapon_effect_25":[1548006,4],"factory":[77944,3478],"route_and_cargo":[605720,2070],"inactive_mode":[-78898,44],"activity":[-78836,36],"activity_field":[541446,14],"hostile":[536160,28],"position_setter":[609776,176],"world_order":[-44096,2458],"weapons":[54772,4266],"extra_story":[51826,1046]}
const MAC_VALUES := {"scope":"combat_training_encounter_construction","campaign_cursor":7,"mission_kind":4,"station_id":78,"system_id":15,"actor_count":4,"waypoints":[[-4000,-3000,80000],[10000,7000,160000]],"authored_route_initial_index":0,"authored_route_loop":false,"pirate_count":3,"pirate_actor_kind":8,"pirate_hull_catalogue_id":2,"pirate_waypoint_index":1,"pirate_mode":5,"pirate_active":false,"pirate_targeting_blocked":true,"companion_actor_id":3,"companion_actor_kind":3,"companion_hull_catalogue_id":30,"companion_position_offset":[700.0,50.0,6000.0],"companion_friendly":true,"companion_current_hull_override":9999999,"companion_name_text_id":1588,"subtype":0,"retains_generated_cargo":true,"companion_replaces_generated_route":true,"weapon_item_sequence":[0,19],"weapon_effect_sequence":[14600,14605],"companion_weapon_item_sequence":[0,25],"companion_weapon_effect_sequence":[14600,14606],"weapon_effect_capacity":4,"weapon_effect_random_bound":2,"zero_means_flipped":true}

static func parameters(data: Variant) -> bool:
	return _parameters(data,VALUES) or _parameters(data,MAC_VALUES)

static func _parameters(data: Variant,expected: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=expected.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in expected:
		if not Equal.equal_value(data.get(key),expected[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, equipment: Dictionary, actors: Dictionary) -> String:
	if not data is Dictionary:return "Missing combat-training construction declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported combat-training construction declarations"
	var npc: Dictionary=actors.get("npc_initialization",{})
	if not Equipment.parameters(equipment) or not Construction.parameters(npc.get("construction")) or not Routes.parameters(npc.get("routes")) or not World.parameters(npc.get("world_initialization")):return "Combat training lacks its equipment or NPC construction context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Combat training lacks its source anchor"
	var layouts: Array=[]
	if _parameters(data,VALUES):layouts.append(SPANS)
	if _parameters(data,MAC_VALUES):layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid combat training extents"
