extends RefCounted
## Source-bound physical player contacts with the first station slot and intact asteroid bodies.
## Source executable bytes are used only during import and never enter a binding pack.
const Layouts=preload("res://src/content/declaration_layouts.gd")
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Scenery=preload("res://src/content/scenery_resource_definitions.gd")
const Station=preload("res://src/content/station_exterior_definitions.gd")
const VALUES := {"scope":"physical_scenery_contacts","player_stage":"after_motion_before_aim_recharge","collision_gate":"player_permission_and_active_statistics","station_slot":0,"station_contact":"strict_authored_point_volume","station_projection_passes":2,"station_damage":0,"asteroid_contact":"strict_point_inside_intact_body_axis_box","asteroid_damage":9999,"player_damage":20,"asteroid_impact":"body_center_minus_player_center_normalized","selected_mining_target_excluded":true,"mining_finish":"inactive_negative_hull_without_combat_destruction","opening_collision_initial_enabled":false,"opening_collision_enabled_phase":4,"opening_collision_escape_phase":5,"opening_collision_earned_escape_enabled":false,"opening_collision_sample":"incoming_player_phase_before_controller"}
const APP_SPANS := {"player_sample":[571779,52],"player_motion":[576697,142],"collision_gate":[576839,90],"world_contact":[585516,1666],"asteroid_active":[547365,22],"asteroid_normal":[550106,158],"asteroid_collider":[550264,202],"asteroid_vtable":[2376994,72],"station_query":[650374,232],"station_projection":[-713946,190],"station_response_vtable":[2378722,24],"box_projection":[-715776,498],"sphere_projection":[-714814,236],"mining_finish":[602607,61],"permission_setter":[560162,14],"opening_constructor_off":[122009,18],"opening_release_on":[139783,128],"opening_escape_off":[150612,306],"opening_escape_guard":[150932,250]}
const MAC_ALTERNATE := {"player_sample":[571243,52],"player_motion":[576161,142],"collision_gate":[576303,90],"world_contact":[584980,1664],"asteroid_active":[546829,22],"asteroid_normal":[549570,158],"asteroid_collider":[549728,202],"asteroid_vtable":[2399562,72],"station_query":[649826,232],"station_projection":[-708050,190],"station_response_vtable":[2401290,24],"box_projection":[-709880,498],"sphere_projection":[-708918,236],"mining_finish":[602059,61],"permission_setter":[559626,14],"opening_constructor_off":[122009,18],"opening_release_on":[139783,128],"opening_escape_off":[150612,306],"opening_escape_guard":[150932,250]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, architecture: String, arrival: Dictionary, scenery: Dictionary, station: Dictionary, opening: Dictionary) -> String:
	if not data is Dictionary:return "Missing physical scenery contact declarations"
	if data.is_empty():return ""
	if architecture!="x86_64" or not parameters(data) or not Scenery.parameters(scenery) or not Station.parameters(station):return "Unsupported physical scenery contact declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Physical scenery contacts lack their source anchor"
	if not Layouts.matches(data.provenance,int(origin.offset),source_bytes,[APP_SPANS,MAC_ALTERNATE]):return "Invalid physical scenery contact extents"
	var initial: Variant=opening.get("provenance",{}).get("initial")
	var motion: Variant=opening.get("player_motion")
	var escape: Variant=opening.get("escape")
	if not Fonts.extent(initial,"offset","bytes",[366],source_bytes) or not motion is Dictionary or not escape is Dictionary:return "Physical opening contact lacks its source declarations"
	if motion.get("motion_before_controller")!=true or motion.get("release_phase")!=data.opening_collision_enabled_phase or motion.get("release_after_event_finished")!=8 or escape.get("entry_phase")!=data.opening_collision_enabled_phase or escape.get("first_phase")!=data.opening_collision_escape_phase or escape.get("entry_after_event_finished")!=10:return "Physical opening contact disagrees with its flight phases"
	var release: Variant=motion.get("provenance",{}).get("release")
	var entry: Variant=escape.get("provenance",{}).get("entry")
	if not Fonts.extent(release,"offset","bytes",[46],source_bytes) or not Fonts.extent(entry,"offset","bytes",[306],source_bytes):return "Physical opening contact lacks its source transitions"
	if int(data.provenance.opening_constructor_off.offset)!=int(initial.offset)-18 or int(data.provenance.opening_release_on.offset)!=int(release.offset) or data.provenance.opening_escape_off!=entry:return "Physical opening contact is detached from its source transitions"
	return ""
