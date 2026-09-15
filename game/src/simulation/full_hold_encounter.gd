extends RefCounted
## Retained combat for supported early flights. The enclosing flight stages
## weapon contacts, late player input and the later NPC pass, then commits them
## together with player, camera and scenery. No mission rewards live here.
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const NpcControl=preload("res://src/simulation/opening_npc_control.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const FreightResources=preload("res://src/content/freighter_destruction_resources.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Appearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const Projectiles=preload("res://src/simulation/projectile_visual_state.gd")
const Impacts=preload("res://src/simulation/ordinary_impact_state.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const TrainingControl=preload("res://src/simulation/combat_training_control.gd")
const Primaries=preload("res://src/simulation/primary_weapons.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Inventory=preload("res://src/simulation/opening_target_inventory.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
var error:=""
var _identity:={}
var _control: RefCounted
var _combat: RefCounted
var _weapons: RefCounted
var _projectiles: RefCounted
var _impacts: RefCounted
var _freighter_resources: RefCounted
var _freighter_assemblies:={}
var _resources: RefCounted
var _elapsed_ms:=0
var _world_elapsed_ms:=0
var _weapon_events:=[]
var _actor_events:=[]
var _primaries: RefCounted
var _inventory: RefCounted
var _scenery_identity: RefCounted
var _primary_contacts:=[]
var _primary_fire:={}
var _contract_context:={}

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, construction: RefCounted, difficulty: float) -> bool:
	error=""
	if bindings==null or not construction is Construction or not Appearance.parameters(bindings.full_hold_appearance):return reject("The second mining encounter requires verified construction and appearance")
	var control:=NpcControl.new();var combat:=Combat.new();var weapons:=Weapons.new();var resources:=Resources.new()
	if not resources.configure_full_hold(library,bindings):return reject(resources.error)
	if not control.configure_full_hold(bindings,catalogues,construction,difficulty) or not control.set_full_hold_destruction(resources):return reject(control.error)
	if not combat.configure_full_hold(bindings,catalogues,construction,difficulty):return reject(combat.error)
	if not weapons.configure_full_hold(bindings,catalogues,construction):return reject(weapons.error)
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":4}
	return _accept_configuration(bindings,library,identity,control,combat,weapons,resources)

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, player: RefCounted, scenery: RefCounted, rank: Variant, difficulty: Variant) -> bool:
	return _configure_equipped(bindings,catalogues,library,player,scenery,rank,difficulty,7)

func configure_ambient_traffic(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, player: RefCounted, scenery: RefCounted, rank: Variant, difficulty: Variant, equipment: RefCounted, reputation: Dictionary) -> bool:
	error=""
	if bindings==null or not player is Player or equipment==null or Travel.journey(bindings.mido_travel,11).is_empty():return reject("Mixed flight requires its equipped player and visit declarations")
	var seed: Dictionary=equipment.snapshot().get("loadout",{}).duplicate(true)
	seed.campaign_cursor=11
	if player.loadout()!=seed:return reject("Mixed flight player and retained equipment disagree")
	return _configure_equipped(bindings,catalogues,library,player,scenery,rank,difficulty,11,equipment,reputation)

func configure_local_traffic(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, construction: RefCounted, difficulty: Variant) -> bool:
	error=""
	if not construction is Construction:return reject("Local combat requires its prepared departure")
	var entry: Dictionary=construction.snapshot()
	var cursor: Variant=entry.get("campaign_cursor")
	if not cursor is int or cursor not in [10,11,12] or Travel.flight(bindings,int(entry.get("location",{}).get("station_id",-1)),cursor).is_empty():return reject("Local combat requires a supported Mido flight")
	var progress: Dictionary=entry.get("departure",{}).get("progress",{})
	return _configure_equipped(bindings,catalogues,library,construction.player_owner(),construction.scenery_owner(),progress.get("rank"),difficulty,cursor,construction.equipment_owner(),progress.get("reputation",{}))

func configure_contract_world(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,construction: RefCounted) -> bool:
	error=""
	if not construction is Construction or not ContractWorld.available(bindings) or construction.contract_owner()==null:return reject("Ordinary contract combat requires its prepared native world")
	var state: Dictionary=construction.contract_owner().snapshot()
	if not _configure_equipped(bindings,catalogues,library,construction.player_owner(),construction.scenery_owner(),state.rank,state.difficulty,state.campaign_cursor,construction.equipment_owner(),state.reputation):return false
	_contract_context=construction.scenery_owner().world_initialization_owner().snapshot().contract_context.duplicate(true)
	return true

func configure_convoy(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,construction: RefCounted) -> bool:
	error=""
	if not construction is Construction or construction.snapshot().get("campaign_cursor")!=14 or construction.contract_owner()==null:return reject("Convoy combat requires its prepared earned departure")
	var state: Dictionary=construction.contract_owner().snapshot()
	return _configure_equipped(bindings,catalogues,library,construction.player_owner(),construction.scenery_owner(),state.rank,state.difficulty,14,construction.equipment_owner(),state.reputation)

func configure_alioth(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,construction: RefCounted) -> bool:
	error=""
	if not construction is Construction or construction.snapshot().get("campaign_cursor")!=16 or construction.contract_owner()==null:return reject("Alioth combat requires its earned prepared departure")
	var state: Dictionary=construction.contract_owner().snapshot()
	return _configure_equipped(bindings,catalogues,library,construction.player_owner(),construction.scenery_owner(),state.rank,state.difficulty,16,construction.equipment_owner(),state.reputation)

func configure_free(bindings: RefCounted,catalogues: RefCounted,library: RefCounted,construction: RefCounted) -> bool:
	error=""
	if not construction is Construction or not load("res://src/content/free_flight_definitions.gd").ordinary_entry(bindings,construction.snapshot()) or construction.contract_owner()==null:return reject("Ordinary combat requires its earned prepared departure")
	var state: Dictionary=construction.contract_owner().snapshot()
	var career: RefCounted=construction.contract_owner()
	var context: Dictionary=career.free_flight_context(bindings,int(state.station_id))
	if context.is_empty():return reject(career.error)
	if not _configure_equipped(bindings,catalogues,library,construction.player_owner(),construction.scenery_owner(),state.rank,state.difficulty,18,construction.equipment_owner(),state.reputation):return false
	_contract_context=context
	return true

func apply_alioth_sequence(attack: RefCounted,random_state: Dictionary) -> bool:
	error=""
	if _identity.get("campaign_cursor")!=16:return reject("This encounter has no Alioth choreography")
	var control: RefCounted=_control.fork_for_frame();control._combat=_combat.fork_for_frame()
	var candidate: Dictionary=control.evaluate_alioth_sequence(attack,_weapons,random_state)
	if candidate.is_empty():return reject(control.error)
	_control=candidate.controller;_combat=_control.combat_owner();_weapons=candidate.weapons
	return true

func apply_convoy_capture(capture: RefCounted) -> bool:
	error=""
	if _identity.get("campaign_cursor")!=14:return reject("This encounter has no convoy choreography")
	var control: RefCounted=_control.fork_for_frame()
	if not control.apply_convoy_capture(capture,_combat):return reject(control.error)
	_control=control;_combat=control.combat_owner()
	return true

func _configure_equipped(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, player: RefCounted, scenery: RefCounted, rank: Variant, difficulty: Variant, cursor: int, equipment: RefCounted=null, reputation: Dictionary={}) -> bool:
	error=""
	if bindings==null or not player is Player or not scenery is Scenery:return reject("Equipped combat requires its player and constructed scenery")
	var world: RefCounted=scenery.world_initialization_owner()
	if world==null or world.snapshot().is_empty() or scenery.snapshot().random_state!=world.snapshot().random_state:return reject("Equipped combat must join its fresh constructed world")
	var control:=TrainingControl.new();var weapons:=Weapons.new();var resources:=Resources.new()
	var freight_resources: RefCounted
	var contract_world: bool=ContractWorld.supports(bindings,cursor) and world.snapshot().has("contract_context")
	var contract_mission: Dictionary=world.snapshot().get("contract_context",{}).get("mission",{})
	var ambient: bool=cursor==18 or (contract_world and contract_mission.is_empty()) or (cursor in [11,12] and world.snapshot().station_id==int(Travel.journey(bindings.mido_travel,cursor).from_station_id))
	if cursor==16:
		var population: RefCounted=world.npc_construction_owner()
		freight_resources=FreightResources.new()
		if not resources.configure_alioth_attack(library,bindings,population) or not freight_resources.configure_alioth_attack(library,bindings):return reject(resources.error+freight_resources.error)
		if not control.configure_alioth_attack(bindings,catalogues,population,equipment,reputation) or not weapons.configure_alioth_attack(bindings,catalogues,population):return reject(control.error+weapons.error)
	elif cursor==14 and world.snapshot().get("npc_construction",{}).has("convoy_context"):
		var population: RefCounted=world.npc_construction_owner()
		freight_resources=FreightResources.new()
		if not resources.configure_convoy(library,bindings,population) or not freight_resources.configure_convoy(library,bindings):return reject(resources.error+freight_resources.error)
		if not control.configure_convoy(bindings,catalogues,population,equipment,reputation) or not weapons.configure_convoy(bindings,catalogues,population):return reject(control.error+weapons.error)
	elif ambient:
		var population: RefCounted=world.npc_construction_owner()
		if population==null:return reject("The mixed encounter requires its retained generated actors")
		freight_resources=FreightResources.new()
		var ready: bool=resources.configure_free(library,bindings,population) and freight_resources.configure_free(library,bindings,population) if cursor==18 else resources.configure_ambient(library,bindings,cursor) and freight_resources.configure(library,bindings,cursor)
		if not ready:return reject(resources.error+freight_resources.error)
		if not control.configure_ambient(bindings,catalogues,population,rank,difficulty,equipment,reputation):return reject(control.error)
		if not weapons.configure_ambient(bindings,catalogues,population,rank,difficulty):return reject(weapons.error)
	elif contract_world and contract_mission.get("kind") in [4,7,12]:
		var population: RefCounted=world.npc_construction_owner()
		if not resources.configure_contract(library,bindings,population):return reject(resources.error)
		if not control.configure_contract(bindings,catalogues,population,equipment):return reject(control.error)
		if not weapons.configure_contract(bindings,catalogues,population):return reject(weapons.error)
	elif cursor in [10,11,12] or (contract_world and contract_mission.get("kind")==0):
		if not resources.configure_local_traffic(library,bindings):return reject(resources.error)
		if not control.configure_local_traffic(bindings,catalogues,world,rank,difficulty,equipment,reputation):return reject(control.error)
		if not weapons.configure_local_traffic(bindings,catalogues,world,rank,difficulty):return reject(weapons.error)
	else:
		if not resources.configure_combat_training(library,bindings):return reject(resources.error)
		if not control.configure(bindings,catalogues,world,rank,difficulty):return reject(control.error)
		if not weapons.configure_combat_training(bindings,catalogues,world,rank,difficulty):return reject(weapons.error)
	if not control.set_destruction(bindings,resources,freight_resources):return reject(control.error)
	var mounts:=Mounts.new();var primaries:=Primaries.new();var inventory:=Inventory.new()
	if not mounts.open(library,catalogues):return reject(mounts.error)
	if not primaries.configure(bindings,catalogues,mounts,player.loadout()):return reject(primaries.error)
	var targets:=inventory.configure_local_travel(bindings,catalogues,player,scenery,cursor) if cursor in [10,11,12,13,14,16,18] else inventory.configure_combat_training(bindings,catalogues,player,scenery)
	if not targets:return reject(inventory.error)
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor}
	if not _accept_configuration(bindings,library,identity,control,control.combat_owner(),weapons,resources,primaries,inventory,scenery.presentation_identity()):return false
	_freighter_resources=freight_resources;_freighter_assemblies={}
	if freight_resources!=null:
		for actor in world.snapshot().npc_construction.actors:
			if actor.population_group in ["freighter","capital"]:_freighter_assemblies[int(actor.actor_id)]=actor.assembly.duplicate(true)
	return true

