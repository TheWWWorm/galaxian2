extends "res://tests/combat_training_story.gd"
## Detached departure built from the captured, acknowledged station transition.
const PreparedTraining=preload("res://src/simulation/first_flight_construction.gd")
const TrainingBriefing=preload("res://src/simulation/mining_briefing.gd")
const PreparedBodies=preload("res://src/content/scenery_body_resources.gd")
const PreparedEffects=preload("res://src/content/scenery_effect_resources.gd")
const TrainingSession=preload("res://src/presentation/first_flight_session.gd")
const PreparedCargo=preload("res://src/simulation/flight_cargo.gd")
const PreparedTargeting=preload("res://src/simulation/mining_targeting.gd")
const PreparedApproach=preload("res://src/simulation/mining_approach.gd")
const PreparedMining=preload("res://src/simulation/mining_session.gd")
const PreparedDrill=preload("res://src/simulation/mining_drill.gd")
const PreparedNotices=preload("res://src/simulation/flight_notices.gd")
const PreparedStation=preload("res://src/content/station_exterior_resources.gd")
const PreparedAutopilot=preload("res://src/simulation/station_autopilot.gd")
const PreparedTargetArt=preload("res://src/presentation/flight_target_frame.gd")
const PreparedScanArt=preload("res://src/presentation/flight_scan_animation.gd")
const PreparedPlayerDeath=preload("res://src/simulation/player_destruction.gd")
const PreparedDeathResources=preload("res://src/content/npc_destruction_resources.gd")
const PreparedEncounter=preload("res://src/simulation/full_hold_encounter.gd")
const PreparedParticles=preload("res://src/simulation/full_hold_particles.gd")
const PreparedFrame=preload("res://src/simulation/first_flight_frame.gd")
const PreparedGeometry=preload("res://src/presentation/full_hold_encounter_geometry.gd")
const PreparedScene=preload("res://src/presentation/first_flight_scene.gd")
const PreparedAudio=preload("res://src/presentation/opening_audio.gd")
var training_scene: Node3D
var training_sound: Node3D

func training_arguments() -> PackedStringArray:
	return preload("res://tests/fixtures/model_capture.gd").arguments()

func run():
	var args:=training_arguments()
	check(args.size() in [3,4],"Expected content, bindings, visuals and optional captures")
	if args.size() in [3,4]:
		verify(args.slice(0,3))
		if is_instance_valid(training_scene):training_scene.free()
		if is_instance_valid(training_sound):training_sound.free()
		if failures==0:await verify_training_application(args)
	if is_instance_valid(training_scene):training_scene.free()
	if is_instance_valid(training_sound):training_sound.free()
	if is_instance_valid(host):host.free()
	print("Combat-training flight: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_training_destruction(args: PackedStringArray, equipment: RefCounted):
	super.verify_training_destruction(args,equipment)
	if bindings.combat_training_story.is_empty():return
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var capture:=Scenario.new()
	check(capture.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)!=null,capture.error)
	var station: RefCounted=capture.station_owner(bindings,cat)
	if station==null:check(false,capture.error);return
	var before: Dictionary=station.snapshot()
	var packet: Dictionary=station.prepare_departure(bindings,cat)
	check(not packet.is_empty(),station.error)
	if packet.is_empty():return
	check(station.snapshot()==before,"Departure preparation changed the acknowledged station")
	check(packet.size()==18 and packet.confirmation_required and packet.confirmation_text_id==386,"Training lost the normal departure confirmation")
	check(packet.loadout.equipment_ids==[22,90,81,55] and packet.cargo.entries==[{"item_id":0,"quantity":1}] and packet.cargo_used==1,"Departure discarded the equipped or spare weapon")
	check(packet.player.vitals.hull==95 and packet.player.vitals.armor==40 and packet.player.vitals.shield==0 and packet.player.gamma==100,"Training did not use the source departure pool reset")
	check(packet.progress==before.progress and packet.mission==before.mission,"Preparing departure granted progress or changed the mission")
	var unack: RefCounted=station.fork();unack._state.equipment_acknowledged=false
	check(unack.prepare_departure(bindings,cat).is_empty(),"Unacknowledged equipment departure was accepted")
	var bodies:=PreparedBodies.new();var effects:=PreparedEffects.new()
	check(bodies.configure(lib,bindings) and effects.configure(lib,bindings),bodies.error+effects.error)
	var flight:=PreparedTraining.new()
	check(flight.prepare(bindings,cat,packet,1789100000,1789100000,true,bodies,effects,equipment),flight.error)
	var state:=flight.snapshot()
	if state.is_empty():return
	check(state.location.campaign_cursor==7 and state.location.station_id==78 and state.location.system_id==15 and state.location.equipment_ids==packet.loadout.equipment_ids,"Training environment reverted to the unarmed replacement ship")
	check(state.player_pose.origin==Vector3(10,10,10000) and state.player_yaw_units==-1600,"Training inherited the wrong placement or yaw")
	check(state.environment_object=={"resource_id":16994,"position":Vector3(-3286,-8199,56915)} and state.before_yaw_random_state=={"state":48304870645230} and state.yaw_random_state=={"state":219906188857953},"Training environment or yaw consumed the wrong random stream")
	check(state.scenery.world_initialization.input_random_state=={"state":153548941033574} and state.camera_input_random_state=={"state":29269289608543},"Training camera did not follow the field and all four NPC constructors")
	check(state.camera_offset==Vector3(-517,1339,9000) and state.random_state=={"state":271576659757395},"Training camera duplicated or omitted an offset/sign draw")
	check(state.scenery.world_initialization.npc_construction.actors.size()==4 and state.scenery.objects.size()==130,"Prepared training population is incomplete")
	var owned: RefCounted=flight.equipment_owner();check(owned.transact("unmount",22),owned.error)
	check(flight.equipment_owner().snapshot()==equipment.snapshot() and station.snapshot()==before,"Mutable departure equipment escaped into its source owner")
	for key in ["cargo_used","cargo","equipment","loadout","progress","mission","player_cache"]:
		var broken:=packet.duplicate(true);broken[key]=-1 if key=="cargo_used" else {}
		check(not flight.prepare(bindings,cat,broken,1789100000,1789100000,true,bodies,effects,equipment) and flight.snapshot()==state,"Rejected departure changed the previous prepared world: "+key)
	check(not flight.prepare(bindings,cat,packet,1789100000,1789100000,true,bodies,effects) and flight.snapshot()==state,"Missing native equipment was reconstructed from packet data")
	verify_training_services(cat,flight,packet)
	verify_training_player_death(cat,flight,packet)
	verify_training_particles(cat,flight,packet)
	verify_training_frame(cat,flight,packet)
	var briefing:=TrainingBriefing.new();check(briefing.configure(bindings,lib,flight,"Space","Tab"),briefing.error)
	if briefing.snapshot().is_empty():return
	for i in 46:check(briefing.advance(150),briefing.error)
	check(briefing.advance(100) and not briefing.snapshot().entry_released,"Training entry released at 7000ms")
	check(briefing.advance(1) and briefing.snapshot().entry_released and not briefing.snapshot().dialogue.visible,"Entry release also displayed the modal")
	for i in 32:check(briefing.advance(150),briefing.error)
	check(briefing.advance(50) and not briefing.snapshot().dialogue.visible,"Training briefing opened at 5000ms HUD time")
	check(briefing.advance(1) and briefing.snapshot().dialogue.visible and briefing.snapshot().dialogue.text_id==int(bindings.combat_training_story.briefing_events[0].text_id),"Training briefing did not wait for entry release and its HUD poll")
	var held:=briefing.snapshot()
	check(briefing.advance(150) and briefing.simulation_delta_ms()==0 and briefing.snapshot()==held,"Training modal instructions auto-dismissed or advanced the flight")
	check(briefing.navigate("next") and briefing.snapshot().dialogue.text_id==int(bindings.combat_training_story.briefing_events[1].text_id),"Training marker explanation was skipped")
	check(briefing.navigate("next") and briefing.snapshot().dialogue.text_id==int(bindings.combat_training_story.briefing_events[2].text_id) and briefing.snapshot().dialogue.desktop_text_id==bindings.desktop_text_id(int(bindings.combat_training_story.briefing_events[2].text_id)),"Training fire controls were substituted twice")
	check(briefing.navigate("previous") and briefing.navigate("next"),briefing.error)
	if bindings.combat_training_story.briefing_events.size()==4:
		check(briefing.navigate("next") and briefing.snapshot().dialogue.text_id==1742 and briefing.snapshot().dialogue.desktop_text_id==1743,"Training omitted or remapped the fourth instruction twice")
		check(briefing.snapshot().dialogue.desktop_text.contains("Tab") and not briefing.snapshot().dialogue.desktop_text.contains("#KEY_"),"Fast Forward instruction lost its supplied key label")
		held=briefing.snapshot()
		check(briefing.advance(150) and briefing.snapshot()==held and briefing.simulation_delta_ms()==0,"Fourth training instruction did not retain its modal hold")
	check(briefing.navigate("next"),briefing.error)
	check(briefing.snapshot().acknowledged and not briefing.snapshot().dialogue.visible and briefing.snapshot().mission==packet.mission and briefing.snapshot().progress==packet.progress,"Briefing acknowledgement completed the combat mission")
	check(TrainingSession.supported(bindings,7)==not StoryRules.station_return(bindings).is_empty(),"Training availability omitted its complete return requirement")

