extends SceneTree
const Frame = preload("res://src/simulation/opening_world_frame.gd")
const Timeline = preload("res://src/simulation/opening_detail_timeline.gd")
const Scenery = preload("res://src/simulation/opening_scenery.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Hostility = preload("res://src/content/npc_hostility_definitions.gd")
const DeathResources = preload("res://src/content/npc_destruction_resources.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3):verify_source(args[i],args[i+1])
	print("Opening world frame checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var scene := Scenery.new();check(scene.configure(bindings,catalogues,1789100000),scene.error)
	var owner := Frame.new()
	check(not owner.configure(bindings,catalogues,scene,0.5),"Partial initialization was accepted")
	if bindings.opening_actors.npc_initialization.get("world_initialization",{}).is_empty():return
	check(scene.complete_world_initialization(bindings,catalogues),scene.error)
	var death_resources: RefCounted
	if not bindings.opening_actors.npc_initialization.get("destruction",{}).is_empty():
		death_resources=DeathResources.new()
		check(death_resources.configure(library,bindings),death_resources.error)
	check(owner.configure(bindings,catalogues,scene,0.5,death_resources),owner.error)
	if death_resources!=null:
		for id in 3:
			check(owner.snapshot().controller.actors[id].destruction.fragments==scene.snapshot().world_initialization.npc_construction.actors[id].fragments,"World did not retain constructor fragments")
	var counts := [];counts.resize(23);counts.fill(1)
	var timeline := Timeline.new()
	check(timeline.configure(bindings,catalogues,library,counts,1.0,0.5),timeline.error)
	var original := {"world_frame":owner.snapshot(),"timeline":timeline.snapshot(),"scenery":scene.snapshot()}
	var has_player: bool=not bindings.opening_actors.get("player_initialization",{}).is_empty()
	check(not original.world_frame.player.is_empty() if has_player else original.world_frame.player.is_empty(),"Player capability differs from its source declaration")
	if has_player:
		check(original.world_frame.player.vitals=={"hull":9999999,"armor":250,"shield":220.0},"Frame lost initial player pools")
	if not bindings.opening_actors.npc_initialization.get("hostility",{}).is_empty():
		var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
		var policy: Dictionary=bindings.opening_actors.npc_initialization.hostility
		check(Hostility.parameters(policy),"Source hostility parameters rejected")
		for key in ["virtual_update","stats_flags","base_flags","fresh_override","kind","overrides"]:
			var wrong := policy.duplicate(true);wrong.provenance[key].offset+=1
			check(not Hostility.validate(wrong,header.source_executable_bytes,header.architecture,bindings.opening_actors.npc_initialization).is_empty(),"Disconnected hostility provenance accepted: "+key)
		check_player_contacts({"world_frame":owner,"timeline":timeline,"scenery":scene})
	var state := owner.evaluate(timeline,scene,0,false)
	if state.is_empty():check(false,owner.error);return
	var scripted_motion: bool=state.world_frame.snapshot().has("player_motion")
	if scripted_motion: check_player_motion_contacts(state)
	check(owner.snapshot()==original.world_frame and timeline.snapshot()==original.timeline and scene.snapshot()==original.scenery,"Evaluation mutated an input owner")
	check(state.timeline.snapshot().elapsed_ms==0 and state.scenery.snapshot().random_state==original.scenery.random_state,"Zero-time frame advanced time or RNG")
	for id in 3:
		check(state.world_frame.snapshot().controller.actors[id].guidance.route==original.scenery.world_initialization.npc_construction.actors[id].route,"Frame lost its initial route")
	var detached: Dictionary=state.world_frame.snapshot();detached.controller.actors[0].guidance.route.waypoints.clear()
	check(not state.world_frame.snapshot().controller.actors[0].guidance.route.waypoints.is_empty(),"Frame snapshot aliases a route")
	for tick in 50:
		state=advance(state,100,false)
		if state.is_empty():return
	check(state.scenery.snapshot().random_state==original.scenery.random_state,"Holding refreshed at or before exactly 5000 ms")
	for row in state.world_frame.snapshot().controller.actors:
		check(row.guidance.selection_elapsed_ms==5000 and row.guidance.boost_elapsed_ms==5000 and row.flight.is_empty(),"Holding did not retain its clocks")
	check_rollback(state,bindings,catalogues)
	state=advance(state,1,false)
	if state.is_empty():return
	# Filled with an independent integer LCG fixture, not the native RNG helper.
	var expected_rng := 31345831516323 if library.manifest.profile.edition=="ios-hd" else 50048063809760
	check(state.scenery.snapshot().random_state.state==expected_rng,"Holding refresh changed ordered RNG draws")
	check_split_frame(state.timeline)
	var activated := false;var moving_frames := 0;var shots := 0;var radio_boundary := false
	for tick in 1000:
		var before: Dictionary=state.timeline.snapshot()
		var logic: RefCounted=state.timeline.fork_for_frame()
		var player_motion := {}
		if scripted_motion:
			var moved: Transform3D=before.scene.player_pose
			moved.origin+=moved.basis.z*200.0
			player_motion={"base_content_id":before.scene.base_content_id,"binding_id":before.scene.binding_id,"prior_pose":before.scene.player_pose,"pose":moved}
		check(logic.begin_frame(100,false,1.0,player_motion),logic.error)
		var logic_state: Dictionary=logic.snapshot()
		var result := advance(state,100,true)
		if result.is_empty():return
		var after: Dictionary=result.timeline.snapshot();var runtime: Dictionary=result.world_frame.snapshot()
		var stable_player: Dictionary=runtime.player.duplicate(true);stable_player.erase("recharge")
		var initial_player: Dictionary=original.world_frame.player.duplicate(true);initial_player.erase("recharge")
		check(stable_player==initial_player,"Precombat frame changed player pools")
		check(after.camera==logic_state.camera,"NPC pass changed the already computed camera view")
		if scripted_motion:
			check(runtime.player_motion==player_motion,"World player movement differs from source 2 units/ms")
			var expected: Vector3=Vector3(18000,-12000,-40000) if after.scene.formation_revealed and not before.scene.formation_revealed else player_motion.pose.origin
			check(after.scene.player_pose.origin==expected,"Formation relocation and player motion ran in the wrong order")
		if before.radio.finished[7] and not before.combat.activated:
			activated=true
			check(after.combat.activated and after.camera.shot.phase==3,"Finished engagement cue did not activate on the next logic pass")
			if death_resources!=null: check_npc_death_world(result)
			for row in state.world_frame.snapshot().controller.actors:
				check(row.guidance.boost_elapsed_ms==before.elapsed_ms,"Holding boost clock was reset before activation")
			for row in runtime.controller.actors:
				check(row.guidance.boost_elapsed_ms==0,"Activation did not consume the overdue holding boost clock")
		if after.radio.finished[7] and not before.radio.finished[7]:
			radio_boundary=true
			check(not after.combat.activated,"Radio presentation activated actors in the same frame")
		for row in runtime.actor_events:
			var id: int=row.actor_id
			check(after.scene.actors[id].pose==after.combat.actors[id].pose,"Scene discarded controller motion")
			if not row.movement.is_empty():
				check(runtime.controller.actors[id].flight.pose==after.combat.actors[id].pose,"Flight and combat poses diverged")
				if before.camera.shot.phase==3:
					moving_frames+=1
					check(after.scene.actors[id].position!=before.scene.actors[id].position,"Active flight did not persist after cinematic drift ended")
			if after.camera.shot.phase<4:check(row.firing.is_empty(),"NPC fired while the player was suppressed")
			for fired in row.firing.get("actors",[]):
				if not fired.outcome.fired:continue
				shots+=1
				var shot: Dictionary=fired.outcome.projectile
				check(shot.position==logic_state.combat.actors[id].pose.origin,"NPC fired from its new pose instead of its preceding pose")
				var retained: Dictionary=runtime.weapons.actors[id].projectiles.slots[shot.slot]
				check(retained==shot and retained.remaining_ms==runtime.weapons.definition.lifetime_ms,"New projectile advanced twice in one frame")
		check(runtime.random_state==result.scenery.snapshot().random_state and runtime.elapsed_ms==after.elapsed_ms,"World owners failed to adopt the same frame")
		state=result
		if after.camera.shot.phase==4:break
	var boundary: Dictionary=state.timeline.snapshot()
	check(boundary.camera.shot.phase==4 and activated and radio_boundary and moving_frames>3,"Frame run missed activation, motion or final handoff")
	# Edition-specific world population consumes a different initial RNG prefix.
	# With the corrected moving target this fixed one-line-radio fixture reaches
	# the narrow firing cone for one Mac actor and no iOS actor at the handoff.
	var expected_shots := (0 if library.manifest.profile.edition=="ios-hd" else 1) if scripted_motion else 3
	check(shots==expected_shots,"Final handoff firing geometry changed")
	check(boundary.radio.finished.slice(0,9).all(func(done):return done) and boundary.radio.started.slice(9).all(func(done):return not done),"Unsupported campaign progress was generated")
	var frozen := snapshots(state)
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,true).is_empty() and snapshots(state)==frozen,"Unsupported encounter advanced without its owners")
	check(state.scenery.snapshot().world_initialization==original.scenery.world_initialization,"Runtime modified constructor records")
	check(not owner.configure(null,catalogues,scene,0.5) and owner.snapshot().is_empty(),"Failed reconfiguration retained the prior frame")
	print(library.manifest.profile.edition,": ordered frame, retained holding/flight, radio boundary and rollback verified; boundary shots=",shots)

func advance(state: Dictionary, delta: int, present_radio: bool) -> Dictionary:
	var result: Dictionary=state.world_frame.evaluate(state.timeline,state.scenery,delta,present_radio)
	if result.is_empty():check(false,state.world_frame.error)
	return result

func check_npc_death_world(source: Dictionary) -> void:
	var state := {"world_frame":source.world_frame.fork_for_frame(),"timeline":source.timeline.fork_for_frame(),"scenery":source.scenery.fork_for_frame()}
	# Inject ordinary lethal hits in a zero-time split frame. This fixture checks
	# world ownership after damage; it does not claim interactive player firing.
	check(state.timeline.begin_frame(0,false,1.0),state.timeline.error)
	var combat: RefCounted=state.timeline.combat_owner()
	for id in 3: check(combat.normal_hit(id,150).destroyed_now,"World fixture did not exhaust NPC hull")
	check(state.timeline.adopt_combat_pass(combat) and state.timeline.finish_frame(false),state.timeline.error)
	var before := snapshots(state)
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,"invalid").is_empty() and snapshots(state)==before,"Late radio failure consumed lethal frames")
	var retired := 0
	for tick in 100:
		state=advance(state,100,false)
		if state.is_empty(): return
		var actors: Array=state.world_frame.snapshot().controller.actors
		retired=0
		for id in 3:
			var life: Dictionary=actors[id].destruction
			var scene: Dictionary=state.timeline.snapshot()
			check(scene.scene.actors[id].pose==life.pose and scene.combat.actors[id].pose==life.pose,"World lost a death pose during cinematic adoption")
			if life.phase=="retired": retired+=1
		if retired==3: break
	check(retired==3,"World did not retain deaths through retirement")
	var controller: Dictionary=state.world_frame.snapshot().controller
	if controller.has("death_accounting"):
		check(before.world_frame.controller.death_accounting.events.is_empty(),"Failed world frame committed kill counters")
		check(controller.death_accounting.events.size()==3 and controller.death_accounting.counter_deltas.player_kills==3 and controller.death_accounting.counter_deltas.pirate_kills==3,"World lost death attribution or repeated counters")
	check(state.timeline.snapshot().radio==before.timeline.radio and state.timeline.snapshot().camera.shot.phase==3,"Death simulation invented radio/campaign completion")
	check(snapshots(source)!=snapshots(state),"World fixture did not advance its detached owners")