func _accept_configuration(bindings: RefCounted, library: RefCounted, identity: Dictionary, control: RefCounted, combat: RefCounted, weapons: RefCounted, resources: RefCounted, primaries: RefCounted=null, inventory: RefCounted=null, scenery_identity: RefCounted=null) -> bool:
	var initial:=identity.duplicate();initial.merge({"elapsed_ms":0,"weapons":weapons.snapshot()})
	if primaries!=null:initial.primaries=primaries.snapshot()
	var projectiles:=Projectiles.new();var impacts:=Impacts.new()
	if not projectiles.configure(bindings,library,initial):return reject(projectiles.error)
	if not impacts.configure(bindings,library,initial):return reject(impacts.error)
	_identity=identity;_control=control;_combat=combat;_weapons=weapons;_projectiles=projectiles;_impacts=impacts
	_resources=resources
	_elapsed_ms=0;_world_elapsed_ms=0;_weapon_events=[];_actor_events=[]
	_primaries=primaries;_inventory=inventory;_scenery_identity=scenery_identity;_primary_contacts=[];_primary_fire={}
	_contract_context={}
	return true

func bind_contract_session(session: RefCounted,bindings: RefCounted=null) -> bool:
	error=""
	if _contract_context.is_empty() or not is_instance_of(session,load("res://src/simulation/contract_session.gd")):return reject("The encounter has no retained contract world")
	return true if session.bind_world(_control,_contract_context,bindings) else reject(session.error)

