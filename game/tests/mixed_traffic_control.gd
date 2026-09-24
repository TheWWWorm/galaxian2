extends "res://tests/mido_ambient_combat.gd"
## Earned equipment and original generated traffic, with explicit distant player,
## lethal-damage fixtures and native world/actor passes. Weapon contacts and the
## application departure are not supplied by this component check.
const Controller=preload("res://src/simulation/combat_training_control.gd")
const SmallResources=preload("res://src/content/npc_destruction_resources.gd")
const FreightResources=preload("res://src/content/freighter_destruction_resources.gd")
const Launch=preload("res://src/simulation/traffic_launch_clock.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
var small_resources: RefCounted
var freight_resources: RefCounted
var populations:=0
var second_lives:=0
var freighters:=0
var last_relaunches:=[]
var firing_cases:=0
var outbound_deaths:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	if small_resources!=null and not failures:check(populations==7 and second_lives==15 and freighters==15 and firing_cases==6 and outbound_deaths==3,"Generated vectors did not exercise all mixed traffic and recycled small ships")
	print("Mixed traffic control: %d checks; %d failures; %d populations; %d second lives; %d freighters; %d firing cases; %d outbound deaths"%[checks,failures,populations,second_lives,freighters,firing_cases,outbound_deaths])
	quit(1 if failures else 0)

func verify_population(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	if failures:return
	if not bindings.ambient_lifecycle.has("recycling"):
		check(not Controller.new().configure_ambient(bindings,catalogues,construction,0,0.5,equipment,REPUTATION),"Earlier pack invented complete traffic recycling");return
	if small_resources==null:
		var library:=Library.new()
		if not library.open(OS.get_cmdline_user_args()[0]):check(false,library.error);return
		small_resources=SmallResources.new();freight_resources=FreightResources.new()
		if not small_resources.configure_ambient(library,bindings) or not freight_resources.configure(library,bindings):check(false,small_resources.error+freight_resources.error);return
	var control:=Controller.new()
	if not control.configure_ambient(bindings,catalogues,construction,0,0.5,equipment,REPUTATION):check(false,control.error);return
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,
		"pose":Transform3D(Basis.IDENTITY,Vector3(2000000,0,0)),"active":true,"hull":95,
		"special_flight":false,"targeting_blocked":false,"alternate_position":null}
	var built: Dictionary=construction.snapshot();var inventory: Dictionary=equipment.snapshot()
	var before: Dictionary=control.snapshot()
	check(control.advance(0,player).is_empty() and control.snapshot()==before,"Mixed traffic ran without both destruction paths")
	check(control.set_destruction(bindings,small_resources,freight_resources),control.error)
	if failures:return
	populations+=1
	before=control.snapshot()
	for dt in [-1,751 if not bindings.fast_forward.is_empty() else 151,0.5,true]:
		check(control.evaluate_ambient_world_logic(dt,control.combat_owner(),before.random_state).is_empty() and control.snapshot()==before,"Invalid world duration mutated traffic")
		check(control.advance(dt,player).is_empty() and control.snapshot()==before,"Invalid actor duration mutated traffic")
	check(control.evaluate_ambient_world_logic(0,control.combat_owner(),{"state":-1}).is_empty() and control.snapshot()==before,"Invalid world RNG partly launched traffic")
	var clock:=Launch.new()
	check(clock.configure(bindings,construction,10000,45000),clock.error)
	var boundary:=clock.advance(0,control.combat_owner().snapshot())
	check(not boundary.checked and not boundary.patrol_checked,"A traffic clock launched at the strict boundary")
	boundary=clock.advance(1,control.combat_owner().snapshot())
	check(boundary.checked and boundary.patrol_checked and boundary.elapsed_ms==0 and boundary.patrol_elapsed_ms==0,"Periodic traffic checks failed to reset both clocks")
	var elapsed:=0
	while elapsed<10050:
		control=step(control,150,player)
		if control==null:return
		elapsed+=150
	var live: Dictionary=control.snapshot();var ids:=[];var small:=[];var freight:=[]
	for actor in live.combat.actors:
		check(actor.active and actor.vitals.hull>0,"A generated actor was not alive after its original launch check")
		ids.append(actor.actor_id)
		if actor.population_group=="freighter":freight.append(actor.actor_id)
		else:small.append(actor.actor_id)
		if actor.population_group=="travel":check(actor.spawn_generation==1 and actor.travel_cycle==1,"Initial travel launch lost its instance")
	freighters+=freight.size()
	verify_weapons(bindings,catalogues,construction,control,player,small,freight)
	for actor in live.combat.actors:
		if actor.population_group=="travel":verify_outbound_death(control,player,actor.actor_id)
	if failures:return
	if not freight.is_empty():
		var lethal_step:=step(control,17,player,freight,true)
		if lethal_step==null:return
		for id in freight:
			check(lethal_step.snapshot().destruction[id].pose.origin==live.combat.actors[id].body_pose.origin+Vector3(0,0,17),"Freighter death skipped its final ordinary cruise before the hull test")
		check(control.snapshot()==live,"A prospective lethal frame moved committed freighters")
	var initial_generations: Array=live.accounting.spawn_generations.duplicate()
	var unhit: RefCounted=control.combat_owner()
	# First destruction is attributed to another ship. Later destruction after
	# each real relaunch belongs to the player; both histories must survive.
	control=step(control,0,player,ids,true)
	if control==null:return
	var first: Dictionary=control.snapshot()
	check(first.accounting.events.size()==ids.size() and first.combat.reputation.events.size()==ids.size(),"Initial deaths lost per-actor accounting")
	check(first.combat.current_reputation==REPUTATION,"Nonplayer deaths changed player reputation")
	var first_actors: Array=first.combat.actors.duplicate(true)
	var killed_again:=[]
	var saw_multiple_patrols:=false
	while elapsed<110000:
		control=step(control,150,player)
		if control==null:return
		elapsed+=150
		var patrol_launches:=0
		for id in last_relaunches:
			check(id not in freight,"A freighter was incorrectly recycled")
			if built.actors[id].population_group=="patrol":patrol_launches+=1
		if patrol_launches>1:saw_multiple_patrols=true
		var current: Dictionary=control.snapshot();var kill_now:=[]
		for id in small:
			var actor: Dictionary=current.combat.actors[id]
			if actor.spawn_generation>initial_generations[id] and actor.active and actor.vitals.hull>0 and id not in killed_again:
				check(current.destruction[id].phase=="ready" and not current.destruction[id].cargo.model_exists and current.destruction[id].cargo.entries==current.cargo[id],"Relaunch kept old salvage or lost newly sampled cargo")
				check(actor.vitals.hull==actor.max_hull and current.combat.provocation.requested_damage[id]==0,"Recycled traffic retained damage")
				check(current.guidance[id].spawn_generation==actor.spawn_generation and current.accounting.spawn_generations[id]==actor.spawn_generation,"Relaunch split the guidance/accounting instance")
				var history:=Reputation.new()
				check(history.restore(bindings,current.combat.reputation),history.error)
				var history_before:=history.snapshot()
				check(not history.record_lethal(first_actors[id]) and history.snapshot()==history_before,"An earlier instance received duplicate lethal credit")
				var stale: Dictionary=control.evaluate_ambient_world_logic(0,unhit,current.random_state)
				check(stale.is_empty(),"World logic accepted combat from a preceding traffic generation")
				kill_now.append(id);killed_again.append(id);second_lives+=1
		if not kill_now.is_empty():
			control=step(control,0,player,kill_now,false)
			if control==null:return
		current=control.snapshot()
		if killed_again.size()==small.size() and freight.all(func(id):return not current.combat.actors[id].active):break
	var final: Dictionary=control.snapshot()
	check(killed_again.size()==small.size(),"A destroyed small ship never relaunched")
	check(final.accounting.events.size()==ids.size()+small.size() and final.combat.reputation.events.size()==ids.size()+small.size(),"Recycling erased deaths or counted one destruction twice")
	check(final.accounting.events.slice(0,ids.size())==first.accounting.events and final.combat.reputation.events.slice(0,ids.size())==first.combat.reputation.events,"Later lives overwrote earlier history")
	check(final.combat.current_reputation.axes==[30,-6+5*small.size()],"Repeated player kills failed to retain the source faction changes")
	for id in freight:
		check(final.combat.actors[id].spawn_generation==0 and not final.combat.actors[id].active and final.destruction[id].phase=="wreck","The original freighter wreck was recycled or discarded")
	if int(built.population.groups.patrol)>1:check(saw_multiple_patrols,"The patrol check relaunched only one eligible ordinary actor")
	var history:=Reputation.new()
	check(history.restore(bindings,final.combat.reputation) and history.snapshot()==final.combat.reputation,history.error)
	if not small.is_empty():
		var corrupt: Dictionary=final.combat.reputation.duplicate(true)
		corrupt.events[-1].spawn_generation=2147483647
		check(not history.restore(bindings,corrupt) and history.snapshot()==final.combat.reputation,"Malformed retained generation replaced valid reputation")
	check(equipment.snapshot()==inventory and construction.snapshot()==built,"Traffic granted player cargo or changed earned inventory/construction")

func verify_weapons(bindings: RefCounted,catalogues: RefCounted,construction: RefCounted,control: RefCounted,player: Dictionary,small: Array,freight: Array) -> void:
	var weapons:=Weapons.new()
	if not weapons.configure_ambient(bindings,catalogues,construction,0,0.5):check(false,weapons.error);return
	var armed:=weapons.snapshot()
	for id in freight:
		check(armed.actors[id].projectiles.is_empty(),"A freighter acquired a small-ship gun")
		check(weapons.fire_combat_training(control.combat_owner(),[{"actor_id":id,"target_actor_id":-1,"pose":control.snapshot().combat.actors[id].pose}]).is_empty() and weapons.snapshot()==armed,"An unarmed freighter fired or mutated another gun")
	for id in small:
		var gun: Dictionary=armed.actors[id].projectiles
		check(gun.weapon.campaign_cursor==11 and gun.weapon.item_id==25 and gun.weapon.damage==3 and gun.weapon.projectile_capacity==4 and gun.weapon.nonplayer_source,"Small traffic lost its verified ordinary gun")
	if small.is_empty():
		var result: Dictionary=control.evaluate(control.combat_owner(),weapons,0,player,control.snapshot().random_state)
		check(not result.is_empty() and result.weapons.snapshot()==armed,control.error)
		return
	var id: int=small[0];var group: RefCounted=control.combat_owner()
	check(group.begin_contact_pass(control.snapshot().random_state,true),group.error)
	var hit: Dictionary=group.normal_hit(id,int(group.snapshot().actors[id].max_hull/2)+1,false)
	check(not hit.is_empty() and hit.accepted and not hit.destroyed_now,"Provocation firing fixture failed")
	var next: RefCounted=control.fork_for_frame();var random: Dictionary=group.contact_random_state()
	var target:=player.duplicate(true);var fired:=false
	for iteration in 12:
		var root: Transform3D=group.snapshot().actors[id].body_pose
		target.pose=Transform3D(Basis.IDENTITY,root.origin+root.basis.z*2000.0)
		check(not weapons.advance(150).is_empty(),weapons.error)
		var operation: Dictionary=next.evaluate(group,weapons,150,target,random)
		if operation.is_empty():check(false,next.error);return
		next=operation.controller;group=operation.combat;weapons=operation.weapons;random=operation.random_state
		for slot in weapons.snapshot().actors[id].projectiles.slots:
			if slot!=null and slot.remaining_ms>0:fired=true
		if fired:break
	check(fired,"Provoked traffic never fired through shared guidance and weapon control")
	if fired:firing_cases+=1

func verify_outbound_death(control: RefCounted,player: Dictionary,id: int) -> void:
	var next: RefCounted=control.fork_for_frame()
	for i in 160:
		next=step(next,150,player)
		if next==null:return
		if next.snapshot().combat.actors[id].actor_mode==6:break
	var outbound: Dictionary=next.snapshot().combat.actors[id]
	check(outbound.actor_mode==6 and outbound.pose!=outbound.body_pose,"Generated travel never exercised the departing collision-pose lag")
	if failures:return
	next=step(next,0,player,[id],true)
	if next==null:return
	var dead: Dictionary=next.snapshot()
	check(dead.combat.actors[id].actor_mode==3 and dead.destruction[id].phase=="tumble" and dead.destruction[id].pose==outbound.body_pose,"Lethal outbound traffic skipped tumble or used its stale statistics pose")
	check(dead.accounting.events.size()==1 and dead.accounting.events[0].spawn_generation==outbound.spawn_generation,"Outbound death was lost or credited to another launch")
	outbound_deaths+=1

func step(control: RefCounted,dt: int,player: Dictionary,damage_ids: Array=[],nonplayer:=false) -> RefCounted:
	var before: Dictionary=control.snapshot()
	var logic: Dictionary=control.evaluate_ambient_world_logic(dt,control.combat_owner(),before.random_state)
	if logic.is_empty():check(false,control.error);return null
	var next: RefCounted=logic.controller;var group: RefCounted=logic.combat;var random: Dictionary=logic.random_state
	last_relaunches=logic.relaunches.duplicate()
	if not damage_ids.is_empty():
		if not group.begin_contact_pass(random,true):check(false,group.error);return null
		for id in damage_ids:
			var hit: Dictionary=group.normal_hit(id,int(group.snapshot().actors[id].max_hull),nonplayer)
			if hit.is_empty() or not hit.destroyed_now:check(false,"Lethal fixture failed: "+group.error);return null
		random=group.contact_random_state()
	var operation: Dictionary=next.advance(dt,player,group,random)
	if operation.is_empty():check(false,next.error);return null
	if control.snapshot()!=before:check(false,"A staged traffic frame mutated committed control");return null
	return next
