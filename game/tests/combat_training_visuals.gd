extends "res://tests/combat_training_focused.gd"
## Earned equipment plus detached, deliberately overlapping projectile fixtures.
const TrainingVisualRules=preload("res://src/content/combat_training_visual_definitions.gd")
const ShotClocks=preload("res://src/simulation/projectile_visual_state.gd")
const HitClocks=preload("res://src/simulation/ordinary_impact_state.gd")
const ShotGeometry=preload("res://src/presentation/projectile_geometry.gd")
const HitGeometry=preload("res://src/presentation/ordinary_impact_geometry.gd")
const ShotPose=preload("res://src/presentation/projectile_pose.gd")
const Capture=preload("res://tests/fixtures/model_capture.gd")
const TrainingScenery=preload("res://src/simulation/opening_scenery.gd")
const TrainingBodies=preload("res://src/content/scenery_body_resources.gd")
const TrainingEffects=preload("res://src/content/scenery_effect_resources.gd")
const TrainingTargets=preload("res://src/simulation/opening_target_inventory.gd")
const TrainingEncounter=preload("res://src/simulation/full_hold_encounter.gd")
var _captures:=[]

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:verify(args.slice(0,3))
	if args.size()==4 and failures==0 and DisplayServer.get_name()!="headless":await capture_models(args[3])
	for entry in _captures:entry.geometry.free()
	print("Combat-training visuals: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_training_destruction(args: PackedStringArray, equipment: RefCounted):
	super.verify_training_destruction(args,equipment)
	verify_training_visuals(args,equipment)
	verify_training_field(equipment)

func verify_training_visuals(args: PackedStringArray, equipment: RefCounted):
	var rules: Dictionary=bindings.combat_training_visuals
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for version in range(1,Bindings.MAX_READER_VERSION+1):check(Bindings.reader_version("resource-registration-v%d"%version)==version,"Supported reader version lost its gate")
	for value in [null,121,true,"resource-registration-v0","resource-registration-v%d"%(Bindings.MAX_READER_VERSION+1),"resource-registration-v0121","resource-registration-v+121","resource-registration-v121 ","resource-registration-v121suffix"]:
		check(Bindings.reader_version(value)==0,"Unsupported reader spelling accepted")
	if Bindings.reader_version(header.reader)>=121:check(TrainingVisualRules.parameters(rules),"Current Mac pack omitted training visuals")
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var player:=TrainingPlayer.new();check(player.configure_combat_training(bindings,cat,equipment),player.error)
	var mounts:=TrainingMounts.new();check(mounts.open(lib,cat),mounts.error)
	var primary:=TrainingPrimary.new();check(primary.configure(bindings,cat,mounts,player.loadout()),primary.error)
	var source:=TrainingWorld.new()
	check(source.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),{"companions_empty":true,"location_match":false,"special_placement":false}),source.error)
	check(not source.generate({"state":int(TRAINING_GOLDEN[0].input_state)}).is_empty(),source.error)
	var guns:=TrainingGuns.new();check(guns.configure_combat_training(bindings,cat,source,0,.5),guns.error)
	var world:=visual_world(primary,guns,0)
	var shots:=ShotClocks.new();var impacts:=HitClocks.new()
	if rules.is_empty():
		check(not shots.configure(bindings,lib,world) and not impacts.configure(bindings,lib,world),"Older pack invented training models")
		return
	check(TrainingVisualRules.validate(rules,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training_weapons,bindings.opening_staging).is_empty(),"Training visuals rejected their source context")
	for key in TrainingVisualRules.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not TrainingVisualRules.parameters(bad),"Changed training visual accepted: "+key)
	for key in TrainingVisualRules.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not TrainingVisualRules.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training_weapons,bindings.opening_staging).is_empty(),"Disconnected visual proof accepted: "+key)
	var construction:=source.snapshot()
	check(shots.configure(bindings,lib,world) and impacts.configure(bindings,lib,world),shots.error+impacts.error)
	if shots.snapshot().is_empty() or impacts.snapshot().is_empty():return
	check(source.snapshot()==construction and world==visual_world(primary,guns,0),"Visual construction changed weapons or consumed retained world randomness")
	check(shots.snapshot().models.map(func(row):return row.model_id)==[6798,6795,6795,6795,6802],"Training travelling model override was lost")
	check(impacts.snapshot().weapons.map(func(row):return row.model_id)==[14606,14605,14605,14605,14606],"Training impact table was replaced by travelling models")
	check(shots.snapshot().models.map(func(row):return row.captured_up)==[true,false,false,false,false],"Player up axis or NPC world-up root changed")
	check(shots.snapshot().models.map(func(row):return [row.start_ms,row.end_ms])==[[0,0],[33,700],[33,700],[33,700],[33,133]],"Static or animated training model range changed")
	check(impacts.snapshot().weapons.map(func(row):return row.slots.size())==[25,4,4,4,4],"Impact allocation changed projectile capacity")
	check(impacts.snapshot().weapons.all(func(row):return row.slots.all(func(slot):return not slot.playing)),"Unused impacts started playing")
	var shot_geometry:=ShotGeometry.new();var hit_geometry:=HitGeometry.new()
	root.add_child(shot_geometry);root.add_child(hit_geometry)
	check(shot_geometry.build(shots,lib,visuals,bindings),shot_geometry.error)
	check(hit_geometry.build(impacts,lib,visuals,bindings),hit_geometry.error)
	if shot_geometry.guns.is_empty() or hit_geometry.guns.is_empty():shot_geometry.free();hit_geometry.free();return
	check(not primary.advance(1).is_empty() and not guns.advance(1).is_empty(),primary.error+guns.error)
	var roll:=Basis(Vector3.UP,Vector3.LEFT,Vector3.BACK)
	var firing:=primary.fire(Transform3D(roll,Vector3.ZERO),true,training_seed(1))
	check(not firing.is_empty(),primary.error)
	if firing.is_empty():shot_geometry.free();hit_geometry.free();return
	var shot: Dictionary=firing.weapons[0].result.projectile
	check(shot.up==Vector3.LEFT and primary.snapshot().guns[0].projectiles.slots[0].up==shot.up,"Mounted shot lost the firing matrix Y column")
	var pose:=ShotPose.sample(shot,2,Transform3D.IDENTITY,false,shots.snapshot().rules,true)
	var upright:=ShotPose.sample(shot,2,Transform3D.IDENTITY,false,shots.snapshot().rules)
	check(pose.get("visible",false) and pose.pose.basis.x.dot(Vector3.UP)>.99 and pose.pose.basis!=upright.pose.basis,"Rolled shot used world up")
	var lost:=shot.duplicate(true);lost.erase("up")
	check(ShotPose.sample(lost,2,Transform3D.IDENTITY,false,shots.snapshot().rules,true).has("error"),"Missing firing orientation was guessed")
	var combat:=training_armed_group(cat,source)
	for id in 4:check(combat.set_pose(id,Transform3D(Basis.IDENTITY,shot.position)),combat.error)
	check(not guns.fire(combat,[0,1,2,3]).is_empty(),guns.error)
	world=visual_world(primary,guns,0)
	check(shots.advance(1) and impacts.advance(1),shots.error+impacts.error)
	var render:=world.duplicate(true);render.elapsed_ms=1;render.projectile_visuals=shots.snapshot()
	var prepared:=shot_geometry.prepare_world(shots,render,Transform3D.IDENTITY)
	check(not prepared.is_empty(),shot_geometry.error)
	if not prepared.is_empty():
		shot_geometry.commit_world(prepared)
		check(shot_geometry.guns.all(func(row):return row.slots[0].visible),"A training weapon model remained invisible")
	var primary_hit:=primary.evaluate_npc_update(combat,[0,1,2,3],0)
	check(not primary_hit.is_empty(),primary.error)
	if primary_hit.is_empty():shot_geometry.free();hit_geometry.free();return
	var npc_hit:=guns.evaluate_combat_training_update(player,Transform3D(Basis.IDENTITY,shot.position),primary_hit.combat,false,0)
	check(not npc_hit.is_empty(),guns.error)
	if npc_hit.is_empty():shot_geometry.free();hit_geometry.free();return
	var bad_events: Array=npc_hit.actors.duplicate(true);bad_events[-1].npc_contacts[-1].slot=99
	var before:=impacts.snapshot()
	check(not impacts.apply_contacts(world,primary_hit.weapons,bad_events) and impacts.snapshot()==before,"Late impact error committed earlier effects")
	check(impacts.apply_contacts(world,primary_hit.weapons,npc_hit.actors),impacts.error)
	check(impacts.snapshot().hits.size()==14,"Impact pass omitted ordered NPC-to-NPC hits")
	check(impacts.snapshot().hits.map(func(row):return row.key)==["player:0","player:0","player:0","player:0","npc:0","npc:0","npc:1","npc:1","npc:2","npc:2","npc:3","npc:3","npc:3","npc:3"],"Impact target groups changed source order")
	for row in impacts.snapshot().weapons:
		check(row.slots[0].playing and row.slots[0].time_ms==row.slots[0].start_ms and row.slots[0].sample_time_ms==row.slots[0].start_ms and row.slots[0].position==shot.position,"Impact restart lost the previous shot position or sampled early")
	render.impact_visuals=impacts.snapshot()
	prepared=hit_geometry.prepare_world(impacts,render,Transform3D.IDENTITY)
	check(not prepared.is_empty(),hit_geometry.error)
	if not prepared.is_empty():
		hit_geometry.commit_world(prepared)
		check(hit_geometry.guns.all(func(row):return row.slots[0].visible),"Training impact model remained invisible")
	var alternative: RefCounted=equipment.fork()
	check(alternative.transact("unmount",22) and alternative.transact("mount",0),alternative.error)
	check(player.configure_combat_training(bindings,cat,alternative),player.error)
	check(primary.configure(bindings,cat,mounts,player.loadout()),primary.error)
	var starter:=ShotClocks.new();var starter_hits:=HitClocks.new()
	var decoded:=ShotClocks.AEM.new().decode(lib.read_resource(bindings.resolve(6754,"mesh"),ShotClocks.AEM.MAX_BYTES))
	check(ShotClocks.Ranges.playback_range(decoded.surfaces,true)=={"start_ms":0,"end_ms":0} and ShotClocks.Ranges.playback_range(decoded.surfaces).is_empty(),"Static projectile weakened required effect animation validation")
	check(starter.configure(bindings,lib,visual_world(primary,guns,0)) and starter_hits.configure(bindings,lib,visual_world(primary,guns,0)),starter.error+starter_hits.error)
	check(starter.snapshot().models[0].model_id==6754 and starter_hits.snapshot().weapons[0].model_id==14600,"Alternative installed starter gun inherited upgraded effects")
	if DisplayServer.get_name()!="headless":
		_captures.append({"geometry":shot_geometry,"clock":shots,"world":world,"indices":[0,1,4],"kind":"projectile"})
		var previous:=world.duplicate(true);previous.elapsed_ms=1
		_captures.append({"geometry":hit_geometry,"clock":impacts,"world":previous,"indices":[0,1],"kind":"impact"})
		check(not primary.advance(1).is_empty() and not primary.fire(Transform3D.IDENTITY,true).is_empty(),primary.error)
		var starter_geometry:=ShotGeometry.new();root.add_child(starter_geometry)
		check(starter_geometry.build(starter,lib,visuals,bindings),starter_geometry.error)
		_captures.append({"geometry":starter_geometry,"clock":starter,"world":visual_world(primary,guns,0),"indices":[0],"kind":"projectile"})
	else:
		shot_geometry.free();hit_geometry.free()
	print("Training visuals: five travelling models, 41 impact slots, captured roll and ordered overlapping contacts")