func verify_training_services(cat: RefCounted, flight: RefCounted, packet: Dictionary):
	var cargo:=PreparedCargo.new();check(cargo.configure_departure(bindings,cat,flight),cargo.error)
	check(cargo.snapshot()==packet.cargo and cargo.snapshot().free_space==24,"Training cargo was treated as a fresh empty mining hold")
	var copied: RefCounted=cargo.fork_for_frame()
	check(copied.add_entries([{"item_id":0,"quantity":1}]) and copied.snapshot().used==2 and cargo.snapshot()==packet.cargo,"Training cargo merges changed the original hold")
	var frame:=PreparedTargetArt.source_geometry(lib,bindings)
	var animation:=PreparedScanArt.source_geometry(lib,bindings,bindings.mining_targeting)
	check(not frame.has("error") and not animation.has("error"),"Training acquisition art is unavailable")
	if frame.has("error") or animation.has("error"):return
	var selection:=PreparedTargeting.new()
	check(selection.configure(bindings,cat,flight,PreparedTargetArt.logical_radii(frame.quarter_size,false),animation.frames),selection.error)
	var approach:=PreparedApproach.new();check(approach.configure(bindings,cat,flight),approach.error)
	var mining:=PreparedMining.new();check(mining.configure(bindings,cat,flight,false),mining.error)
	var scenery: RefCounted=flight.scenery_owner();var index:=-1
	for body in scenery.snapshot().bodies.objects:
		if body.source_size_value>=4:index=int(body.index);break
	check(index>=0,"Prepared source field has no mining candidate")
	if index>=0:
		var drill:=PreparedDrill.new()
		check(drill.configure_for_scenery(bindings,cat,packet.loadout.equipment_ids,scenery,index,Vector2.ZERO),drill.error)
	var notices:=PreparedNotices.new();check(notices.configure(bindings,lib,flight,cat),notices.error)
	var station:=PreparedStation.new();check(station.configure(lib,bindings,cat,flight),station.error)
	var autopilot:=PreparedAutopilot.new();check(autopilot.configure(bindings,cat,flight,station),autopilot.error)
	check(station.snapshot().station_id==78 and not autopilot.snapshot().active,"Training lost its station or started autopilot on entry")

func verify_training_player_death(cat: RefCounted, flight: RefCounted, packet: Dictionary):
	var reference: Dictionary=flight.snapshot()
	var resources:=PreparedDeathResources.new()
	check(resources.configure_combat_training(lib,bindings),resources.error)
	var death:=PreparedPlayerDeath.new();check(death.configure(bindings,resources,flight),death.error)
	if death.snapshot().is_empty():return
	var player: RefCounted=flight.player_owner();var pose: Transform3D=reference.player_pose
	check(not death.start(player,pose,Vector3.ZERO,reference.camera_view.pose,7),"Living training player began destruction")
	var guns:=TrainingGuns.new()
	check(guns.configure_combat_training(bindings,cat,flight.scenery_owner().world_initialization_owner(),int(packet.progress.rank),.5),guns.error)
	var weapon: Dictionary=guns.snapshot().actors[0].projectiles.weapon
	check(player.set_permissions(true,true),player.error)
	# Explicit lethal-contact fixture: feed the actual pirate weapon through
	# normal player damage. This does not claim a complete flight playthrough.
	var hits:=0
	while player.snapshot().vitals.hull>0 and hits<100:
		check(not player.weapon_hit(weapon,true,true,false).is_empty(),player.error);hits+=1
	check(player.snapshot().vitals.hull==0 and player.snapshot().vitals.armor==0,"Pirate contact did not exhaust the equipped training pools")
	check(not death.start(player,pose,Vector3.ZERO,reference.camera_view.pose,9),"Training death accepted an unsupported later mission")
	check(death.start(player,pose,Vector3.ZERO,reference.camera_view.pose,7),death.error)
	var initial:=death.snapshot()
	check(initial.departure_cursor==7 and initial.campaign_cursor==7 and initial.equipment_ids==packet.loadout.equipment_ids and not initial.statistics_active and not initial.camera_follow_enabled,"Training death lost its equipped player or camera handoff")
	var random: Dictionary=reference.random_state
	check(not death.advance(150,pose,random,true).is_empty() and death.snapshot()==initial,"Paused training death advanced")
	for i in 30:
		var step: Dictionary=death.advance(100,pose,random)
		check(not step.is_empty(),death.error)
		if step.is_empty():return
		random=step.random_state
	check(death.snapshot().elapsed_ms==3000 and death.snapshot().events.breakup and not death.snapshot().body_visible and death.snapshot().effect.active,"Training player breakup lost the shared 3000ms boundary")
	check(death.snapshot().events.sound_events.size()==1 and death.snapshot().events.sound_events[0] in [18,19],"Training player used NPC tumble sound")
	var returning:=PreparedPlayerDeath.new();check(returning.configure(bindings,resources,flight),returning.error)
	check(returning.start(player,pose,Vector3.ZERO,reference.camera_view.pose,8),"Source training return cursor lost player death support")
	check(flight.snapshot()==reference and flight.equipment_owner().snapshot()==packet.equipment,"Detached lethal fixture changed the earned departure")

