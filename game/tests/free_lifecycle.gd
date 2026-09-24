extends "res://tests/mixed_traffic_control.gd"
## Earned equipment prerequisite with explicit ordinary population inputs and
## lethal-contact fixtures. This does not create an earned campaign departure.
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const FreePopulation=preload("res://tests/free_population.gd")
const NPCSystems=preload("res://src/content/npc_systems_definitions.gd")
const SystemsActor=preload("res://src/simulation/opening_combat_actor.gd")
var observed_factions:={}
var verified_wrecks:={}

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Ordinary traffic lifecycle: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	if not FreeLife.available(bindings):
		if FreeLife.Traffic.available(bindings):
			var construction:=Construction.new()
			if not construction.configure_free_factory(bindings,cat,0,[81,86],FreePopulation.CONTEXT,2) or construction.generate({"state":98765}).is_empty():check(false,construction.error);return
			check(FreeLife.population(bindings,construction.snapshot()).is_empty(),"Earlier traffic declarations inferred an ordinary lifecycle")
			check(not FreightResources.new().configure_free(library,bindings,construction),"Earlier traffic declarations inferred faction wreck resources")
		return
	verify_standing(bindings)
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	if not Scenario.prepare_alioth_component(equipment,bindings,cat):check(false,equipment.error);return
	var inventory: Dictionary=equipment.snapshot()
	for vector in [[2,0,0.5],[22,0,0.5],[30,20,1.0]]:
		var context:=FreePopulation.CONTEXT.duplicate();context.rank=vector[1];context.difficulty=vector[2]
		var construction:=Construction.new()
		if not construction.configure_free_traffic(bindings,cat,equipment,context,vector[0]) or construction.generate({"state":98765}).is_empty():check(false,construction.error);return
		var packet: Dictionary=construction.snapshot()
		var resources:=SmallResources.new();var freight:=FreightResources.new()
		if not resources.configure_free(library,bindings,construction) or not freight.configure_free(library,bindings,construction):check(false,resources.error+freight.error);return
		var control:=Controller.new()
		if not control.configure_ambient(bindings,cat,construction,context.rank,context.difficulty,equipment,REPUTATION) or not control.set_destruction(bindings,resources,freight):check(false,control.error);return
		verify_ordinary_reactions(bindings,cat,equipment,construction)
		verify_ordinary_contacts(bindings,cat,equipment,construction)
		if NPCSystems.available(bindings):verify_ordinary_systems(bindings,cat,equipment,construction,control)
		verify_ordinary_control(bindings,cat,construction,control,freight)
		check(construction.snapshot()==packet and equipment.snapshot()==inventory,"Detached lifecycle changed construction or earned equipment")
		if failures:return
	for faction in [0,1,2,8]:check(observed_factions.has(faction),"Missing ordinary faction branch: "+str(faction))
	check(verified_wrecks.size()==2,"Missing Terran or Nivelian destruction resources")

func verify_standing(bindings: RefCounted) -> void:
	var rules: Dictionary=bindings.mido_travel.free_lifecycle.standing
	for faction in [0,1,2,3,8]:
		for value in [-100,-71,-70,0,70,71,100]:
			for axis in 2:
				var reputation:={"axes":[0,0],"override":-1};reputation.axes[axis]=value
				var expected:={"hostile":false,"friendly":false}
				if faction==8:expected.hostile=true
				elif axis==int(faction/2):
					var signed_value: int=value*(-1 if faction%2==0 else 1)
					expected.hostile=signed_value>70;expected.friendly=signed_value< -70
				check(FreeLife.standing(rules,faction,reputation,false)==expected,"Faction axis, sign or strict standing boundary changed")
				check(FreeLife.standing(rules,faction,reputation,true)=={"hostile":true,"friendly":false},"Forced hostility lost precedence")
	check(FreeLife.standing(rules,9,REPUTATION,false).is_empty() and FreeLife.standing(rules,0,{"axes":[0,0],"override":0},false).is_empty(),"Unsupported standing override was inferred")

func ordinary_group(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted,reputation: Dictionary=REPUTATION) -> RefCounted:
	var context: Dictionary=construction.snapshot().free_context
	var group:=fresh(bindings,cat,equipment,construction,context.rank,context.difficulty,reputation)
	if group==null:return null
	for id in group.snapshot().actors.size():
		if not group.refresh_hostility(id):check(false,group.error);return null
	return group

