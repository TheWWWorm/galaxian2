extends RefCounted
## Ordinary arrival placement; travel permission remains with the native session.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"augmenta_ordinary_arrival","campaign_cursor":18,"system_id":19,"arrival_flags":{"special_arrival":true,"void_encounter":false},"pirate_faction":8,"chance_bound":100,"normal_chance":20,"hard_chance":40,"hard_difficulty":1.5,"rank_added_to_chance":true,"chance_strict":true,"position_multiplier":3.0,"selection_after_shared_hull":true,"selection_before_count_test":true,"excluded_special_systems":[32,33]}
const SPANS = {"free_arrival_marker":[382634,133],"free_arrival_ambush":[-19839,241],"free_arrival_rank":[876350,12],"free_arrival_player_position":[562384,14],"free_arrival_entity_position":[-724356,26],"free_arrival_matrix_position":[1241402,96],"free_arrival_position_scale":[1556910,4],"free_arrival_hard_mode":[873106,34],"free_arrival_other_systems":[873024,82],"free_arrival_hard_constant":[1545698,4]}

# Native composition.
static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("free_arrival")) and load("res://src/content/free_flight_definitions.gd").available(bindings)

static func context_supported(bindings: RefCounted,context: Dictionary) -> bool:
	if context.get("special_arrival")==false:return true
	if context.get("special_arrival")!=true or bindings==null or not parameters(bindings.mido_travel.get("free_arrival")):return false
	var position: Variant=context.get("player_position")
	if not position is Vector3 or not position.is_finite():return false
	var absolute: Vector3=position.abs()
	return maxf(absolute.x,maxf(absolute.y,absolute.z))<=100000000.0

static func select_origin(rules: Dictionary,context: Dictionary,population: Dictionary,random: RefCounted) -> void:
	# The factory has selected its common hostile hull. This draw precedes the
	# count test and must also be retained for a selected group of zero actors.
	if not context.special_arrival or population.hostile_faction!=int(rules.pirate_faction):return
	var threshold:=int(rules.hard_chance if context.difficulty==float(rules.hard_difficulty) else rules.normal_chance)+int(context.rank)
	var drawn: int=random.next_int(int(rules.chance_bound))
	var previous: Vector3=population.unused_route_origin
	var triggered:=drawn<threshold
	if triggered:population.unused_route_origin=context.player_position*float(rules.position_multiplier)
	population.arrival_ambush={"chance_draw":drawn,"threshold":threshold,"triggered":triggered,"previous_origin":previous,"origin":population.unused_route_origin}
