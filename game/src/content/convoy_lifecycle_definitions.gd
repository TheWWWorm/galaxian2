extends RefCounted
## Authored convoy lifecycle variations; shared motion remains native.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"mido_convoy_ship_lifecycle","campaign_cursor":14,"terran_hostility":{"actor_kind":0,"axis":0,"hostile_below":-70,"friendly_above":70},"capital_death":{"model_id":18304,"model_resource":"resources/data/assets/main/3d/meshes/ships/battleship_terran_explosion_anim.aem","initial_material_id":34716,"wreck_material_id":33356,"wreck_layout_id":0,"capital_kills_delta":1,"medal_id":39,"attached_damage":9999999,"attached_actor_ids":[]}}
const SPANS = {"convoy_lifecycle_factory_death_model":[79935,13],"convoy_lifecycle_death_model_context":[633586,336],"convoy_lifecycle_capital_death_effects":[634134,4064],"convoy_lifecycle_default_attachment":[-81548,948],"convoy_lifecycle_small_ship_constructor":[605172,2562],"convoy_lifecycle_large_ship_constructor":[631244,1108],"convoy_lifecycle_hostility":[807440,128],"convoy_lifecycle_friendliness":[807568,128]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("convoy_lifecycle"))