func sample_contract_clock(world_ms: int,poll_ms: int) -> bool:
	error=""
	if _contract_context.is_empty():return reject("This encounter has no ordinary contract scene clock")
	return true if _control.sample_scene_clock(world_ms,poll_ms) else reject(_control.error)

func evaluate_contract_session(session: RefCounted,radio_active: bool=false,poll_results: bool=true,periodic_poll_allowed: bool=true) -> Dictionary:
	error=""
	if _contract_context.is_empty() or not is_instance_of(session,load("res://src/simulation/contract_session.gd")):return fail("The encounter has no retained contract career")
	# Contacts have already changed the encounter bodies. Retain that exact
	# body state without inserting an extra actor/guidance update before polling.
	var control: RefCounted=_control.fork_for_frame();control._combat=_combat.fork_for_frame()
	var result: Dictionary=session.evaluate_flight(control,radio_active,poll_results,periodic_poll_allowed)
	if result.is_empty():return fail(session.error)
	_control=result.controller;_combat=_control.combat_owner()
	return {"session":result.session,"opened":result.opened}

func acknowledge_contract_result(session: RefCounted,serial: int) -> Dictionary:
	error=""
	if _contract_context.is_empty() or not is_instance_of(session,load("res://src/simulation/contract_session.gd")):return fail("No retained contract result is available")
	var result: Dictionary=session.acknowledge_flight_result(_control,serial)
	if result.is_empty():return fail(session.error)
	_control=result.controller;_combat=_control.combat_owner()
	return result

