extends RefCounted
## Source-bound Alioth lifecycle variations. Native owners share ordinary rules.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Attack=preload("res://src/content/alioth_attack_definitions.gd")
const VALUES = {"scope":"alioth_attack_lifecycle","campaign_cursor":16,"system_id":19,"actor_kinds":[0,0,0,9,9,9,9,0,0,0],"boost_enabled":true,"retains_factory_previous_hull":true,"forced_friendly_kind":0,"reaction_factions":[0,1],"primary_faction":0,"void_reputation_change":0,"void_pirate_kills_delta":0,"void_cargo":{"actor_kind":9,"cargo_model_id":16916,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_005_void.aem"},"freighter_death":{"model_id":18302,"model_resource":"resources/data/assets/main/3d/meshes/ships/cargo_003_terran_explosion_anim.aem","initial_material_id":34708,"wreck_material_id":33354,"wreck_layout_id":3,"model_scale":1.0}}
const SPANS = {"alioth_lifecycle_target_opposition":[614204,102],"alioth_lifecycle_freighter_factory":[80265,13],"alioth_lifecycle_small_constructor":[605172,2562],"alioth_lifecycle_freighter_update":[634134,4064],"alioth_lifecycle_death_model":[633586,336],"alioth_lifecycle_cargo_model":[-77266,246],"alioth_lifecycle_friendship":[535652,28],"alioth_lifecycle_normal_hit":[538936,1846],"alioth_lifecycle_reputation":[807862,184],"alioth_lifecycle_reputation_axis":[808046,184],"alioth_lifecycle_secondary_faction":[734674,76],"alioth_lifecycle_world_death":[106510,1044],"alioth_lifecycle_freighter_wreck_table":[638178,20]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return Attack.available(bindings) and parameters(bindings.mido_travel.get("alioth_lifecycle"))
