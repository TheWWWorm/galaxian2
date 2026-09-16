extends RefCounted
## Ordinary ship setup; the session separately owns earned departure permission.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Population=preload("res://src/content/free_population_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Delivery=preload("res://src/content/ordinary_contracts_definitions.gd")
const VALUES = {"scope":"augmenta_ordinary_ship_setup","campaign_cursor":18,"opposition":{"exclusive_factions":[8,9,10],"pairs":[[0,1],[2,3]]},"nivelian_boxes":[{"offset":[0,-85,24],"half_extents":[2167.5,622.5,5440]},{"offset":[0,710,292],"half_extents":[1495,467.5,5725]},{"offset":[0,1510,-2886],"half_extents":[1375,505,1375]}]}
const SPANS = {"free_traffic_nivelian_boxes":[80500,278],"free_traffic_box_values":[1575482,48],"free_traffic_opposition":[614052,268]}

# Native composition.
static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	if not Population.available(bindings) or not parameters(bindings.mido_travel.get("free_traffic")):return false
	# These common modules also validate travel declarations. Resolve them after
	# loading the declaration graph to keep its optional children independent.
	return load("res://src/content/ambient_combat_definitions.gd").parameters(bindings.ambient_combat) and load("res://src/content/contract_ship_combat_definitions.gd").parameters(bindings.early_contracts.get("ship_combat"))

static func population(bindings: RefCounted,packet: Dictionary,rank: Variant,difficulty: Variant) -> Dictionary:
	if not available(bindings) or not Numbers.integer(rank,0,20) or difficulty not in [0.5,1.0]:return {}
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key):return {}
	var context: Variant=packet.get("free_context")
	var source: Variant=packet.get("population")
	var actors: Variant=packet.get("actors")
	var rules: Dictionary=bindings.mido_travel.free_population
	if not context is Dictionary or not source is Dictionary or not actors is Array:return {}
	if not context_valid(bindings,context) or context.rank!=rank or context.difficulty!=difficulty:return {}
	var visit:=Campaign.active_visit(bindings.mido_travel,context)
	if actors.is_empty() and not Delivery.active_courier(context) and not visit:return {}
	for key in ["campaign_cursor","station_id","system_id"]:
		if source.get(key)!=context[key]:return {}
	if packet.get("campaign_cursor")!=context.campaign_cursor or packet.get("station_id")!=context.station_id:return {}
	var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").location(bindings.mido_travel,context.station_id)
	if source.get("system_faction")!=world.faction or source.get("security")!=world.security or not source.get("groups") is Dictionary:return {}
	if actors.size()>Population.maximum_actor_count(bindings,rank,float(difficulty),context) or source.get("actor_count")!=actors.size():return {}
	if not context.side_missions_empty and source.groups.get("delivery_pirate")!=Delivery.extra_count(bindings,context):return {}
	if Delivery.active_courier(context) and source.get("mission_kind")!=0:return {}
	if visit and (source.get("mission_kind")!=156 or not actors.is_empty()):return {}
	if not source.get("hostile_selected") is bool or source.get("hostile_faction") not in [1,8]:return {}
	if not source.hostile_selected and source.groups.get("hostile")!=0:return {}
	var hulls: Dictionary=bindings.early_contracts.encounter_construction.hulls
	if not Numbers.integer(packet.get("player_ship_id"),0,hulls.factions.size()-1):return {}
	var count:=0
	for role in Delivery.group_order(bindings,context):
		var n: Variant=source.groups.get(role)
		if not Numbers.integer(n,0,actors.size()):return {}
		for index in int(n):
			if count>=actors.size():return {}
			var row: Variant=actors[count]
			if not row is Dictionary or row.get("actor_id")!=count or row.get("population_group")!=role:return {}
			if not actor_matches(bindings,row,role,int(source.hostile_faction)):return {}
			count+=1
	if count!=actors.size():return {}
	var data: Dictionary=bindings.ambient_combat.duplicate(true)
	data.merge(context,true);data.scope="augmenta_ordinary_combat";data.actor_count=count
	data.free_traffic=bindings.mido_travel.free_traffic.duplicate(true)
	data.freighter_boxes={0:bindings.mido_travel.alioth_attack.population.freighter_combat.boxes.duplicate(true),2:data.free_traffic.nivelian_boxes.duplicate(true)}
	return data

static func context_valid(bindings: RefCounted,context: Variant) -> bool:
	if bindings==null or not context is Dictionary:return false
	var rules: Dictionary=bindings.mido_travel.get("free_population",{})
	if not Population.parameters(rules):return false
	var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").location(bindings.mido_travel,context.get("station_id"))
	if world.is_empty() or context.get("system_id")!=world.system_id:return false
	if not Campaign.supported(bindings.mido_travel,context.get("campaign_cursor")) or not Delivery.mission_context_valid(bindings,context):return false
	if context.get("companions_empty")!=true:return false
	for key in ["station_response","void_encounter"]:
		if context.get(key)!=false:return false
	if not load("res://src/content/free_arrival_definitions.gd").context_supported(bindings,context):return false
	return Numbers.integer(context.get("rank"),0,20) and context.get("difficulty") in [0.5,1.0]

static func actor_matches(bindings: RefCounted,row: Dictionary,role: String,hostile_faction: int=-1,live:=false) -> bool:
	var faction: Variant=row.get("actor_kind");var hull: Variant=row.get("hull_catalogue_id")
	if not faction is int or not hull is int:return false
	if role=="freighter":
		if faction not in [0,2] or hull!=15 or row.get("subtype")!=1:return false
		return live or (row.get("world_flag")==true and row.get("model_assembly_required")==true and Equal.equal_value(row.get("assembly"),bindings.mido_travel.free_population.freighter_assemblies[str(faction)]))
	if role not in ["patrol","travel","hostile","delivery_pirate"] or row.get("subtype")!=0:return false
	if role=="delivery_pirate":
		if not Delivery.available(bindings) or faction!=int(bindings.mido_travel.ordinary_contracts.population.actor_kind):return false
	elif role=="hostile":
		if faction not in [1,8] or (hostile_faction>=0 and faction!=hostile_faction):return false
	elif faction!=0:return false
	var hulls: Dictionary=bindings.early_contracts.encounter_construction.hulls
	if hull<0 or hull>=hulls.factions.size() or int(hulls.factions[hull])!=faction:return false
	return faction==1 or hull>int(hulls.mask_limit) or (int(hulls.excluded_mask)>>hull)&1==0