func visual_world(primary: RefCounted, guns: RefCounted, elapsed: int) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":elapsed,"primaries":primary.snapshot(),"weapons":guns.snapshot()}

func verify_training_field(equipment: RefCounted):
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var bodies:=TrainingBodies.new();var effects:=TrainingEffects.new()
	check(bodies.configure(lib,bindings) and effects.configure(lib,bindings),bodies.error+effects.error)
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	var scenery:=TrainingScenery.new()
	check(scenery.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),conditions,1789100000,true,bodies,effects),scenery.error)
	var field:=scenery.snapshot()
	if field.is_empty():return
	check(field.objects.size()==130 and field.center==Vector3(12298,36830,77237),"Training changed ordinary station scenery count or center")
	check(field.world_initialization.input_random_state=={"state":153548941033574},"NPC construction did not follow the complete field RNG")
	var world: RefCounted=scenery.world_initialization_owner()
	check(world!=null and world.snapshot().npc_construction.actors.size()==4,"Training scenery omitted its NPC construction")
	if world==null:return
	var reference:=TrainingWorld.new()
	check(reference.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),conditions),reference.error)
	check(reference.generate(field.world_initialization.input_random_state)==world.snapshot() and field.random_state==world.snapshot().random_state,"Scenery duplicated or omitted constructor effect draws")
	var detached: RefCounted=scenery.world_initialization_owner();detached.clear()
	check(scenery.snapshot()==field and world.snapshot()==field.world_initialization,"Detached construction changed retained scenery")
	check(not scenery.complete_world_initialization(bindings,cat) and scenery.snapshot()==field,"Training initialized its NPCs a second time")
	var player:=TrainingPlayer.new();check(player.configure_combat_training(bindings,cat,equipment),player.error)
	var targets:=TrainingTargets.new();check(targets.configure_combat_training(bindings,cat,player,scenery),targets.error)
	if targets.snapshot().is_empty():return
	check(targets.snapshot().npc_ids==[0,1,2,3] and targets.snapshot().scenery_indices.size()==130,"Training primary target list omitted source bodies")
	var mounts:=TrainingMounts.new();check(mounts.open(lib,cat),mounts.error)
	var primary:=TrainingPrimary.new();check(primary.configure(bindings,cat,mounts,player.loadout()),primary.error)
	check(not primary.advance(1).is_empty(),primary.error)
	var live:=LiveTraining.new();check(live.configure(bindings,cat,world,0,.5),live.error)
	check(not live.advance(0,training_player(Vector3(10000,7000,160000))).is_empty(),live.error)
	var combat: RefCounted=live.combat_owner()
	# Overlap the NPCs with one actual generated asteroid. The asteroid field
	# remains unmodified, and the one shot must survive both target groups.
	var position: Vector3=field.objects[0].position
	for id in 4:check(combat.set_pose(id,Transform3D(Basis.IDENTITY,position)),combat.error)
	var mount: Vector3=primary.snapshot().guns[0].mount.position
	var fired:=primary.fire(Transform3D(Basis.IDENTITY,position-mount-Vector3(0,0,100)),true,training_seed(1))
	check(not fired.is_empty(),primary.error)
	var initial:=primary.snapshot();var original: Dictionary=combat.snapshot()
	var bad_weapon: Dictionary=initial.guns[0].projectiles.weapon.duplicate(true);bad_weapon.campaign_cursor=4
	check(not scenery._bodies.supports_weapon_hit(bad_weapon),"Scenery accepted kind2 outside the verified training context")
	bad_weapon.campaign_cursor=7;bad_weapon.dispersion.steps=3
	check(not scenery._bodies.supports_weapon_hit(bad_weapon),"Scenery accepted unsupported kind2 declarations")
	var hit:=scenery.evaluate_primary_contacts(primary,combat,targets,0)
	check(not hit.is_empty(),scenery.error)
	if hit.is_empty():return
	check(primary.snapshot()==initial and combat.snapshot()==original and scenery.snapshot()==field,"Complete training contacts changed an input owner")
	var ordered: Array=hit.weapons[0].contacts.map(func(row):return row.target)
	check(ordered.slice(0,4)==[{"group":"npc","index":0},{"group":"npc","index":1},{"group":"npc","index":2},{"group":"npc","index":3}] and ordered.has({"group":"scenery","index":0}),"Training shot did not visit NPCs then the real asteroid")
	check(hit.weapons[0].motion.cleared==[1] and hit.weapons[0].motion.moved.is_empty(),"Training shot moved between target groups")
	check(hit.scenery.snapshot().bodies.objects[0].vitals.hull<field.bodies.objects[0].vitals.hull,"Training primary omitted asteroid damage")
	var invalid: RefCounted=combat.fork_for_frame();invalid._actors[3]._state.position=Vector3(NAN,0,0)
	check(scenery.evaluate_primary_contacts(primary,invalid,targets,0).is_empty() and primary.snapshot()==initial and scenery.snapshot()==field,"Late contact failure changed a primary or scenery body")
	print("Training field: 130 source asteroids, shared construction RNG and complete transactional primary contacts")
	verify_training_encounter(cat,player,scenery)