func verify_ordinary_reactions(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	var kinds:={}
	for actor in construction.snapshot().actors:
		if actor.population_group!="travel":kinds[actor.actor_kind]=actor.actor_id
	for faction in kinds:
		observed_factions[faction]=true
		var id: int=kinds[faction];var group:=ordinary_group(bindings,cat,equipment,construction)
		if group==null:return
		var before: Dictionary=group.snapshot();var hull: int=before.actors[id].max_hull
		var random:=Random.new();random.restore(group.contact_random_state())
		# Neutral source factions 0/1 warn and force only matching ships.
		# Nivelian traders and already-hostile pirates do not enter this branch.
		if faction in [0,1]:
			var threshold: int=int(floor(float(hull)*0.33))
			damage(group,id,threshold)
			check(not group.snapshot().provocation.warning_issued and group.contact_random_state()==random.snapshot(),"Warning crossed the wrong requested-damage boundary")
			var warning:=damage(group,id,1);var draw:=random.next_int(3)
			check(warning.reactions.size()==1 and warning.reactions[0].text_id==415+draw and warning.reactions[0].voice_event_id==645+draw,"Ordinary warning changed source radio or draw order")
			var half: int=int(hull/2)
			damage(group,id,half-threshold-1)
			check(not group.snapshot().provocation.forced_hostile[id],"Exact half hull forced retaliation")
			damage(group,id,1);check(group.refresh_hostility(id) and group.snapshot().actors[id].hostile,"Ordinary individual retaliation failed")
			var full_threshold: int=int(floor(float(hull)*0.66))
			damage(group,id,full_threshold-half-1)
			check(not group.snapshot().provocation.response_issued,"Faction response crossed its strict boundary")
			var response:=damage(group,id,1);draw=random.next_int(3)
			check(response.reactions.size()==1 and response.reactions[0].text_id==418+draw and response.reactions[0].voice_event_id==650+draw,"Ordinary response changed source radio")
			var reaction: Dictionary=group.snapshot().provocation
			check(reaction.station_response_flag==(faction==0) and group.contact_random_state()==random.snapshot(),"Secondary faction set the station response or consumed extra radio randomness")
			for actor in before.actors:check(reaction.forced_hostile[actor.actor_id]==(actor.actor_kind==faction),"Faction response forced an unrelated faction")
		else:
			damage(group,id,int(hull*0.75))
			check(group.snapshot().provocation==before.provocation and group.contact_random_state()==random.snapshot(),"Ineligible faction accumulated player provocation")
		var npc:=ordinary_group(bindings,cat,equipment,construction)
		if npc==null:return
		var initial: Dictionary=npc.snapshot()
		check(damage(npc,id,hull,true).destroyed_now and npc.current_reputation()==REPUTATION and npc.snapshot().provocation==initial.provocation,"NPC kill changed player standing or provocation")
		var player_group:=ordinary_group(bindings,cat,equipment,construction)
		if player_group==null:return
		check(damage(player_group,id,hull).destroyed_now,"Player lethal fixture failed")
		var expected:=REPUTATION.duplicate(true)
		if faction==0:expected.axes[0]-=5
		elif faction==1:expected.axes[0]+=5
		elif faction==2:expected.axes[1]-=5
		else:expected.axes[1]-=1
		check(player_group.current_reputation()==expected,"Ordinary kill changed the wrong reputation axis or scale")
		var retained: Dictionary=player_group.snapshot()
		check(not damage(player_group,id,1).accepted and player_group.snapshot()==retained,"Repeated lethal hit granted credit twice")
		var history:=Reputation.new();check(history.restore(bindings,retained.reputation) and history.snapshot()==retained.reputation,history.error)
		check(not history.record_lethal(retained.actors[id]),"Restored history credited the same death twice")

func verify_ordinary_control(bindings: RefCounted,cat: RefCounted,construction: RefCounted,control: RefCounted,freight: RefCounted) -> void:
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,"pose":Transform3D(Basis.IDENTITY,Vector3(2000000,0,0)),"active":true,"hull":95,"special_flight":false,"targeting_blocked":false,"alternate_position":null}
	var before: Dictionary=control.snapshot()
	for dt in [-1,751 if not bindings.fast_forward.is_empty() else 151,0.5,true]:check(control.advance(dt,player).is_empty() and control.snapshot()==before,"Invalid ordinary frame partially advanced control")
	check(control.evaluate_ambient_world_logic(0,control.combat_owner(),{"state":-1}).is_empty() and control.snapshot()==before,"Invalid ordinary world stream mutated control")
	var clock:=Launch.new()
	if not clock.configure(bindings,construction,10000,45000):check(false,clock.error);return
	var boundary:=clock.advance(0,before.combat)
	check(not boundary.checked and not boundary.patrol_checked,"Ordinary traffic relaunched at an exact clock boundary")
	boundary=clock.advance(1,before.combat)
	check(boundary.checked and boundary.patrol_checked and boundary.elapsed_ms==0 and boundary.patrol_elapsed_ms==0,"Ordinary traffic did not reset strict periodic clocks")
	var elapsed:=0
	while elapsed<10050:
		control=step(control,150,player)
		if control==null:return
		elapsed+=150
	var live: Dictionary=control.snapshot();var ids:=[];var recycle:=[];var hostile:=[]
	for actor in live.combat.actors:
		check(actor.active and actor.vitals.hull==actor.max_hull,"Ordinary traffic did not enter its alive state")
		ids.append(actor.actor_id)
		if actor.population_group in ["patrol","travel"]:recycle.append(actor.actor_id)
		elif actor.population_group=="hostile":hostile.append(actor.actor_id)
		if actor.population_group=="travel":check(actor.spawn_generation==1 and actor.travel_cycle==1,"Ordinary travel launch lost its instance")
	var weapons:=Weapons.new();var context: Dictionary=construction.snapshot().free_context
	if not weapons.configure_ambient(bindings,cat,construction,context.rank,context.difficulty):check(false,weapons.error);return
	var controlled: Dictionary=control.evaluate(control.combat_owner(),weapons,100,player,live.random_state)
	check(not controlled.is_empty() and control.snapshot()==live,"Ordinary weapon/control frame failed or mutated its retained owner: "+control.error)
	verify_ordinary_fire(control,weapons,player)
	var credited:={}
	for actor in live.combat.actors:
		if actor.actor_kind not in [2,8] or credited.has(actor.actor_kind):continue
		credited[actor.actor_kind]=true
		var killed: RefCounted=step(control,0,player,[actor.actor_id],false)
		if killed==null:return
		var state: Dictionary=killed.snapshot();var pirate: bool=actor.actor_kind==8
		check(state.accounting.events.size()==1 and state.accounting.counter_deltas.player_kills==(1 if pirate else 0) and state.accounting.counter_deltas.pirate_kills==(1 if pirate else 0),"Player death accounting confused a pirate with a neutral Nivelian trader")
		check(state.combat.current_reputation.axes==[30,-7 if pirate else -11],"Player death accounting changed the source faction standing")
	if NPCSystems.available(bindings):
		var disabled: RefCounted=control.combat_owner()
		if not disabled.begin_contact_pass(control.snapshot().random_state,true):check(false,disabled.error);return
		for id in ids:
			var pools: Dictionary=disabled.actor_snapshot(id).systems
			check(disabled.systems_hit(id,1).get("accepted",false),disabled.error)
			check(disabled.systems_hit(id,pools.capacity,true).get("accepted",false),disabled.error)
		if control.advance(0,player,disabled).is_empty():check(false,control.error);return
	control=step(control,0,player,ids,true)
	if control==null:return
	var dead: Dictionary=control.snapshot()
	check(dead.accounting.events.size()==ids.size() and dead.combat.reputation.events.size()==ids.size(),"Ordinary deaths lost accounting")
	check(dead.combat.current_reputation==REPUTATION and dead.accounting.counter_deltas.player_kills==0 and dead.accounting.counter_deltas.pirate_kills==0,"NPC kills granted player credit")
	check(dead.combat.provocation.requested_damage.all(func(value):return value==0),"NPC kills created player crime")
	for actor in dead.combat.actors:
		if actor.population_group=="freighter" and not verified_wrecks.has(actor.actor_kind):
			verify_ordinary_wreck(bindings,freight,control.destruction_owner(actor.actor_id),dead.random_state)
			verified_wrecks[actor.actor_kind]=true
	var killed_again:=[]
	while elapsed<95000:
		control=step(control,150,player)
		if control==null:return
		elapsed+=150
		for id in last_relaunches:check(id in recycle,"Augmenta recycled a hostile ship or freighter")
		var state: Dictionary=control.snapshot();var kill_now:=[]
		for id in recycle:
			var actor: Dictionary=state.combat.actors[id]
			if actor.spawn_generation>live.combat.actors[id].spawn_generation and actor.active and actor.vitals.hull>0 and id not in killed_again:
				check(state.destruction[id].phase=="ready" and state.destruction[id].cargo.entries==state.cargo[id] and not state.destruction[id].cargo.model_exists,"Relaunch retained an old wreck or lost sampled cargo")
				check(actor.vitals.hull==actor.max_hull and state.guidance[id].spawn_generation==actor.spawn_generation and state.accounting.spawn_generations[id]==actor.spawn_generation,"Relaunch split actor, guidance and accounting instances")
				check(state.combat.provocation.requested_damage[id]==0,"Relaunch retained requested damage")
				if NPCSystems.available(bindings):
					check(actor.systems.integrity==actor.systems.capacity and not actor.systems.disabled and not actor.systems_disabled,"Recycled traffic retained EMP damage or disable state")
					check(state.combat.provocation.systems_requested_damage[id]==0,"Recycled traffic retained requested systems damage")
					var recycled: RefCounted=control.combat_owner()
					if not recycled.begin_contact_pass(state.random_state,true):check(false,recycled.error);return
					var hit: Dictionary=recycled.systems_hit(id,actor.systems.capacity)
					var systems_history:=Reputation.new()
					check(hit.get("disabled_now",false) and systems_history.restore(bindings,recycled.snapshot().reputation),"A new traffic instance could not retain EMP reputation after an earlier death: "+systems_history.error)
					var stale: Dictionary=recycled.actor_snapshot(id);stale.spawn_generation-=1
					check(not systems_history.record_systems_depletion(stale,hit),"Recycled systems history accepted an earlier traffic generation")
				var history:=Reputation.new();check(history.restore(bindings,state.combat.reputation),history.error)
				check(not history.record_lethal(dead.combat.actors[id]),"Recycled history accepted a stale death")
				kill_now.append(id);killed_again.append(id)
		if not kill_now.is_empty():
			control=step(control,0,player,kill_now,false)
			if control==null:return
	var final: Dictionary=control.snapshot()
	check(killed_again.size()==recycle.size(),"A supported ordinary patrol/travel actor failed to recycle")
	check(final.accounting.events.size()==ids.size()+recycle.size() and final.combat.reputation.events.size()==ids.size()+recycle.size(),"Recycling duplicated or erased lethal history")
	check(final.combat.current_reputation.axes==[30-5*recycle.size(),-6],"Relaunched Terran kills changed the source standing delta")
	check(final.accounting.events.slice(0,ids.size())==dead.accounting.events and final.combat.reputation.events.slice(0,ids.size())==dead.combat.reputation.events,"Recycling rewrote earlier deaths")
	for id in hostile:check(final.combat.actors[id].spawn_generation==live.combat.actors[id].spawn_generation and final.combat.actors[id].vitals.hull==0 and not final.combat.actors[id].active,"Augmenta security3 incorrectly respawned its hostile tail")
	for actor in final.combat.actors:
		if actor.population_group=="freighter":check(not actor.active and final.destruction[actor.actor_id].phase=="wreck","Freighter did not retain and clean up its wreck")
	check(final.defeat_status.is_empty(),"Ordinary traffic granted a story or contract completion")

