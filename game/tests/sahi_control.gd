extends "res://tests/sahi_population.gd"
## Detached, source-selected encounter. Real NPC projectiles exercise the battle;
## explicit lethal contacts separately test attribution and duplicate protection.
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Story=preload("res://src/content/story_encounter_definitions.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")

func test_label() -> String:return "Sahi native encounter"

func after_population(library: RefCounted,bindings: RefCounted,cat: RefCounted,equipment: RefCounted,scenery: RefCounted,player: RefCounted) -> void:
	var held: Dictionary=equipment.snapshot()
	var world: RefCounted=scenery.world_initialization_owner()
	var packet: Dictionary=world.snapshot().npc_construction
	var data:=Story.compose(bindings,cat,packet)
	if data.is_empty():check(false,"Accepted Sahi world did not compose its combat profile");return
	check(data.npc_weapons.slice(3).all(func(row):return row.unarmed),"Sahi freighters acquired guns")
	# Rank8: int((8-2)*float32(.9))+2 = 7; the authored .8 modifier truncates to5.
	check(data.npc_weapons.slice(0,3).all(func(row):return row.item_id==5 and row.damage==5),"Sahi rank-eight easy Void weapon damage changed")
	var changed:=packet.duplicate(true);changed.actors[0].actor_kind=8
	check(Story.compose(bindings,cat,changed).is_empty(),"Story entry admitted an altered cast")
	changed=packet.duplicate(true);changed.binding_id="foreign"
	check(Story.compose(bindings,cat,changed).is_empty(),"Story entry admitted foreign content")
	var encounter:=Encounter.new()
	if not encounter.configure_story(bindings,cat,library,player,scenery,equipment,Reputation.initial(bindings)):check(false,encounter.error);return
	var initial: Dictionary=encounter.snapshot()
	check(initial.controller.support_state=="story_combat" and initial.controller.destruction.size()==5,"Sahi did not prepare all native combat/death owners")
	check(initial.controller.destruction.slice(3).all(func(row):return row.model_scale==1.0 and row.material_id==34704 and row.cargo.entries.is_empty()),"Sahi freighters changed faction wreck art or gained cargo")
	check(initial.controller.destruction.slice(0,3).all(func(row):return row.cargo.entries==packet.actors[row.actor_id].cargo),"Sahi fighter death regenerated its cargo")
	for id in 5:
		var body: Dictionary=initial.combat.actors[id]
		check(body.actor_kind==packet.actors[id].actor_kind and body.pose==packet.actors[id].statistics_pose,"Sahi combat replaced its generated actor")
		if id>=3:check(body.max_hull==380 and body.vitals.hull==380 and body.point_boxes.size()==3,"Sahi freighter hull division or point volumes changed")
	verify_live(encounter,bindings,player,world.snapshot().random_state)
	verify_accounting(encounter,bindings,player,world.snapshot().random_state)
	check(equipment.snapshot()==held and encounter.snapshot()==initial,"Detached encounter checks changed equipment or retained combat")

func target(bindings: RefCounted,pose: Transform3D,player: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":pose,"ship_id":0,"active":true,"hull":int(player.snapshot().vitals.hull),"special_flight":false,"targeting_blocked":false,"alternate_position":null}

func verify_live(encounter: RefCounted,bindings: RefCounted,player: RefCounted,random: Dictionary) -> void:
	var control: RefCounted=encounter._control.fork_for_frame()
	var weapons: RefCounted=encounter._weapons.fork_for_frame()
	var pose:=Transform3D(Basis.IDENTITY,Vector3(-100000,0,100000))
	var initial: Dictionary=control.snapshot();var time:=0;var shots:=0;var hits:=0;var dead_at:={}
	while time<240000:
		time+=100
		var combat: RefCounted=control.combat_owner()
		if not combat.begin_contact_pass(random,true):check(false,combat.error);return
		var contacts: Dictionary=weapons.evaluate_combat_training_update(player,pose,combat,false,100)
		if contacts.is_empty():check(false,weapons.error);return
		weapons=contacts.weapons;player=contacts.player;combat=contacts.combat
		for event in contacts.actors:hits+=event.npc_contacts.size()
		var frame: Dictionary=control.evaluate(combat,weapons,100,target(bindings,pose,player),combat.contact_random_state())
		if frame.is_empty():check(false,control.error);return
		control=frame.controller;weapons=frame.weapons;random=frame.random_state
		for event in frame.actors:
			if not event.firing.is_empty() and event.firing.actors[0].outcome.fired:shots+=1
		var state: Dictionary=control.career_snapshot()
		for event in state.accounting.events:
			if event.actor_id>=3 and not dead_at.has(event.actor_id):dead_at[event.actor_id]=time
		if dead_at.size()==2:break
	var result: Dictionary=control.snapshot()
	check(dead_at.size()==2 and shots>0 and hits>0,"Actual Sahi NPC fire did not destroy the two freighters: "+str(dead_at))
	check(result.accounting.events.size()==2 and result.accounting.counter_deltas.player_kills==0 and result.accounting.counter_deltas.pirate_kills==0,"Sahi NPC battle awarded player kills or duplicated deaths")
	check(result.combat.current_reputation==Reputation.initial(bindings),"NPC battle changed player reputation")
	check(result.combat.actors.slice(3).all(func(row):return row.nonplayer_kill and row.body_pose.origin==initial.combat.actors[row.actor_id].body_pose.origin),"Sahi freighters cruised or lost NPC attribution")
	check(result.flight[0].root_pose!=initial.flight[0].root_pose and result.defeat_status.is_empty(),"Sahi flight did not move or invented mission completion")
	print("Sahi NPC battle: ",time,"ms; ",shots," shots; ",hits," contacts; freighter deaths ",dead_at)

func verify_accounting(encounter: RefCounted,bindings: RefCounted,player: RefCounted,random: Dictionary) -> void:
	var control: RefCounted=encounter._control.fork_for_frame();var combat: RefCounted=control.combat_owner()
	var pose:=Transform3D(Basis.IDENTITY,Vector3(-100000,0,100000))
	if not combat.begin_contact_pass(random,true) or not combat.refresh_hostility(0):check(false,combat.error);return
	var hit: Dictionary=combat.normal_hit(0,100000,false)
	if hit.is_empty():check(false,combat.error);return
	var first: Dictionary=control.advance(100,target(bindings,pose,player),combat,combat.contact_random_state())
	if first.is_empty():check(false,control.error);return
	var state: Dictionary=control.snapshot()
	check(state.accounting.events.size()==1 and state.accounting.counter_deltas.player_kills==1 and state.accounting.counter_deltas.pirate_kills==0,"Void destruction lost a player kill or counted it as a pirate")
	check(state.combat.current_reputation==Reputation.initial(bindings),"Void destruction changed player faction reputation")
	check(control.advance(-1,target(bindings,pose,player),null,first.random_state).is_empty() and control.snapshot()==state,"Rejected duration partially advanced Sahi combat")
	for frame in 40:
		var step: Dictionary=control.advance(100,target(bindings,pose,player),null,control.snapshot().random_state)
		if step.is_empty():check(false,control.error);return
	var after: Dictionary=control.snapshot()
	check(after.accounting.events.size()==1 and after.destruction[0].cargo.entries==state.destruction[0].cargo.entries,"Sahi breakup duplicated a kill or replaced generated cargo")
