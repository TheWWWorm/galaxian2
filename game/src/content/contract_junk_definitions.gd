extends RefCounted
## Verified stationary contract debris and result deadline.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Encounters=preload("res://src/content/contract_encounter_definitions.gd")
const Results=preload("res://src/content/contract_flight_result_definitions.gd")
const Particles=preload("res://src/content/full_hold_particle_definitions.gd")
const Transit=preload("res://src/content/convoy_transit_definitions.gd")
const VALUES = {"scope":"mido_contract_junk_lifecycle","campaign_cursor":13,"kind":7,"initial_mode":0,"destroyed_mode":4,"initial_active":true,"initial_targeting_blocked":false,"initial_model_draw_enabled":true,"hostile_remaining_delta":-1,"debris_destroyed_delta":1,"initial_debris_destroyed":0,"sound_id":22,"drop_draw_bound":100,"drop_inclusive_maximum":9,"cargo_item_id":99,"quantity_draw_bound":10,"quantity_add":1,"cargo_model_id":16990,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_001_midorian.aem","cargo_retains_activity":true,"empty_disables_activity":true,"empty_clears_selected_target":true,"stationary":true,"cargo_cleanup_milliseconds":-1,"burst_member_index":0,"burst_count":1,"burst_size_override":-1,"burst_initial_emitting":true,"burst_preset":{"preset_id":21,"material_id":20099,"flags":33554689,"capacity":10,"size_jitter":200,"lifetime_ms":1000,"even_spacing":0,"fade_in_ms":0,"size_growth_per_second":500,"scatter_xz":0,"scatter_y":0,"velocity_scatter":0,"animation_frames":16,"size":1600.0,"emission_per_second":500.0,"relative_velocity_factor":0.0,"local_velocity_z":0.0,"local_offset_y":0.0,"local_offset_z":0.0,"local_offset_z_jitter":0.0,"start_rgba":[255,255,255,255],"end_rgba":[255,255,255,255],"uv_rect":[0.0,0.0,0.25,0.25]},"deadline_milliseconds":121000,"deadline_comparison":"strictly_greater","deadline_uses_periodic_poll":true,"deadline_requires_idle_radio":false,"success_precedes_deadline":true,"failure_credit_delta":0}
const SPANS = {"junk_lifecycle_update":[640402,508],"junk_lifecycle_render":[640910,62],"junk_lifecycle_world_count":[107554,28],"junk_lifecycle_deadline_exclusion":[482186,12],"junk_lifecycle_deadline_poll":[388744,340],"junk_lifecycle_particle_registration":[63495,30],"junk_lifecycle_particle_copy":[498043,1407],"junk_lifecycle_initial_statistic":[881233,11],"junk_lifecycle_burst_size":[1556978,4]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

# Native helpers.
static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.early_contracts.get("junk_lifecycle")) and Encounters.parameters(bindings.early_contracts.get("encounter_construction")) and Results.available(bindings) and Particles.parameters(bindings.full_hold_particles)

static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not available(bindings):return {}
	var encounter: Variant=packet.get("contract_encounter")
	var actors: Variant=packet.get("actors")
	if not encounter is Dictionary or not encounter.get("context") is Dictionary or not actors is Array:return {}
	var context: Dictionary=encounter.context
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key) or context.get(key)!=bindings.get(key):return {}
	if not Transit.supports(bindings.mido_travel,packet.get("campaign_cursor")) or context.get("campaign_cursor")!=packet.campaign_cursor or packet.get("station_id")!=context.get("station_id") or context.station_id not in [75,76,77,78,79]:return {}
	if not context.get("rank") is int or context.rank<0 or context.rank>=bindings.opening_handoff.get("rank_thresholds",[]).size() or context.get("difficulty") not in [0.5,1.0]:return {}
	var mission: Variant=encounter.get("mission")
	if not mission is Dictionary or mission!=context.get("mission") or mission.get("kind")!=7 or encounter.get("kind")!=7 or mission.get("story")!=false or mission.get("difficulty") not in [1,2]:return {}
	var count:=15+2*int(mission.difficulty)
	if actors.size()!=count or encounter.get("actor_count")!=count:return {}
	var rules: Dictionary=bindings.early_contracts.junk_lifecycle
	var construction: Dictionary=bindings.early_contracts.encounter_construction.junk
	var data:={"campaign_cursor":context.campaign_cursor,"station_id":context.station_id,"rank":context.rank,"difficulty":context.difficulty,
		"mission":mission.duplicate(true),"lifecycle":rules.duplicate(true),"actor_count":count,"npc_weapons":[],"actors":[]}
	for id in count:
		var row: Variant=actors[id]
		if not row is Dictionary or row.get("actor_id")!=id or row.get("population_group")!="debris" or row.get("actor_kind")!=-1:return {}
		for pair in [["type_id","type_id"],["hull","hull"],["half_extent","half_extent"],["mode","mode"],["hostile","hostile"],["friendly","friendly"]]:
			if row.get(pair[0])!=construction[pair[1]]:return {}
		if not construction.model_ids.any(func(id):return int(id)==row.get("resource_id")) or row.get("cargo")!=[] or row.get("fragments")!=[] or not row.get("body_pose") is Transform3D or row.body_pose!=row.get("statistics_pose") or not row.body_pose.is_finite():return {}
		data.actors.append({"actor_id":id,"actor_kind":-1,"population_group":"debris","hostile":true,
			"cargo_model_id":int(rules.cargo_model_id),"cargo_model_resource":rules.cargo_model_resource})
	return data