func verify_ordinary_systems(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted,control: RefCounted) -> void:
	# Direct damage is a detached component fixture. Paid launch, detonation and
	# save retention are covered by secondary_fitting_application.
	var context: Dictionary=construction.snapshot().free_context
	var kinds:={};var active:=[]
	for actor in control.snapshot().combat.actors:
		var freight: bool=actor.population_group=="freighter"
		var capacity: int=(40 if context.rank==0 else 140)*(3 if freight else 1)
		check(actor.systems.capacity==capacity and actor.systems.integrity==capacity and actor.systems.recovery_ms==(45000 if freight else 15000),"Ordinary systems lost rank, subtype or difficulty-independent capacity")
		if actor.active:kinds[actor.actor_kind]=actor.actor_id;active.append(actor.actor_id)
	for faction in kinds:
		var id: int=kinds[faction];var group:=ordinary_group(bindings,cat,equipment,construction)
		if group==null:return
		var actor: Dictionary=group.actor_snapshot(id)
		var third: int=int(actor.systems.capacity/3)
		var partial: Dictionary=group.systems_hit(id,third)
		check(partial.get("accepted",false) and group.actor_snapshot(id).vitals==actor.vitals and group.advance_systems(id,150) and group.actor_snapshot(id).systems.integrity==actor.systems.capacity-third,"Partial EMP damage changed combat pools or recovered spontaneously")
		check(not group.snapshot().provocation.warning_issued,"EMP warned at the exact one-third boundary")
		var edge: Dictionary=group.systems_hit(id,1)
		check(not edge.is_empty() and group.snapshot().provocation.warning_issued==(faction==0),"EMP warning ignored the system's primary faction or strict boundary")
		var hit: Dictionary=group.systems_hit(id,group.actor_snapshot(id).systems.integrity)
		check(hit.get("disabled_now",false) and hit.first_disable_by_player and group.actor_snapshot(id).vitals==actor.vitals,"EMP depletion changed hull or lost first-disable attribution")
		var disabled: Dictionary=group.snapshot();var expected:=REPUTATION.duplicate(true)
		if faction==0:expected.axes[0]-=2
		elif faction==1:expected.axes[0]+=2
		elif faction==2:expected.axes[1]-=2
		check(group.current_reputation()==expected and not disabled.provocation.response_issued and not disabled.provocation.station_response_flag,"EMP depletion changed the wrong faction axis or requested a station response")
		for other in disabled.actors:check(other.script_hostile==(faction==0 and other.actor_kind==0),"EMP faction response changed unrelated ships or lost persistent hostility")
		check(not group.systems_hit(id,1).get("accepted",true) and group.snapshot()==disabled,"Empty systems accepted another penalty")
		check(group.advance_systems(id,1000),group.error)
		var repeated: Dictionary=group.systems_hit(id,group.actor_snapshot(id).systems.integrity)
		check(repeated.get("accepted",false) and not repeated.disabled_now and not repeated.first_disable_by_player and group.snapshot().reputation.events.size()==2,"Repeated depletion during recovery lost its separate reputation event")
		var history:=Reputation.new();var retained: Dictionary=group.snapshot().reputation
		check(history.restore(bindings,retained) and history.snapshot()==retained,history.error)
		check(not history.record_systems_depletion(group.actor_snapshot(id),repeated),"Systems reputation credited the same hit twice")
		var npc:=ordinary_group(bindings,cat,equipment,construction)
		if npc==null:return
		var previous: Dictionary=npc.snapshot()
		check(npc.systems_hit(id,actor.systems.capacity,true).get("disabled_now",false) and npc.current_reputation()==REPUTATION and npc.snapshot().provocation==previous.provocation,"NPC EMP damage created player crime or reputation")
		var detached: Dictionary=npc.snapshot()
		for invalid in [-1,0.5,true]:check(npc.systems_hit(id,invalid).is_empty() and npc.snapshot()==detached,"Invalid EMP damage partially mutated ordinary combat")
	# A direct actor frame covers the strict recovery boundary; the controller
	# below checks ordering with an ordinary bounded duration.
	for row in construction.snapshot().actors:
		if row.population_group not in ["patrol","freighter"]:continue
		var actor:=SystemsActor.new()
		if not actor.configure_ambient(bindings,cat,construction,row.actor_id,context.rank,context.difficulty) or not actor.enable_local_combat():check(false,actor.error);return
		var initial: Dictionary=actor.snapshot()
		check(actor.systems_hit(initial.systems.capacity).get("disabled_now",false),actor.error)
		check(actor.advance_systems(initial.systems.recovery_ms) and actor.snapshot().systems.disabled and actor.snapshot().systems.integrity==initial.systems.capacity,"Ordinary systems recovered before the strict integer boundary")
		if row.population_group=="freighter":check(actor.snapshot().systems_motion_ms==0.0 and not actor.snapshot().systems_disabled,"Freighter EMP movement timer inherited strict integrity recovery")
		check(actor.advance_systems(400) and not actor.snapshot().systems.disabled,"Ordinary systems failed to recover after full capacity")
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,"pose":Transform3D(Basis.IDENTITY,Vector3(2000000,0,0)),"active":true,"hull":95,"special_flight":false,"targeting_blocked":false,"alternate_position":null}
	var staged: RefCounted=control.fork_for_frame();var damage_owner: RefCounted=staged.combat_owner()
	if not damage_owner.begin_contact_pass(staged.snapshot().random_state,true):check(false,damage_owner.error);return
	for id in active:check(damage_owner.systems_hit(id,damage_owner.actor_snapshot(id).systems.capacity,true).get("accepted",false),damage_owner.error)
	var before: Dictionary=staged.snapshot()
	if staged.advance(150,player,damage_owner).is_empty():check(false,staged.error);return
	for id in active:
		var actor: Dictionary=staged.snapshot().combat.actors[id]
		check(actor.body_pose==before.combat.actors[id].body_pose and actor.pose==before.combat.actors[id].pose and actor.systems_disabled,"Ordinary actor movement advanced during EMP disable")
	check(control.snapshot()==before,"Staged EMP controller changed its retained parent")
	var resumed: RefCounted=control.fork_for_frame();var boundary: RefCounted=resumed.combat_owner();var freighters:=[]
	if not boundary.begin_contact_pass(before.random_state,true):check(false,boundary.error);return
	for actor in before.combat.actors:
		if actor.population_group!="freighter":continue
		freighters.append(actor.actor_id)
		check(boundary.systems_hit(actor.actor_id,actor.systems.capacity,true).get("disabled_now",false) and boundary.advance_systems(actor.actor_id,45000),boundary.error)
	if resumed.advance(1,player,boundary).is_empty():check(false,resumed.error);return
	for id in freighters:
		var actor: Dictionary=resumed.snapshot().combat.actors[id]
		check(actor.systems.disabled and not actor.systems_disabled and actor.body_pose.origin==before.combat.actors[id].body_pose.origin+Vector3(0,0,1),"Freighter cruise waited for strict integrity recovery after its separate timer expired")

