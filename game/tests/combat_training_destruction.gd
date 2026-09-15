extends "res://tests/combat_training_weapons.gd"
## Earned application equipment followed by detached combat/death fixtures.
## Large direct hits isolate finite hull, attribution and lifecycle boundaries.
const TrainingDeathRules=preload("res://src/content/combat_training_destruction_definitions.gd")
const TrainingDeathResources=preload("res://src/content/npc_destruction_resources.gd")
const TrainingDeathOwner=preload("res://src/simulation/npc_destruction.gd")
const TrainingDeathCounters=preload("res://src/simulation/npc_death_accounting.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:await verify(args)
	if is_instance_valid(host):host.free()
	print("Combat-training destruction: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_second_return(args: PackedStringArray):
	await super.after_second_return(args)
	var before: Dictionary=host.session.snapshot()
	var equipment: RefCounted=host.session._world.equipment_owner()
	verify_training_destruction(args,equipment)
	check_training_station_retained(before,"destruction")

func verify_training_destruction(args: PackedStringArray, equipment: RefCounted):
	var cat:=Catalogues.new()
	if not cat.open(lib):check(false,cat.error);return
	var resources:=TrainingDeathResources.new()
	var rules: Dictionary=bindings.combat_training_destruction
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if header.reader=="resource-registration-v120":check(TrainingDeathRules.parameters(rules),"Current Mac pack omitted training death")
	if not TrainingDeathRules.parameters(rules):
		check(not resources.configure_combat_training(lib,bindings),"Older pack invented training cargo resources")
		check(not TrainingDeathCounters.new().configure_combat_training(bindings),"Older pack invented training death counters")
		return
	check(TrainingDeathRules.validate(rules,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.combat_training_control,bindings.combat_training_weapons,bindings.opening_actors).is_empty(),"Training death rejected its source context")
	for key in TrainingDeathRules.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not TrainingDeathRules.parameters(bad),"Changed training death declaration accepted: "+key)
	for key in TrainingDeathRules.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not TrainingDeathRules.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.combat_training_control,bindings.combat_training_weapons,bindings.opening_actors).is_empty(),"Disconnected training death proof accepted: "+key)
	check(resources.configure_combat_training(lib,bindings),resources.error)
	if resources.snapshot().is_empty():return
	check(resources.snapshot().cargo_models.map(func(row):return row.model_id)==[16993,16993,16993,16990],"Gunant inherited the pirate container")
	var world:=TrainingWorld.new()
	check(world.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),{"companions_empty":true,"location_match":false,"special_placement":false}),world.error)
	check(not world.generate({"state":int(TRAINING_GOLDEN[0].input_state)}).is_empty(),world.error)
	var world_before:=world.snapshot()
	verify_training_cargo_motion(world,resources)
	verify_training_death_pass(cat,world,resources)
	verify_initial_gunant_death(cat,world,resources)
	verify_training_projectile_death(cat,world,resources,equipment)
	check(world.snapshot()==world_before,"Detached destruction changed construction or station progress")

func training_death_seed(world: RefCounted, id: int) -> Dictionary:
	var row: Dictionary=world.snapshot().npc_construction.actors[id].duplicate(true)
	row.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":7})
	return row

