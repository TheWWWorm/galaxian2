extends SceneTree
const TargetFrame = preload("res://src/presentation/flight_target_frame.gd")
const NpcMarkers = preload("res://src/presentation/flight_npc_markers.gd")
const Frame = preload("res://src/simulation/opening_world_frame.gd")
const Timeline = preload("res://src/simulation/opening_detail_timeline.gd")
const Scenery = preload("res://src/simulation/opening_scenery.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const BodyResources = preload("res://src/content/scenery_body_resources.gd")
const EffectResources = preload("res://src/content/scenery_effect_resources.gd")
const DeathResources = preload("res://src/content/npc_destruction_resources.gd")
const Flight = preload("res://src/simulation/flight_motion.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3): verify_profile(args[i],args[i+1])
	print("Opening player flight checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var bodies := BodyResources.new();var effects := EffectResources.new();var deaths := DeathResources.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not deaths.configure(library,bindings):
		check(false,bodies.error+effects.error+deaths.error);return
	var scenery := Scenery.new();var owner := Frame.new();var timeline := Timeline.new()
	var counts := [];counts.resize(23);counts.fill(1)
	if not scenery.configure(bindings,catalogues,1789100000,true,bodies,effects) or not scenery.complete_world_initialization(bindings,catalogues):
		check(false,scenery.error);return
	if not owner.configure(bindings,catalogues,scenery,0.5,deaths) or not timeline.configure(bindings,catalogues,library,counts,1.0,0.5):
		check(false,owner.error+timeline.error);return
	var configured := owner.snapshot()
	if not bindings.opening_actors.npc_initialization.get("hull",{}).is_empty():
		for actor in timeline.snapshot().combat.actors:
			check(actor.factory_hull==34 and actor.max_hull==150 and actor.hull_percent==100,"World initialization lost verified NPC capacity")
	if bindings.opening_staging.get("player_flight",{}).is_empty():
		check(not owner.configure_player_flight(bindings,catalogues,library,scenery,1.0) and owner.snapshot()==configured,"Legacy pack acquired ordinary player flight")
		return
	check(not owner.configure_player_flight(bindings,catalogues,library,scenery,NAN) and owner.snapshot()==configured,"Invalid input configuration changed the world")
	if not owner.configure_player_flight(bindings,catalogues,library,scenery,1.0): check(false,owner.error);return
	check(not owner.configure_player_flight(bindings,catalogues,library,scenery,1.0),"Player weapons could reset mid-session")
	if not bindings.opening_staging.get("player_aim",{}).is_empty():
		check(owner.configure_player_aim(bindings),owner.error)
		check(not owner.configure_player_aim(bindings),"Aim history could be reset twice")
	if not bindings.opening_staging.get("npc_scanner",{}).is_empty():
		var frame := TargetFrame.source_geometry(library,bindings);var animation := NpcMarkers.source_geometry(library,bindings)
		check(owner.configure_npc_scanner(bindings,catalogues,TargetFrame.logical_radii(frame.quarter_size,false),animation.frames),owner.error)
		check(not owner.configure_npc_scanner(bindings,catalogues,Vector2(76,57),25),"Scanner history could reset twice")
	var state := {"world_frame":owner,"timeline":timeline,"scenery":scenery}
	check(owner.snapshot().primaries.guns.size()==2,"Opening primary equipment was not preserved")
	check(owner.snapshot().player_flight.angular_units==Vector2.ZERO,"Fresh steering is nonzero")
	var handoff := false
	for tick in 1000:
		var before: Dictionary=state.timeline.snapshot()
		var result := step(state,100,Vector2(0,0.8),true)
		if result.is_empty(): return
		var after: Dictionary=result.timeline.snapshot();var frame: Dictionary=result.world_frame.snapshot()
		if after.camera.shot.phase==4:
			check(before.camera.shot.phase==3,"Skipped cinematic release")
			check(frame.player_motion.pose.basis==before.scene.player_pose.basis,"Release frame steered before the controller")
			check(frame.player_flight.angular_units.y>0,"Release frame failed to sample steering")
			check(frame.primary_fire.weapons.size()==2,"Release frame failed to dispatch both primaries")
			for gun in frame.primaries.guns:
				var slots: Array=gun.projectiles.slots.filter(func(slot):return slot!=null and slot.remaining_ms>0)
				check(slots.size()==1 and slots[0].remaining_ms==gun.projectiles.weapon.lifetime_ms,"New player shot advanced in its launch frame")
			state=result;handoff=true;break
		check(frame.player_flight.angular_units==Vector2.ZERO and frame.primary_fire.is_empty(),"Cinematic input leaked before release")
		for gun in frame.primaries.guns: check(gun.projectiles.slots.filter(func(slot):return slot!=null and slot.remaining_ms>0).is_empty(),"Cinematic fire created a projectile")
		state=result
	check(handoff,"Opening did not reach player release")
	if not handoff:return
	var reference := Flight.new();check(reference.configure(bindings,bindings.base_content_id),reference.error)
	for tick in 12:
		var before: Dictionary=state.timeline.snapshot();var old: Dictionary=state.world_frame.snapshot()
		var expected := reference.advance(before.scene.player_pose,old.player_flight.angular_units,1.0,0.1)
		var result := step(state,100,Vector2(0.4,-0.5),false)
		if result.is_empty():return
		check(result.timeline.snapshot().scene.player_pose.is_equal_approx(expected),"Live flight failed to use the preceding angular state")
		check(result.timeline.snapshot().camera.shot.phase==4,"Fight changed the cinematic phase")
		state=result
	check(not state.timeline.snapshot().scene.player_pose.basis.is_equal_approx(Basis.IDENTITY),"Player input never changed heading")
	check_rollback(state)
	if state.world_frame._aim!=null:check_contact_feedback(state)
	check_player_death_boundary(state)
	check_primary_kills(state)
	print(library.manifest.profile.edition,": cinematic release, next-frame steering, primary clocks, contacts, death credit and postcombat boundary verified")

func check_contact_feedback(state: Dictionary) -> void:
	for target in ["npc","scenery"]:
		var frame: RefCounted=state.world_frame.fork_for_frame()
		var timeline: RefCounted=state.timeline.fork_for_frame()
		var combat: RefCounted=timeline.combat_owner()
		var hull: int=combat.snapshot().actors[0].vitals.hull
		check(combat._actors[0].set_permissions(true,false,true),"Could not prepare a denied damage fixture")
		check(timeline.adopt_contact_pass(combat),timeline.error)
		for mount in frame._primaries._guns:
			for shot in mount.projectiles.snapshot().slots:
				if shot!=null:check(mount.projectiles.retire(shot.id),mount.projectiles.error)
		check(frame._aim.sample_feedback(false,201,true) and frame._aim.sample_feedback(false,0,true),frame._aim.error)
		var position: Vector3=combat.snapshot().actors[0].pose.origin if target=="npc" else state.scenery.snapshot().bodies.objects[0].position
		var gun: RefCounted=frame._primaries._guns[0].projectiles
		gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
		check(gun.fire(position,Vector3.BACK,true).get("fired",false),gun.error)
		var result := step({"world_frame":frame,"timeline":timeline,"scenery":state.scenery},0,Vector2.ZERO,false)
		if result.is_empty():return
		var contacts := []
		for weapon in result.world_frame.snapshot().primary_contacts:contacts.append_array(weapon.contacts)
		check(not contacts.is_empty() and contacts[0].target.group==target,"Feedback fixture missed its real target")
		check(result.timeline.snapshot().combat.actors[0].vitals.hull==hull,"Denied or unrelated contact changed NPC hull")
		check(result.world_frame.snapshot().player_aim.contact_flash==(target=="npc"),"Reticle used applied damage or scenery contact instead of NPC contact")

func check_primary_kills(state: Dictionary) -> void:
	# Controlled damage/shot fixtures retain actual source equipment, target poses,
	# collision extents and frame scheduling. They do not claim player playtesting.
	var frame: RefCounted=state.world_frame.fork_for_frame()
	var timeline: RefCounted=state.timeline.fork_for_frame()
	var combat: RefCounted=timeline.combat_owner()
	for actor in combat.snapshot().actors:
		check(not combat.normal_hit(actor.actor_id,actor.vitals.hull-1).is_empty(),combat.error)
	check(timeline.adopt_contact_pass(combat),timeline.error)
	for gun in frame._primaries._guns:
		for shot in gun.projectiles.snapshot().slots:
			if shot!=null: check(gun.projectiles.retire(shot.id),gun.projectiles.error)
	var gun: RefCounted=frame._primaries._guns[0].projectiles
	for actor in combat.snapshot().actors:
		gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
		check(gun.fire(actor.pose.origin,Vector3.BACK,true).get("fired",false),gun.error)
	var fixture := {"world_frame":frame,"timeline":timeline,"scenery":state.scenery.fork_for_frame()}
	var unchanged := snapshot(fixture)
	check(frame.evaluate(timeline,fixture.scenery,100,"invalid",1.0,Vector2(1,1),true,Vector2i(800,600)).is_empty(),"Late failure accepted staged primary kills")
	check(snapshot(fixture)==unchanged,"Failed frame committed kills, fragments or radio")
	var result := step(fixture,100,Vector2.ZERO,false)
	if result.is_empty():return
	for actor in result.timeline.snapshot().combat.actors:
		check(actor.vitals.hull==0,"Primary contact did not reach its target before the actor pass")
		if actor.has("max_hull"):
			check(actor.factory_hull==34 and actor.max_hull==150 and actor.hull_percent==0,"Committed death lost source NPC capacity")
	if frame._aim!=null:check(result.world_frame.snapshot().player_aim.contact_flash,"Real player NPC contacts did not reach reticle feedback")
	var accounting: Dictionary=result.world_frame.snapshot().controller.death_accounting
	check(accounting.counter_deltas.player_kills==3 and accounting.events.size()==3,"Player primary kills failed to enter one-time accounting")
	check(result.timeline.snapshot().radio.active_event==9,"Postcombat radio did not observe the current hulls")
	var reached := false
	for tick in 200:
		if result.timeline.snapshot().radio.finished[10]: reached=true;break
		result=step(result,100,Vector2.ZERO,false)
		if result.is_empty():return
	check(reached,"Postcombat radio did not reach its source boundary")
	var before := snapshot(result)
	check(result.world_frame.evaluate(result.timeline,result.scenery,100,true).is_empty(),"Unsupported postcombat mission was advanced")
	check(snapshot(result)==before,"Postcombat boundary changed retained state")

func check_player_death_boundary(state: Dictionary) -> void:
	var frame: RefCounted=state.world_frame.fork_for_frame()
	frame._player_state._state.vitals={"hull":1,"armor":0,"shield":0.0}
	var gun: RefCounted=frame._weapons._guns[0]
	for shot in gun.snapshot().slots:
		if shot!=null: check(gun.retire(shot.id),gun.error)
	gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
	check(gun.fire(state.timeline.snapshot().scene.player_pose.origin,Vector3.BACK,true).get("fired",false),gun.error)
	var result: Dictionary=frame.evaluate(state.timeline,state.scenery,0,true,1.0,Vector2(1,1),true,Vector2i(800,600))
	check(not result.is_empty(),frame.error)
	if result.is_empty():return
	check(result.world_frame.snapshot().player.vitals.hull==0 and result.world_frame.snapshot().primary_fire.is_empty(),"Lethal contact allowed later player firing")
	var before := snapshot(result)
	check(result.world_frame.evaluate(result.timeline,result.scenery,100,true).is_empty(),"Unsupported player death transition advanced")
	check(snapshot(result)==before,"Player death boundary changed state")

func check_rollback(state: Dictionary) -> void:
	var before := snapshot(state)
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,"invalid",1.0,Vector2(1,1),true,Vector2i(800,600)).is_empty(),"Late radio failure accepted")
	check(snapshot(state)==before,"Failed frame committed steering, shots, damage or clocks")
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,true,1.0,Vector2(INF,0),true,Vector2i(800,600)).is_empty(),"Invalid steering accepted")
	check(snapshot(state)==before,"Invalid steering changed frame state")
	var zero := step(state,0,Vector2.ZERO,false)
	if not zero.is_empty(): check(zero.timeline.snapshot().scene.player_pose==state.timeline.snapshot().scene.player_pose,"Zero time moved the player")

func step(state: Dictionary, delta: int, command: Vector2, fire: bool) -> Dictionary:
	var result: Dictionary=state.world_frame.evaluate(state.timeline,state.scenery,delta,true,1.0,command,fire,Vector2i(800,600))
	check(not result.is_empty(),state.world_frame.error)
	if not result.is_empty() and state.world_frame._aim!=null:
		var expected: RefCounted=state.world_frame._aim.fork_for_frame()
		var before: Dictionary=state.timeline.snapshot()
		var after: Dictionary=result.world_frame.snapshot()
		check(expected.advance(after.player_motion.pose,before.camera.view.get("pose",Transform3D.IDENTITY),Vector2i(800,600)),expected.error)
		check(after.player_aim.point==expected.snapshot().point,"World used the controller's later pose/camera for its aim")
		check(after.player_aim.visible==(result.timeline.snapshot().camera.shot.phase==4 and after.player.vitals.hull>0),"World reticle visibility differs from the ordinary alive player")
	return result

func snapshot(state: Dictionary) -> Dictionary:
	return {"frame":state.world_frame.snapshot(),"timeline":state.timeline.snapshot(),"scenery":state.scenery.snapshot()}

func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