func verify_training_encounter(cat: RefCounted, player: RefCounted, scenery: RefCounted):
	var encounter:=TrainingEncounter.new()
	if bindings.combat_training_visuals.is_empty():
		check(not encounter.configure_combat_training(bindings,cat,lib,player,scenery,0,.5),"Older pack invented a complete training encounter")
		return
	check(encounter.configure_combat_training(bindings,cat,lib,player,scenery,0,.5),encounter.error)
	if encounter.snapshot().is_empty():return
	var initial:=encounter.snapshot();var field: Dictionary=scenery.snapshot();var original_player: Dictionary=player.snapshot()
	check(initial.campaign_cursor==7 and initial.primaries.guns.size()==1 and initial.weapons.actors.size()==4,"Encounter omitted a retained weapon owner")
	check(initial.controller.random_state==field.random_state and initial.projectile_visuals.elapsed_ms==0,"Encounter reset world randomness or advanced its visuals")
	var wrong: RefCounted=scenery.fork_for_frame();wrong._random_state=training_seed(1)
	check(not encounter.configure_combat_training(bindings,cat,lib,player,wrong,0,.5) and encounter.snapshot()==initial,"Rejected configuration replaced the accepted encounter")
	var pose:=Transform3D(Basis.IDENTITY,Vector3(10000,7000,160000))
	var world:=encounter.evaluate_world(player,pose,0,field.random_state)
	check(not world.is_empty(),encounter.error)
	if world.is_empty():return
	var activated: RefCounted=world.encounter
	check(activated.snapshot().combat.actors[0].active and activated.snapshot().elapsed_ms==0 and activated.snapshot().world_elapsed_ms==0,"Zero-time world pass lost activation or advanced weapon time")
	check(encounter.snapshot()==initial and scenery.snapshot()==field and player.snapshot()==original_player,"Staged activation changed accepted owners")
	var early: Dictionary=activated.evaluate_weapons(player,pose,1,scenery)
	check(not early.is_empty(),activated.error)
	if early.is_empty():return
	var ready: RefCounted=early.encounter
	check(ready.snapshot().elapsed_ms==1 and ready.snapshot().projectile_visuals.elapsed_ms==1 and ready.snapshot().impact_visuals.elapsed_ms==1 and ready.snapshot().world_elapsed_ms==0,"Early weapons advanced the wrong clocks")
	var disabled: Dictionary=ready.evaluate_primary_fire(early.player,pose,true,false,world.random_state)
	check(not disabled.is_empty(),ready.error)
	check(disabled.encounter.snapshot().primary_fire.is_empty() and disabled.random_state==world.random_state,"Held input fired or consumed dispersion values")
	# Keep the actual NPC roots and field. Disclose a near-lethal hull, a muzzle
	# placed at pirate0 and a fixed spread seed to verify the known death vector.
	check(not ready._combat.normal_hit(0,46,false).is_empty(),ready._combat.error)
	var mount: Vector3=ready.snapshot().primaries.guns[0].mount.position
	pose.origin=ready.snapshot().combat.actors[0].pose.origin-mount-Vector3(0,0,100)
	var late: Dictionary=ready.evaluate_primary_fire(early.player,pose,true,true,training_seed(1))
	check(not late.is_empty(),ready.error)
	if late.is_empty():return
	var fired: RefCounted=late.encounter;var fired_state: Dictionary=fired.snapshot()
	check(fired_state.primary_fire.weapons[0].result.fired and fired_state.primary_fire.weapons[0].audio_events[0].source_id==66,"Late input omitted the equipped primary or its sound")
	check(fired_state.combat.actors[0].vitals.hull==2 and fired_state.primaries.guns[0].projectiles.slots[0].remaining_ms==1000,"A new shot contacted or advanced during late input")
	check(fired_state.elapsed_ms==1 and fired_state.impact_visuals.hits.is_empty(),"Late fire resampled effects or weapon time")
	var bad: RefCounted=fired.fork_for_frame();bad._weapons._identity.binding_id="f".repeat(64)
	var bad_before: Dictionary=bad.snapshot()
	check(bad.evaluate_weapons(early.player,pose,0,early.scenery).is_empty() and bad.snapshot()==bad_before and early.scenery.snapshot()==field,"A failed NPC phase committed earlier primary damage")
	var contact: Dictionary=fired.evaluate_weapons(early.player,pose,0,early.scenery)
	check(not contact.is_empty(),fired.error)
	if contact.is_empty():return
	var hit: RefCounted=contact.encounter;var contact_state: Dictionary=hit.snapshot()
	check(contact_state.combat.actors[0].vitals.hull==0 and contact_state.combat.actors[0].actor_mode!=4,"Contact skipped lethal hull or prematurely completed an explosion")
	check(contact_state.primary_contacts[0].motion.cleared==[1] and contact_state.primaries.guns[0].projectiles.slots[0]==null,"Complete contact pass left the projectile live")
	check(contact_state.impact_visuals.hits.size()>=1 and contact_state.primary_fire.is_empty(),"Early contact lost its impact or replayed firing audio")
	check(fired.snapshot()==fired_state and early.player.snapshot()==original_player,"Contact phase changed its input encounter or player")
	bad=hit.fork_for_frame();bad._weapons._definitions[3].actor_kind+=1;bad_before=bad.snapshot()
	check(bad.evaluate_world(contact.player,pose,0,late.random_state).is_empty() and bad.snapshot()==bad_before,"A late firing failure committed NPC death or counters")
	world=hit.evaluate_world(contact.player,pose,0,late.random_state)
	check(not world.is_empty(),hit.error)
	if world.is_empty():return
	var dying: RefCounted=world.encounter;var state: Dictionary=dying.snapshot()
	check(state.actor_events[0].destruction.state.countdown_ms==2313 and world.random_state.state==93651525288237,"Late primary spread and NPC death changed shared random order")
	check(state.controller.accounting.counter_deltas.pirate_kills==1 and not state.controller.defeat_status.satisfied,"Lethal contact lost attribution or completed the training mission")
	var retained: RefCounted=dying.npc_destruction_owner(0)
	check(retained!=null and retained.snapshot()==state.controller.destruction[0],"Encounter presentation lost retained cargo destruction")
	retained.clear()
	check(dying.snapshot()==state,"Presentation changed the accepted destruction owner")
	check(contact.scenery.update(0,Vector3.ZERO,1.0,null,world.random_state),contact.scenery.error)
	check(contact.scenery.snapshot().random_state==world.random_state,"Scenery reset the post-NPC random stream")
	check(encounter.snapshot()==initial and scenery.snapshot()==field and player.snapshot()==original_player,"Composed phases changed initial owners")
	verify_training_npc_launch(encounter,player,scenery)
	print("Training encounter: early complete contacts, late fire, zero-time activation, ordered destruction and atomic failures")