func finish_contract_session(session: RefCounted) -> RefCounted:
	error=""
	if _contract_context.is_empty() or not is_instance_of(session,load("res://src/simulation/contract_session.gd")):reject("The encounter has no retained contract career");return null
	var control: RefCounted=_control.fork_for_frame();control._combat=_combat.fork_for_frame()
	var result: RefCounted=session.finish_flight(control,true)
	if result==null:reject(session.error)
	return result

func evaluate_weapons(player: RefCounted, pose: Transform3D, milliseconds: int, scenery: RefCounted=null, shared_random_state: Variant=null, display_available:=true) -> Dictionary:
	error=""
	if _control==null or not Numbers.integer(milliseconds,0,150) or target(player,pose).is_empty():return fail("Invalid encounter weapon frame")
	if _primaries!=null and (not scenery is Scenery or scenery.presentation_identity()!=_scenery_identity):return fail("Equipped contacts require the retained complete scenery")
	var prior:=snapshot();var next:=fork_for_frame()
	if not next._projectiles.advance(milliseconds):return fail(next._projectiles.error)
	if not next._impacts.advance(milliseconds):return fail(next._impacts.error)
	var field: RefCounted=scenery
	var contact_random:={}
	if next._primaries!=null:
		var primary: Dictionary=field.evaluate_primary_contacts(next._primaries,next._combat,next._inventory,milliseconds,shared_random_state,display_available)
		if primary.is_empty():return fail(field.error)
		field=primary.scenery;next._primaries=primary.primaries;next._combat=primary.combat;next._primary_contacts=primary.weapons
		contact_random=primary.get("random_state",{})
	var pass_result: Dictionary
	if next._primaries==null:
		pass_result=next._weapons.evaluate_player_update(player,pose,next._combat.shooter_states(),false,milliseconds)
	else:
		pass_result=next._weapons.evaluate_combat_training_update(player,pose,next._combat,false,milliseconds)
	if pass_result.is_empty():return fail(next._weapons.error)
	if not next._impacts.apply_contacts(prior,next._primary_contacts,pass_result.actors):return fail(next._impacts.error)
	if next._primaries!=null:next._combat=pass_result.combat
	next._weapons=pass_result.weapons;next._weapon_events=pass_result.actors;next._elapsed_ms+=milliseconds
	next._primary_fire={}
	var result:={"encounter":next,"player":pass_result.player}
	if field!=null:result.scenery=field
	if not contact_random.is_empty():result.random_state=contact_random
	return result

