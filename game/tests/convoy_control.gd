extends "res://tests/convoy_world.gd"
## Actual native flight owners; the entry and lethal contacts are explicit
## component fixtures, not an earned campaign handoff or a manual playthrough.
const ActorControl=preload("res://src/simulation/combat_training_control.gd")
const Group=preload("res://src/simulation/opening_combat_group.gd")
const DeathResources=preload("res://src/content/npc_destruction_resources.gd")
const CapitalResources=preload("res://src/content/freighter_destruction_resources.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Life=preload("res://src/content/convoy_lifecycle_definitions.gd")
var _equipment: RefCounted

func verify_bodies(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,context: Dictionary,world: RefCounted) -> void:
	super.verify_bodies(bindings,cat,equipment,context,world)
	_equipment=equipment
	if not Life.available(bindings):return
	var construction: RefCounted=world.npc_construction_owner()
	for value in [-100,-71,-70,0,70,71,100]:
		var group:=Group.new()
		if not group.configure_convoy(bindings,cat,construction,equipment,{"axes":[value,0],"override":-1}):check(false,group.error);return
		for id in 7:
			check(group.refresh_hostility(id),group.error)
			var actor: Dictionary=group.snapshot().actors[id]
			check(actor.hostile==(id<3 or value< -70) and actor.friendly==(id>=3 and value>70),"Terran standing lost its source axis or strict threshold")
	var group:=Group.new()
	if not group.configure_convoy(bindings,cat,construction,equipment,Reputation.initial(bindings)) or not group.begin_contact_pass(world.snapshot().random_state,true):check(false,group.error);return
	var before: Dictionary=group.snapshot()
	check(group.normal_hit(0,-1).is_empty() and group.snapshot()==before,"Invalid hit partially changed the convoy")
	for id in [0,3,5]:
		if group.normal_hit(id,group.snapshot().actors[id].vitals.hull,false).is_empty():check(false,group.error);return
	check(group.current_reputation()=={"axes":[20,-1],"override":-1},"Actual convoy lethal hits lost faction standing")
	check(group.snapshot().provocation.requested_damage==[0,0,0,0,0,0,0] and group.snapshot().provocation.pending_radio.is_empty(),"Convoy created an inapplicable Mido faction warning")

func verify_capture(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	if not Life.available(bindings):
		check(not ActorControl.new().configure_convoy(bindings,cat,construction,_equipment,Reputation.initial(bindings)),"Earlier pack enabled incomplete convoy combat")
		return
	if not library.select_language("gb"):check(false,library.error);return
	var resources:=DeathResources.new();var capital:=CapitalResources.new();var radio_resources:=RadioResources.new()
	if not resources.configure_convoy(library,bindings,construction) or not capital.configure_convoy(library,bindings) or not radio_resources.prepare(library,bindings,null,14):check(false,resources.error+capital.error+radio_resources.error);return
	check(capital.snapshot().model.model_id==18304 and capital.snapshot().initial_material.id==34716 and capital.snapshot().wreck_material.id==33356 and capital.snapshot().model_scale==2.0,"Capital breakup used the ambient freighter's art")
	for lethal in [-1,1,5,6]:
		var control:=ActorControl.new();var weapons:=Weapons.new();var player:=Player.new();var capture:=Capture.new();var radio:=Radio.new()
		if not control.configure_convoy(bindings,cat,construction,_equipment,Reputation.initial(bindings)) or not control.set_destruction(bindings,resources,capital) or not weapons.configure_convoy(bindings,cat,construction) or not player.configure_convoy(bindings,cat,_equipment,construction) or not capture.configure(bindings) or not radio.configure(bindings,library,radio_resources.line_counts,14):check(false,control.error+weapons.error+player.error+capture.error+radio.error);return
		var initial_combat: RefCounted=control.combat_owner()
		var initial: Dictionary=control.snapshot();var now:=0;var fired:=0;var hit_count:=0
		var pose:=Transform3D(Basis.IDENTITY,Vector3(40000,0,120000))
		var random: Dictionary=construction.snapshot().random_state
		while now<240000:
			now+=100
			var combat: RefCounted=control.combat_owner()
			if not combat.begin_contact_pass(random,true):check(false,combat.error);return
			if lethal>=0 and now==20000:
				var result: Dictionary=combat.normal_hit(lethal,combat.snapshot().actors[lethal].vitals.hull,lethal==1)
				if result.is_empty():check(false,combat.error);return
			var contacts: Dictionary=weapons.evaluate_combat_training_update(player,pose,combat,false,100)
			if contacts.is_empty():check(false,weapons.error);return
			weapons=contacts.weapons;player=contacts.player;combat=contacts.combat
			for actor in contacts.actors:hit_count+=actor.npc_contacts.size()
			if not capture.advance(100,radio.snapshot(),pose,combat.snapshot().actors[6].body_pose) or not control.apply_convoy_capture(capture,combat):check(false,capture.error+control.error);return
			combat=control.combat_owner()
			if capture.snapshot().phase==Capture.Stage.ARRIVAL_REQUIRED:break
			var target:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":pose,"ship_id":0,"active":true,"hull":int(player.snapshot().vitals.hull),"special_flight":false,"targeting_blocked":false,"alternate_position":null}
			var step: Dictionary=control.evaluate(combat,weapons,100,target,random)
			if step.is_empty():check(false,control.error);return
			control=step.controller;weapons=step.weapons;random=step.random_state
			for actor in step.actors:
				if not actor.firing.is_empty() and actor.firing.actors[0].outcome.fired:fired+=1
			var state: Dictionary=control.snapshot()
			var targets:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,"player_targets":state.combat.actors.map(func(actor):return {"scenery":false,"current_hull":int(actor.vitals.hull)})}
			radio.step_convoy(now,targets)
			if not radio.error.is_empty():check(false,radio.error);return
			if capture.snapshot().phase==Capture.Stage.ARRIVAL_REQUIRED:break
		var final: Dictionary=control.snapshot()
		check(fired>0 and hit_count>0,"Convoy guidance never fired a contacting shot")
		check(final.combat.actors[3].body_pose!=initial.combat.actors[3].body_pose,"Terran fighter never flew")
		check(capture.snapshot().phase==Capture.Stage.ARRIVAL_REQUIRED,"Live convoy did not reach the source capture handoff: "+str(capture.snapshot()))
		check(final.defeat_status.is_empty(),"Convoy issued generic contract completion")
		check(final.combat.actors.slice(0,3).all(func(actor):return actor.convoy_script_retired and not actor.active and actor.actor_mode==4 and actor.vitals.hull==0),"EMP did not retire its source pirates")
		check(final.accounting.events.all(func(event):return not final.combat.actors[event.actor_id].convoy_script_retired or event.actor_id==1 or final.combat.actors[event.actor_id].nonplayer_kill),"Capture granted a player pirate kill")
		check(final.accounting.counter_deltas.capital_ship_kills==(1 if lethal>=5 else 0),"Capital ship kill was missing or duplicated")
		if lethal>=5:
			check(final.destruction[lethal].phase=="wreck" and final.destruction[lethal].material_id==33356,"Capital death did not finish the original breakup")
		else:check(final.combat.actors[6].body_pose.origin.z>37000,"Captured capital ship failed to cruise")
		var retained: Dictionary=control.snapshot()
		check(control.advance(0,{},initial_combat,random).is_empty() and control.snapshot()==retained,"A stale combat owner revived captured pirates")
		var reset:=Capture.new();reset.configure(bindings)
		check(not control.apply_convoy_capture(reset) and control.snapshot()==retained,"Stale capture rewound live combat")
		print("Convoy live case ",lethal,": ",now,"ms, ",fired," firing events, ",hit_count," NPC contacts, ",final.accounting.counter_deltas)
