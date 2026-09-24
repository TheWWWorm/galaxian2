extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Authored one-time placement of the existing second-trip pirate.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Story=preload("res://src/content/full_hold_story_definitions.gd")
const Death=preload("res://src/content/full_hold_destruction_definitions.gd")
const VALUES := {"scope":"full_hold_pirate_appearance","campaign_cursor":4,"trigger_cursor":5,"actor_id":0,"actor_kind":8,"hull_catalogue_id":2,"subtype":0,"once_per_flight":true,"offset":[5000,0,30000],"offset_space":"world","yaw_radians":3.1415927410125732,"actor_mode":1,"active":true,"model_draw_enabled":true,"node_draw_requested":true,"bank_child":true,"statistics_before_yaw":true,"preserve_hull":true,"preserve_cargo":true,"preserve_guidance":true,"preserve_bank_history":true,"preserve_effect_clocks":true,"preserve_cleanup_clock":true,"dead_actor_reenters_death":true,"repeat_death_counters":true}
const SPANS := {"mission_controller":[138688,93478],"activation":[630538,82],"placement":[609228,176],"visibility":[609826,78],"model_install":[-79336,272],"actor_factory":[77944,3478],"matrix_setter":[-724186,24],"position_setter":[-724066,68],"euler_addition":[-723090,140],"effect_trigger":[-681366,484],"activation_virtual":[2399714,8],"model_install_virtual":[2399706,8],"offset_x":[1545990,4],"offset_z":[1545586,4],"yaw":[1546070,4]}

const MAC_ALTERNATE := {"mission_controller":[138688,93490],"activation":[631086,82],"placement":[609776,176],"visibility":[610374,78],"model_install":[-79336,272],"actor_factory":[77944,3478],"matrix_setter":[-730082,24],"position_setter":[-729962,68],"euler_addition":[-728986,140],"effect_trigger":[-687254,484],"activation_virtual":[2377146,8],"model_install_virtual":[2377138,8],"offset_x":[1520974,4],"offset_z":[1520570,4],"yaw":[1521054,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, story: Dictionary, death: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-trip appearance declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-trip appearance declarations"
	if not Story.parameters(story) or not Death.parameters(death):return "Second-trip appearance lacks verified story or destruction context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second-trip appearance lacks its source anchor"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid full hold appearance extents"
