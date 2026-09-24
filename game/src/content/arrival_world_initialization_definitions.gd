extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## A rescue world profile composed with the shared source initialization proof.
const Declarations=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"rescue_world_initialization","campaign_cursor":1,"world_type":3,"actor_count":1,"quest_kind":11,"quest_scripted":true,"requires_empty_companions":true,"requires_ordinary_location":true,"requires_campaign_mode":true,"center_random_bound":100000,"center_offsets":[-50000,-50000,20000],"center_after_station_count":true,"reseed_before_field":true,"weapon_item_sequence":[0,25],"weapon_effect_sequence":[14600,14606],"weapon_kind":0,"projectile_visual_id":6802,"weapon_effect_capacity":4,"weapon_effect_random_bound":2,"zero_means_flipped":true}
const SPANS := {"x86_64":{"quest_wrapper":[399256,10],"quest_arguments":[399283,12],"quest_fields":[399346,28],"quest_scripted":[399523,45],"quest_absent":[400436,14],"quest_scripted_getter":[400856,16],"world_scripted_gate":[-42348,96],"world_scripted_loader":[-42120,91],"center":[-35100,664],"npc_weapon_enabled":[607329,30],"weapon_kind_dispatch":[57456,56],"weapon_kind_table":[58994,44],"rescue_weapon":[55980,24],"cursor_getter":[858156,12],"effect_model_25":[1572942,4]},"armv7":{"quest_wrapper":[408846,16],"quest_arguments":[408362,8],"quest_fields":[408476,26],"quest_scripted":[408628,24],"quest_absent":[409546,16],"quest_scripted_getter":[409682,12],"world_scripted_gate":[-40978,88],"world_scripted_loader":[-40692,80],"center":[-33840,558],"npc_weapon_enabled":[547464,24],"weapon_kind_dispatch":[52314,30],"weapon_kind_table":[52344,11],"rescue_weapon":[52744,18],"cursor_getter":[798162,8],"effect_model_25":[2459150,4]}}

const MAC_ALTERNATE := {"quest_wrapper":[399772,10],"quest_arguments":[399799,12],"quest_fields":[399862,28],"quest_scripted":[400039,45],"quest_absent":[400952,14],"quest_scripted_getter":[401372,16],"world_scripted_gate":[-42348,96],"world_scripted_loader":[-42120,91],"center":[-35100,664],"npc_weapon_enabled":[607877,30],"weapon_kind_dispatch":[57456,56],"weapon_kind_table":[58994,44],"rescue_weapon":[55980,24],"cursor_getter":[858788,12],"effect_model_25":[1548006,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Declarations.equal_value(data.get(key),VALUES[key]):return false
	return true

static func entry_conditions(data: Variant) -> bool:
	# This capability fixes the cursor at one, below the source getter's >44
	# threshold. Its historical requires_campaign_mode label is not a setting.
	return data is Dictionary and data.size()==2 and data.get("companions_empty") is bool and data.companions_empty and data.get("location_match") is bool and not data.location_match

static func validate(data: Variant, bytes: int, arch: String, arrival: Dictionary, actors: Dictionary, construction: Dictionary, environment: Dictionary) -> String:
	if not data is Dictionary:return "Missing rescue world initialization capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(arch):return "Unsupported rescue world initialization declarations"
	var shared: Dictionary=actors.get("npc_initialization",{}).get("world_initialization",{})
	var cache: Dictionary=actors.get("player_initialization",{}).get("flight_cache",{})
	if arrival.get("campaign_cursor")!=1 or arrival.get("actor_kind")!=3 or arrival.get("actor_hull_id")!=30 or construction.is_empty() or environment.is_empty() or shared.is_empty() or cache.get("quest_kind")!=11:return "Rescue world initialization lacks its source context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315 if arch=="x86_64" else 310],bytes):return "Rescue world initialization lacks its actor anchor"
	if data.provenance.size()!=SPANS[arch].size():return "Invalid rescue world initialization provenance"
	var layouts: Array=[SPANS[arch]]
	if arch=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),bytes,layouts) else "Disconnected rescue world initialization declaration"