func check_player_contacts(initial: Dictionary) -> void:
	var original := snapshots(initial)
	var owner: RefCounted=initial.world_frame.fork_for_frame()
	for actor in initial.timeline.snapshot().combat.actors:
		check(not actor.hostile and not actor.active,"Fresh NPC hostility or holding state changed")
	inject_player_shots(owner,initial.timeline.snapshot().scene.player_pose.origin)
	var first: Dictionary=owner.evaluate(initial.timeline,initial.scenery,0,false)
	if first.is_empty():check(false,owner.error);return
	for event in first.world_frame.snapshot().weapon_events:
		check(event.contacts.size()==1 and event.contacts[0].damage.resolution.branch=="nonhostile" and event.contacts[0].damage.resolution.amount==0,"Weapon pass did not read preceding NPC hostility")
	check(first.world_frame.snapshot().player.vitals.shield==220.0,"Initial nonhostile three-point shots damaged the shield")
	for actor in first.timeline.snapshot().combat.actors:
		check(actor.hostile and not actor.active,"Holding NPC failed to refresh hostility on a zero-time frame")
	inject_player_shots(first.world_frame,first.timeline.snapshot().scene.player_pose.origin)
	var frozen := snapshots(first)
	check(first.world_frame.evaluate(first.timeline,first.scenery,0,"invalid").is_empty(),"Late presentation error accepted after player hits")
	check(snapshots(first)==frozen,"Late frame failure committed player damage, contact cleanup or NPC state")
	var next: Dictionary=first.world_frame.evaluate(first.timeline,first.scenery,0,false)
	if next.is_empty():check(false,first.world_frame.error);return
	check(next.world_frame.snapshot().player.vitals.shield==211.0,"World lost ordered hostile damage from its three guns")
	for event in next.world_frame.snapshot().weapon_events:
		check(event.contacts.size()==1 and event.contacts[0].damage.resolution.branch=="ordinary","Following weapon pass did not retain NPC hostility")
	check(snapshots(initial)==original,"Player-contact frame mutated its initial owners")
	# Returned contact events must be detached from the world owner.
	var copy: Dictionary=next.world_frame.snapshot();copy.weapon_events[0].contacts.clear()
	check(next.world_frame.snapshot().weapon_events[0].contacts.size()==1,"Weapon event snapshot aliases the world")
	if next.world_frame.snapshot().player.has("recharge"):
		check_recharge_order(next)
	if next.world_frame.snapshot().player.has("repair"):
		check_repair_order(next)

