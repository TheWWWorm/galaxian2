extends RefCounted
## Ordinary delivery traffic and selected courier construction.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"ordinary_delivery_contracts","population":{"side_kinds":[0,11,15],"difficulty_divisor":10.0,"count_multiplier":5.0,"actor_kind":8,"subtype":0,"enabled":true,"hull_choice":"per_actor","position_offsets":[-80000.0,-50000.0,-80000.0],"position_bounds":[160000,100000,160000]},"courier":{"kind":0,"actor_count":0,"reseed":false}}
const SPANS = {"ordinary_contracts_reseed":[-31265,31],"ordinary_contracts_side_slot":[859500,22],"ordinary_contracts_count":[-31097,103],"ordinary_contracts_pirates":[-18932,503],"ordinary_contracts_dispatch":[-15605,124],"ordinary_contracts_empty_return":[-4930,38],"ordinary_contracts_divisor":[1557090,4],"ordinary_contracts_multiplier":[1557114,4],"ordinary_contracts_xz_offset":[1575126,4],"ordinary_contracts_y_offset":[1575142,4]}

# Native composition.
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("ordinary_contracts"))

static func delivery_mission(bindings: RefCounted,mission: Variant) -> bool:
	if not available(bindings) or not mission is Dictionary:return false
	if not Numbers.integer(mission.get("kind"),0,11) or mission.kind not in [0,11] or mission.get("story")!=false or not Numbers.integer(mission.get("difficulty"),1,9):return false
	return not load("res://src/content/ordinary_world_definitions.gd").location(bindings.mido_travel,mission.get("station_id")).is_empty()

static func active_courier(context: Dictionary) -> bool:
	return context.get("mission_kind")==0 and context.get("mission_completed")==false and context.get("side_missions_empty")==false

static func mission_context_valid(bindings: RefCounted,context: Dictionary) -> bool:
	if context.get("mission_story")!=false:return false
	if context.get("side_missions_empty")==true:
		return context.get("side_mission",{})=={} and context.get("mission_kind")==-1 and context.get("mission_completed")==true
	if context.get("side_missions_empty")!=false or not delivery_mission(bindings,context.get("side_mission")):return false
	var side: Dictionary=context.side_mission
	var selected: bool=int(side.kind)==0 and side.station_id==context.get("station_id")
	var position: Variant=context.get("player_position")
	if not position is Vector3 or not position.is_finite():return false
	if position.abs()[position.abs().max_axis_index()]>100000000.0:return false
	return context.get("mission_kind")== (0 if selected else -1) and context.get("mission_completed")== (not selected)

static func extra_count(bindings: RefCounted,context: Dictionary) -> int:
	if not available(bindings) or context.get("side_missions_empty",true) or active_courier(context):return 0
	var side: Dictionary=context.get("side_mission",{})
	if not delivery_mission(bindings,side):return 0
	var data: Dictionary=bindings.mido_travel.ordinary_contracts.population
	return pirate_count(data,int(side.difficulty))

static func pirate_count(data: Dictionary,difficulty: int) -> int:
	return int(Vitals.single(Vitals.single(float(difficulty)/float(data.difficulty_divisor))*float(data.count_multiplier)))

static func maximum_extra_count(bindings: RefCounted) -> int:
	if not available(bindings):return 0
	return pirate_count(bindings.mido_travel.ordinary_contracts.population,int(bindings.early_contracts.ordinary_generation.offers.difficulty_draw_bound))

static func group_order(bindings: RefCounted,context: Dictionary) -> Array:
	var order: Array=bindings.mido_travel.free_population.group_order.duplicate()
	if context.get("side_missions_empty")==false:order.append("delivery_pirate")
	return order
