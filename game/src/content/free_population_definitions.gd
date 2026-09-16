extends RefCounted
## Ordinary population parameters. Construction alone does not permit departure.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Navigation=preload("res://src/content/free_navigation_definitions.gd")
const Ambient=preload("res://src/content/ambient_population_definitions.gd")
const Encounters=preload("res://src/content/contract_encounter_definitions.gd")
const VALUES = {"scope":"augmenta_ordinary_population","campaign_cursor":18,"system_id":19,"station_ids":[95,96,97,98,99],"security_field":0,"faction_field":2,"supported_difficulties":[0.5,1.0],"mission_kind":-1,"mission_completed":true,"mission_story":false,"group_order":["patrol","travel","freighter","hostile"],"hostile_chance_thresholds":[90,65,35,10],"hostile_count_bound":4,"hostile_difficulty_offset":-0.5,"hostile_rank_divisor":4,"easy_security":3,"easy_difficulty_threshold":1.0,"easy_count_bound":2,"easy_count_offset":1,"pirate_faction":8,"enemy_factions":[1,0,3,2],"station_response_minimum":7,"freighter_alternate_threshold":30,"freighter_alternate_factions":[2,1,0,3],"hostile_hull_choice":"once_per_group_before_count_test","freighter_assemblies":{"0":{"body_resource_ids":[17065,17066,17067],"child_resource_ids":[[17070,17074,17069],[17070],[17070]],"lod_distances":[25000,45000],"maximum_distance":0,"model_scale":1.0},"2":{"body_resource_ids":[17060,17062,17063],"child_resource_ids":[[17061,17064],[],[]],"lod_distances":[35000,60000],"maximum_distance":0,"model_scale":1.0}}}
const SPANS = {"free_population_counts":[-31195,1136],"free_population_overrides":[-30047,1080],"free_population_security":[734654,10],"free_population_enemy_factions":[807738,76],"free_population_freighter_alternate":[-24536,22],"free_population_freighter_choice":[-22069,138],"free_population_patrol_choice":[-24730,83],"free_population_hostile_choice":[-19918,79],"free_population_hostile_factory":[-19598,174],"free_population_hostile_tail":[-19021,77],"free_population_freighter_model":[-217816,205],"free_population_void_initial":[882994,11],"free_population_void_selection":[857626,325]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return Navigation.available(bindings) and Ambient.parameters(bindings.ambient_population) and Encounters.parameters(bindings.early_contracts.get("encounter_construction")) and parameters(bindings.mido_travel.get("free_population"))

static func maximum_actor_count(bindings: RefCounted,rank: int,difficulty: float,context: Dictionary={}) -> int:
	var delivery=preload("res://src/content/ordinary_contracts_definitions.gd")
	if delivery.active_courier(context) or delivery.Campaign.active_visit(bindings.mido_travel,context):return 0
	var rules: Dictionary=bindings.mido_travel.free_population
	var groups: Dictionary=bindings.ambient_population
	var hostiles:=int(3.0*(1.0+difficulty+float(rules.hostile_difficulty_offset)))+int(float(rank)/float(rules.hostile_rank_divisor))
	if difficulty<float(rules.easy_difficulty_threshold):hostiles=int(rules.easy_count_bound)
	return 3+int(groups.extra_patrol_count_bound)-1+1+int(groups.travel_count_bound)-1+int(groups.freighter_count_bound)-1+hostiles+delivery.extra_count(bindings,context)