func check_repair_order(state: Dictionary) -> void:
	var world: RefCounted=state.world_frame.fork_for_frame()
	# Synthetic fitted device and prior damage exercise scheduling. The authentic
	# starting loadout has no repair device and keeps its authored hull override.
	world._player_state._repair._state.device_mode=0
	world._player_state._state.vitals={"hull":9999998,"armor":240,"shield":0.0}
	world._player_state._repair._state.hull_elapsed_ms=600
	world._player_state._repair._state.armor_elapsed_ms=1000
	var primed := {"world_frame":world,"timeline":state.timeline,"scenery":state.scenery}
	inject_player_shots(primed.world_frame,primed.timeline.snapshot().scene.player_pose.origin)
	var frozen := snapshots(primed)
	check(primed.world_frame.evaluate(primed.timeline,primed.scenery,1,"invalid").is_empty() and snapshots(primed)==frozen,"Late failure consumed equipment repair")
	var result := advance(primed,1,false)
	if result.is_empty():return
	var current: Dictionary=result.world_frame.snapshot()
	check(current.weapon_events[0].contacts[0].damage.before.hull==9999999 and current.weapon_events[0].contacts[0].damage.before.armor==242,"Repair did not precede the current weapon pass")
	check(current.player.vitals=={"hull":9999999,"armor":233,"shield":0.0},"World discarded ordered repair or hostile armor damage")
	check(current.player.repair.hull_elapsed_ms==0 and current.player.repair.armor_elapsed_ms==0,"World retained repair overshoot")
	check(snapshots(primed)==frozen,"Repair frame mutated its input owners")