func verify_training_particles(cat: RefCounted, flight: RefCounted, packet: Dictionary):
	var reference: Dictionary=flight.snapshot()
	var player: RefCounted=flight.player_owner();var scenery: RefCounted=flight.scenery_owner()
	var encounter:=PreparedEncounter.new()
	check(encounter.configure_combat_training(bindings,cat,lib,player,scenery,int(packet.progress.rank),.5),encounter.error)
	var death:=PreparedPlayerDeath.new();check(death.configure(bindings,encounter.destruction_resources(),flight),death.error)
	var particles:=PreparedParticles.new()
	check(particles.configure(bindings,encounter.snapshot().combat,death,1789100000),particles.error)
	var initial:=particles.snapshot()
	if initial.is_empty():return
	check(initial.owners.keys()==["player","npc0","npc1","npc2","npc3","world"] and initial.owners.npc3.mode==0,"Training particles lost Gunant's initial ordinary mode or actor order")
	for id in 4:
		var row: Dictionary=initial.owners["npc%d"%id]
		check(not row.trail.enabled and not row.smoke.enabled and not row.fire.enabled,"Healthy training NPC emitted damage effects")
	check(particles.advance(reference.player_pose,0) and particles.snapshot()==initial,"Zero-time training particles consumed an emitter step")
	# Move only the fixture player close enough for the normal zero-time NPC
	# activation, then apply normal damage. Inactive NPCs ignore weapon hits.
	var pose:=Transform3D(Basis.IDENTITY,Vector3(10000,7000,160000))
	var activated: Dictionary=encounter.evaluate_world(player,pose,0,reference.random_state)
	check(not activated.is_empty(),encounter.error)
	if activated.is_empty():return
	check(particles.finish_npc_pass(encounter.snapshot().combat,activated.encounter.snapshot().combat,activated.encounter.snapshot().actor_events,0,1.0),particles.error)
	encounter=activated.encounter
	# Explicit lethal fixture through normal NPC damage. The retained encounter
	# still owns all guidance, tumble, breakup and actor ordering; no mission or
	# complete-flight coverage is implied by placing these hits here.
	for id in 3:check(not encounter._combat.normal_hit(id,9999999).is_empty(),encounter._combat.error)
	var random: Dictionary=activated.random_state
	for tick in 22:
		var before: Dictionary=encounter.snapshot().combat
		check(particles.advance(reference.player_pose,150),particles.error)
		var previous:=particles.snapshot()
		var result: Dictionary=encounter.evaluate_world(player,pose,150,random)
		check(not result.is_empty(),encounter.error)
		if result.is_empty():return
		var after: Dictionary=result.encounter.snapshot()
		var broken: Array=after.actor_events.duplicate(true);broken[3].movement.root_pose="invalid"
		check(not particles.finish_npc_pass(before,after.combat,broken,150,1.0) and particles.snapshot()==previous,"Last-actor particle failure retained earlier flags or roots")
		check(particles.finish_npc_pass(before,after.combat,after.actor_events,150,1.0),particles.error)
		encounter=result.encounter;random=result.random_state
		var state:=particles.snapshot()
		if tick==0:
			for id in 3:
				var key:="npc%d"%id
				check(state.owners[key].trail.enabled and state.owners[key].smoke.enabled and state.owners[key].fire.enabled and state.owners[key].trail.cursor==0,"NPC death emitted before the next early manager pass")
		if tick==1:
			for id in 3:
				var key:="npc%d"%id
				check(state.owners[key].trail.cursor==1 and state.owners[key].trail.baseline==previous.owners[key].trail.baseline and state.owners[key].trail.baseline!=state.owners.npc3.trail.baseline,"Training trails shared another ship's retained root")
	var final:=particles.snapshot()
	for id in 3:
		var row: Dictionary=final.owners["npc%d"%id]
		check(row.death_phase=="explosion" and not row.trail.enabled and not row.smoke.enabled and not row.fire.enabled,"Pirate breakup did not stop its independent emitters")
	check(not final.owners.npc3.damaged and not final.owners.npc3.trail.enabled and final.owners.npc3.trail.cursor==0 and final.owners.npc3.root_pose!=initial.owners.npc3.root_pose,"Gunant's healthy moving emitter root was replaced by a pirate's death state")
	check(final.elapsed_ms==3300 and flight.snapshot()==reference,"Particle fixture changed its construction or advanced the wrong clock")

