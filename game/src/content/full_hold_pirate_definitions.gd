extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Second-trip pirate combat context, separate from campaign progression.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/full_hold_flight_definitions.gd")
const Hull=preload("res://src/content/npc_hull_definitions.gd")
const Handoff=preload("res://src/content/opening_handoff_definitions.gd")
const Guidance=preload("res://src/content/opening_npc_guidance_definitions.gd")
const Holding=preload("res://src/content/npc_holding_definitions.gd")
const Hostility=preload("res://src/content/npc_hostility_definitions.gd")
const Weapon=preload("res://src/content/opening_npc_weapon_definitions.gd")
const VALUES := {"scope":"full_hold_pirate_combat","campaign_cursor":4,"actor_id":0,"actor_kind":8,"hull_catalogue_id":2,"subtype":0,"rank_base":20,"rank_multiplier":14,"cursor_multiplier":4,"difficulty_offset":-0.5,"percentage_scale":100.0,"initial_hostile":true,"current_hull_is_factory_hull":true,"primary_weapon":{"actor_ids":[0],"actor_kind":8,"category":0,"damage":1,"interval_ms":592,"item_id":19,"kind":1,"launch_mode":"ordinary","lifetime_ms":3000,"local_muzzle":[0.0,0.0,0.0],"model_resource_id":6795,"projectile_capacity":4,"speed_units_per_millisecond":16.0},"activation_cursor":5,"activation_phase_before":0,"activation_phase_after":1,"activation_offset":[5000,0,30000],"activation_yaw_radians":3.1415927410125732,"activation_mode":1,"proximity_half_extent":25000,"target_activation_half_extent":50000}
const SPANS := {"factory_hull":[78110,433],"factory_no_override":[78713,244],"ordinary_vtable":[2399706,32],"initial_pools":[534334,138],"previous_hull_sample":[607290,39],"weapon_damage":[55284,51],"weapon_postpass":[54772,4266],"weapon_constructor":[-190034,1052],"scripted_activation":[151367,208],"proximity_activation":[617194,408],"holding_activation":[619682,255],"mode_dispatch":[627906,40],"proximity_positive":[1575066,4],"proximity_negative":[1588430,4],"activation_x":[1545990,4],"activation_z":[1545586,4],"activation_yaw":[1546070,4],"projectile_speed":[1575350,4],"hull_getter":[537554,12],"hull_percent":[535144,150],"model_assignment":[-79336,272],"world_assignment":[608550,340],"activate":[630538,82],"world_player":[105946,14]}

const MAC_ALTERNATE := {"factory_hull":[78110,433],"factory_no_override":[78713,244],"ordinary_vtable":[2377138,32],"initial_pools":[534870,138],"previous_hull_sample":[607838,39],"weapon_damage":[55284,51],"weapon_postpass":[54772,4266],"weapon_constructor":[-190526,1052],"scripted_activation":[151367,208],"proximity_activation":[617742,408],"holding_activation":[620230,255],"mode_dispatch":[628454,40],"proximity_positive":[1550130,4],"proximity_negative":[1563506,4],"activation_x":[1520974,4],"activation_z":[1520570,4],"activation_yaw":[1521054,4],"projectile_speed":[1550414,4],"hull_getter":[538090,12],"hull_percent":[535680,150],"model_assignment":[-79336,272],"world_assignment":[609098,340],"activate":[631086,82],"world_player":[105946,14]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary, actors: Dictionary, handoff: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-trip pirate declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-trip pirate declarations"
	if not Flight.parameters(flight) or not Handoff.parameters(handoff):return "Second pirate lacks its flight and earned progress context"
	var npc: Dictionary=actors.get("npc_initialization",{})
	if not Hull.parameters(npc.get("hull")) or not Guidance.parameters(npc.get("guidance")) or not Holding.parameters(npc.get("holding")) or not Hostility.parameters(npc.get("hostility")) or not Weapon.parameters(npc.get("primary_weapon")):return "Second pirate lacks shared combat declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second pirate lacks its source anchor"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid full hold pirate extents"
