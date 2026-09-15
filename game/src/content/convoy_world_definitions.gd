extends RefCounted
## Composition of already imported convoy and shared factory declarations.
## This describes the active encounter at Kernstal, not permission to start it.
const Capture=preload("res://src/content/convoy_capture_definitions.gd")
const Ship=preload("res://src/content/convoy_ship_definitions.gd")
const Combat=preload("res://src/content/contract_ship_combat_definitions.gd")
const Lifecycle=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const ConvoyLifecycle=preload("res://src/content/convoy_lifecycle_definitions.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const World=preload("res://src/content/contract_world_definitions.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Travel.parameters(bindings.mido_travel) and Capture.parameters(bindings.mido_travel.get("convoy_capture")) and Ship.available(bindings) and Combat.parameters(bindings.early_contracts.get("ship_combat")) and ControlRules.parameters(bindings.combat_training_control) and World.available(bindings)

static func flight(bindings: RefCounted,station_id: int) -> Dictionary:
	if not available(bindings) or not ConvoyLifecycle.available(bindings) or station_id!=int(bindings.mido_travel.convoy_capture.station_id):return {}
	var result: Dictionary=bindings.first_flight.duplicate(true)
	var convoy: Dictionary=bindings.mido_travel.convoy_capture
	result.scope="mido_convoy_flight"
	for key in ["campaign_cursor","station_id","system_id","mission_kind"]:result[key]=int(convoy[key])
	result.player_position=convoy.population.player_position.duplicate()
	result.actor_count=int(convoy.population.actor_count)
	return result

static func combat_population(bindings: RefCounted,combat: Dictionary) -> bool:
	if flight(bindings,79).is_empty() or combat.get("campaign_cursor")!=14:return false
	for key in ["base_content_id","binding_id"]:
		if combat.get(key)!=bindings.get(key):return false
	var actors: Variant=combat.get("actors")
	var expected: Array=bindings.mido_travel.convoy_capture.population.actors
	if not actors is Array or actors.size()!=expected.size():return false
	for id in actors.size():
		if not actors[id] is Dictionary:return false
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:
			if actors[id].get(key)!=int(expected[id][key]):return false
		if actors[id].get("population_group")!=("capital" if int(expected[id].subtype)==1 else "fighter"):return false
	return true

static func context_valid(bindings: RefCounted,context: Dictionary) -> bool:
	if not available(bindings):return false
	var data: Dictionary=bindings.mido_travel.convoy_capture
	for key in ["base_content_id","binding_id"]:
		if context.get(key)!=bindings.get(key):return false
	for key in ["campaign_cursor","station_id","system_id","mission_kind"]:
		if not context.get(key) is int or context[key]!=int(data[key]):return false
	return context.get("mission_story")==true and context.get("mission_completed")==false and context.get("rank") is int and context.rank>=0 and context.rank<=20 and context.get("difficulty") in [0.5,1.0]

static func initialization(bindings: RefCounted) -> Dictionary:
	if not available(bindings):return {}
	var data: Dictionary=bindings.mido_travel.convoy_capture.population.duplicate(true)
	var shared: Dictionary=bindings.opening_actors.npc_initialization.world_initialization
	for key in ["weapon_effect_capacity","weapon_effect_random_bound","zero_means_flipped"]:data[key]=shared[key]
	data.weapon_groups=["fighter"]
	data.weapon_item_sequence=[];data.weapon_effect_sequence=[];data.faction_weapon_effects={}
	for faction in bindings.early_contracts.ship_combat.weapons.factions:
		if int(faction.actor_kind) not in [0,8]:continue
		var item:=int(faction.item_id)
		data.faction_weapon_effects[int(faction.actor_kind)]={"items":[0,item],"resources":[World.impact_model(bindings,0),World.impact_model(bindings,item)]}
	return data

static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not packet.get("convoy_context") is Dictionary or not context_valid(bindings,packet.convoy_context):return {}
	var context: Dictionary=packet.convoy_context
	for key in ["base_content_id","binding_id","campaign_cursor","station_id"]:
		if packet.get(key)!=context[key]:return {}
	var source: Dictionary=bindings.mido_travel.convoy_capture.population
	if not packet.get("actors") is Array or packet.actors.size()!=int(source.actor_count):return {}
	var data: Dictionary=bindings.combat_training_control.duplicate(true)
	data.merge({"campaign_cursor":context.campaign_cursor,"station_id":context.station_id,"system_id":context.system_id,"actor_count":int(source.actor_count),"rank":context.rank,"difficulty":context.difficulty,
		"target_memberships":[],"player_weapon_targets":[],"npc_weapons":[],"actor_kinds":[],"hull_catalogue_ids":[]},true)
	for id in packet.actors.size():
		var row: Variant=packet.actors[id]
		var expected: Dictionary=source.actors[id]
		if not row is Dictionary:return {}
		for key in ["actor_id","actor_kind","subtype","hull_catalogue_id"]:
			if not row.get(key) is int or row[key]!=int(expected[key]):return {}
		var capital: bool=int(expected.subtype)==int(bindings.mido_travel.convoy_ship.subtype)
		if row.get("population_group")!=("capital" if capital else "fighter") or not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return {}
		data.actor_kinds.append(row.actor_kind);data.hull_catalogue_ids.append(row.hull_catalogue_id);data.player_weapon_targets.append(id)
		var weapon: Dictionary={"unarmed":true} if capital else Combat.shared_weapon(bindings.early_contracts.ship_combat.weapons,context.campaign_cursor,context.rank,float(context.difficulty),row.actor_kind)
		if weapon.is_empty():return {}
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:weapon[key]=row[key]
		data.npc_weapons.append(weapon)
	for id in packet.actors.size():
		# The source target list includes the player even on Terran actors;
		# hostility is a subsequent guidance decision, not a membership filter.
		var targets: Array=[int(data.player_target_id)]
		for other in packet.actors.size():
			if data.actor_kinds[id]!=data.actor_kinds[other]:targets.append(other)
		data.target_memberships.append(targets)
	return data

static func lifecycle(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not Lifecycle.available(bindings) or not ConvoyLifecycle.available(bindings):return {}
	var data:=population(bindings,packet)
	if data.is_empty():return {}
	# The same ordinary ship routines serve authored encounters and contracts.
	# Keep the convoy's population and mission identity; only share their rules.
	data.lifecycle=bindings.early_contracts.ship_lifecycle.duplicate(true)
	data.capital_death=bindings.mido_travel.convoy_lifecycle.capital_death.duplicate(true)
	data.cargo=bindings.combat_training_destruction.cargo.duplicate(true)
	data.selection_skipped_modes=data.lifecycle.selection_skipped_modes.map(func(mode):return int(mode))
	data.nonhostile_remaining_delta=int(bindings.combat_training_destruction.nonhostile_remaining_delta)
	data.actors=[]
	for actor in packet.actors:
		var row: Dictionary={}
		for key in ["actor_id","actor_kind","hull_catalogue_id","subtype","population_group"]:row[key]=actor[key]
		for model in data.lifecycle.cargo_models:
			if int(model.actor_kind)==actor.actor_kind:
				row.cargo_model_id=int(model.cargo_model_id);row.cargo_model_resource=model.cargo_model_resource
		if not row.has("cargo_model_id"):return {}
		data.actors.append(row)
	return data

static func npc_hit(data: Dictionary,weapon: Dictionary) -> bool:
	if data.get("campaign_cursor")!=14 or not data.get("npc_weapons") is Array:return false
	for row in data.npc_weapons:
		if row.get("unarmed",false):continue
		var matches:=true
		for key in ["item_id","category","kind","damage","nonplayer_source"]:
			if weapon.get(key)!=row.get(key):matches=false;break
		if matches:return true
	return false