func verify_training_cargo_motion(world: RefCounted, resources: RefCounted):
	for id in [0,3]:
		var row:=training_death_seed(world,id)
		var owner:=TrainingDeathOwner.new()
		check(owner.configure_combat_training(bindings,resources,row),owner.error)
		if owner.snapshot().is_empty():continue
		check(owner.snapshot().cargo.entries==row.cargo and owner.snapshot().fragments==row.fragments,"Death regenerated cargo or fragments")
		# A disclosed cargo fixture checks both source-selected container types;
		# the live controller below separately preserves the actual generated list.
		row.cargo=[{"item_id":0,"quantity":1}]
		check(owner.configure_combat_training(bindings,resources,row),owner.error)
		check(owner.capture(Transform3D(Basis.IDENTITY,Vector3(100,200,300)),2.0,Basis(Vector3.FORWARD,.25)),owner.error)
		var state:=owner.advance(0,training_seed(4))
		check(not state.is_empty(),owner.error)
		if state.is_empty():continue
		check(state.started and state.state.countdown_ms==1862 and state.random_state.state==228198391288061 and state.sound_events==[20],"Training death changed source tumble draws")
		var rng: Dictionary=state.random_state
		for i in 12:state=owner.advance(150,rng)
		state=owner.advance(62,rng)
		check(state.state.phase=="tumble" and state.state.countdown_ms==0 and not state.state.cargo.model_exists,"Death broke up at countdown equality")
		var preceding: Transform3D=state.state.pose
		state=owner.advance(1,rng)
		check(state.breakup and state.state.phase=="explosion" and state.state.mode==4 and state.random_state.state==22064196792072 and state.sound_events==[19],"Breakup changed its source draws or mode")
		check(state.state.cargo.model_exists and state.state.cargo.pose.basis==Basis.IDENTITY and state.state.cargo.pose.origin==preceding.origin+Vector3(0,0,2),"Container did not use identity axes and post-tumble position")
		check(state.state.effect.position==preceding.origin,"Explosion shifted to post-tumble container position")
		var cargo_pose: Transform3D=state.state.cargo.pose
		var next:=owner.advance(1,state.random_state)
		check((next.state.cargo.pose.origin-cargo_pose.origin).distance_to(Vector3(8.2244958878,-40.3748016357,-28.4118976593))<.001,"Cargo drift lost per-update source precision")
		check(next.state.drift_speed==49.04899978637695 and next.state.statistics_pose==next.state.cargo.pose and next.state.cargo.rotation_radians==Vector3.ZERO,"Cargo statistics, drag or truncated rotation changed")
		var paused:=owner.advance(0,next.random_state)
		check(paused.state.cargo.pose==next.state.cargo.pose and paused.state.statistics_pose==paused.state.pose*Transform3D(paused.state.bank_basis,Vector3.ZERO),"Zero-delta cargo moved or retained the later statistics copy")
		var before:=owner.snapshot()
		check(owner.advance(151,paused.random_state).is_empty() and owner.snapshot()==before,"Oversized cargo frame committed motion")
		var clone: RefCounted=owner.fork_for_frame()
		clone._state.cleanup_elapsed_ms=60000;clone._state.effect.active=false
		var cleanup: Dictionary=clone.advance(1,paused.random_state)
		check(cleanup.retired_now and cleanup.state.phase=="retired" and not cleanup.state.cargo.model_exists and cleanup.state.cleanup_elapsed_ms==0,"Positive late cleanup lost its delete/reset boundary")
		clone=owner.fork_for_frame();clone._state.cleanup_elapsed_ms=60001;clone._state.effect.active=false
		var early: Dictionary=clone.advance(0,paused.random_state)
		check(early.retired_now and early.state.cargo.model_exists and early.state.cleanup_elapsed_ms==60001 and early.random_state==paused.random_state,"Early retirement deleted cargo or consumed draws")