func verify_ordinary_wreck(bindings: RefCounted,resources: RefCounted,death: RefCounted,random: Dictionary) -> void:
	var initial: Dictionary=death.snapshot();var faction: int=initial.actor_kind
	var pack: RefCounted=resources.faction_owner(faction)
	if pack==null:check(false,"Missing original freighter faction resources");return
	var assets: Dictionary=pack.snapshot()
	check(assets.model.model_id==(18302 if faction==0 else 18301) and assets.initial_material.id==(34708 if faction==0 else 34704) and assets.wreck_material.id==(33354 if faction==0 else 33353),"Freighter used another faction's breakup or wreck art")
	check(initial.phase=="animation" and initial.model_scale==1.0 and not initial.world_movement_enabled,"Ordinary freighter skipped breakup entry or retained cruise")
	check(initial.cargo.model_id==(16992 if faction==0 else 16993),"Freighter salvage changed faction models")
	observe_ordinary_death(pack,death,"entry")
	var saw_middle:=false
	while death.snapshot().phase=="animation":
		var event: Dictionary=death.advance(100,random)
		if event.is_empty():check(false,death.error);return
		random=event.random_state
		var state: Dictionary=death.snapshot()
		if not saw_middle and state.phase=="animation" and state.animation.time_ms>=(initial.animation.start_ms+initial.animation.end_ms)/2:
			observe_ordinary_death(pack,death,"middle");saw_middle=true
	observe_ordinary_death(pack,death,"animation-end")
	check(death.snapshot().wreck_elapsed_ms==0 and death.snapshot().material_id==initial.material_id,"Animation remainder advanced the wreck clock")
	for ms in [140,1]:
		var event: Dictionary=death.advance(ms,random)
		if event.is_empty():check(false,death.error);return
		random=event.random_state
		check(death.snapshot().material_id==(initial.material_id if ms==140 else assets.wreck_material.id),"Wreck material changed at the wrong boundary")
		observe_ordinary_death(pack,death,"wreck-boundary" if ms==140 else "wreck-material")
	while death.snapshot().cleanup_elapsed_ms<60000:
		var event: Dictionary=death.advance(mini(150,60000-death.snapshot().cleanup_elapsed_ms),random)
		if event.is_empty():check(false,death.error);return
		random=event.random_state
	check(death.snapshot().active,"Wreck cleanup violated its strict time boundary")
	var final: Dictionary=death.advance(1,random)
	check(not final.is_empty() and not death.snapshot().active and death.snapshot().phase=="wreck","Wreck did not clean up after 60 seconds")
	observe_ordinary_death(pack,death,"cleanup")
	var before: Dictionary=death.snapshot()
	check(death.advance(-1,random).is_empty() and death.snapshot()==before,"Invalid duration changed a retained ordinary wreck")

