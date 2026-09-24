extends RefCounted
## Original convoy capital-ship data; no campaign or encounter completion.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"mido_convoy_capital_ship","campaign_cursor":14,"actor_kind":0,"subtype":1,"hull_catalogue_id":14,"actor_ids":[5,6],"assembly":{"body_resource_ids":[14311,14312,14313],"child_resource_ids":[[14316,14315],[14316],[14316]],"lod_distances":[35000,60000],"maximum_distance":0,"model_scale":2.0},"combat":{"hull_multiplier":25,"shield_multiplier":3,"range":45000,"point_geometry":true,"boxes":[{"offset":[0,-2240.0,21608.0],"half_extents":[380.0,320.0,1445.0]},{"offset":[0,-2342.0,18392.0],"half_extents":[630.0,1780.0,1835.0]},{"offset":[0,-786.0,8926.0],"half_extents":[3705.0,3870.0,7770.0]},{"offset":[0,-4950.0,9656.0],"half_extents":[410.0,520.0,3575.0]},{"offset":[0,3420.0,-452.0],"half_extents":[655.0,470.0,2440.0]},{"offset":[0,-270.0,-9018.0],"half_extents":[3760.0,3435.0,10235.0]},{"offset":[0,-5088.0,-7962.0],"half_extents":[650.0,1450.0,6605.0]},{"offset":[0,3526.0,-11604.0],"half_extents":[1630.0,440.0,5320.0]},{"offset":[0,5212.0,-12332.0],"half_extents":[1630.0,1320.0,4205.0]},{"offset":[0,2004.0,-15852.0],"half_extents":[7930.0,1255.0,5455.0]},{"offset":[0,-2610.0,-15852.0],"half_extents":[7930.0,1255.0,5455.0]}]},"cargo":{"multiplier_bound":8,"multiplier_offset":5,"has_floor":false,"has_generated_patrol_route":false},"motion":{"initial_cruise_enabled":false,"capture_actor_id":6,"distance_per_ms":1.0,"engine_sound_id":-1}}
const SPANS = {"convoy_ship_factory_dispatch":[-219266,28],"convoy_ship_assembly":[-219009,225],"convoy_ship_assembly_scale":[1557082,4],"convoy_ship_factory_hull":[78349,37],"convoy_ship_box_factory":[78968,967],"convoy_ship_box_values":[1575574,160],"convoy_ship_box_constructor":[-710254,138],"convoy_ship_box_half_scale":[1544586,4],"convoy_ship_box_point":[-710024,122],"convoy_ship_cargo":[632025,115],"convoy_ship_initial_state":[632233,57],"convoy_ship_motion_gate":[634522,64],"convoy_ship_motion_step":[633922,212],"convoy_ship_motion_flag":[633028,14],"convoy_ship_model_move":[-722702,234]}

const MAC_SPANS = {"convoy_ship_factory_dispatch":[-220222,28],"convoy_ship_assembly":[-219965,225],"convoy_ship_assembly_scale":[1532082,4],"convoy_ship_factory_hull":[78349,37],"convoy_ship_box_factory":[78968,967],"convoy_ship_box_values":[1550638,160],"convoy_ship_box_constructor":[-716150,138],"convoy_ship_box_half_scale":[1519570,4],"convoy_ship_box_point":[-715920,122],"convoy_ship_cargo":[632573,115],"convoy_ship_initial_state":[632781,57],"convoy_ship_motion_gate":[635070,64],"convoy_ship_motion_step":[634470,212],"convoy_ship_motion_flag":[633576,14],"convoy_ship_model_move":[-728598,234]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("convoy_ship"))

static func boxes(bindings: RefCounted) -> Array:
	if not available(bindings):return []
	var result:=[]
	for row in bindings.mido_travel.convoy_ship.combat.boxes:
		result.append({"offset":Vector3(row.offset[0],row.offset[1],row.offset[2]),"half_extents":Vector3(row.half_extents[0],row.half_extents[1],row.half_extents[2])})
	return result
