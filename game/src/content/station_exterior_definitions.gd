extends RefCounted
## Actual first mining station model and point volumes; no arrival transition.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const VALUES := {"scope":"first_mining_station_exterior","station_id":78,"system_id":15,"faction":3,"system_faction_field":2,"model_ids":[21078,21878,22078],"render_types":[28,0,2],"position":[0,0,0],"rotation":[0,3.1415927410125732,0],"mesh_axis_map":[1,2,3],"sphere_axis_map":[1,3,-2],"collision_resource":"resources/data/bin/collision.bin","collision_record_limit":136,"collision_box_kind":1,"collision_position_map":[-1,3,2],"collision_half_extent_map":[1,3,2],"collision_scale":1,"bounds_margin":5000,"bounds_rounding":"truncate","bounds_test":"strict_axis_box","volume_test":"strict_axis_box","light_animation_supported":false,"docking_transition_supported":false}
const SPANS := {"world_station":[-39936,286],"station_exclusion":[872234,488],"station_constructor":[642332,291],"model_choice":[644326,327],"ordinary_layers_gate":[646014,36],"mido_layers":[647628,243],"constructor_finish":[648859,112],"collision_loader":[-677702,346],"little_endian_int":[1394106,53],"shape_dispatch":[645756,197],"box_arguments":[648537,290],"box_constructor":[-710264,147],"box_origin":[-708682,54],"box_point":[-710024,122],"station_point":[649814,244],"station_vtable":[2401210,48],"box_vtable":[2396530,8],"layer_parent":[-724500,48],"layer_bounds_merge":[1164173,94],"sphere_merge":[1063050,810],"layer_sphere":[1061850,1192],"mesh_vertex_copy":[1222939,213],"mesh_sphere_load":[1214430,269],"mesh_sphere_attach":[1163398,45],"model_rotation":[-723494,90],"faction_read":[-673260,45],"faction_argument":[-672644,107],"faction_constructor":[734132,137],"faction_getter":[734664,10],"rotation_pi":[1546070,4],"bounds_padding":[1545990,4],"box_scale":[1544610,4],"box_half":[1544586,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary) -> String:
	if not data is Dictionary:return "Missing station exterior declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight):return "Unsupported station exterior declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station exterior lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station exterior provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid station exterior extent: "+key
	return ""
