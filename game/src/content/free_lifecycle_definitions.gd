extends RefCounted
## Complete ordinary traffic simulation requires this verified lifecycle context.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Traffic=preload("res://src/content/free_traffic_definitions.gd")
const VALUES = {"scope":"augmenta_ordinary_lifecycle","campaign_cursor":18,"system_id":19,"standing":{"axes":[0,0,1,1],"hostile_signs":[-1,1,-1,1],"threshold":70,"unconditional_hostiles":[8]},"reactions":{"primary_faction":0,"eligible_factions":[0,1],"radio_requires_empty_mission":true,"empty_mission_kind":-1,"force_matching_faction_only":true},"recycling_groups":["patrol","travel"],"hostile_relaunch_security":[0,1],"unrestricted_relaunch_faction":9,"nivelian_death":{"model_id":18301,"model_resource":"resources/data/assets/main/3d/meshes/ships/cargo_002_nivelian_explosion_anim.aem","model_scale":1.0,"initial_material_id":34704,"wreck_layout_id":2,"wreck_material_id":33353}}
const SPANS = {"free_lifecycle_hostile":[807440,128],"free_lifecycle_friendly":[807568,128],"free_lifecycle_secondary":[734674,76],"free_lifecycle_hostile_relaunch":[113209,238],"free_lifecycle_nivelian_death":[80766,17],"free_lifecycle_wreck_kind":[633786,41],"free_lifecycle_wreck_material":[637724,129],"free_lifecycle_wreck_table":[638178,20]}

# Native composition.
static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return Traffic.available(bindings) and parameters(bindings.mido_travel.get("free_lifecycle")) and load("res://src/content/contract_ship_lifecycle_definitions.gd").available(bindings)

static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not available(bindings) or not packet.get("free_context") is Dictionary:return {}
	var context: Dictionary=packet.free_context
	var data: Dictionary=load("res://src/content/ambient_lifecycle_definitions.gd").guidance(bindings,packet,context.get("rank"),context.get("difficulty"))
	if data.is_empty():return {}
	data.merge(context,true);data.free_context=context.duplicate(true)
	data.free_lifecycle=bindings.mido_travel.free_lifecycle.duplicate(true)
	data.lifecycle=bindings.early_contracts.ship_lifecycle.duplicate(true)
	data.lifecycle.reactions=data.free_lifecycle.reactions.duplicate(true)
	data.cargo=bindings.combat_training_destruction.cargo.duplicate(true)
	data.actors=[];data.npc_weapons=[]
	for actor in packet.actors:
		var row:={}
		for key in ["actor_id","actor_kind","hull_catalogue_id","subtype","population_group"]:row[key]=actor[key]
		for model in data.lifecycle.cargo_models:
			if int(model.actor_kind)==actor.actor_kind:
				row.cargo_model_id=int(model.cargo_model_id);row.cargo_model_resource=model.cargo_model_resource
		if not row.has("cargo_model_id"):return {}
		data.actors.append(row)
		var weapon: Dictionary={"unarmed":true} if actor.population_group=="freighter" else load("res://src/content/contract_ship_combat_definitions.gd").shared_weapon(bindings.early_contracts.ship_combat.weapons,int(context.campaign_cursor),int(context.rank),float(context.difficulty),actor.actor_kind)
		if weapon.is_empty():return {}
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:weapon[key]=actor[key]
		data.npc_weapons.append(weapon)
	return data

static func standing(rules: Dictionary,faction: int,reputation: Dictionary,forced: bool) -> Dictionary:
	if not Equal.equal_value(rules,VALUES.standing) or not load("res://src/simulation/faction_reputation.gd").valid_state(reputation):return {}
	if rules.unconditional_hostiles.any(func(value):return int(value)==faction) or forced:return {"hostile":true,"friendly":false}
	if faction<0 or faction>=rules.axes.size():return {}
	var value: int=reputation.axes[int(rules.axes[faction])]*int(rules.hostile_signs[faction])
	return {"hostile":value>int(rules.threshold),"friendly":value< -int(rules.threshold)}

static func npc_hit(data: Dictionary,weapon: Dictionary) -> bool:
	if data.get("campaign_cursor")!=18 or not data.has("free_lifecycle"):return false
	for row in data.npc_weapons:
		if row.get("unarmed",false):continue
		var matches:=true
		for key in ["item_id","category","kind","damage","nonplayer_source"]:
			if weapon.get(key)!=row.get(key):matches=false;break
		if matches:return true
	return false

static func live_population(bindings: RefCounted,combat: Dictionary) -> bool:
	if not available(bindings) or not Traffic.context_valid(bindings,combat.get("free_context")):return false
	var context: Dictionary=combat.free_context
	for key in ["base_content_id","binding_id"]:
		if combat.get(key)!=bindings.get(key):return false
	if combat.get("campaign_cursor")!=context.campaign_cursor or combat.get("provocation",{}).get("station_id")!=context.station_id:return false
	var actors: Variant=combat.get("actors")
	if not actors is Array or actors.size()>Traffic.Population.maximum_actor_count(bindings,int(context.rank),float(context.difficulty),context):return false
	if actors.is_empty() and not Traffic.Delivery.active_courier(context):return false
	var order: Array=Traffic.Delivery.group_order(bindings,context)
	var previous:=-1
	for id in actors.size():
		var row: Variant=actors[id]
		if not row is Dictionary or row.get("actor_id")!=id or row.get("free_traffic")!=true or row.get("ambient_traffic")!=true:return false
		var group: int=order.find(row.get("population_group"))
		if group<previous or group<0 or not Traffic.actor_matches(bindings,row,order[group],-1,true):return false
		previous=group
	return true