func verify_training_frame(cat: RefCounted, flight: RefCounted, packet: Dictionary):
	var world:=PreparedFrame.new()
	check(world.configure(bindings,cat,lib,flight,"F",.5),world.error)
	if world.snapshot().is_empty():return
	var initial:=world.snapshot()
	check(initial.actors.size()==4 and initial.ship_detail.selections.size()==5 and initial.radio.started==[false,false],"Training frame omitted an actor, LOD owner or radio")
	check(initial.npc_scanner.equipment_id==81 and initial.npc_scanner.duration_ms==4000 and not initial.npc_scanner.visible,"Training scanner did not use the equipped source device")
	verify_training_scanner(world)
	training_scene=PreparedScene.new();root.add_child(training_scene)
	check(training_scene.build(lib,bindings,visuals,cat,world),training_scene.error)
	if training_scene.camera==null:return
	training_sound=PreparedAudio.new();root.add_child(training_sound)
	check(training_sound.configure_full_hold(lib,bindings,world,42),training_sound.error)
	if not accept_training_presentation(world):return
	check(world.evaluate(150,Vector2.ZERO,1,true).snapshot()==initial,"Paused training flight advanced")
	for i in 47:
		world=training_frame_step(world,150)
		if world==null:return
	check(world.snapshot().entry_released and not world.snapshot().dialogue.visible and world.snapshot().player.damage_allowed,"Shared training entry did not release control and damage")
	while not world.dialogue_visible():
		world=training_frame_step(world,150)
		if world==null:return
	check(world.snapshot().dialogue.text_id==int(bindings.combat_training_story.briefing_events[0].text_id),"Shared training frame omitted the briefing")
	var before:=world.snapshot()
	var modal: RefCounted=world.evaluate(150,Vector2.ONE,1,false,Vector2i.ZERO,Vector2.ZERO,true)
	check(modal!=null,world.error)
	if modal==null:return
	check(modal.snapshot().random_state==before.random_state and modal.snapshot().player_pose==before.player_pose and modal.snapshot().encounter.elapsed_ms==before.encounter.elapsed_ms and modal.snapshot().encounter.primary_fire.is_empty(),"Modal training frame moved, fired or consumed world time")
	for i in bindings.combat_training_story.briefing_events.size():
		var next: RefCounted=world.navigate("next");check(next!=null,world.error)
		if next==null:return
		world=next
		if not accept_training_presentation(world):return
	check(world.snapshot().campaign_cursor==7 and not world.dialogue_visible() and not world.snapshot().combat_objective_acknowledged,"Briefing completed training")
	verify_training_route_frame(world)
	verify_fast_forward_frame(world)
	# Disclosed close-placement fixture, preserving all source NPC construction,
	# loadout and normal activation. This is not an unmodified playthrough.
	world._pose=Transform3D(Basis.IDENTITY,Vector3(10000,7000,160000));world._statistics_pose=world._pose
	world=training_frame_step(world,0)
	if world==null:return
	var activated:=world.snapshot()
	check(activated.actors.slice(0,3).all(func(actor):return actor.active) and activated.radio.started==[true,false],"Accepted NPC activation was not visible to this frame's radio")
	var fired: RefCounted=world.evaluate(150,Vector2.ZERO,0,false,Vector2i.ZERO,Vector2.ZERO,true)
	check(fired!=null,world.error)
	if fired==null:return
	var shooting: Dictionary=fired.snapshot()
	check(not shooting.encounter.primary_fire.is_empty() and shooting.encounter.primary_fire.weapons[0].result.fired and shooting.encounter.primaries.guns[0].projectiles.available_slots==24,"Late training input did not fire the mounted weapon")
	check(world.snapshot()==activated,"Prospective training fire changed its accepted input world")
	world=fired
	if not accept_training_presentation(world):return
	# Normal damage feeds the real tumble/breakup owners. Mission completion
	# must wait for their mode4 transitions and the HUD poll, then acknowledgement.
	for id in 3:check(not world._encounter._combat.normal_hit(id,9999999).is_empty(),world._encounter._combat.error)
	world=training_frame_step(world,0)
	if world==null:return
	check(not world.snapshot().combat_objective_satisfied and world.snapshot().campaign_cursor==7,"Zero hull skipped pirate tumble and mission polling")
	var frames:=0
	while not world.dialogue_visible() and frames<80:
		world=training_frame_step(world,150);frames+=1
		if world==null:return
	var completion:=world.snapshot()
	check(completion.dialogue.visible and completion.dialogue.text_id==int(bindings.combat_training_story.completion_events[0].text_id) and completion.combat_objective_satisfied and completion.campaign_cursor==7,"Training did not offer its five completion lines after the three explosions")
	check(completion.progress.player_kills==packet.progress.player_kills+3 and completion.progress.pirate_kills==packet.progress.pirate_kills+3,"Training lost earned pirate kill attribution")
	check(not completion.equipment.get("training_inventory_released",false),"Showing completion dialogue released protected inventory")
	if not completion.dialogue.visible:return
	for i in 5:
		var next: RefCounted=world.navigate("next");check(next!=null,world.error)
		if next==null:return
		world=next
		if not accept_training_presentation(world):return
	var returning:=world.snapshot()
	check(returning.get("player_route",{}).is_empty() and (training_scene.waypoint_marker==null or not training_scene.waypoint_marker.visible),"Acknowledged completion retained the player route")
	check(returning.campaign_cursor==8 and returning.mission=={"kind":11,"station_id":78,"reward":0,"bonus":0} and returning.combat_objective_acknowledged and not returning.cargo_objective_acknowledged,"Training acknowledgement changed cargo progress or selected the wrong return")
	check(returning.equipment.training_inventory_released and returning.equipment.protected_item_ids==[] and returning.equipment.cargo==packet.cargo,"Training acknowledgement discarded cargo or failed to release protected items")
	var prices: Array=returning.equipment.prices.installed
	for index in prices.size():
		if prices[index]!=null:
			var values: Array=cat.tables.items[index].arrays[2]
			check(prices[index].unit_price==int(values[15])+int((int(values[17])-int(values[15]))/2.0),"Installed price used item identity instead of the actual slot position")
	var geometry:=PreparedGeometry.new();root.add_child(geometry)
	check(geometry.build(world.encounter_owner(),lib,visuals,bindings),geometry.error)
	if geometry.actors.size()==4:
		var prepared: Dictionary=geometry.prepare_world(world.encounter_owner(),returning.camera_view.pose,returning.ship_detail)
		check(not prepared.is_empty(),geometry.error)
		if not prepared.is_empty():
			geometry.commit_world(prepared)
			check(geometry.actors[3].hull.get_meta("source_ship_id")==30 and geometry.actors[3].engine.get_meta("source_resource_id")==18030,"Gunant used the pirate hull or engine")
			var invalid: Dictionary=returning.ship_detail.duplicate(true);invalid.selections.erase(3)
			var pose: Transform3D=geometry.actors[0].hull.transform
			check(geometry.prepare_world(world.encounter_owner(),returning.camera_view.pose,invalid).is_empty() and geometry.actors[0].hull.transform==pose,"Last-actor presentation failure changed an accepted hull")
	geometry.free()
	# Close placement at the actual station only reduces travel time. Normal
	# autopilot selection, the pre-motion contact and station volume gate remain.
	world._pose=Transform3D(Basis.IDENTITY,Vector3(0,0,10000));world._statistics_pose=world._pose
	world=training_frame_step(world,0)
	if world==null:return
	var inbound: RefCounted=world.start_station_autopilot();check(inbound!=null,world.error)
	if inbound==null:return
	world=training_frame_step(inbound,0)
	if world==null:return
	var arrival:=world.prepare_station();check(not arrival.is_empty(),world.error)
	if arrival.is_empty():return
	check(arrival.campaign_cursor==8 and arrival.loadout==packet.loadout and arrival.cargo==packet.cargo and arrival.equipment==returning.equipment,"Training docking lost its loadout, cargo or released inventory")
	check(arrival.progress==returning.progress and arrival.mission==returning.mission,"Training docking granted unearned progress or rewards")
	if not StoryRules.station_return(bindings).is_empty():verify_training_station_return(cat,world)