func evaluate_world_logic(milliseconds: int, random_state: Dictionary) -> Dictionary:
	error=""
	if _control==null or not Numbers.integer(milliseconds,0,150):return fail("Invalid encounter world-logic frame")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var next:=fork_for_frame()
	if _identity.campaign_cursor in [11,12,13,14,18] and _control.snapshot().has("traffic_clock"):
		var result: Dictionary=_control.evaluate_ambient_world_logic(milliseconds,_combat,random_state)
		if result.is_empty():return fail(_control.error)
		next._control=result.controller;next._combat=result.combat
		return {"encounter":next,"random_state":result.random_state}
	return {"encounter":next,"random_state":random.snapshot()}

func reset_primary_fire_intervals() -> bool:
	error=""
	if _primaries==null:return reject("This encounter has no equipped primary owner")
	if not _primaries.reset_fire_intervals():return reject(_primaries.error)
	return true

func evaluate_primary_fire(player: RefCounted, pose: Transform3D, requested: bool, input_enabled: bool, random_state: Dictionary) -> Dictionary:
	error=""
	var input:=target(player,pose);var random:=Random.new()
	if _primaries==null or input.is_empty():return fail("Late primary input requires an equipped encounter")
	if not random.restore(random_state):return fail(random.error)
	var next:=fork_for_frame();var result:=random.snapshot()
	next._primary_fire={}
	if requested and input_enabled and input.active and input.hull>0:
		next._primary_fire=next._primaries.fire(pose,true,result)
		if next._primary_fire.is_empty():return fail(next._primaries.error)
		result=next._primary_fire.random_state
	return {"encounter":next,"random_state":result}

func evaluate_cue(player: RefCounted, pose: Transform3D, cursor: int) -> RefCounted:
	error=""
	var input:=target(player,pose)
	if _control==null or input.is_empty():reject("Invalid second-trip cue player");return null
	if _primaries!=null:reject("Training mission cues belong to its flight controller");return null
	var operation: Dictionary=_control.apply_full_hold_appearance(_combat,cursor,input)
	if operation.is_empty():reject(_control.error);return null
	var next:=fork_for_frame();next._control=operation.controller;next._combat=operation.combat
	return next