func verify_training_death_pass(cat: RefCounted, world: RefCounted, resources: RefCounted):
	var live:=LiveTraining.new()
	check(live.configure(bindings,cat,world,0,.5),live.error)
	check(live.set_destruction(bindings,resources),live.error)
	var player:=training_player(Vector3(10000,7000,160000))
	check(not live.advance(0,player).is_empty(),live.error)
	if live.snapshot().is_empty():return
	check(not live.set_destruction(bindings,resources),"Live training replaced its death resources")
	var before:=live.snapshot()
	var combat: RefCounted=live.combat_owner()
	for id in 4:check(not combat.normal_hit(id,int(combat.snapshot().actors[id].vitals.hull),id%2==1).is_empty(),combat.error)
	var incoming: Dictionary=combat.snapshot()
	if incoming.has("reputation"):
		check(combat.reputation_after({"axes":[30,-3],"override":-1})=={"axes":[30,-5],"override":-1},"Mixed lethal hits lost retained reputation or awarded NPC kill credit")
	var rng:=training_seed(4)
	var event:=live.advance(0,player,combat,rng)
	check(not event.is_empty(),live.error)
	if event.is_empty():return
	check(combat.snapshot()==incoming and before.random_state!=rng,"Death mutated incoming combat or ignored shared RNG fixture")
	check(event.death_events.size()==4 and event.firing_requests.is_empty() and event.defeat_status.defeated==0,"Lethal hull completed training or fired weapons")
	check(event.random_state.state==75387640520761 and event.death_events.map(func(row):return row.state.countdown_ms)==[1862,1767,1962,2552],"Four deaths did not consume the shared RNG in actor order")
	var counters: Dictionary=live.snapshot().accounting.counter_deltas
	check(counters=={"hostile_remaining":-3,"hostile_deaths":3,"world_player_kills":2,"world_other_kills":1,"player_kills":2,"pirate_kills":2,"nonhostile_remaining":-1},"Mixed player/NPC attribution or Gunant counter path changed")
	for id in 4:
		var death: Dictionary=live.snapshot().destruction[id]
		check(death.cargo.entries==world.snapshot().npc_construction.actors[id].cargo and death.mode==3,"Controller lost generated cargo or entered the wrong death phase")
		check(not live.snapshot().combat.actors[id].engine_draw_enabled,"Dying actor kept engine drawing")
		# Cross the refresh threshold on the next update. Dead modes must keep
		# selection untouched while their independent timers continue ticking.
		live._guidance[id]._state.selection_elapsed_ms=5000
	var selection: Dictionary=live.snapshot()
	event=live.advance(1,player)
	check(not event.is_empty(),live.error)
	if event.is_empty():return
	check(event.random_state==selection.random_state and live.snapshot().accounting==selection.accounting,"Continued death consumed selection draws or counted a second kill")
	for id in 4:
		check(live.snapshot().guidance[id].selection_elapsed_ms==5001 and live.snapshot().guidance[id].target_index==selection.guidance[id].target_index,"Dead actor refreshed target selection")
	before=live.snapshot()
	var bad: RefCounted=live.combat_owner();bad._actors[3]._state.body_pose.origin.x+=1
	check(live.advance(1,player,bad).is_empty() and live.snapshot()==before,"Late pose mismatch leaked earlier death motion or RNG")
	for delta in [-1,true,.5,151]:check(live.advance(delta,player).is_empty() and live.snapshot()==before,"Invalid death frame changed retained owners")
	check(live.advance(1,player,null,{"state":-1}).is_empty() and live.snapshot()==before,"Invalid shared RNG changed the controller")
	for i in 22:
		event=live.advance(150,player)
		if event.is_empty():check(false,live.error);return
	check(live.defeat_status()=={"kind":18,"defeated":3,"required":3,"satisfied":true},"Three exploded pirates failed condition18")
	check(live.snapshot().destruction.all(func(row):return row.phase=="explosion"),"Condition18 waited for cargo cleanup")
	var accounted: Dictionary=live.snapshot().accounting
	for i in 34:
		event=live.advance(150,player)
		if event.is_empty():check(false,live.error);return
	check(live.snapshot().accounting==accounted and live.defeat_status().satisfied,"Effect expiry recounted kills or cleared pirate defeat")
	if incoming.has("reputation"):check(live.snapshot().combat.reputation==incoming.reputation,"Death animation or effect expiry repeated a lethal reputation change")
	var original:=live.snapshot();var fork: RefCounted=live.fork_for_frame()
	check(not fork.advance(1,player).is_empty() and live.snapshot()==original,"Forked destruction changed accepted state")

