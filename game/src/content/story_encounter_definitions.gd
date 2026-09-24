extends RefCounted
## Compose an authored population once at encounter entry. The flight's existing
## combat, motion, hit and cargo owners consume this accepted construction.
const Sahi=preload("res://src/content/sahi_encounter_definitions.gd")
const Dima=preload("res://src/content/dima_encounter_definitions.gd")
const Post=preload("res://src/content/post_sahi_definitions.gd")
const BaseFlight=preload("res://src/content/first_flight_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const Life=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const AliothLife=preload("res://src/content/alioth_lifecycle_definitions.gd")
const Weapons=preload("res://src/content/contract_ship_combat_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const FreighterDeath=preload("res://src/content/freighter_destruction_definitions.gd")

## Source story dispatch shares the verified ordinary placement, wormhole and
## camera constructor but does not make Sahi an ordinary FreeFlight destination.
static func entry_conditions(cursor: int) -> Dictionary:
	if cursor not in [24,25,26,28,29]:return {}
	return {"companions_empty":true,"location_match":cursor in [25,29],"special_placement":false}

static func flight(bindings: RefCounted,context: Dictionary) -> Dictionary:
	if bindings==null or not BaseFlight.parameters(bindings.first_flight) or not selected(bindings,context):return {}
	var result: Dictionary=bindings.first_flight.duplicate(true)
	result.scope="sahi_story_flight"
	for key in ["campaign_cursor","system_id","station_id","mission_kind"]:result[key]=int(context[key])
	result.erase("actor_count")
	return result

static func prepared_entry(bindings: RefCounted,entry: Dictionary) -> bool:
	var context: Dictionary=entry.get("sahi_context",{})
	if not selected(bindings,context):return false
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if entry.get(key)!=context.get(key):return false
	return entry.get("location",{}).get("station_id")==context.station_id and entry.get("scenery",{}).get("world_initialization",{}).get("npc_construction",{}).get("sahi_context") == context

static func combat_population(bindings: RefCounted,combat: Dictionary) -> bool:
	if bindings==null or not Sahi.coherent(bindings.mido_travel):return false
	var cursor: Variant=combat.get("campaign_cursor")
	var dima: bool=cursor==28 and Dima.Thynome.coherent(bindings.mido_travel)
	if cursor!=24 and not dima and (cursor not in [25,26,29] or not Post.portal_available(bindings.mido_travel,cursor)):return false
	var actors: Variant=combat.get("actors")
	var cast: Array=bindings.mido_travel.sahi_encounter.population.actors
	if dima:
		cast=[]
		for group in bindings.mido_travel.thynome_expedition.world28.cast.groups:
			for _index in int(group.count):cast.append({"actor_kind":int(group.actor_kind),"subtype":int(group.subtype),"hull_catalogue_id":int(group.hull_catalogue_id)})
	if cursor in [25,26,29]:
		var rule: Dictionary=bindings.mido_travel.post_sahi["void"].population if cursor in [25,29] else bindings.mido_travel.post_sahi.pursuers
		cast=[]
		for id in int(rule.count):cast.append({"actor_kind":int(rule.actor_kind),"subtype":int(rule.subtype),"hull_catalogue_id":int(rule.hull_catalogue_id)})
	if not actors is Array or actors.size()!=cast.size():return false
	for id in actors.size():
		var actor: Variant=actors[id];var row: Dictionary=cast[id]
		if not actor is Dictionary or not actor.get("authored_story",false) or actor.get("actor_id")!=id:return false
		for key in ["actor_kind","subtype","hull_catalogue_id"]:
			if actor.get(key)!=int(row[key]):return false
		for key in ["base_content_id","binding_id"]:
			if actor.get(key)!=bindings.get(key):return false
	return true

static func compose(bindings: RefCounted,catalogues: RefCounted,packet: Dictionary) -> Dictionary:
	if bindings==null or catalogues==null or catalogues.content_id!=bindings.base_content_id:return {}
	if not Life.available(bindings) or not FreeLife.available(bindings) or not AliothLife.available(bindings) or not ControlRules.parameters(bindings.combat_training_control):return {}
	var context: Variant=packet.get("sahi_context")
	if not context is Dictionary or not selected(bindings,context):return {}
	for key in ["base_content_id","binding_id"]:
		if context.get(key)!=bindings.get(key) or packet.get(key)!=bindings.get(key):return {}
	for key in ["campaign_cursor","station_id"]:
		if packet.get(key)!=context.get(key):return {}
	if not Numbers.integer(context.get("rank"),0,20) or context.get("difficulty") not in [0.5,1.0]:return {}
	var dima: bool=Dima.selected(bindings.mido_travel,context)
	var source: Dictionary=bindings.mido_travel.sahi_encounter.duplicate()
	if dima:source.population=Dima.population(bindings.mido_travel,context)
	elif context.campaign_cursor in [25,26,29]:source.population=Post.population(bindings.mido_travel,context)
	if source.population.is_empty():return {}
	var actors: Variant=packet.get("actors")
	if not actors is Array or actors.size()!=int(source.population.actor_count):return {}
	for id in actors.size():
		var row: Variant=actors[id];var expected: Dictionary=source.population.actors[id]
		if not row is Dictionary:return {}
		for key in ["actor_id","actor_kind","subtype","hull_catalogue_id"]:
			if not row.get(key) is int or row[key]!=int(expected[key]):return {}
		if not Flight.rigid_pose(row.get("body_pose")) or row.get("statistics_pose")!=row.body_pose:return {}
		if row.get("population_group")!=("freighter" if row.subtype==1 else "fighter"):return {}
		if row.subtype==1:
			if row.get("assembly")!=source.population.freighter_assembly or row.get("cargo")!=[] or row.get("hull_divisors")!=[int(source.population.freighter_hull_divisor)] or row.get("cruise_enabled")!=false:return {}
	var data: Dictionary=bindings.combat_training_control.duplicate(true)
	data.merge(context,true)
	data.authored_story=true;data.context_key="sahi_context"
	data.actor_count=actors.size();data.actor_kinds=actors.map(func(row):return row.actor_kind)
	data.hull_catalogue_ids=actors.map(func(row):return row.hull_catalogue_id)
	data.actor_rows=actors;data.context=context
	if not Numbers.integer(packet.get("player_ship_id"),0,catalogues.tables.ships.size()-1):return {}
	data.player_ship_id=packet.player_ship_id
	for key in ["initial_actor_mode","initial_active","initial_hostile","friendly","initial_actor_targeting_blocked","initial_statistics_targeting_blocked"]:
		data[key]=bindings.mido_travel.traffic_control[key]
	data.freighter=source.population.freighter_combat
	data.free_traffic=bindings.mido_travel.free_traffic
	data.standing=bindings.mido_travel.free_lifecycle.standing
	data.lifecycle=bindings.early_contracts.ship_lifecycle.duplicate(true)
	var population: Dictionary=bindings.mido_travel.free_population
	var faction_system:=18 if context.campaign_cursor==29 else int(bindings.mido_travel.post_sahi["void"].return_system_id) if context.system_id==-1 else int(context.system_id)
	var faction:=int(catalogues.tables.systems[faction_system].fields[int(population.faction_field)])
	if faction<0 or faction>=population.enemy_factions.size():return {}
	data.lifecycle.reactions.primary_faction=faction
	data.lifecycle.reactions.eligible_factions=[faction,int(population.enemy_factions[faction])]
	data.cargo=bindings.combat_training_destruction.cargo
	data.nonhostile_remaining_delta=int(bindings.combat_training_destruction.nonhostile_remaining_delta)
	data.selection_skipped_modes=data.lifecycle.selection_skipped_modes
	data.actors=[];data.npc_weapons=[]
	data.player_weapon_targets=source.weapons.player_weapon_targets.map(func(id):return int(id))
	data.target_memberships=source.weapons.npc_target_memberships.map(func(ids):return ids.map(func(id):return int(id)))
	if dima:
		data.player_weapon_targets=range(actors.size())
		data.target_memberships=source.population.dima.target_memberships.map(func(ids):return ids.map(func(id):return int(id)))
	elif context.campaign_cursor in [25,26,29]:
		data.player_weapon_targets=range(actors.size())
		data.target_memberships=actors.map(func(_actor):return [-1])
	var models: Array=data.lifecycle.cargo_models.duplicate()
	models.append(bindings.mido_travel.alioth_lifecycle.void_cargo)
	for actor in actors:
		var row: Dictionary={}
		for key in ["actor_id","actor_kind","hull_catalogue_id","subtype","population_group"]:row[key]=actor[key]
		for model in models:
			if int(model.actor_kind)==actor.actor_kind:
				row.cargo_model_id=int(model.cargo_model_id);row.cargo_model_resource=model.cargo_model_resource
		if not row.has("cargo_model_id"):return {}
		data.actors.append(row)
		var weapon:={"unarmed":true}
		if actor.population_group=="fighter":
			weapon=Weapons.scaled_parameters(bindings.early_contracts.ship_combat.weapons,int(context.campaign_cursor),int(context.rank),float(context.difficulty))
			if weapon.is_empty():return {}
			var original: Dictionary=source.weapons["void"]
			for key in ["item_id","kind","catalogue_kind","model_resource_id"]:weapon[key]=int(original[key])
			weapon.damage=int(Vitals.single(Vitals.single(float(weapon.damage))*float(original.damage_multiplier)))
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:weapon[key]=actor[key]
		data.npc_weapons.append(weapon)
	var freight: Dictionary=FreighterDeath.for_alioth(bindings) if dima else bindings.freighter_destruction.duplicate(true)
	if freight.is_empty():return {}
	if not dima:freight.merge(bindings.mido_travel.free_lifecycle.nivelian_death,true)
	for key in ["campaign_cursor","station_id","system_id"]:freight[key]=int(context[key])
	freight.actor_kind=0 if dima else 2
	for model in models:
		if int(model.actor_kind)==freight.actor_kind:
			freight.cargo_model_id=int(model.cargo_model_id);freight.cargo_model_resource=model.cargo_model_resource
	data.freighter_death=freight
	return data

static func selected(bindings: RefCounted,context: Dictionary) -> bool:
	return bindings!=null and (Sahi.selected(bindings.mido_travel,context) or Post.selected(bindings.mido_travel,context) or Dima.selected(bindings.mido_travel,context))

static func npc_hit(data: Dictionary,weapon: Dictionary) -> bool:
	for row in data.npc_weapons:
		if row.get("unarmed",false):continue
		var matches:=true
		for key in ["item_id","category","kind","damage","nonplayer_source"]:
			if weapon.get(key)!=row.get(key):matches=false;break
		if matches:return true
	return false