func verify_training_station_return(cat: RefCounted, world: RefCounted):
	var station:=preload("res://src/simulation/station_entry.gd").new()
	check(station.configure_return(bindings,cat,lib,world),station.error)
	if station.snapshot().is_empty():return
	var before: Dictionary=station.snapshot()
	check(before.campaign_cursor==8 and before.cargo==world.snapshot().cargo and before.equipment==world.equipment_owner().snapshot() and before.source_marked_item_ids==[],"Training station return discarded or reprotected the earned equipment")
	var reload:=preload("res://src/simulation/station_entry.gd").new()
	check(not reload.configure_reload(bindings,cat,lib,station),"Station reloaded before the return was acknowledged")
	for i in 9:
		check(station.snapshot().dialogue.text_id==int(bindings.combat_training_story.station_return.events[i].text_id) and station.snapshot().campaign_cursor==8,"Training station conversation skipped a line or advanced early")
		check(station.acknowledge(),station.error)
	var accepted: Dictionary=station.snapshot()
	check(accepted.phase=="station_reload_required" and accepted.campaign_cursor==9 and accepted.cargo==before.cargo and accepted.equipment==before.equipment and accepted.reward_credits==0,"Station acknowledgement lost cargo, changed equipment or skipped the reload")
	check(accepted.progress.rank_score==before.progress.rank_score+int(bindings.opening_handoff.cursor_weight) and accepted.progress.player_kills==before.progress.player_kills,"Return acknowledgement changed kill credit or counted its cursor twice")
	check(reload.configure_reload(bindings,cat,lib,station),reload.error)
	var restored: Dictionary=reload.snapshot()
	check(restored.phase=="station_followup_required" and restored.boundary=="station_followup_required" and restored.station_reloaded and restored.campaign_cursor==9 and restored.player_cache==accepted.player_cache and restored.cargo==accepted.cargo and restored.equipment==accepted.equipment,"Station reload lost the retained player or inventory")
	check(not reload.acknowledge() and reload.prepare_departure(bindings,cat).is_empty() and reload.snapshot()==restored,"Unsupported station follow-up advanced or launched")
	after_training_reload(cat,reload)

func after_training_reload(_cat: RefCounted, _station: RefCounted):
	pass

func verify_training_scanner(world: RefCounted):
	var scanner: RefCounted=world._scanner.fork_for_frame()
	var combat: Dictionary=world.snapshot().encounter.combat.duplicate(true)
	for actor in combat.actors:
		actor.active=true;actor.pose=Transform3D(Basis.IDENTITY,Vector3(0,0,-1000))
	var aim:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400,300,-1000),"viewport_size":Vector2i(800,600)}
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,4000,true),scanner.error)
	check(scanner.snapshot().candidate_actor_id==0 and scanner.snapshot().selected_actor_id==-1 and scanner.snapshot().elapsed_ms==4000,"Training scanner skipped source population order or acquired at equality")
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,1,true),scanner.error)
	check(scanner.snapshot().selected_actor_id==0 and scanner.snapshot().events==[{"kind":"sound","source_id":26,"actor_id":0}],"Starter scanner invented cargo inspection or lost acquisition audio")
	for id in 3:combat.actors[id].actor_mode=4
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,4001,true),scanner.error)
	check(scanner.snapshot().selected_actor_id==3 and scanner.snapshot().markers.size()==1 and not scanner.snapshot().markers[0].hostile,"Friendly mode-zero Gunant was omitted after pirate destruction")
	var held: Dictionary=scanner.snapshot()
	combat.actors[3].hull_catalogue_id=2
	check(not scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true) and scanner.snapshot()==held,"Training scanner accepted a pirate hull for Gunant")

func prepare_application_locations(cat: RefCounted) -> bool:
	# Keep the existing earned equipment fixture, but seed its earlier cache
	# through a real rescue session and the application's first station entry.
	# The completed opening input remains an explicitly declared three-kill fixture.
	var player: RefCounted=load("res://src/simulation/opening_player_state.gd").new()
	if not player.configure(bindings,cat):check(false,player.error);return false
	var handoff: RefCounted=load("res://src/simulation/opening_handoff.gd").new()
	var opening: Dictionary=load("res://tests/opening_handoff_fixture.gd").completed(bindings,player,3)
	var packet: Dictionary=handoff.prepare(bindings,cat,opening)
	var rescue: Node3D=load("res://src/presentation/arrival_session.gd").new()
	host.viewport.add_child(rescue);host.session=rescue
	if not rescue.configure(lib,bindings,visuals,packet,0,1789100000):check(false,rescue.error);return false
	for i in 500:
		if rescue.status!="running":break
		if not rescue.step((i+1)*100000):check(false,rescue.error);return false
	var before: Dictionary=rescue.snapshot()
	if not host.enter_station(60000000,42):check(false,host.status.text);return false
	var locations: Dictionary=host.locations_snapshot()
	check(locations.locations[0].population.initial_random==before.scenery.random_state,"First station contacts lost the live rescue random stream")
	check(locations.locations[0].population.context.campaign_cursor==1,"First station contacts were generated at another campaign cursor")
	host.session.free();host.session=null
	return true