func evaluate_world(player: RefCounted, pose: Transform3D, milliseconds: int, random_state: Dictionary) -> Dictionary:
	error=""
	var input:=target(player,pose)
	if _control==null or not Numbers.integer(milliseconds,0,150) or input.is_empty():return fail("Invalid encounter NPC frame")
	var operation: Dictionary=_control.evaluate(_combat,_weapons,milliseconds,input,random_state)
	if operation.is_empty():return fail(_control.error)
	var next:=fork_for_frame()
	next._control=operation.controller;next._combat=operation.combat;next._weapons=operation.weapons
	next._actor_events=operation.actors;next._world_elapsed_ms+=milliseconds
	return {"encounter":next,"random_state":operation.random_state}

func target(player: RefCounted, pose: Transform3D) -> Dictionary:
	if not player is Player or not Flight.rigid_pose(pose):return {}
	var state: Dictionary=player.snapshot()
	for key in _identity:
		if state.get(key)!=_identity[key]:return {}
	if state.get("ship_id")!=0:return {}
	# Ordinary starter construction keeps these source flags clear. Damage
	# permission is independently controlled by the departure controller.
	return {"base_content_id":_identity.base_content_id,"binding_id":_identity.binding_id,
		"ship_id":0,"pose":pose,"active":state.active,"hull":state.vitals.hull,
		"targeting_blocked":false,"special_flight":false,"alternate_position":null}

func snapshot() -> Dictionary:
	if _control==null:return {}
	var result:=_identity.duplicate()
	result.merge({"elapsed_ms":_elapsed_ms,"world_elapsed_ms":_world_elapsed_ms,
		"combat":_combat.snapshot(),"controller":_control.snapshot(),"weapons":_weapons.snapshot(),
		"weapon_events":_weapon_events.duplicate(true),"actor_events":_actor_events.duplicate(true),
		"projectile_visuals":_projectiles.snapshot(),"impact_visuals":_impacts.snapshot()})
	if _primaries!=null:
		result.primaries=_primaries.snapshot();result.primary_contacts=_primary_contacts.duplicate(true);result.primary_fire=_primary_fire.duplicate(true)
	return result

func projectile_visual_owner() -> RefCounted:return null if _projectiles==null else _projectiles.fork_for_frame()
func combat_owner() -> RefCounted:return null if _combat==null else _combat.fork_for_frame()
func impact_visual_owner() -> RefCounted:return null if _impacts==null else _impacts.fork_for_frame()
func npc_destruction_owner(actor_id: int) -> RefCounted:return null if _control==null else _control.destruction_owner(actor_id)
func freighter_assembly(actor_id: int) -> Dictionary:return _freighter_assemblies.get(actor_id,{}).duplicate(true)
func freighter_resources() -> RefCounted:return _freighter_resources
func destruction_resources() -> RefCounted:return null if _resources==null else _resources.fork_for_frame()
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._contract_context=_contract_context.duplicate(true)
	if _control==null:return copy
	copy._identity=_identity;copy._control=_control.fork_for_frame();copy._combat=_combat.fork_for_frame()
	copy._weapons=_weapons.fork_for_frame();copy._projectiles=_projectiles.fork_for_frame();copy._impacts=_impacts.fork_for_frame()
	copy._resources=_resources;copy._freighter_resources=_freighter_resources;copy._freighter_assemblies=_freighter_assemblies
	copy._primaries=null if _primaries==null else _primaries.fork_state()
	copy._inventory=_inventory;copy._scenery_identity=_scenery_identity
	copy._primary_contacts=_primary_contacts.duplicate(true);copy._primary_fire=_primary_fire.duplicate(true)
	copy._elapsed_ms=_elapsed_ms;copy._world_elapsed_ms=_world_elapsed_ms
	copy._weapon_events=_weapon_events.duplicate(true);copy._actor_events=_actor_events.duplicate(true)
	return copy
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
