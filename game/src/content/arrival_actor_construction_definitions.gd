extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Verified rescue factory records; full world construction remains separate.
const Declarations=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"rescue_npc_factory_records","campaign_cursor":1,"actor_id":0,"actor_kind":3,"hull_catalogue_id":30,"subtype":0,"retains_generated_cargo":true,"replaces_generated_route":true,"authored_route_loop":false,"authored_route_initial_index":0,"body_basis_identity":true,"model_local_pose_identity":true,"placed_statistics_copy_body":true}
const SPANS := {"x86_64":{"factory_constructor":[78713,112],"factory_cargo_guard":[78873,25],"factory_finish":[81328,32],"generated_route_and_cargo":[606999,205],"authored_route_default":[721233,12],"attachment":[-79336,271],"placement":[609228,176],"body_node":[-725004,355],"model_node":[-725444,430],"instance_allocation":[1162298,40],"instance_matrix_init":[1064122,27],"identity_matrix":[1213114,129],"model_factory_gate":[-219294,66],"model_factory_normal":[-217601,1136],"model_binding":[1163242,680],"animation_initialization":[1067530,112]},"armv7":{"factory_constructor":[73746,114],"factory_cargo_guard":[73898,16],"factory_finish":[76536,18],"generated_route_and_cargo":[547150,200],"authored_route_default":[648850,10],"attachment":[-73172,180],"placement":[549118,88],"body_node":[-1073722,174],"model_node":[-1074006,266],"instance_allocation":[1908850,90],"instance_matrix_init":[1861446,40],"identity_matrix":[1882206,120],"identity_zero":[1882326,4],"model_factory_gate":[-205250,10],"model_factory_gate13":[-204580,12],"model_factory_normal":[-204202,816],"model_factory_finish":[-203184,184],"model_binding":[1909622,508],"animation_initialization":[1864154,82]}}

const MAC_ALTERNATE := {"factory_constructor":[78713,112],"factory_cargo_guard":[78873,25],"factory_finish":[81328,32],"generated_route_and_cargo":[607547,205],"authored_route_default":[721857,12],"attachment":[-79336,271],"placement":[609776,176],"body_node":[-730900,355],"model_node":[-731340,430],"instance_allocation":[1159618,40],"instance_matrix_init":[1064786,27],"identity_matrix":[1206898,128],"model_factory_gate":[-220250,66],"model_factory_normal":[-218557,1136],"model_binding":[1160546,664],"animation_initialization":[1068258,112]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Declarations.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, bytes: int, arch: String, arrival: Dictionary, actors: Dictionary, environment: Dictionary) -> String:
	if not data is Dictionary:return "Missing rescue actor construction capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(arch):return "Unsupported rescue actor construction declarations"
	if arrival.get("campaign_cursor")!=1 or arrival.get("actor_kind")!=3 or arrival.get("actor_hull_id")!=30 or environment.is_empty() or actors.get("npc_initialization",{}).get("construction",{}).is_empty() or actors.get("npc_initialization",{}).get("routes",{}).is_empty():return "Rescue actor construction lacks its source context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315 if arch=="x86_64" else 310],bytes):return "Rescue actor construction lacks its actor anchor"
	if data.provenance.size()!=SPANS[arch].size():return "Invalid rescue actor construction provenance"
	var layouts: Array=[SPANS[arch]]
	if arch=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),bytes,layouts) else "Disconnected rescue actor construction declaration"
