extends RefCounted
## Composition of original Alioth actors and the shared NPC body factory.
## This validates construction; it does not authorize a campaign departure.
const Attack=preload("res://src/content/alioth_attack_definitions.gd")
const Ambient=preload("res://src/content/ambient_combat_definitions.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Weapons=preload("res://src/content/contract_ship_combat_definitions.gd")
const World=preload("res://src/content/contract_world_definitions.gd")
const Life=preload("res://src/content/alioth_lifecycle_definitions.gd")
const SharedLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")

static func available(bindings: RefCounted) -> bool:
	# Ambient provenance covers the complete shared factory, including Terran
	# freighter rank/difficulty scaling. Attack provenance supplies its assembly,
	# collision volumes and subsequent scripted hull changes.
	return Attack.available(bindings) and Travel.parameters(bindings.mido_travel) and Ambient.parameters(bindings.ambient_combat) and ControlRules.parameters(bindings.combat_training_control)

static func flight(bindings: RefCounted,station_id: int=98) -> Dictionary:
	if not load("res://src/content/alioth_flight_definitions.gd").available(bindings) or not available(bindings) or station_id!=int(bindings.mido_travel.alioth_attack.station_id):return {}
	var result: Dictionary=bindings.first_flight.duplicate(true)
	result.scope="alioth_attack_flight"
	for key in ["campaign_cursor","station_id","system_id","mission_kind"]:result[key]=int(bindings.mido_travel.alioth_attack[key])
	result.actor_count=int(bindings.mido_travel.alioth_attack.population.actor_count)
	return result

static func combat_population(bindings: RefCounted,combat_state: Dictionary) -> bool:
	if combat_state.get("campaign_cursor")!=16 or flight(bindings).is_empty():return false
	for key in ["base_content_id","binding_id"]:
		if combat_state.get(key)!=bindings.get(key):return false
	var expected: Array=bindings.mido_travel.alioth_attack.population.actors
	var actors: Variant=combat_state.get("actors")
	if not actors is Array or actors.size()!=expected.size():return false
	for id in actors.size():
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:
			if actors[id].get(key)!=int(expected[id][key]):return false
		if not actors[id].get("alioth_attack",false):return false
	return true

static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not available(bindings) or not packet.get("alioth_context") is Dictionary:return {}
	var context: Dictionary=packet.alioth_context
	var source: Dictionary=bindings.mido_travel.alioth_attack
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key) or context.get(key)!=bindings.get(key):return {}
	for key in ["campaign_cursor","station_id","system_id","mission_kind"]:
		if not context.get(key) is int or context[key]!=int(source[key]):return {}
	if packet.get("campaign_cursor")!=context.campaign_cursor or packet.get("station_id")!=context.station_id:return {}
	if context.get("mission_story")!=true or context.get("mission_completed")!=false or not Numbers.integer(context.get("rank"),0,20) or context.get("difficulty") not in [0.5,1.0]:return {}
	var actors: Variant=packet.get("actors")
	if not actors is Array or actors.size()!=int(source.population.actor_count):return {}
	for id in actors.size():
		var row: Variant=actors[id];var expected: Dictionary=source.population.actors[id]
		if not row is Dictionary:return {}
		for key in ["actor_id","actor_kind","subtype","hull_catalogue_id"]:
			if not row.get(key) is int or row[key]!=int(expected[key]):return {}
		var freight: bool=int(expected.subtype)==1
		if row.get("population_group")!=("freighter" if freight else "fighter") or not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return {}
		if freight:
			if not Equal.equal_value(row.get("assembly"),source.population.freighter_assembly) or row.get("model_assembly_required")!=true:return {}
			if row.get("friendly")!=source.population.freighter_friendly or row.get("cruise_enabled")!=source.population.freighter_cruise_enabled:return {}
			if row.get("hull_divisors")!=([3,6] if id==0 else [3]) or row.get("cargo")!=[]:return {}
		elif int(expected.actor_kind)==9:
			if row.get("hull_multiplier")!=int(source.population.void_hull_multiplier):return {}
		elif row.get("friendly")!=source.population.escort_friendly or row.get("current_hull_override")!=int(source.population.escort_current_hull):return {}
	var data: Dictionary=context.duplicate(true)
	data.actor_count=actors.size()
	for key in ["rank_base","rank_multiplier","cursor_multiplier","difficulty_offset","percentage_scale","engagement_half_extent","initial_model_draw_enabled","initial_node_draw_requested","initial_engine_draw_enabled"]:
		data[key]=bindings.combat_training_control[key]
	for key in ["initial_actor_mode","initial_active","initial_hostile","friendly","initial_actor_targeting_blocked","initial_statistics_targeting_blocked"]:
		data[key]=bindings.mido_travel.traffic_control[key]
	return data

