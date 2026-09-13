extends RefCounted
## Retained combat for supported early flights. The enclosing flight stages
## weapon contacts, late player input and the later NPC pass, then commits them
## together with player, camera and scenery. No mission rewards live here.
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const NpcControl=preload("res://src/simulation/opening_npc_control.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
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
var error:=""
var _identity:={}
var _control: RefCounted
var _combat: RefCounted
var _weapons: RefCounted
var _projectiles: RefCounted
var _impacts: RefCounted
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
	error=""
	if bindings==null or not player is Player or not scenery is Scenery:return reject("Training combat requires its equipped player and constructed scenery")
	var world: RefCounted=scenery.world_initialization_owner()
	if world==null or world.snapshot().is_empty() or scenery.snapshot().random_state!=world.snapshot().random_state:return reject("Training combat must join its fresh constructed world")
	var control:=TrainingControl.new();var weapons:=Weapons.new();var resources:=Resources.new()
	if not resources.configure_combat_training(library,bindings):return reject(resources.error)
	if not control.configure(bindings,catalogues,world,rank,difficulty) or not control.set_destruction(bindings,resources):return reject(control.error)
	if not weapons.configure_combat_training(bindings,catalogues,world,rank,difficulty):return reject(weapons.error)
	var mounts:=Mounts.new();var primaries:=Primaries.new();var inventory:=Inventory.new()
	if not mounts.open(library,catalogues):return reject(mounts.error)
	if not primaries.configure(bindings,catalogues,mounts,player.loadout()):return reject(primaries.error)
	if not inventory.configure_combat_training(bindings,catalogues,player,scenery):return reject(inventory.error)
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":7}
	return _accept_configuration(bindings,library,identity,control,control.combat_owner(),weapons,resources,primaries,inventory,scenery.presentation_identity())

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
	return true

func evaluate_weapons(player: RefCounted, pose: Transform3D, milliseconds: int, scenery: RefCounted=null) -> Dictionary:
	error=""
	if _control==null or not Numbers.integer(milliseconds,0,150) or target(player,pose).is_empty():return fail("Invalid encounter weapon frame")
	if _primaries!=null and (not scenery is Scenery or scenery.presentation_identity()!=_scenery_identity):return fail("Training contacts require the retained complete scenery")
	var prior:=snapshot();var next:=fork_for_frame()
	if not next._projectiles.advance(milliseconds):return fail(next._projectiles.error)
	if not next._impacts.advance(milliseconds):return fail(next._impacts.error)
	var field: RefCounted=scenery
	if next._primaries!=null:
		var primary: Dictionary=field.evaluate_primary_contacts(next._primaries,next._combat,next._inventory,milliseconds)
		if primary.is_empty():return fail(field.error)
		field=primary.scenery;next._primaries=primary.primaries;next._combat=primary.combat;next._primary_contacts=primary.weapons
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
	return result

func evaluate_primary_fire(player: RefCounted, pose: Transform3D, requested: bool, input_enabled: bool, random_state: Dictionary) -> Dictionary:
	error=""
	var input:=target(player,pose);var random:=Random.new()
	if _primaries==null or input.is_empty():return fail("Late primary input requires the equipped training encounter")
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
func destruction_resources() -> RefCounted:return null if _resources==null else _resources.fork_for_frame()
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	if _control==null:return copy
	copy._identity=_identity;copy._control=_control.fork_for_frame();copy._combat=_combat.fork_for_frame()
	copy._weapons=_weapons.fork_for_frame();copy._projectiles=_projectiles.fork_for_frame();copy._impacts=_impacts.fork_for_frame()
	copy._resources=_resources
	copy._primaries=null if _primaries==null else _primaries.fork_state()
	copy._inventory=_inventory;copy._scenery_identity=_scenery_identity
	copy._primary_contacts=_primary_contacts.duplicate(true);copy._primary_fire=_primary_fire.duplicate(true)
	copy._elapsed_ms=_elapsed_ms;copy._world_elapsed_ms=_world_elapsed_ms
	copy._weapon_events=_weapon_events.duplicate(true);copy._actor_events=_actor_events.duplicate(true)
	return copy
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