func check_recharge_order(state: Dictionary) -> void:
	# An overdue fractional pulse must enter hit accounting before the three guns.
	var primed := advance(state,100,false)
	if primed.is_empty():return
	check(primed.world_frame.snapshot().player.recharge.elapsed_ms==100,"World lost strict recharge threshold")
	inject_player_shots(primed.world_frame,primed.timeline.snapshot().scene.player_pose.origin)
	var frozen := snapshots(primed)
	check(primed.world_frame.evaluate(primed.timeline,primed.scenery,1,"invalid").is_empty() and snapshots(primed)==frozen,"Late failure consumed shield recharge")
	var result := advance(primed,1,false)
	if result.is_empty():return
	var current: Dictionary=result.world_frame.snapshot()
	check(current.player.vitals.shield==202.0 and current.player.recharge.elapsed_ms==0,"Recharge ran after hits or failed to reset its clock")
	check(current.weapon_events[0].contacts[0].damage.before.shield==211.36666870117188,"First contact did not observe the binary32 shield pulse")
	check(snapshots(primed)==frozen,"Recharge frame mutated its input owners")

func inject_player_shots(owner: RefCounted, position: Vector3) -> void:
	# Synthetic pre-existing slots exercise scheduling; fresh source guns are empty.
	for gun in owner._weapons._guns:
		check(not gun.advance(601).is_empty(),gun.error)
		check(gun.fire(position,Vector3.BACK,true).get("fired",false),gun.error)