func verify_training_npc_launch(encounter: RefCounted, player: RefCounted, scenery: RefCounted):
	# Put the player directly ahead of the retained pirate root. A zero-time world
	# pass releases the actor; this fixture then ages only the weapon cooldown.
	var root: Transform3D=encounter.snapshot().combat.actors[0].pose
	var pose:=Transform3D(Basis.IDENTITY,root.origin+root.basis.z*10000)
	var random: Dictionary=scenery.snapshot().random_state
	var phase: Dictionary=encounter.evaluate_world(player,pose,0,random)
	check(not phase.is_empty(),encounter.error)
	if phase.is_empty():return
	var live: RefCounted=phase.encounter;random=phase.random_state
	var field: RefCounted=scenery
	for i in 4:
		phase=live.evaluate_weapons(player,pose,150,field)
		check(not phase.is_empty(),live.error)
		if phase.is_empty():return
		live=phase.encounter;player=phase.player;field=phase.scenery
	var before: Dictionary=live.snapshot()
	phase=live.evaluate_world(player,pose,150,random)
	check(not phase.is_empty(),live.error)
	if phase.is_empty():return
	var after: Dictionary=phase.encounter.snapshot()
	var firing: Dictionary=after.actor_events[0].firing
	check(not firing.is_empty() and firing.actors[0].outcome.fired,"Aligned training pirate did not fire after its source cooldown")
	if firing.is_empty() or not firing.actors[0].outcome.fired:return
	var shot: Dictionary=after.weapons.actors[0].projectiles.slots[0]
	check(shot.position==before.combat.actors[0].pose.origin and shot.remaining_ms==3000,"NPC launch used its post-motion pose or advanced a new shot")
	check(after.combat.actors[0].pose.origin!=shot.position and after.world_elapsed_ms==150 and after.elapsed_ms==600,"NPC motion failed to follow firing in the later world phase")
	check(firing.actors[0].audio_events[0].position==shot.position and firing.actors[0].audio_events[0].source_id==61,"NPC launch audio lost its source or pre-motion position")
	check(field.update(150,Vector3.ZERO,1.0,null,phase.random_state),field.error)
	check(field.snapshot().random_state==phase.random_state,"Ordinary scenery disturbed a stream without a pending destruction")

