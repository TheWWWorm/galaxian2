extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Verified scripted rescue motion; NPC combat/factory systems remain separate.
const Declarations=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"rescue_mode_five_branch","campaign_cursor":1,"actor_id":0,"actor_kind":3,"hull_catalogue_id":30,"initial_mode":0,"initial_active":true,"script_mode":5,"script_active":false,"script_targeting_blocked":true,"active_mode":1,"activation_half_extent":50000,"target_index":0,"inactive_route_requires_target_list":true,"ordinary_travel_in_mode_five":false,"bank_updates_in_mode_five":false,"statistics_sync_before_mode":true}
const SPANS := {"x86_64":{"initial_mode":[-80932,25],"initial_active":[534937,7],"half_extent":[607204,38],"mode_setter":[-78898,44],"sync":[611560,61],"copy":[1237754,240],"route_gate":[614426,17],"target_fallback":[616370,26],"relative_position":[617108,86],"dispatch":[619552,40],"mode_five":[619682,255],"dispatch_table":[627906,40]},"armv7":{"initial_mode":[-74770,16],"initial_active":[490768,36],"half_extent":[547350,36],"mode_setter":[-72894,28],"sync":[551278,62],"copy":[1957842,164],"route_gate":[553906,18],"target_fallback":[554318,28],"relative_position":[554834,48],"dispatch":[557064,14],"mode_five":[558094,260],"dispatch_table":[557078,20]}}

const MAC_ALTERNATE := {"initial_mode":[-80932,25],"initial_active":[535473,7],"half_extent":[607752,38],"mode_setter":[-78898,44],"sync":[612108,61],"copy":[1230450,240],"route_gate":[614974,17],"target_fallback":[616918,26],"relative_position":[617656,86],"dispatch":[620100,40],"mode_five":[620230,255],"dispatch_table":[628454,40]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Declarations.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, bytes: int, arch: String, arrival: Dictionary, actors: Dictionary, environment: Dictionary) -> String:
	if not data is Dictionary:return "Missing rescue actor motion capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(arch):return "Unsupported rescue actor motion declarations"
	if arrival.get("campaign_cursor")!=1 or arrival.get("actor_kind")!=3 or arrival.get("actor_hull_id")!=30 or environment.is_empty() or actors.get("npc_initialization",{}).get("flight",{}).is_empty():return "Rescue actor motion lacks its source context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315 if arch=="x86_64" else 310],bytes):return "Rescue actor motion lacks its actor anchor"
	if data.provenance.size()!=SPANS[arch].size():return "Invalid rescue actor motion provenance"
	var layouts: Array=[SPANS[arch]]
	if arch=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),bytes,layouts) else "Disconnected rescue actor motion declaration"
