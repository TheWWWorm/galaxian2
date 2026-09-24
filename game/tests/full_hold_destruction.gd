extends SceneTree
## Mac cargo-bearing death components with synthetic lethal hits. Collection,
## mission placement and complete second-trip application playback remain separate.
const Fixtures=preload("res://tests/full_hold_control.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/full_hold_destruction_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Death=preload("res://src/simulation/npc_destruction.gd")
const Accounting=preload("res://src/simulation/npc_death_accounting.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Guns=preload("res://src/simulation/opening_npc_weapons.gd")
const NpcControl=preload("res://src/simulation/opening_npc_control.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Recovery=preload("res://src/simulation/tractor_recovery.gd")
const RecoveryRules=preload("res://src/content/tractor_recovery_definitions.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const SEED={"state":25214903913}
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Full-hold destruction: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","This check requires Mac content")
	var fixture:=Fixtures.new();var flight:=Construction.new();var resources:=Resources.new()
	if not flight.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000):check(false,flight.error);fixture.free();return
	if bindings.full_hold_destruction.is_empty():
		check(not resources.configure_full_hold(lib,bindings) and resources.snapshot().is_empty(),"Legacy pack invented cargo destruction resources")
		var control:=NpcControl.new();control.configure_full_hold(bindings,cat,flight,.5)
		check(not control.set_full_hold_destruction(resources),"Legacy pack accepted unverified cargo death")
		fixture.free();return
	if not resources.configure_full_hold(lib,bindings):check(false,resources.error);fixture.free();return
	var row: Dictionary=flight.snapshot().scenery.world_initialization.npc_construction.actors[0]
	check(row.cargo==[{"item_id":112,"quantity":1},{"item_id":118,"quantity":8}],"Retained reference cargo changed")
	check(resources.snapshot().cargo_model=={"model_id":16993,"resource":Definitions.VALUES.cargo_model_resource},"Cargo model has the wrong source mapping")
	verify_contract(args,lib,bindings)
	verify_lifecycle(bindings,resources,row)
	verify_failure(bindings,resources,row)
	for npc_credit in [false,true]:verify_controller(bindings,cat,flight,resources,fixture,npc_credit,lib)
	# This Unix-second fixture produces an empty cargo list through the real
	# field/route/actor generator, without editing the constructor's output.
	var empty_world:=Construction.new()
	if not empty_world.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100043):check(false,empty_world.error)
	else:
		check(empty_world.snapshot().scenery.world_initialization.npc_construction.actors[0].cargo.is_empty(),"Natural empty-cargo fixture changed")
		verify_controller(bindings,cat,empty_world,resources,fixture,false,lib)
	fixture.free()

func verify_contract(args: PackedStringArray, lib: RefCounted, bindings: RefCounted):
	var data: Dictionary=bindings.full_hold_destruction
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_control,bindings.opening_actors).is_empty(),"Valid cargo/death declaration rejected")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed cargo/death parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_control,bindings.opening_actors).is_empty(),"Shifted cargo/death proof accepted: "+key)
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-death-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","extent","control_absent","accounting_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_destruction")
			"wrong_type":changed.full_hold_destruction=false
			"changed":changed.full_hold_destruction.cleanup_after_ms=4500
			"extent":changed.full_hold_destruction.provenance.cargo_model.offset+=1
			"control_absent":changed.full_hold_control={}
			"accounting_absent":changed.opening_actors.npc_initialization.death_accounting={}
			"empty":changed.full_hold_destruction={};changed.full_hold_appearance={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(args[1],lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		check(accepted and reader.full_hold_destruction.is_empty() if scenario=="empty" else not accepted and reader.binding_id.is_empty() and reader.full_hold_destruction.is_empty(),"Cargo/death reader failure or stale data: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func broken_up(bindings: RefCounted, resources: RefCounted, row: Dictionary) -> RefCounted:
	var death:=Death.new();var initial:=row.duplicate(true);initial.body_pose=Transform3D.IDENTITY
	if not death.configure_full_hold(bindings,resources,initial):check(false,death.error);return null
	check(death.snapshot().retire_on_transfer,"The configured actor lost its original immediate-transfer retirement flag")
	var event: Dictionary=death.advance(0,SEED)
	if event.is_empty():check(false,death.error);return null
	check(event.state.countdown_ms==1862 and event.random_state.state==228198391288061 and event.sound_events==[20],"Independent initial death RNG/delay changed")
	check(not event.state.retire_on_transfer,"Entering tumble did not clear immediate-transfer retirement")
	var random: Dictionary=event.random_state
	for i in 18:death.advance(100,random)
	death.advance(62,random)
	check(death.snapshot().phase=="tumble" and death.snapshot().countdown_ms==0 and not death.snapshot().cargo.model_exists,"Death broke up at countdown equality")
	event=death.advance(1,random)
	if event.is_empty():check(false,death.error);return null
	check(event.breakup and event.random_state.state==22064196792072 and event.sound_events==[19] and event.state.drift_speed==50.04999923706055,"Independent breakup RNG or drift changed")
	return death

func verify_lifecycle(bindings: RefCounted, resources: RefCounted, row: Dictionary):
	var death:=broken_up(bindings,resources,row)
	if death==null:return
	var initial: Dictionary=death.snapshot();var random:={"state":22064196792072}
	check(initial.cargo.model_exists and initial.cargo.pose==Transform3D.IDENTITY and initial.statistics_pose==initial.cargo.pose and initial.pose.basis!=Basis.IDENTITY,"Container inherited the tumbling hull rotation")
	check(initial.cleanup_elapsed_ms==0 and initial.effect.elapsed_ms==0 and initial.cargo.entries==row.cargo,"Breakup consumed explosion time or changed generated cargo")
	var clone: RefCounted=death.fork_for_frame()
	var zero: Dictionary=clone.advance(0,random)
	check(zero.state.cargo==initial.cargo and zero.state.statistics_pose==initial.pose and zero.random_state==random,"Zero-time mode4 moved cargo or copied the wrong statistics pose")
	check(not zero.state.retire_on_transfer,"An active explosion armed immediate-transfer retirement")
	# Drift is per positive update: equal update counts, different elapsed time.
	var once: Dictionary=death.advance(1,random);var slower: Dictionary=clone.advance(150,random)
	check(once.state.cargo.pose.origin==Vector3(8.224495887756348,-40.37480163574219,-28.411897659301758) and once.state.drift_speed==49.04899978637695,"Independent first drift sample changed")
	check(once.state.cargo.pose==slower.state.cargo.pose and once.state.drift_speed==slower.state.drift_speed and once.state.cleanup_elapsed_ms!=slower.state.cleanup_elapsed_ms,"Cargo drift was incorrectly scaled by elapsed time")
	death=broken_up(bindings,resources,row)
	if death==null:return
	var expired_count:=0
	for step in 342:
		var before: Dictionary=death.snapshot();var event: Dictionary=death.advance(16,random)
		if event.is_empty():check(false,death.error);return
		if event.expired:expired_count+=1
		check(event.random_state==random and event.sound_events.is_empty() and event.state.cargo.entries==row.cargo and not event.retired_now,"Cargo update consumed RNG, replayed sound, lost cargo or retired early")
		check(event.state.cargo.pose.basis==Basis.IDENTITY and event.state.statistics_pose==event.state.cargo.pose and event.state.pose.origin==event.state.cargo.pose.origin,"Cargo rotation quantization or paired translation changed")
		if not before.effect.active:check(event.state.effect==before.effect,"Inactive explosion kept advancing or restarted")
	var end: Dictionary=death.snapshot()
	check(end.drift_speed==0 and end.cargo.pose.origin==Vector3(410.8144226074219,-2016.72607421875,-1419.17822265625) and expired_count==1,"Independent 342-update drift stop changed")
	check(not end.retire_on_transfer,"Positive cargo updates armed immediate-transfer retirement after effect expiry")
	var stopped: RefCounted=death.fork_for_frame();var stationary: Dictionary=stopped.advance(0,random)
	check(stationary.state.retire_on_transfer and stationary.state.phase=="explosion" and stationary.state.cargo.model_exists and not death.snapshot().retire_on_transfer,"A zero-time pass after effect expiry lost the retained transfer flag or changed its parent")
	stationary=stopped.advance(1,random)
	check(stationary.state.retire_on_transfer,"A later positive cargo update cleared the retained transfer flag")
	var frozen: Transform3D=end.cargo.pose
	while death.snapshot().cleanup_elapsed_ms<60000:
		var dt:=mini(150,60000-int(death.snapshot().cleanup_elapsed_ms))
		var event: Dictionary=death.advance(dt,random)
		if event.is_empty():check(false,death.error);return
	end=death.snapshot()
	check(end.phase=="explosion" and end.cleanup_elapsed_ms==60000 and end.cargo.model_exists and end.cargo.pose==frozen and not death.retires_before_update(),"Cargo lifetime lost strict 60000-ms equality")
	var last: Dictionary=death.advance(0,random)
	check(last.state.phase=="explosion" and last.state.cargo.model_exists,"Zero-time equality retired cargo")
	last=death.advance(1,random)
	check(last.retired_now and last.state.phase=="retired" and not last.state.cargo.model_exists and last.state.cleanup_elapsed_ms==0 and last.state.cargo.entries==row.cargo,"Expired cargo cleanup did not preserve the retained item record")
	var retired: Dictionary=death.snapshot();last=death.advance(150,random)
	check(last.state==retired and not last.retired_now and last.random_state==random,"Retired cargo continued updating")
	# Independent no-cargo branch: this remains an immediate following-pass exit.
	var empty:=row.duplicate(true);empty.cargo=[];death=broken_up(bindings,resources,empty)
	if death==null:return
	for i in 30:death.advance(150,random)
	check(death.snapshot().effect.active,"Explosion expired at exact duration equality")
	death.advance(1,random)
	check(death.snapshot().phase=="explosion" and death.retires_before_update() and not death.snapshot().cargo.model_exists,"Empty pirate gained a 60-second cargo lifetime")
	last=death.advance(0,random)
	check(last.retired_now and last.state.cleanup_elapsed_ms==4501,"Empty pirate failed its early retirement")
	# Isolate the second lifetime gate: elapsed cleanup alone cannot retire an
	# active explosion. Also cover an already-overdue following-pass early exit.
	death=broken_up(bindings,resources,row);death._state.cleanup_elapsed_ms=60000
	last=death.advance(1,random)
	check(last.state.phase=="explosion" and last.state.cargo.model_exists and not death.retires_before_update(),"Cleanup ignored its active-explosion gate")
	death._state.effect.active=false
	var overdue: Dictionary=death.snapshot();last=death.advance(150,random)
	check(last.retired_now and last.state.cleanup_elapsed_ms==overdue.cleanup_elapsed_ms and last.state.cargo==overdue.cargo and last.random_state==random,"Overdue early retirement ran late cargo movement/cleanup")
	# Isolated source cutoff boundary, keeping a real configured container.
	for speed in [0.05102040246129036,0.051020409911870956]:
		death=broken_up(bindings,resources,row);death._state.drift_speed=speed
		last=death.advance(1,random)
		check((last.state.drift_speed==0)==(speed<0.051020405),"Strict binary32 drift cutoff changed")

func verify_failure(bindings: RefCounted, resources: RefCounted, row: Dictionary):
	var death:=Death.new();var snapshot:=row.duplicate(true)
	for key in ["actor_id","actor_kind","hull_catalogue_id","subtype","cargo","fragments","body_pose"]:
		var bad:=row.duplicate(true);bad[key]=null
		check(not death.configure_full_hold(bindings,resources,bad) and death.snapshot().is_empty(),"Invalid cargo death row accepted: "+key)
	for entries in [[{"item_id":233,"quantity":1}],[{"item_id":1,"quantity":-1}],[{"item_id":true,"quantity":1}]]:
		var bad:=row.duplicate(true);bad.cargo=entries
		check(not death.configure_full_hold(bindings,resources,bad),"Invalid generated item accepted")
	check(death.configure_full_hold(bindings,resources,row),death.error)
	var before: Dictionary=death.snapshot()
	for dt in [-1,751 if not bindings.fast_forward.is_empty() else 151,true,null,0.5]:check(death.advance(dt,SEED).is_empty() and death.snapshot()==before,"Invalid death clock mutated cargo")
	check(death.advance(16,{"state":-1}).is_empty() and death.snapshot()==before,"Invalid random stream consumed cargo death")
	check(death.capture(Transform3D.IDENTITY,3e38),death.error);before=death.snapshot()
	check(death.advance(150,SEED).is_empty() and death.snapshot()==before,"Coordinate overflow partly initialized cargo death")
	death.clear();check(death.snapshot().is_empty() and death.fork_for_frame().snapshot().is_empty(),"Cargo death clear retained ownership")
	check(row==snapshot,"Preparing cargo death changed original constructor records")

func verify_controller(bindings: RefCounted, cat: RefCounted, flight: RefCounted, resources: RefCounted, fixture: SceneTree, npc_credit: bool,library: RefCounted):
	var control:=NpcControl.new();var combat:=Combat.new();var guns:=Guns.new();var hold:=Cargo.new()
	if not control.configure_full_hold(bindings,cat,flight,.5) or not combat.configure_full_hold(bindings,cat,flight,.5) or not guns.configure_full_hold(bindings,cat,flight) or not hold.configure_departure(bindings,cat,flight):check(false,control.error+combat.error+guns.error+hold.error);return
	var world: Dictionary=flight.snapshot();var cargo: Dictionary=hold.snapshot();var before: Dictionary=control.snapshot()
	var wrong:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":4,"actors":[]}
	for id in 3:wrong.actors.append({"actor_id":id,"cargo":[],"fragments":world.scenery.world_initialization.npc_construction.actors[0].fragments})
	check(not control.set_initial_destruction(resources,wrong) and control.snapshot()==before,"Opening-only API discarded the second pirate's retained cargo")
	check(not control.set_full_hold_destruction(Resources.new()) and control.snapshot()==before,"Missing cargo resources partly prepared destruction")
	if not control.set_full_hold_destruction(resources):check(false,control.error);return
	check(not control.set_full_hold_destruction(resources),"Second-trip controller replaced its retained cargo")
	var player: Dictionary=fixture.target(bindings,Fixtures.ORIGIN+Vector3(0,0,20000))
	var frame: Dictionary=control.evaluate(combat,guns,0,player,SEED)
	if frame.is_empty():check(false,control.error);return
	control=frame.controller;combat=frame.combat;guns=frame.weapons
	check(combat.normal_hit(0,50,npc_credit).destroyed_now,"Synthetic lethal hit failed")
	var dead: Dictionary=combat.snapshot();before=control.snapshot();var gun: Dictionary=guns.snapshot()
	var bad:=player.duplicate(true);bad.pose.origin.x=INF
	check(control.evaluate(combat,guns,16,bad,frame.random_state).is_empty() and control.snapshot()==before and combat.snapshot()==dead and guns.snapshot()==gun,"Failed lethal frame partly consumed owners or kill credit")
	frame=control.evaluate(combat,guns,16,player,frame.random_state)
	if frame.is_empty():check(false,control.error);return
	check(control.snapshot()==before and combat.snapshot()==dead and guns.snapshot()==gun,"Successful candidate mutated input owners")
	var event: Dictionary=frame.actors[0];var life: Dictionary=event.destruction.state
	check(event.destruction.started and event.firing.is_empty() and event.movement.is_empty() and frame.controller.snapshot().actors[0].flight.history==before.actors[0].flight.history,"Dying pirate advanced bank history or used living flight/firing")
	check(life.pose.origin==Fixtures.ORIGIN+Vector3(0,0,32) and life.statistics_pose.origin==Fixtures.ORIGIN and frame.combat.snapshot().actors[0].pose==life.statistics_pose,"Death lost its source pre-motion statistics or captured speed")
	var expected:={"hostile_remaining":-1,"hostile_deaths":1,"world_player_kills":0 if npc_credit else 1,"world_other_kills":1 if npc_credit else 0,"player_kills":0 if npc_credit else 1,"pirate_kills":0 if npc_credit else 1}
	check(event.death_accounting.counter_deltas==expected and event.death_accounting.nonplayer_kill==npc_credit,"Cargo pirate kill attribution changed")
	var damaged: RefCounted=frame.combat.fork_for_frame();damaged._actors[0]._state.body_pose.origin.x+=1
	check(frame.controller.evaluate(damaged,frame.weapons,16,player,frame.random_state).is_empty(),"Diverged hull transform was hidden by matching cargo statistics")
	var broken:=0;var expired:=0
	for tick in 450:
		control=frame.controller;combat=frame.combat;guns=frame.weapons
		frame=control.evaluate(combat,guns,150,player,frame.random_state)
		if frame.is_empty():check(false,"Repeated cargo death: "+control.error);return
		event=frame.actors[0];life=event.destruction.state
		if event.destruction.breakup:
			broken+=1
			if not npc_credit and life.cargo.eligible and RecoveryRules.available(bindings):verify_recovery(bindings,cat,library,flight,frame)
		if event.destruction.expired:expired+=1
		check(not event.has("death_accounting") and event.firing.is_empty() and event.movement.is_empty() and not frame.combat.collision_context(0).eligible,"Repeated pirate death fired, collided or granted another kill")
		if life.phase=="retired":break
	check(life.phase=="retired" and broken==1 and expired==1 and not frame.combat.snapshot().actors[0].active,"Cargo pirate did not finish its retained lifecycle")
	check(frame.controller.snapshot().death_accounting.counter_deltas==expected and frame.controller.snapshot().death_accounting.events.size()==1,"Repeated cargo death altered earned counters")
	control=frame.controller;combat=frame.combat;guns=frame.weapons;before=control.snapshot()
	frame=control.evaluate(combat,guns,150,player,frame.random_state)
	check(not frame.is_empty() and frame.controller.snapshot()==before and frame.actors[0].decision.is_empty(),"Retired pirate still selected targets or advanced timers")
	check(flight.snapshot()==world and hold.snapshot()==cargo,"Pirate death changed mission progress, construction or player cargo")

func verify_recovery(bindings: RefCounted,cat: RefCounted,library: RefCounted,flight: RefCounted,frame: Dictionary) -> void:
	var encounter:=Encounter.new()
	if not encounter.configure(bindings,cat,library,flight,0.5):check(false,encounter.error);return
	# Reuse the real generated actor's actual lethal/tumble/breakup path above.
	# The detached tractor/hold below are equipment component vectors, not an
	# earned fitting or a new career fixture. No input owner is rewritten.
	encounter._control=frame.controller;encounter._combat=frame.combat;encounter._weapons=frame.weapons
	verify_recovery_encounter(bindings,cat,encounter,0,flight.player_owner(),frame.random_state)

func verify_recovery_encounter(bindings: RefCounted,cat: RefCounted,encounter: RefCounted,id: int,player_owner: RefCounted,world_random: Dictionary) -> void:
	var original: Dictionary=encounter.snapshot()
	var life: Dictionary=encounter.npc_destruction_owner(id).snapshot()
	var actor: Dictionary=encounter.combat_snapshot().actors[id]
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,"equipment_ids":[68,81]}
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,life.cargo.pose.origin-Vector3(0,0,1300)),"autopilot":false}
	var observed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"actor_id":id,"actor_kind":actor.actor_kind,"actor_mode":4,"hull":0,"active":true,
		"cargo_eligible":true,"cargo_model_exists":true,"retire_on_transfer":life.retire_on_transfer,
		"body_pose":life.pose,"cargo_pose":life.cargo.pose,"cargo_entries":life.cargo.entries,
		"collision_centers":[],"friendly":actor.get("friendly",false),"statistics_exempt":false,"body_motion_blocked":false,
		"body_motion_detached":false,"special_cargo":false}
	var freighter: bool=actor.get("population_group","")=="freighter"
	if freighter:observed.freighter_position=encounter._control._flight[id].source_position()
	for used in [0,25]:
		var tractor:=Recovery.new();var hold:=Cargo.new()
		if not tractor.configure(bindings,cat,seed):check(false,tractor.error);return
		hold._state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
			"ship_id":0,"capacity":25,"used":used,"entries":[] if used==0 else [{"item_id":118,"quantity":used}]}
		hold._item_count=cat.tables.items.size();hold._recovery_cargo_ids=[116,117];hold._equipment_ids=[68,81]
		if not hold.bind_recovery(tractor) or not tractor.queue_acquired_wreck(observed):check(false,hold.error+tractor.error);return
		var source_hold: Dictionary=hold.snapshot();var source_tractor: Dictionary=tractor.snapshot()
		var started: Dictionary=encounter.evaluate_cargo_recovery(tractor,hold,0,player)
		if started.is_empty():check(false,encounter.error);return
		check(started.frame.phase=="started" and started.encounter.snapshot()==original and started.cargo.snapshot()==source_hold,"Recovery start moved or transferred the real wreck")
		if freighter and used==0:
			# Detached numerical vectors deliberately separate integer origin
			# from the visible body. None becomes a generated world or save.
			var vector: Dictionary=observed.duplicate(true)
			vector.freighter_position=Vector3i(17,-23,31)
			var numeric: RefCounted=started.tractor.fork_for_frame()
			if not numeric.advance(100,player,vector,source_hold):check(false,numeric.error);return
			var changes: Dictionary=numeric.snapshot().frame.actor_changes
			check(changes.body_pose.origin==Vector3(17,-23,-969) and changes.statistics_pose==changes.body_pose and changes.freighter_position==Vector3i(17,-23,-969),"Freighter pulling used the visible body's origin instead of retained integer coordinates")
			for invalid in [Vector3(17,-23,31),Vector3i(0,0,-2147483600),Vector3i(2147483647,0,0)]:
				vector.freighter_position=invalid
				numeric=started.tractor.fork_for_frame()
				var before: Dictionary=numeric.snapshot()
				check(not numeric.advance(100,player,vector,source_hold) and numeric.snapshot()==before,"Invalid freighter coordinates partly advanced the recovery frame")
		var pulled: Dictionary=started.encounter.evaluate_cargo_recovery(started.tractor,started.cargo,100,player)
		if pulled.is_empty():check(false,started.encounter.error);return
		var moved: Dictionary=pulled.encounter.npc_destruction_owner(id).snapshot();var body: Dictionary=pulled.encounter.combat_snapshot().actors[id]
		var expected_statistics: Transform3D=life.statistics_pose
		if freighter:
			expected_statistics=life.pose
			expected_statistics.origin=Vector3(observed.freighter_position)-Vector3(0,0,1000)
			check(moved.pose==expected_statistics and moved.wreck_shape_origin==life.wreck_shape_origin and pulled.encounter._control._flight[id].source_position()==Vector3i(expected_statistics.origin),"Freighter pulling lost its integer origin or moved independent wreck volumes")
		check(pulled.frame.phase=="pulling" and moved.cargo.pose.origin==life.cargo.pose.origin-Vector3(0,0,1000) and body.body_pose==moved.pose and body.pose==expected_statistics and moved.statistics_pose==expected_statistics,"Pulling confused physical cargo/body motion with the retained statistics transform")
		var blocked: RefCounted=pulled.encounter.fork_for_frame()
		blocked._combat=pulled.encounter._combat.fork_for_frame()
		blocked._combat._recovery_totals=blocked.recovery_totals();blocked._combat._recovery_totals.accepted_quantity=2147483647
		var blocked_before: Dictionary=blocked.snapshot()
		var prior: Dictionary=pulled.encounter.snapshot();var pending: Dictionary=pulled.tractor.snapshot()
		if used==0:
			check(blocked.evaluate_cargo_recovery(pulled.tractor,pulled.cargo,0,player).is_empty() and blocked.recovery_totals().accepted_quantity==2147483647 and blocked.snapshot()==blocked_before and pulled.tractor.snapshot()==pending and pulled.cargo.snapshot()==source_hold,"A rejected counter update partly published its cargo/wreck transaction")
		var picked: Dictionary=pulled.encounter.evaluate_cargo_recovery(pulled.tractor,pulled.cargo,0,player)
		if picked.is_empty():check(false,pulled.encounter.error);return
		var transferred: Dictionary=picked.encounter.npc_destruction_owner(id).snapshot()
		var first:=Recovery.first_positive(life.cargo.entries)
		var attempted:=maxi(1,mini(life.cargo.entries[first].quantity,25-used))
		var accepted:=attempted if used==0 else 0
		var remaining: Array=life.cargo.entries.duplicate(true);remaining[first].quantity-=attempted
		check(picked.frame.phase=="pickup" and picked.encounter.recovery_totals().accepted_quantity==accepted and picked.cargo.snapshot().used==used+accepted,"World progress counted rejected cargo or disagreed with the actual hold")
		if actor.actor_kind in [0,1,2,3]:
			var history: Array=picked.encounter.combat_snapshot().reputation.events
			check(history.size()==original.combat.reputation.events.size()+1 and history[-1].event_kind=="cargo_recovered" and history[-1].actor_id==id,"Capacity acceptance incorrectly gated or repeated the wreck's faction change")
		if actor.actor_kind==-1:
			check(picked.encounter.combat_snapshot().reputation==original.combat.reputation and picked.frame.events.all(func(event):return event.kind!="faction_cargo_taken"),"Debris collection borrowed the container model's faction")
			check(transferred.phase=="destroyed" and transferred.cargo.model_id==16990 and not transferred.active,"Debris collection changed its container or retained active cargo")
		check(picked.encounter.recovery_totals().friendly_cargo_taken==actor.get("friendly",false),"Capacity acceptance lost the source friendly-cargo flag")
		check(not transferred.cargo.eligible and not transferred.cargo.model_exists and transferred.cargo.entries==remaining and picked.encounter.combat_snapshot().actors[id].active==not life.retire_on_transfer,"Pickup lost the first-row subtraction, remaining cargo or retained death lifetime")
		check(encounter.snapshot()==original and tractor.snapshot()==source_tractor and hold.snapshot()==source_hold and pulled.encounter.snapshot()==prior and pulled.tractor.snapshot()==pending,"A successful recovery mutated a parent branch")
		var repeated: RefCounted=picked.tractor.fork_for_frame();check(repeated.queue_acquired_wreck(observed),repeated.error)
		check(picked.encounter.evaluate_cargo_recovery(repeated,picked.cargo,0,player).is_empty() and picked.encounter.recovery_totals().accepted_quantity==accepted,"A stale queued observation recovered the wreck's remaining rows again")
		var continued: Dictionary=picked.encounter.evaluate_world(player_owner,player.pose,0,world_random)
		if continued.is_empty():check(false,picked.encounter.error);return
		check(continued.encounter.recovery_totals().accepted_quantity==accepted and not continued.encounter.npc_destruction_owner(id).snapshot().cargo.eligible,"The following NPC phase lost the accepted quantity or recreated transferred cargo")
		if actor.actor_kind==-1:
			check(continued.random_state==world_random and continued.encounter.snapshot().controller.accounting==original.controller.accounting and not continued.encounter.combat_snapshot().actors[id].active,"Collected debris replayed a drop, destruction reward or activation in the next NPC phase")

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
