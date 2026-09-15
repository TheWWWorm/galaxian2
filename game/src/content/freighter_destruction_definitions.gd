extends RefCounted
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
## Original early Mido freighter lifecycle. This capability grants no mission progress.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Combat=preload("res://src/content/ambient_combat_definitions.gd")
const Convoy=preload("res://src/content/convoy_lifecycle_definitions.gd")
const VALUES = {"scope":"early_mido_freighter_destruction","campaign_cursor":11,"station_id":79,"system_id":15,"actor_kind":3,"subtype":1,"hull_catalogue_id":15,"animation_mode":3,"wreck_mode":4,"model_id":18300,"model_resource":"resources/data/assets/main/3d/meshes/ships/cargo_001_midorian_explosion_anim.aem","cargo_model_id":16990,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_001_midorian.aem","wreck_resource":"resources/data/bin/wreck_collisions.bin","wreck_layout_id":1,"wreck_record_limit":6,"wreck_box_scale":1.100000023841858,"wreck_sphere_scale":0.6000000238418579,"initial_material_id":34700,"wreck_material_id":33352,"wreck_change_at_ms":141,"cleanup_after_ms":60000,"cargo_rotation_delta_shift":1,"cargo_angle_fraction":1.52587890625e-05,"cargo_angle_tau":6.2831854820251465,"initial_effect_scale":1.0,"final_effect_scale":6.0,"effect_type":0,"initial_sound_id":20,"effect_sound_base":18,"effect_sound_bound":2,"fragments_generated_on_death":true,"cargo_spawn_phase":"animation","cargo_initial_basis":"identity","cargo_drift":false,"animation_advances_on_entry":true,"world_movement_on_death":false,"interaction_blocked_during_animation":false,"wreck_draw_after_cleanup":true,"nonhostile_remaining_delta":-1,"pirate_kills_delta":0}
const SPANS = {"freighter_update":[634134,4064],"death_model":[633586,336],"freighter_draw":[638262,174],"cargo_model":[-77266,246],"cargo_predicate":[-77020,46],"active_setter":[-78854,18],"wreck_reader":[-677302,398],"wreck_volumes":[-220182,888],"freighter_point":[638832,218],"effect_fragments":[-682314,482],"effect_reset":[-682904,424],"effect_scale":[-683262,358],"effect_trigger":[-681366,484],"effect_sound":[-681822,456],"hostile_death":[106510,1044],"nonhostile_death":[107650,12],"animation_mode":[1067530,112],"animation_step":[1068036,309],"wreck_box_scale":[1557770,4],"wreck_sphere_scale":[1556934,4],"effect_scales":[1588802,8],"cargo_angle_fraction":[1575014,4],"cargo_angle_tau":[1575058,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func for_context(bindings: RefCounted,cursor: Variant,station_id: Variant=null) -> Dictionary:
	if bindings==null or not parameters(bindings.freighter_destruction):return {}
	var context:=Combat.for_context(bindings,cursor,station_id)
	if context.is_empty():return {}
	var result: Dictionary=bindings.freighter_destruction.duplicate(true)
	result.campaign_cursor=int(cursor);result.station_id=int(context.station_id)
	return result

static func for_convoy(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.freighter_destruction) or not Convoy.available(bindings):return {}
	var result: Dictionary=bindings.freighter_destruction.duplicate(true)
	result.merge(bindings.mido_travel.convoy_lifecycle.capital_death,true)
	result.campaign_cursor=int(bindings.mido_travel.convoy_lifecycle.campaign_cursor)
	result.actor_kind=int(bindings.mido_travel.convoy_ship.actor_kind)
	result.hull_catalogue_id=int(bindings.mido_travel.convoy_ship.hull_catalogue_id)
	result.cargo_model_id=16992;result.cargo_model_resource="resources/data/assets/main/3d/meshes/misc/container_003_terran.aem"
	result.model_scale=float(bindings.mido_travel.convoy_ship.assembly.model_scale)
	return result

static func for_alioth(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.freighter_destruction) or not Alioth.Life.available(bindings):return {}
	var result: Dictionary=bindings.freighter_destruction.duplicate(true)
	result.merge(bindings.mido_travel.alioth_lifecycle.freighter_death,true)
	for key in ["campaign_cursor","station_id","system_id"]:result[key]=int(bindings.mido_travel.alioth_attack[key])
	result.actor_kind=0;result.cargo_model_id=16992
	result.cargo_model_resource="resources/data/assets/main/3d/meshes/misc/container_003_terran.aem"
	return result

static func for_free(bindings: RefCounted,faction: int,context: Dictionary) -> Dictionary:
	if not FreeLife.available(bindings) or not FreeLife.Traffic.context_valid(bindings,context) or faction not in [0,2]:return {}
	var result:=for_alioth(bindings)
	if result.is_empty():return {}
	if faction==2:result.merge(bindings.mido_travel.free_lifecycle.nivelian_death,true)
	for key in ["campaign_cursor","station_id","system_id"]:result[key]=int(context[key])
	result.actor_kind=faction
	for row in bindings.early_contracts.ship_lifecycle.cargo_models:
		if int(row.actor_kind)==faction:
			result.cargo_model_id=int(row.cargo_model_id);result.cargo_model_resource=row.cargo_model_resource
	return result

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,combat: Dictionary) -> String:
	if not data is Dictionary:return "Missing freighter destruction declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Combat.parameters(combat):return "Unsupported freighter destruction declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Freighter destruction lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid freighter destruction provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid freighter destruction extent: "+key
	return ""