func check_player_motion_contacts(initial: Dictionary) -> void:
	var prior := snapshots(initial)
	var center: Vector3=prior.timeline.scene.player_pose.origin
	# At 100 ms the target has moved +200 Z. With source velocity +16, these
	# samples straddle the strict 1200-unit bounds differently before/after move.
	for offset in [-1150.0,1350.0]:
		var owner: RefCounted=initial.world_frame.fork_for_frame()
		inject_player_shots(owner,center+Vector3(0,0,offset))
		var frozen: Dictionary=owner.snapshot()
		check(owner.evaluate(initial.timeline,initial.scenery,100,"invalid").is_empty() and owner.snapshot()==frozen,"Late failure committed player movement/contacts")
		var result: Dictionary=owner.evaluate(initial.timeline,initial.scenery,100,false)
		if result.is_empty(): check(false,owner.error);return
		for event in result.world_frame.snapshot().weapon_events:
			check(event.contacts.size()==(0 if offset<0 else 1),"Contact sampled player position before cinematic movement")
		check(result.timeline.snapshot().scene.player_pose.origin==center+Vector3(0,0,200),"Cinematic player movement was lost or doubled")
	check(snapshots(initial)==prior,"Speculative player movement mutated original world")

func snapshots(state: Dictionary) -> Dictionary:
	return {"world_frame":state.world_frame.snapshot(),"timeline":state.timeline.snapshot(),"scenery":state.scenery.snapshot()}

func check_rollback(state: Dictionary, bindings: RefCounted, catalogues: RefCounted) -> void:
	var frozen := snapshots(state)
	for invalid in [-1,1.5,1001]:
		check(state.world_frame.evaluate(state.timeline,state.scenery,invalid,true).is_empty(),"Invalid frame time accepted")
	# Invalid final presentation is detected after every staged simulation pass.
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,"yes").is_empty(),"Implicit radio presentation accepted")
	check(snapshots(state)==frozen,"Failed frame consumed time, RNG or actor/scenery state")
	var stale := Scenery.new();check(stale.configure(bindings,catalogues,1789100000),stale.error)
	check(stale.complete_world_initialization(bindings,catalogues),stale.error)
	check(state.world_frame.evaluate(state.timeline,stale,0,true).is_empty(),"Frame accepted another world with matching content IDs")
	var advanced: RefCounted=state.timeline.fork_for_frame()
	check(advanced.update(1,false,false,false,1),advanced.error)
	check(state.world_frame.evaluate(advanced,state.scenery,0,true).is_empty(),"Frame accepted a separately advanced timeline")
	var broken: RefCounted=state.scenery.fork_for_frame()
	broken._random_state={"state":-1}
	check(state.world_frame.evaluate(state.timeline,broken,100,true).is_empty(),"Frame silently replaced its retained random stream")
	check(not broken.update(100,Vector3.ZERO,1.0,null,{"state":-1}) and broken.snapshot().random_state=={"state":-1},"Invalid shared RNG partially updated scenery")

func check_split_frame(timeline: RefCounted) -> void:
	var staged: RefCounted=timeline.fork_for_frame();var original: Dictionary=timeline.snapshot()
	check(not staged.finish_frame(true),"Radio finished without a logic pass")
	check(staged.begin_frame(100,false,1),staged.error)
	var pending: Dictionary=staged.snapshot()
	check(not staged.begin_frame(100,false,1) and staged.snapshot()==pending,"Two logic passes consumed one radio frame")
	check(not staged.finish_frame(1) and staged.snapshot()==pending,"Invalid radio flag mutated a pending frame")
	var actors: RefCounted=staged.combat_owner()
	var moved: Transform3D=actors.snapshot().actors[0].pose;moved.origin.x+=100
	check(actors.set_pose(0,moved),actors.error)
	actors._actors[2]._state.pose.origin=Vector3.INF
	actors._actors[2]._state.position=Vector3.INF
	check(not staged.adopt_combat_pass(actors) and staged.snapshot()==pending,"Invalid last actor partially adopted an earlier pose")
	check(staged.finish_frame(false),staged.error)
	var finished: Dictionary=staged.snapshot()
	check(not staged.finish_frame(false) and staged.snapshot()==finished,"One logic pass produced two radio frames")
	check(timeline.snapshot()==original,"Split-frame fork mutated its source")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
