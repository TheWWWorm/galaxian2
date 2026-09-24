extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Verified kind-8 cargo retention and destruction context for the second trip.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const ControlDefinitions=preload("res://src/content/full_hold_control_definitions.gd")
const Death=preload("res://src/content/npc_destruction_definitions.gd")
const Accounting=preload("res://src/content/npc_death_accounting_definitions.gd")
const VALUES := {"scope":"full_hold_pirate_destruction","campaign_cursor":4,"actor_id":0,"actor_kind":8,"hull_catalogue_id":2,"subtype":0,"retains_generated_cargo":true,"companion":false,"mission_kind":154,"cargo_model_id":16993,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_002_nivelian.aem","cargo_spawn_at_post_tumble_position":true,"cargo_initial_basis":"identity","cargo_drift_per_positive_update":true,"cargo_drift_decay":0.9800000190734863,"cargo_drift_cutoff":0.05000000074505806,"cleanup_after_ms":60000,"cleanup_requires_inactive_effect":true,"cargo_rotation_delta_shift":1,"cargo_angle_fraction":1.52587890625e-05,"cargo_angle_tau":6.2831854820251465,"cargo_angle_truncated_to_integer":true,"statistics_copy_before_motion":true,"cargo_statistics_after_positive_update":true,"cargo_sets_statistics_owner":true,"counter_population":1}
const SPANS := {"npc_update":[610766,17180],"actor_constructor":[-81548,948],"npc_constructor":[605172,2562],"cargo_model":[-77266,246],"cargo_predicate":[-77020,46],"drift_setter":[537670,14],"drift_getter":[537698,14],"cargo_owner":[535790,14],"model_constructor":[-725444,430],"model_position_setter":[-724148,82],"model_rotation":[-723090,140],"model_translation":[-722902,200],"effect_update":[-680458,538],"world_death":[106510,1044],"retire":[-78854,18],"pirate_counter":[876300,26],"drift_decay":[1582570,4],"drift_cutoff":[1573782,4],"angle_fraction":[1575014,4],"angle_tau":[1575058,4]}

const MAC_ALTERNATE := {"npc_update":[611314,17180],"actor_constructor":[-81548,948],"npc_constructor":[605720,2562],"cargo_model":[-77266,246],"cargo_predicate":[-77020,46],"drift_setter":[538206,14],"drift_getter":[538234,14],"cargo_owner":[536326,14],"model_constructor":[-731340,430],"model_position_setter":[-730044,82],"model_rotation":[-728986,140],"model_translation":[-728798,200],"effect_update":[-686346,538],"world_death":[106510,1044],"retire":[-78854,18],"pirate_counter":[876932,26],"drift_decay":[1557634,4],"drift_cutoff":[1548846,4],"angle_fraction":[1550078,4],"angle_tau":[1550122,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, control: Dictionary, actors: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-trip destruction declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-trip destruction declarations"
	var npc: Dictionary=actors.get("npc_initialization",{})
	if not ControlDefinitions.parameters(control) or not Death.parameters(npc.get("destruction")) or not Accounting.parameters(npc.get("death_accounting")) or npc.get("construction",{}).is_empty():return "Second-trip destruction lacks verified control, death or accounting context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second-trip destruction lacks its source anchor"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid full hold destruction extents"