func verify_training_application(args: PackedStringArray):
	if not TrainingSession.supported(bindings,7):return
	# Restore the prerequisite captured by the actual equipment tutorial. All
	# subsequent input and transitions use the application's normal session.
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var scenario:=Scenario.new();check(scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)!=null,scenario.error)
	var owner: RefCounted=scenario.station_owner(bindings,cat)
	if owner==null:check(false,scenario.error);return
	root.size=Vector2i(1280,720)
	host=Host.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.set_context(lib,bindings,visuals);host.set_process(false)
	for i in 3:await process_frame
	if bindings.early_contracts.has("station_generation") and not prepare_application_locations(cat):return
	var station:=Station.new();host.viewport.add_child(station);host.session=station;station._world=owner
	now_us=0
	if not station._build_scene(lib,bindings,visuals,cat,now_us,42) or not host.station_panel.configure(lib,bindings,visuals) or not station.activate():check(false,station.error+host.station_panel.error);return
	station._dialogue_started=true
	await restore_test_focus()
	station.rebase_time(now_us)
	if bindings.early_contracts.has("station_generation"):
		# The equipment fixture skips intervening same-location mining sessions.
		# They do not regenerate the first Var Hastra population.
		check(host.locations_snapshot().locations.size()==1 and host.locations_snapshot().locations[0].station_id==78,"Training setup lost the first station population")
	host.present_session()
	var accepted: Dictionary=station.snapshot()
	check(host._launch_button.visible and not host._pause_button.visible and host.request_departure(),"Ready training station did not offer its normal departure confirmation")
	var packet: Dictionary=host._launch_packet.duplicate(true)
	host.cancel_departure()
	check(station.snapshot()==accepted and not host.enter_first_flight(now_us),"Cancelled training departure changed the station")
	var textures: Dictionary=visuals.textures;visuals.textures={}
	check(host.request_departure() and not host.enter_first_flight(now_us,1789100000,1789100000) and host.session==station and station.snapshot()==accepted,"Failed training preparation lost the equipped station")
	visuals.textures=textures
	check(host.retry_transition() and host.enter_first_flight(now_us,1789100000,1789100000),host.status.text)
	if not host.session is TrainingSession:return
	host.session.rebase_time(now_us)
	check(not is_instance_valid(station) and host.session.snapshot().equipment==packet.equipment and host.session.flight_audio!=null,"Training departure lost its native equipment or audio")
	for i in 140:
		if host.session.snapshot().dialogue.visible:break
		if not training_app_step():return
	check(host.session.snapshot().dialogue.text_id==int(bindings.combat_training_story.briefing_events[0].text_id) and host.session.briefing_audio.snapshot().history.back().source_id==189,"Training session omitted its source briefing and voice")
	if args.size()==4:
		await capture(args[3],"training-app-briefing")
		await capture_phone(args[3],"training-app-briefing-phone")
	for i in bindings.combat_training_story.briefing_events.size():
		if args.size()==4 and i==3:await capture(args[3],"training-app-fast-forward-instruction")
		key(KEY_ENTER)
		check(host.session.error.is_empty(),host.session.error)
		if not host.session.error.is_empty():return
	check(host.session.can_control() and host.session.snapshot().campaign_cursor==7,"Training briefing failed to release the actual controls")
	if not host.session.can_control():return
	await verify_fast_forward_input(args)
	key_down(KEY_SPACE)
	check(host._controls.snapshot().held.fire and host.session.snapshot().mining_approach.phase=="idle","Primary input was consumed as a mining action")
	if not training_app_step():return
	check(host.session.snapshot().encounter.primary_fire.weapons[0].result.fired,"Held keyboard fire did not reach the training session")
	key_up(KEY_SPACE)
	key(KEY_ESCAPE);var paused: Dictionary=host.session.snapshot()
	if not training_app_step():return
	check(host.session.snapshot()==paused and not host._controls.snapshot().held.fire,"Paused training advanced or kept fire held")
	key(KEY_ESCAPE);host.session.rebase_time(now_us)
	# Actual trigger input, then a disclosed close placement for activation.
	var event:=InputEventJoypadMotion.new();event.device=7;event.axis=JOY_AXIS_TRIGGER_RIGHT;event.axis_value=.9;host._unhandled_input(event)
	# Either tutorial starter gun may be mounted; each has its own cooldown.
	for i in 30:
		if not training_app_step():return
		if host.session.snapshot().encounter.primary_fire.weapons[0].result.fired:break
	check(host.session.snapshot().encounter.primary_fire.weapons[0].result.fired,"Held controller trigger did not fire after the source cooldown")
	event=InputEventJoypadMotion.new();event.device=7;event.axis=JOY_AXIS_TRIGGER_RIGHT;event.axis_value=0;host._unhandled_input(event)
	var flight: RefCounted=host.session.flight_owner()
	flight._pose=Transform3D(Basis.IDENTITY,Vector3(10000,7000,160000));flight._statistics_pose=flight._pose
	check(host.session._commit(flight,false),host.session.error)
	if not training_app_step():return
	check(host.session.snapshot().radio.started[0] and host.session.snapshot().actors.slice(0,3).all(func(actor):return actor.active),"Training session did not activate its native encounter or radio")
	# Allow the source follow camera to settle after this disclosed placement.
	for i in 20:
		if not training_app_step():return
	if not bindings.ordinary_music.is_empty():
		var music: Dictionary=host.session.flight_audio.snapshot()
		check(bindings.ordinary_music.battle_event_ids.any(func(id):return int(id)==music.music_id) and music.active.has(music.music_id),"Accepted training battle did not play a source combat cue")
	if args.size()==4:
		await capture(args[3],"training-app-encounter")
		await capture_phone(args[3],"training-app-encounter-phone")
	flight=host.session.flight_owner()
	for id in 3:check(not flight._encounter._combat.normal_hit(id,9999999).is_empty(),flight._encounter._combat.error)
	check(host.session._commit(flight,false),host.session.error)
	for i in 100:
		if host.session.snapshot().dialogue.visible:break
		if not training_app_step():return
	check(host.session.snapshot().dialogue.text_id==int(bindings.combat_training_story.completion_events[0].text_id) and host.session.snapshot().campaign_cursor==7,"Training session did not wait for native deaths and completion instructions")
	if not host.session.snapshot().dialogue.visible:return
	for i in 5:
		check(host.session.objective_audio.snapshot().history.back().source_id==439+i,"Training completion used the wrong acknowledged voice")
		key(KEY_ENTER)
	check(host.session.snapshot().campaign_cursor==8 and host.session.snapshot().equipment.training_inventory_released,"Application completion did not release the earned inventory")
	if mine_on_training_return():
		# Mining remains available on the return trip. The ordinary drill earns
		# ore into the same equipped hold without repricing retained inventory.
		var prices: Dictionary=host.session.snapshot().equipment.prices.duplicate(true)
		if not start_second_drill():return
		for i in 500:
			var drill: Dictionary=host.session.snapshot().mining_session.drill
			if drill.is_empty():break
			var desired: Vector2=-(drill.point+(drill.input+drill.drift)*5.0)*.2-drill.drift
			var command:=Vector2.ZERO
			for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1,absf(desired[axis])/3.0))
			if not step(command):return
		var mined: Dictionary=host.session.snapshot()
		check(mined.cargo.used==25 and mined.cargo.entries[0]=={"item_id":0,"quantity":1} and mined.equipment.cargo==mined.cargo and mined.scenery.mined_count==1,"Post-training mining lost the spare weapon or desynchronized equipment cargo")
		check(mined.equipment.prices.installed==prices.installed and mined.equipment.prices.cargo[0]==prices.cargo[0],"Post-training mining repeated the inventory price reset")
	flight=host.session.flight_owner();flight._pose=Transform3D(Basis.IDENTITY,Vector3(0,0,10000));flight._statistics_pose=flight._pose
	check(host.session._commit(flight,false),host.session.error)
	button(JOY_BUTTON_Y)
	check(choose_open_keyboard_flight_action("station_autopilot"),"Controller destination menu did not select station guidance")
	if not training_app_step():return
	check(host.session.status=="station_transition_required","Training application did not accept the normal station contact gate")
	if host.session.status!="station_transition_required":return
	var arrived: Dictionary=host.session.snapshot();var previous: Node=host.session
	textures=visuals.textures;visuals.textures={}
	check(not host.enter_station(now_us,42) and host.session==previous and host.session.snapshot().cargo==arrived.cargo,"Failed training return destroyed the accepted flight")
	visuals.textures=textures
	check(host.retry_transition(),host.status.text)
	if not host.session is Station:return
	host.session.rebase_time(now_us)
	for i in 10:
		if not training_app_step():return
	if args.size()==4:
		await capture(args[3],"training-app-return")
		await capture_phone(args[3],"training-app-return-phone")
	for i in 9:
		check(host.session.snapshot().dialogue.text_id==int(bindings.combat_training_story.station_return.events[i].text_id) and host.session.audio.snapshot().history.back().source_id==444+i,"Training return lost its dialogue or original voice")
		key(KEY_ENTER)
	check(host.session.status=="station_reload_required" and host.session.snapshot().campaign_cursor==9,"Final return acknowledgement skipped source station reload")
	var reloading: Node=host.session;var retained: Dictionary=reloading.snapshot()
	textures=visuals.textures;visuals.textures={}
	check(not host.enter_station(now_us,42) and host.session==reloading and reloading.snapshot()==retained,"Failed reload destroyed the acknowledged station")
	visuals.textures=textures
	check(host.retry_transition(),host.status.text)
	var final: Dictionary=host.session.snapshot()
	var following: bool=not preload("res://src/content/ordinary_flight_definitions.gd").station_conversation(bindings,9).is_empty()
	check(not is_instance_valid(reloading) and final.phase==("conversation" if following else "station_followup_required") and final.equipment==retained.equipment and final.player_cache==retained.player_cache and final.cargo==arrived.cargo,"Application reload lost the earned inventory or player state")
	check(host.session.audio.snapshot().history.is_empty() and not host.request_departure() and not host.session.navigate("next",host.station_panel),"Station reload played speech or accepted input before its delayed conversation")
	host.present_session()
	if args.size()==4:await capture(args[3],"training-app-followup-entry")
	await after_training_application_reload(args)
	await verify_training_game_over(args,packet,owner.equipment_owner())

