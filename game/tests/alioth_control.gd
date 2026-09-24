extends SceneTree
## Earned equipment fixture; explicit Alioth entry/position. The live battle
## case uses actual NPC guidance/projectiles, with no injected lethal contacts.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Life=preload("res://src/content/alioth_lifecycle_definitions.gd")
const ActorControl=preload("res://src/simulation/combat_training_control.gd")
const Group=preload("res://src/simulation/opening_combat_group.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const DeathResources=preload("res://src/content/npc_destruction_resources.gd")
const FreightResources=preload("res://src/content/freighter_destruction_resources.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Attack=preload("res://src/simulation/alioth_attack.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Alioth live control: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	if not Life.available(bindings):
		check(not ActorControl.new().configure_alioth_attack(bindings,cat,null,null,Reputation.initial(bindings)),"Earlier reader enabled incomplete Alioth combat")
		check(not FreightResources.new().configure_alioth_attack(lib,bindings),"Earlier reader enabled the Alioth wreck")
		return
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	if not Scenario.prepare_alioth_component(equipment,bindings,cat):check(false,equipment.error);return
	var equipment_before: Dictionary=equipment.snapshot()
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,150000))
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,"station_id":98,"system_id":19,"rank":0,"difficulty":0.5,"mission_kind":4,"mission_story":true,"mission_completed":false}
	var world:=World.new()
	if not world.configure_alioth_attack(bindings,cat,equipment.snapshot().loadout,context,pose.origin,{"companions_empty":true,"location_match":false,"special_placement":false}) or world.generate({"state":42}).is_empty():check(false,world.error);return
	var construction: RefCounted=world.npc_construction_owner()
	var resources:=DeathResources.new();var freight:=FreightResources.new()
	if not resources.configure_alioth_attack(lib,bindings,construction) or not freight.configure_alioth_attack(lib,bindings):check(false,resources.error+freight.error);return
	check(freight.snapshot().model.model_id==18302 and freight.snapshot().initial_material.id==34708 and freight.snapshot().wreck_material.id==33354 and freight.snapshot().model_scale==1.0,"Alioth freighter used the wrong destruction art")
	check(resources.snapshot().cargo_models[3].model_id==16916 and resources.snapshot().cargo_models[7].model_id==16992,"Void/Terran cargo lost its original faction art")
	for standing in [-100,0,100]:
		var group:=Group.new()
		if not group.configure_alioth_attack(bindings,cat,construction,equipment,{"axes":[standing,0],"override":-1}) or not group.begin_contact_pass(world.snapshot().random_state,true):check(false,group.error);return
		for id in 10:
			check(group.refresh_hostility(id),group.error)
			check(group.snapshot().actors[id].hostile==(id>=3 and id<7) and group.snapshot().actors[id].friendly==(id<3 or id>=7),"Alioth forced friendship changed with reputation")
		# Explicit nonlethal player fixture checks reactions independently of
		# the unassisted battle below. No warning interrupts an active story.
		var hit:=group.normal_hit(7,400,false)
		if hit.is_empty() or not group.refresh_hostility(7):check(false,group.error);return
		check(not group.snapshot().actors[7].hostile and group.snapshot().actors[7].friendly and group.snapshot().actors[7].forced_hostile,"Provocation overrode the mission's forced friendship")
		check(group.snapshot().provocation.requested_damage[7]==400 and group.snapshot().provocation.pending_radio.is_empty() and group.contact_random_state()==world.snapshot().random_state,"Story reactions lost requested damage or consumed radio RNG")
		var retained: Dictionary=group.snapshot()
		check(group.normal_hit(3,-1).is_empty() and group.snapshot()==retained,"Invalid damage changed Alioth combat")
	verify_live(bindings,cat,lib,construction,equipment,resources,freight,pose,world.snapshot().random_state)
	verify_lethal_accounting(bindings,cat,construction,equipment,resources,freight,pose,world.snapshot().random_state)
	check(equipment.snapshot()==equipment_before,"Detached Alioth combat changed station equipment or campaign progress")