func observe_ordinary_death(_resources: RefCounted,_death: RefCounted,_label: String) -> void:
	pass

func verify_ordinary_contacts(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	var context: Dictionary=construction.snapshot().free_context
	var weapons:=Weapons.new();var group:=ordinary_group(bindings,cat,equipment,construction)
	if group==null:return
	if not weapons.configure_ambient(bindings,cat,construction,context.rank,context.difficulty):check(false,weapons.error);return
	var guns:={};var targets:={}
	for row in weapons.snapshot().actors:
		if not row.projectiles.is_empty():guns[construction.snapshot().actors[row.actor_id].actor_kind]=row.projectiles.weapon
	for actor in group.snapshot().actors:
		if actor.active:targets[actor.actor_kind]=actor.actor_id
	for weapon in guns.values():
		for id in targets.values():
			var collision: Dictionary=group.collision_context(id)
			var point: Vector3=collision.center
			if collision.path=="point_geometry":point+=collision.boxes[0].offset
			var projectiles:=shot(weapon,point)
			if projectiles==null:return
			var before: Dictionary=group.snapshot();var bullets: Dictionary=projectiles.snapshot()
			var contacts:=Contacts.new();var result:=contacts.evaluate(projectiles,group,[id])
			if result.is_empty():check(false,contacts.error);return
			check(result.contacts.size()==1 and result.contacts[0].damage.accepted,"A source faction gun missed its explicit ordinary contact fixture")
			check(result.combat.snapshot().actors[id].vitals.hull==before.actors[id].vitals.hull-int(weapon.ordinary_hit_policy.nonplayer_damage),"NPC contact applied the wrong faction damage")
			check(result.combat.snapshot().provocation==before.provocation and result.combat.current_reputation()==REPUTATION,"NPC contact created player crime")
			check(group.snapshot()==before and projectiles.snapshot()==bullets,"Prospective faction contact mutated retained combat or projectiles")
	var wrong: Dictionary=guns.values()[0].duplicate(true);wrong.damage+=1
	check(not group.supports_weapon_hit(wrong),"Undeclared ordinary faction damage was accepted")

func verify_ordinary_fire(control: RefCounted,weapons: RefCounted,player: Dictionary) -> void:
	var group: RefCounted=control.combat_owner();var random: Dictionary=control.snapshot().random_state
	if not group.begin_contact_pass(random,true) or group.normal_hit(0,int(group.snapshot().actors[0].max_hull/2)+1,false).is_empty():check(false,group.error);return
	random=group.contact_random_state()
	var staged: RefCounted=control.fork_for_frame();var guns: RefCounted=weapons.fork_for_frame();var target:=player.duplicate(true);var fired:=false
	for iteration in 12:
		var pose: Transform3D=group.snapshot().actors[0].body_pose
		target.pose=Transform3D(Basis.IDENTITY,pose.origin+pose.basis.z*2000.0)
		if guns.advance(150).is_empty():check(false,guns.error);return
		var result: Dictionary=staged.evaluate(group,guns,150,target,random)
		if result.is_empty():check(false,staged.error);return
		staged=result.controller;guns=result.weapons;group=result.combat;random=result.random_state
		for slot in guns.snapshot().actors[0].projectiles.slots:
			if slot!=null and slot.remaining_ms>0:fired=true
		if fired:break
	check(fired,"Provoked Terran patrol never fired through ordinary guidance/control")