func verify_fast_forward_frame(world: RefCounted) -> void:
	if not world.fast_forward_available():return
	var original: Dictionary=world.snapshot()
	var branch: RefCounted=world.press_fast_forward()
	check(branch!=null and branch.snapshot().fast_forward.held and not branch.snapshot().fast_forward.active,"Training waypoint alone enabled Fast Forward")
	if branch==null:return
	branch=branch.release_flight_action(true)
	# This detached flight follows normal manual movement away from the station;
	# it neither changes the accepted training position nor earns progress.
	for tick in 160:
		if branch.snapshot().player_pose.origin.length()>35000:break
		var next: RefCounted=branch.evaluate(150)
		check(next!=null,branch.error)
		if next==null:return
		branch=next
	check(branch.snapshot().player_pose.origin.length()>35000,"Fast Forward fixture never reached open space")
	branch=branch.start_station_autopilot()
	if branch==null:check(false,"Cannot start the existing station guidance");return
	branch=branch.press_fast_forward()
	if branch==null:check(false,"Cannot deliver Time to released flight");return
	check(branch.snapshot().fast_forward.active,"Eligible station guidance refused held Time")
	var before: Dictionary=branch.snapshot()
	var expected_guide: RefCounted=branch._autopilot.fork_for_frame()
	check(expected_guide.advance(750,branch._pilot.angular_units.x,1.0),expected_guide.error)
	var advanced: RefCounted=branch.evaluate(150)
	check(advanced!=null,branch.error)
	if advanced==null:return
	var state: Dictionary=advanced.snapshot()
	check(state.player_pose==expected_guide.snapshot().player_pose,"Fast Forward did not perform one 750ms player update")
	check(state.world_phase_elapsed_ms-before.world_phase_elapsed_ms==750 and state.encounter.elapsed_ms-before.encounter.elapsed_ms==750,"Fast Forward capped or duplicated a world/weapon pass")
	check(state.world_elapsed_ms-before.world_elapsed_ms==150 and state.hud_elapsed_ms-before.hud_elapsed_ms==150,"Fast Forward scaled mission or HUD elapsed time")
	check(state.flight_audio.serial==before.flight_audio.serial+1 and state.fast_forward.camera_ms==150 and state.fast_forward.camera_passes==5,"Fast Forward duplicated a complete frame or lost its camera schedule")
	var camera: RefCounted=branch._camera.fork_for_frame()
	for i in 5:check(camera.update(150,advanced._shot,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player_pose":state.player_pose}),camera.error)
	check(state.camera_view==camera.snapshot(),"Connected camera differs from five divided-time follow updates")
	check(branch.snapshot()==before and world.snapshot()==original,"Prospective Fast Forward advanced its accepted parent")
	var released: RefCounted=advanced.release_flight_action(false)
	check(released!=null and released.snapshot().fast_forward.held and not released.snapshot().fast_forward.active,"Another action release cleared Time hold or kept acceleration")
	if released==null:return
	var repeated: RefCounted=released.press_fast_forward()
	check(repeated!=null and not repeated.snapshot().fast_forward.active,"Held input restarted acceleration after another control's release")
	var invalid: RefCounted=branch.fork_for_frame();invalid._targeting._field_identity=RefCounted.new()
	var invalid_before: Dictionary=invalid.snapshot()
	check(invalid.evaluate(150)==null and invalid.snapshot()==invalid_before,"Rejected scaled frame changed its parent timing/input state")
	# Move through actual guidance until the published near flag cancels on the
	# following frame. Do not precompute a fresh threshold before the player pass.
	var approaching: RefCounted=advanced
	var near_seen:=false
	for tick in 80:
		var prior: Dictionary=approaching.snapshot()
		var next: RefCounted=approaching.evaluate(150)
		check(next!=null,approaching.error)
		if next==null:return
		var now: Dictionary=next.snapshot()
		if prior.fast_forward.near_target:
			check(not now.fast_forward.active and now.fast_forward.held and now.world_phase_elapsed_ms-prior.world_phase_elapsed_ms==150,"Near-target cancellation used the new position or cleared Time hold")
			near_seen=true;break
		approaching=next
	check(near_seen,"Guided Fast Forward never reached its verified near boundary")

func verify_fast_forward_input(args: PackedStringArray) -> void:
	if not host.session.fast_forward_available():return
	host.set_touch_controls(false)
	check(not host._time_button.is_visible_in_tree(),"Desktop Time button ignored hidden touch controls")
	key_down(KEY_TAB)
	check(host.session.snapshot().fast_forward.held and not host.session.snapshot().fast_forward.active,"Keyboard Time steered a training waypoint")
	key_up(KEY_TAB)
	check(choose_keyboard_flight_action(KEY_Q,"station_autopilot"),"Q menu did not select station guidance")
	key_down(KEY_TAB)
	check(host.session.snapshot().fast_forward.active,"Keyboard Time did not accelerate existing guidance")
	key_up(KEY_UP)
	check(host.session.snapshot().fast_forward.active,"A steering release was treated as an action-button release")
	key(KEY_SLASH)
	check(host.session.snapshot().fast_forward.held and not host.session.snapshot().fast_forward.active,"Action release did not cancel keyboard acceleration")
	key_up(KEY_TAB);key_down(KEY_TAB)
	check(host.session.snapshot().fast_forward.active,"Fresh keyboard press could not rearm acceleration")
	key(KEY_ESCAPE)
	check(not host.session.snapshot().fast_forward.held and not host.session.snapshot().fast_forward.active,"Pause retained Fast Forward input")
	key(KEY_ESCAPE)
	TouchInput.set_preference(host,true);host.present_session()
	check(host._time_button.is_visible_in_tree() and not host._time_button.disabled,"Enabled touch Time button is unavailable")
	if args.size()==4:
		await capture(args[3],"training-app-time-touch")
		await capture_phone(args[3],"training-app-time-phone")
		TouchInput.set_preference(host,true);host.present_session()
	host._time_button.button_down.emit()
	check(host.session.snapshot().fast_forward.active,"Touch Time down did not reach the session")
	host.set_touch_controls(false)
	host.handle_action_events(host._controls.take_events())
	check(not host.session.snapshot().fast_forward.held and not host.session.snapshot().fast_forward.active,"Hiding touch controls retained accelerated flight")
	key(KEY_BRACKETRIGHT)
	check(choose_keyboard_flight_action(KEY_Q,"cancel_autopilot"),"Q menu did not cancel station guidance")
	check(not host.session.snapshot().station_autopilot.active,"Input fixture left autopilot enabled")

func choose_keyboard_flight_action(opener: int, action: String) -> bool:
	key(opener)
	return choose_open_keyboard_flight_action(action)

func choose_open_keyboard_flight_action(action: String) -> bool:
	if not host.flight_menu.visible:return false
	var rows: Array=host.flight_menu.snapshot().rows
	for index in rows.size():
		if rows[index].action!=action:continue
		key(KEY_1+index)
		return not host.flight_menu.visible
	host.close_flight_menu();return false

func mine_on_training_return() -> bool:
	return true

func after_training_application_reload(_args: PackedStringArray):
	pass

func verify_training_game_over(args: PackedStringArray, packet: Dictionary, equipment: RefCounted):
	# Separate death branch from the same earned departure; source projectile
	# contact starts destruction after a disclosed reduction of the player pools.
	host.reset()
	var session:=TrainingSession.new();host.viewport.add_child(session);host.session=session
	if not session.configure(lib,bindings,visuals,packet,true,now_us,1789100000,1789100000,false,equipment) or not session.activate():check(false,session.error);return
	session.transition_rejected.connect(host.transition_error)
	for i in 140:
		if session.snapshot().dialogue.visible:break
		if not training_app_step():return
	for i in bindings.combat_training_story.briefing_events.size():key(KEY_ENTER)
	var world: RefCounted=session.flight_owner()
	world._pose=Transform3D(Basis.IDENTITY,Vector3(10000,7000,160000));world._statistics_pose=world._pose
	check(session._commit(world,false),session.error)
	if not training_app_step():return
	var fixture:=DeathFixture.new();var dead: RefCounted=fixture.lethal(session.flight_owner())
	check(dead!=null and fixture.failures==0,"Training source projectile did not start the application death branch")
	fixture.free()
	if dead==null:return
	check(session._commit(dead,false),session.error);host.present_session()
	var before: Dictionary=session.snapshot()
	check(not session.can_control() and before.campaign_cursor==7 and not before.combat_objective_acknowledged,"Player destruction advanced training or retained control")
	for reason in ["user","focus","hidden"]:
		session.set_pause(reason,true,now_us)
		check(training_app_step() and session.snapshot()==before and session.flight_audio.snapshot().paused and not session.request_game_over_exit(),"Pause advanced training death or accepted continuation: "+reason)
		session.set_pause(reason,false,now_us)
	var identity: Dictionary=session.scene.game_over._identity.duplicate(true)
	var sound: Dictionary=session.flight_audio.snapshot()
	session.scene.game_over._identity.binding_id="foreign"
	check(not session.step(now_us+100000) and session.snapshot()==before and session.flight_audio.snapshot()==sound,"Rejected training death presentation committed state or sound")
	session.scene.game_over._identity=identity
	key_down(KEY_SPACE)
	for i in 180:
		if session.snapshot().player_destruction.phase=="game_over":break
		if not training_app_step():return
	check(session.snapshot().player_destruction.phase=="game_over" and session.status=="running","Training death did not wait at the game-over acknowledgement")
	if args.size()==4:await capture(args[3],"training-app-game-over")
	key_down(KEY_SPACE)
	check(session.status=="running","Fire held through destruction acknowledged game over")
	key_up(KEY_SPACE);key(KEY_ENTER)
	check(session.status=="game_over_transition_required",session.error)
	check(host.enter_game_over() and host.session==null and host.game_over_result().transition.campaign_cursor==7,"Training game over lost its source menu transition")

func training_app_step() -> bool:
	now_us+=100000
	var controls: Dictionary=host._controls.snapshot()
	if not host.session.step(now_us,controls.command,controls.held.fire):check(false,host.session.error);return false
	host.present_session();return true

func verify_training_route_frame(world: RefCounted) -> void:
	if not world.snapshot().has("player_route"):return
	var original: Dictionary=world.snapshot()
	var branch: RefCounted=world.fork_for_frame()
	var waypoint: Vector3=original.player_route.waypoints[0]
	branch._pose=Transform3D(Basis.IDENTITY,waypoint+Vector3(0,0,-2010));branch._statistics_pose=branch._pose
	var crossing: RefCounted=branch.evaluate(150,Vector2.ZERO,1)
	check(crossing!=null,branch.error)
	if crossing==null:return
	check(absf(crossing.snapshot().player_pose.origin.z-waypoint.z)<2000,"Waypoint timing fixture did not cross its arrival box")
	check(crossing.snapshot().player_route.index==0,"Waypoint used a post-motion position")
	var reached: RefCounted=crossing.evaluate(0,Vector2.ZERO,0)
	check(reached!=null,crossing.error)
	if reached==null:return
	check(reached.snapshot().player_route.index==1 and reached.snapshot().flight_notices.pending.any(func(row):return row.source_id==23 and row.text_ids==[532]),"Waypoint arrival omitted the next point or original notice")
	check(world.snapshot()==original and reached.snapshot().progress==original.progress,"Prospective navigation changed the accepted world or earned progress")

func training_frame_step(world: RefCounted, milliseconds: int) -> RefCounted:
	var next: RefCounted=world.evaluate(milliseconds,Vector2.ZERO,0)
	check(next!=null,world.error)
	if next!=null and not accept_training_presentation(next):return null
	return next

func accept_training_presentation(world: RefCounted) -> bool:
	var audio: Dictionary=training_sound.prepare_full_hold(world)
	check(not audio.is_empty(),training_sound.error)
	if audio.is_empty():return false
	var accepted: bool=training_scene.present(world,false,int(world.snapshot().world_elapsed_ms))
	check(accepted,training_scene.error)
	if not accepted:return false
	training_sound.commit_frame(audio)
	return true