static func combat(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	var data:=population(bindings,packet)
	if data.is_empty() or not Weapons.parameters(bindings.early_contracts.get("ship_combat")):return {}
	var weapon_rules: Dictionary=bindings.early_contracts.ship_combat.weapons
	var attack_rules: Dictionary=bindings.mido_travel.alioth_attack.weapons
	data.npc_weapons=[];data.player_weapon_targets=[];data.target_memberships=[]
	for actor in packet.actors:
		var weapon: Dictionary={"unarmed":true}
		if actor.population_group=="fighter":
			weapon=Weapons.scaled_parameters(weapon_rules,int(data.campaign_cursor),int(data.rank),float(data.difficulty))
			if weapon.is_empty():return {}
			var void_weapon: Dictionary=attack_rules["void"]
			var source: Dictionary=void_weapon if actor.actor_kind==int(void_weapon.actor_kind) else weapon_rules.factions[0]
			for key in ["actor_kind","item_id","kind","catalogue_kind","model_resource_id"]:weapon[key]=int(source[key])
			if actor.actor_kind==int(void_weapon.actor_kind):weapon.damage*=int(source.damage_multiplier)
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:weapon[key]=actor[key]
		data.npc_weapons.append(weapon);data.player_weapon_targets.append(actor.actor_id)
		var targets:=[]
		# At story16, ordinary Void actors list the other faction first and
		# the player last. Terran actors retain the ordinary player-first list.
		for other in packet.actors:
			if other.actor_kind!=actor.actor_kind:targets.append(other.actor_id)
		if actor.actor_kind==int(attack_rules.player_last_actor_kind):targets.append(-1)
		else:targets.push_front(-1)
		data.target_memberships.append(targets)
	return data

static func initialization(bindings: RefCounted) -> Dictionary:
	if not available(bindings) or not Weapons.parameters(bindings.early_contracts.get("ship_combat")) or not World.available(bindings):return {}
	var data: Dictionary=bindings.mido_travel.alioth_attack.population.duplicate(true)
	var shared: Dictionary=bindings.opening_actors.npc_initialization.world_initialization
	for key in ["weapon_effect_capacity","weapon_effect_random_bound","zero_means_flipped"]:data[key]=shared[key]
	var source: Dictionary=bindings.mido_travel.alioth_attack.weapons["void"]
	var ordinary:=World.impact_model(bindings,0)
	data.weapon_groups=["fighter"];data.weapon_item_sequence=[];data.weapon_effect_sequence=[]
	data.faction_weapon_effects={0:{"items":[0,0],"resources":[ordinary,ordinary]},
		int(source.actor_kind):{"items":[0,int(source.item_id)],"resources":[ordinary,int(source.impact_model_id)]}}
	return data

static func lifecycle(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not Life.available(bindings) or not SharedLife.available(bindings):return {}
	var data:=combat(bindings,packet)
	if data.is_empty():return {}
	var shared: Dictionary=bindings.combat_training_control
	for key in shared:
		if not data.has(key):data[key]=shared[key]
	data.actor_kinds=packet.actors.map(func(actor):return actor.actor_kind)
	data.hull_catalogue_ids=packet.actors.map(func(actor):return actor.hull_catalogue_id)
	data.alioth_lifecycle=bindings.mido_travel.alioth_lifecycle.duplicate(true)
	data.lifecycle=bindings.early_contracts.ship_lifecycle.duplicate(true)
	data.lifecycle.reactions.eligible_factions=data.alioth_lifecycle.reaction_factions.duplicate()
	data.lifecycle.reactions.primary_faction=int(data.alioth_lifecycle.primary_faction)
	data.cargo=bindings.combat_training_destruction.cargo.duplicate(true)
	data.selection_skipped_modes=data.lifecycle.selection_skipped_modes.map(func(mode):return int(mode))
	data.nonhostile_remaining_delta=int(bindings.combat_training_destruction.nonhostile_remaining_delta)
	var models: Array=data.lifecycle.cargo_models.duplicate(true)
	models.append(data.alioth_lifecycle.void_cargo)
	data.actors=[]
	for actor in packet.actors:
		var row: Dictionary={}
		for key in ["actor_id","actor_kind","hull_catalogue_id","subtype","population_group"]:row[key]=actor[key]
		for model in models:
			if int(model.actor_kind)==actor.actor_kind:
				row.cargo_model_id=int(model.cargo_model_id);row.cargo_model_resource=model.cargo_model_resource
		if not row.has("cargo_model_id"):return {}
		data.actors.append(row)
	return data

static func npc_hit(data: Dictionary,weapon: Dictionary) -> bool:
	if not data.has("alioth_lifecycle"):return false
	for row in data.npc_weapons:
		if row.get("unarmed",false):continue
		var matches:=true
		for key in ["item_id","category","kind","damage","nonplayer_source"]:
			if weapon.get(key)!=row.get(key):matches=false;break
		if matches:return true
	return false