func verify_initial_gunant_death(cat: RefCounted, world: RefCounted, resources: RefCounted):
	var live:=LiveTraining.new();check(live.configure(bindings,cat,world,0,.5),live.error)
	check(live.set_destruction(bindings,resources),live.error)
	var combat: RefCounted=live.combat_owner()
	check(not combat.normal_hit(3,9999999,false).is_empty(),combat.error)
	if combat.snapshot().has("reputation"):
		check(combat.reputation_after({"axes":[30,-3],"override":-1})=={"axes":[30,2],"override":-1},"Gunant's friendly flag incorrectly suppressed a player lethal reputation change")
	var event:=live.advance(0,training_player(Vector3.ZERO),combat)
	check(not event.is_empty(),live.error)
	if event.is_empty():return
	check(event.death_events.size()==1 and event.death_events[0].state.actor_id==3 and event.death_events[0].state.mode==3,"Gunant's initial mode ignored lethal hull")
	check(live.snapshot().accounting.counter_deltas.nonhostile_remaining==-1 and live.snapshot().accounting.counter_deltas.player_kills==0 and not live.defeat_status().satisfied,"Gunant awarded pirate credit or completed the mission")
	# First lethal selection still reaches the patrol fallback before the hull
	# guard. Continuing mode3 must skip it, even at the next waypoint.
	var guidance: RefCounted=live._guidance[3].get_script().new()
	check(guidance.configure_combat_training(bindings,cat,world,3,0,.5),guidance.error)
	var root:=Transform3D(Basis.IDENTITY,Vector3(-4000,-3000,80000))
	check(combat.set_pose(3,root,root),combat.error)
	var actor: Dictionary=combat.snapshot().actors[3]
	var absent:=training_player(Vector3(0,0,1000000));absent.active=false;absent.hull=0
	var decision: Dictionary=guidance.update(0,actor,root,absent,training_seed(4),combat.snapshot().actors)
	check(not decision.is_empty(),guidance.error)
	if decision.is_empty():return
	check(decision.dying and guidance.snapshot().route.index==1 and guidance.snapshot().desired_position==Vector3(10000,7000,160000),"First lethal pass skipped source route advancement")
	root.origin=Vector3(10000,7000,160000);actor.pose=root;actor.actor_mode=3
	decision=guidance.update(0,actor,root,absent,decision.random_state,combat.snapshot().actors)
	check(not decision.is_empty() and guidance.snapshot().route.index==1,"Continued tumble advanced the patrol")

func verify_training_projectile_death(cat: RefCounted, world: RefCounted, resources: RefCounted, equipment: RefCounted):
	var live:=LiveTraining.new();check(live.configure(bindings,cat,world,0,.5),live.error)
	check(live.set_destruction(bindings,resources),live.error)
	var target:=training_player(Vector3(10000,7000,160000))
	check(not live.advance(0,target).is_empty(),live.error)
	var combat: RefCounted=live.combat_owner()
	check(not combat.normal_hit(0,46,false).is_empty(),combat.error)
	var player:=TrainingPlayer.new();check(player.configure_combat_training(bindings,cat,equipment),player.error)
	var mounts:=TrainingMounts.new();check(mounts.open(lib,cat),mounts.error)
	var gun:=TrainingPrimary.new();check(gun.configure(bindings,cat,mounts,player.loadout()),gun.error)
	check(not gun.advance(1).is_empty(),gun.error)
	var mount: Vector3=gun.snapshot().guns[0].mount.position
	# Position the test player's muzzle at the retained pirate body. The live
	# NPC pose remains untouched, so contact can feed the same controller.
	var pose:=Transform3D(Basis.IDENTITY,combat.snapshot().actors[0].pose.origin-mount-Vector3(0,0,100))
	var fired:=gun.fire(pose,true,training_seed(1))
	check(not fired.is_empty(),gun.error)
	if fired.is_empty():return
	var hit:=gun.evaluate_npc_update(combat,[0,1,2,3],0)
	check(not hit.is_empty(),gun.error)
	if hit.is_empty():return
	check(hit.combat.snapshot().actors[0].vitals.hull==0 and not hit.combat.snapshot().actors[0].nonplayer_kill,"Equipped primary did not pass lethal attribution to combat")
	var event:=live.advance(0,target,hit.combat,fired.random_state)
	check(not event.is_empty(),live.error)
	if event.is_empty():return
	check(event.death_events.size()==1 and event.death_events[0].state.actor_id==0 and live.snapshot().accounting.counter_deltas.pirate_kills==1,"Projectile contact failed to enter controller-owned destruction")
	check(event.random_state.state==93651525288237 and event.death_events[0].state.countdown_ms==2313,"Primary spread and death restarted or reordered the shared RNG")