func capture_models(output: String):
	for entry in _captures:
		var clock: RefCounted=entry.clock.fork_for_frame();var world: Dictionary=entry.world.duplicate(true)
		check(clock.advance(50),clock.error)
		if entry.kind=="impact":
			var primary_events: Array=world.primaries.guns.map(func(gun):return {"mount_id":gun.mount_id,"contacts":[]})
			var npc_events: Array=world.weapons.actors.map(func(actor):return {"actor_id":actor.actor_id,"contacts":[],"npc_contacts":[]})
			check(clock.apply_contacts(world,primary_events,npc_events),clock.error)
			world.impact_visuals=clock.snapshot()
		else:
			world.projectile_visuals=clock.snapshot()
			for gun in ShotClocks.weapons(world):
				for shot in gun.projectiles.slots:
					if shot!=null:shot.position=Vector3.ZERO;shot.velocity=Vector3.RIGHT;shot.up=Vector3.UP
		world.elapsed_ms=clock.snapshot().elapsed_ms
		var prepared: Dictionary=entry.geometry.prepare_world(clock,world,Transform3D.IDENTITY)
		check(not prepared.is_empty(),entry.geometry.error)
		if prepared.is_empty():continue
		entry.geometry.commit_world(prepared)
		for index in entry.indices:
			for other in _captures:
				for gun in other.geometry.guns:
					for model in gun.slots:model.visible=false
			var model: Node3D=entry.geometry.guns[index].slots[0];model.visible=true
			var rows: Array=clock.snapshot().get("models",clock.snapshot().get("weapons",[]))
			var name:="%s-%d.png"%[entry.kind,rows[index].model_id]
			var result:=await Capture.capture(self,model,output.path_join(name))
			check(result.get("saved",false) and result.get("lit_pixels",0)>40,"Source model did not render independently: "+name+" "+str(result))
			print(name,": ",result)
