extends RefCounted
## Original recurring portal inside the first Void world.
const Equal = preload("res://src/content/opening_escape_definitions.gd")
const Stage = preload("res://src/content/sahi_stage_definitions.gd")
const Thynome = preload("res://src/content/thynome_expedition_definitions.gd")
const Probe = preload("res://src/content/void_probe_definitions.gd")
const VALUES = {"scope":"void_return_portal","campaign_cursor":25,"mission_kind":156,"system_id":-1,"station_id":-1,"same_station":true,"portal":{"model_id":16994,"environment_slot":3,"initial_elapsed_ms":0,"initial_extent":4096,"open_duration_ms":3000,"close_start_ms":60000,"hide_at_ms":63001,"extent_scale":4096,"model_scale_shift":4,"model_scale_fraction":1.52587890625e-05,"facing_x_offset":0.5,"animation_advances_while_hidden":true,"closed_relocates":true,"relocation":{"opening_elapsed_ms":-3000,"random_bounds":[60000,2,40000,40000],"x_magnitude_offset":30000,"x_positive_sign_draw":0,"y_offset":20000,"z_offset":-60000,"z_draw_multiplier":-1,"preserve_closing_extent_on_relocation_frame":true,"facing_uses_relocated_position":true,"cancel_player_autopilot_on_relocation":true}},"contact":{"cube_half_extent":40000.0,"cube_boundary":"exclusive","distance_rounding":"truncate","pull_radius":40000,"pull_distance_shift":8,"pull_step":"per_contact_update","entry_distance_maximum":999,"requires_visible":true,"requires_not_closing":true,"requires_inactive_mining":true}}
const SPANS = {"void_portal_update":[655588,1380],"void_portal_vtable":[2401610,192],"void_portal_draw":[656968,34],"void_portal_facing":[655548,26],"void_portal_duration":[1546010,4],"void_portal_extent":[1588942,4],"void_portal_scale":[1575014,4],"void_portal_facing_offset":[1544586,4],"void_portal_next_factory_dispatch":[871502,4],"void_portal_next_factory":[861944,107],"void_portal_protected_cargo_getter":[-81574,10],"void_portal_next_cargo_loop":[871388,8],"void_portal_protect_cargo_item":[-84714,10],"void_portal_same_station":[858058,26],"void_portal_station_equal":[853288,22],"void_portal_portal_constructor":[655150,180],"void_portal_portal_contact":[585200,684],"void_portal_portal_closing":[655460,20],"void_portal_portal_point_xyz":[642072,96],"void_portal_portal_point_xyz_wrapper":[642202,12],"void_portal_portal_point_wrapper":[-76580,26],"void_portal_entry_ready":[562952,38],"void_portal_void_station_allocation":[854382,28],"void_portal_void_station_defaults":[850809,68]}
const MAC_SPANS = {"void_portal_update":[656136,1380],"void_portal_vtable":[2379042,192],"void_portal_draw":[657516,34],"void_portal_facing":[656096,26],"void_portal_duration":[1520994,4],"void_portal_extent":[1564038,4],"void_portal_scale":[1550078,4],"void_portal_facing_offset":[1519570,4],"void_portal_next_factory_dispatch":[872134,4],"void_portal_next_factory":[862576,107],"void_portal_protected_cargo_getter":[-81574,10],"void_portal_next_cargo_loop":[872020,8],"void_portal_protect_cargo_item":[-84714,10],"void_portal_same_station":[858690,26],"void_portal_station_equal":[853920,22],"void_portal_portal_constructor":[655698,180],"void_portal_portal_contact":[585736,684],"void_portal_portal_closing":[656008,20],"void_portal_portal_point_xyz":[642620,96],"void_portal_portal_point_xyz_wrapper":[642750,12],"void_portal_portal_point_wrapper":[-76580,26],"void_portal_entry_ready":[563488,38],"void_portal_void_station_allocation":[855014,28],"void_portal_void_station_defaults":[851441,68]}

# Native composition.
static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func coherent(travel: Dictionary) -> bool:
	return parameters(travel.get("void_portal")) and Stage.coherent(travel)

static func selected(travel: Dictionary,context: Dictionary) -> bool:
	if not coherent(travel):return false
	if context.get("mission_story")!=true or context.get("mission_completed")!=false or context.get("mission_failed")!=false:return false
	var expected:=selected_identity(travel,context.get("campaign_cursor"))
	if expected.is_empty():return false
	for key in expected:
		if not context.get(key) is int or context[key]!=expected[key]:return false
	return true

static func selected_identity(travel: Dictionary,cursor: Variant) -> Dictionary:
	if cursor==VALUES.campaign_cursor:
		return {"campaign_cursor":int(VALUES.campaign_cursor),"mission_kind":int(VALUES.mission_kind),
			"system_id":int(VALUES.system_id),"station_id":int(VALUES.station_id),
			"current_station_id":int(VALUES.station_id),"void_station_id":int(VALUES.station_id)}
	if cursor==28 and Thynome.coherent(travel):
		var mission: Dictionary=travel.thynome_expedition.mission28
		var world: Dictionary=travel.thynome_expedition.world28.entry
		return {"campaign_cursor":int(mission.campaign_cursor),"mission_kind":int(mission.kind),
			"system_id":int(mission.system_id),"station_id":int(mission.station_id),
			"current_station_id":int(world.selected_station_id),"void_station_id":int(world.persistent_portal_station_id)}
	if cursor==29 and Thynome.coherent(travel) and Probe.parameters(travel.get("void_probe")):
		var mission: Dictionary=travel.void_probe.mission29
		var world: Dictionary=travel.void_probe.world29.entry
		return {"campaign_cursor":int(mission.campaign_cursor),"mission_kind":int(mission.kind),
			"system_id":int(mission.system_id),"station_id":int(mission.station_id),
			"current_station_id":int(world.selected_station_id),"void_station_id":int(world.persistent_portal_station_id),
			"return_station_id":int(world.recorded_return_station_id)}
	return {}

## The mission29 selection is rejected by the original portal transition until
## final result Next retires it. Physical portal pull remains independent.
static func contact_admission(probe: Dictionary,portal: Dictionary,selection: Variant) -> int:
	if not Probe.parameters(probe) or portal.get("campaign_cursor")!=int(probe.mission29.campaign_cursor) or not selection is Dictionary or selection.size()!=9:return -1
	for key in ["base_content_id","binding_id"]:
		if selection.get(key)!=portal.get(key):return -1
	for key in ["campaign_cursor","mission_kind","current_station_id","return_station_id"]:
		if not selection.get(key) is int:return -1
	for key in ["mission_story","mission_completed","mission_failed"]:
		if not selection.get(key) is bool:return -1
	if selection.current_station_id!=int(probe.world29.entry.selected_station_id) or selection.return_station_id!=int(probe.world29.entry.recorded_return_station_id) or selection.mission_failed:return -1
	if selection.campaign_cursor==int(probe.mission29.campaign_cursor):
		return 0 if selection.mission_kind==int(probe.mission29.kind) and selection.mission_story else -1
	return 1 if selection.campaign_cursor==int(probe.world29.final_next.advances_to_cursor) and selection.mission_kind==-1 and not selection.mission_story and selection.mission_completed else -1