func configure_control(bindings: RefCounted,cat: RefCounted,construction: RefCounted,equipment: RefCounted,resources: RefCounted,freight: RefCounted) -> RefCounted:
	var control:=ActorControl.new()
	if not control.configure_alioth_attack(bindings,cat,construction,equipment,Reputation.initial(bindings)) or not control.set_destruction(bindings,resources,freight):check(false,control.error);return null
	return control

func target(bindings: RefCounted,pose: Transform3D,player: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":pose,"ship_id":0,"active":true,"hull":int(player.snapshot().vitals.hull),"special_flight":false,"targeting_blocked":false,"alternate_position":null}

func verify_live(bindings: RefCounted,cat: RefCounted,lib: RefCounted,construction: RefCounted,equipment: RefCounted,resources: RefCounted,freight: RefCounted,pose: Transform3D,random: Dictionary) -> void:
	var control: RefCounted=configure_control(bindings,cat,construction,equipment,resources,freight)
	if control==null:return
	var player:=Player.new();var weapons:=Weapons.new();var radio:=Radio.new();var dialogue:=RadioResources.new();var attack:=Attack.new()
	if not player.configure_alioth_attack(bindings,cat,equipment,construction) or not weapons.configure_alioth_attack(bindings,cat,construction) or not lib.select_language("gb") or not dialogue.prepare(lib,bindings,null,16) or not radio.configure(bindings,lib,dialogue.line_counts,16) or not attack.configure(bindings):check(false,player.error+weapons.error+lib.error+dialogue.error+radio.error+attack.error);return
	var initial: Dictionary=control.snapshot()
	for id in range(3,10):check(initial.guidance[id].maximum_hull==initial.combat.actors[id].max_hull and initial.guidance[id].previous_hull==initial.combat.actors[id].factory_hull,"Scripted hull changes overwrote the factory's boost sample")
	var now:=0;var hits:=0;var fired:=0;var dead_at:={};var phases:={0:0};var retired_hulls:={}
	while now<240000:
		now+=100
		var combat: RefCounted=control.combat_owner()
		if not combat.begin_contact_pass(random,true):check(false,combat.error);return
		var contacts:=weapons.evaluate_combat_training_update(player,pose,combat,false,100)
		if contacts.is_empty():check(false,weapons.error);return
		if attack.snapshot().phase>=Attack.Stage.ESCAPE_VIEW:
			for event in contacts.actors:
				if event.actor_id in [3,4,5,6] and (not event.npc_contacts.is_empty() or not event.contacts.is_empty()):check(false,"Escaping Void projectiles retained collision targets");return
		weapons=contacts.weapons;player=contacts.player;combat=contacts.combat
		for event in contacts.actors:hits+=event.npc_contacts.size()
		var step: Dictionary=control.evaluate(combat,weapons,100,target(bindings,pose,player),combat.contact_random_state())
		if step.is_empty():check(false,control.error);return
		control=step.controller;weapons=step.weapons;random=step.random_state
		for event in step.actors:
			if not event.firing.is_empty() and event.firing.actors[0].outcome.fired:fired+=1
		combat=control.combat_owner()
		for id in 3:
			if not dead_at.has(id) and combat.snapshot().actors[id].vitals.hull==0:dead_at[id]=now
		radio.step_alioth_attack(now,combat.alioth_actor_context())
		if not radio.error.is_empty():check(false,radio.error);return
		var previous_attack: RefCounted=attack.fork_for_frame()
		if not attack.advance(100,radio.snapshot(),combat.alioth_actor_context(),pose,Transform3D(Basis.IDENTITY,Vector3(0,0,210000)),random):check(false,attack.error);return
		var cue: Dictionary=attack.snapshot()
		var retained: Dictionary=control.snapshot();var retained_weapons: Dictionary=weapons.snapshot()
		if not cue.frame.actor_overrides.is_empty():
			verify_dying_escape(bindings,control,weapons,previous_attack,radio.snapshot(),player,pose,0)
			verify_dying_escape(bindings,control,weapons,previous_attack,radio.snapshot(),player,pose,6000)
		var applied: Dictionary=control.evaluate_alioth_sequence(attack,weapons)
		if applied.is_empty():check(false,control.error);return
		if not phases.has(cue.phase):phases[cue.phase]=now
		if not cue.frame.actor_overrides.is_empty():
			check(control.snapshot()==retained and weapons.snapshot()==retained_weapons,"Prospective escape mutated retained owners")
			for row in cue.frame.actor_overrides:
				var id: int=row.actor_id;var after: Dictionary=applied.controller.snapshot()
				check(after.combat.actors[id].body_pose==row.body_pose and after.combat.actors[id].pose==retained.combat.actors[id].pose,"Escape changed the wrong transform or moved collision statistics early")
				check(after.guidance[id].route.waypoints==row.route_points and after.guidance[id].alioth_targets_cleared and applied.weapons.snapshot().target_memberships[id].is_empty(),"Escape did not replace the route and clear gun targets")
				check(applied.weapons.snapshot().actors[id].projectiles==retained_weapons.actors[id].projectiles and after.guidance[id].boost_elapsed_ms==retained.guidance[id].boost_elapsed_ms,"Escape reset live projectile or boost state")
		if not cue.frame.retire_actor_ids.is_empty():
			for id in cue.frame.retire_actor_ids:
				var after: Dictionary=applied.controller.snapshot().combat.actors[id]
				retired_hulls[id]=retained.combat.actors[id].vitals.hull
				check(after.vitals==retained.combat.actors[id].vitals and not after.active and after.actor_mode==4 and not after.model_draw_enabled,"Escape retirement changed hulls or kept a Void ship active")
			check(applied.controller.snapshot().accounting==retained.accounting,"Escape retirement awarded combat credit")
		control=applied.controller;weapons=applied.weapons;random=applied.random_state
		if cue.phase==Attack.Stage.RETURN_FLIGHT:break
	var state: Dictionary=control.snapshot()
	check(dead_at.size()==3 and hits>0 and fired>0,"Actual Alioth NPC shots did not destroy all three freighters: "+str(dead_at))
	check(state.accounting.events.filter(func(event):return event.actor_id<3).size()==3,"Freighter death was lost or counted twice")
	check(state.accounting.counter_deltas.player_kills==0 and state.accounting.counter_deltas.pirate_kills==0 and state.combat.current_reputation==Reputation.initial(bindings),"NPC battle granted unearned player credit or reputation")
	check(state.combat.actors.slice(0,3).all(func(actor):return actor.nonplayer_kill and actor.body_pose==initial.combat.actors[actor.actor_id].body_pose),"Freighter cruise or lethal attribution changed")
	check(state.defeat_status.is_empty(),"Alioth invented contract completion")
	check(state.flight[3].root_pose!=initial.flight[3].root_pose,"Void ships did not fly")
	check(radio.snapshot().started[2],"Actual exhausted hulls did not trigger the source radio condition")
	check(attack.snapshot().completion_ready and phases.size()==7 and retired_hulls.size()==4,"Unassisted battle did not run the full escape sequence")
	check(control.evaluate_alioth_sequence(attack,weapons).is_empty() and control.snapshot()==state,"A repeated escape frame changed combat")
	check(state.combat.actors.slice(3,7).all(func(actor):return actor.alioth_script_retired and actor.vitals.hull==retired_hulls[actor.actor_id]),"Retired Void hulls changed after leaving")
	var before: Dictionary=control.snapshot()
	check(control.advance(751 if not bindings.fast_forward.is_empty() else 151,target(bindings,pose,player),null,random).is_empty() and control.snapshot()==before,"Overlong frame partially advanced Alioth")
	var wrong: RefCounted=control.combat_owner();wrong._identity.campaign_cursor=14
	check(control.advance(0,target(bindings,pose,player),wrong,random).is_empty() and control.snapshot()==before,"Foreign combat partially advanced Alioth")
	print("Alioth unassisted battle/escape: ",now,"ms; ",fired," shots; ",hits," NPC contacts; freighter lethal clocks ",dead_at,"; phases ",phases,"; player hull ",player.snapshot().vitals.hull)

func verify_dying_escape(bindings: RefCounted,retained: RefCounted,weapons: RefCounted,sequence: RefCounted,radio: Dictionary,player: RefCounted,pose: Transform3D,age: int) -> void:
	# Separate, explicit lethal fixtures cover a Void ship already tumbling or
	# shedding cargo when the story relocates it. They do not alter the live run.
	var control: RefCounted=retained.fork_for_frame();var attack: RefCounted=sequence.fork_for_frame()
	var combat: RefCounted=control.combat_owner();var random: Dictionary=control.snapshot().random_state
	if not combat.begin_contact_pass(random,true) or combat.normal_hit(3,combat.snapshot().actors[3].vitals.hull,false).is_empty() or control.advance(0,target(bindings,pose,player),combat,combat.contact_random_state()).is_empty():check(false,combat.error+control.error);return
	for ms in range(0,age,100):
		if control.advance(100,target(bindings,pose,player)).is_empty():check(false,control.error);return
	var before: Dictionary=control.snapshot();var death: Dictionary=before.destruction[3]
	check(death.phase==("tumble" if age==0 else "explosion"),"Explicit pre-escape death fixture did not reach its requested phase")
	if not attack.advance(100,radio,control.combat_owner().alioth_actor_context(),pose,Transform3D(Basis.IDENTITY,Vector3(0,0,210000)),before.random_state):check(false,attack.error);return
	var result: Dictionary=control.evaluate_alioth_sequence(attack,weapons)
	if result.is_empty():check(false,control.error);return
	control=result.controller;var next: Dictionary=control.snapshot()
	check(next.destruction[3].phase==death.phase and next.destruction[3].cargo==death.cargo and next.destruction[3].effect==death.effect and next.destruction[3].countdown_ms==death.countdown_ms,"Escape restarted an existing death or moved separated cargo/effects")
	check(next.accounting==before.accounting and next.combat.actors[3].vitals.hull==0,"Escape healed a dying ship or counted it twice")
	if control.advance(0,target(bindings,pose,player)).is_empty():check(false,control.error);return
	var flags:=radio.duplicate(true);flags.started[3]=true;flags.finished[3]=true
	if not attack.advance(0,flags,control.combat_owner().alioth_actor_context(),pose,Transform3D(Basis.IDENTITY,Vector3(0,0,210000)),control.snapshot().random_state):check(false,attack.error);return
	result=control.evaluate_alioth_sequence(attack,result.weapons)
	if result.is_empty():check(false,control.error);return
	control=result.controller;next=control.snapshot()
	if control.advance(100,target(bindings,pose,player)).is_empty():check(false,control.error);return
	check(control.snapshot().destruction[3]==next.destruction[3] and control.snapshot().accounting==next.accounting,"Script retirement continued breakup or duplicated death credit")

func verify_lethal_accounting(bindings: RefCounted,cat: RefCounted,construction: RefCounted,equipment: RefCounted,resources: RefCounted,freight: RefCounted,pose: Transform3D,random: Dictionary) -> void:
	var control: RefCounted=configure_control(bindings,cat,construction,equipment,resources,freight)
	if control==null:return
	var player:=Player.new()
	if not player.configure_alioth_attack(bindings,cat,equipment,construction):check(false,player.error);return
	var combat: RefCounted=control.combat_owner()
	if not combat.begin_contact_pass(random,true):check(false,combat.error);return
	# Separate explicit lethal fixtures exercise both families' full breakup,
	# zero-frame death, source faction standing, and once-only kill ownership.
	for id in [0,3,7]:
		if not combat.refresh_hostility(id) or combat.normal_hit(id,combat.snapshot().actors[id].vitals.hull,false).is_empty():check(false,combat.error);return
	check(combat.current_reputation()=={"axes":[20,0],"override":-1},"Terran kills or Void no-standing rule changed")
	var first: Dictionary=control.advance(0,target(bindings,pose,player),combat,combat.contact_random_state())
	if first.is_empty():check(false,control.error);return
	for ms in range(0,15000,100):
		if control.advance(100,target(bindings,pose,player)).is_empty():check(false,control.error);return
	var state: Dictionary=control.snapshot()
	check(state.destruction[0].phase=="wreck" and state.destruction[0].material_id==33354,"Terran freighter did not finish the original breakup/wreck")
	check(state.accounting.events.size()==3 and state.accounting.counter_deltas.player_kills==1 and state.accounting.counter_deltas.pirate_kills==0,"Void kill accounting duplicated or counted as a pirate")
	check(state.destruction[3].cargo.model_id==16916 and state.destruction[7].cargo.model_id==16992,"Small-ship death changed original cargo models")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
