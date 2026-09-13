extends SceneTree
## Mac live-frame death checks. Departure packets, initial close placements,
## retained input and positioned lethal projectiles are disclosed fixtures.
## Motion, contacts, mining, cargo, death and world phases use native owners.
const Fixture=preload("res://tests/full_hold_control.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
var checks:=0
var failures:=0
var ready: RefCounted
var captures:={}

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	print("Player death flight: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","Mac content is required")
	var fixture:=Fixture.new();var construction:=Construction.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,bodies.error+effects.error);fixture.free();return
	var prepared:=construction.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000,true,bodies,effects)
	fixture.free()
	if not prepared:check(false,construction.error);return
	var initial: Dictionary=construction.snapshot()
	ready=Frame.new()
	if not ready.configure(bindings,cat,lib,construction,"E",.5):check(false,ready.error);return
	if bindings.player_destruction.is_empty():
		check(ready.destruction_owner()==null,"Older flight fabricated destruction support")
		return
	check(ready.destruction_owner().snapshot().phase=="ready" and ready.snapshot().random_state==initial.random_state,"Preparing death advanced its clocks or consumed world randomness")
	for i in 160:
		if ready.dialogue_visible():break
		ready=step(ready,100)
		if ready==null:return
	ready=ready.navigate("next")
	if ready==null:check(false,"Could not acknowledge the source second-flight briefing");return
	var before: Dictionary=ready.snapshot()
	verify_manual()
	verify_guidance()
	verify_mining()
	verify_early_return()
	verify_game_over()
	if not bindings.full_hold_particles.is_empty():verify_particles()
	check(ready.snapshot()==before and construction.snapshot()==initial,"Death branches modified accepted flight or station construction")
	if failures==0:await verify_render(args,lib,bindings,cat)

func step(world: RefCounted, milliseconds: int, command:=Vector2.ZERO, throttle:=1.0, drill:=Vector2.ZERO) -> RefCounted:
	var next: RefCounted=world.evaluate(milliseconds,command,throttle,false,Vector2i.ZERO,drill)
	if next==null:check(false,world.error)
	return next

func lethal(world: RefCounted, milliseconds:=0, command:=Vector2.ZERO, throttle:=1.0, drill:=Vector2.ZERO) -> RefCounted:
	var branch: RefCounted=world.fork_for_frame()
	var gun: RefCounted=branch._encounter._weapons._guns[0]
	var weapon: Dictionary=gun.snapshot().weapon
	while branch._player.snapshot().vitals.hull>1:
		if branch._player.weapon_hit(weapon,true,true,false).is_empty():check(false,branch._player.error);return null
	var contact: Transform3D=branch._pose
	if branch._mining.has_active_drill():
		pass
	elif branch._approach.snapshot().phase!="idle":
		var approach: RefCounted=branch._approach.fork_for_frame()
		if not approach.advance(branch._scenery,milliseconds):check(false,approach.error);return null
		contact=approach.snapshot().player_pose
	elif branch._autopilot.snapshot().active:
		var guide: RefCounted=branch._autopilot.fork_for_frame()
		if not guide.advance(milliseconds,branch._pilot.angular_units.x,throttle):check(false,guide.error);return null
		contact=guide.snapshot().player_pose
	else:
		var pilot: RefCounted=branch._pilot.fork_for_frame()
		contact=pilot.advance(branch._pose,command,throttle,float(milliseconds)/1000.0)
		if not pilot.error.is_empty():check(false,pilot.error);return null
	gun._elapsed_ms=593
	check(gun.fire(contact.origin,Vector3.RIGHT,true).get("fired",false),"Could not position the lethal source projectile")
	var next:=step(branch,milliseconds,command,throttle,drill)
	if next!=null:check(next.snapshot().player.vitals.hull==0 and next.death_active(),"Actual projectile contact did not start destruction")
	return next

func verify_manual():
	var moving: RefCounted=ready.fork_for_frame()
	moving._pilot.angular_units=Vector2(150,-600)
	moving._model_basis=Basis(Vector3.BACK,1.1)
	var before: Dictionary=moving.snapshot()
	var pilot: RefCounted=moving._pilot.fork_for_frame()
	var expected: Transform3D=pilot.advance(before.player_pose,Vector2.ZERO,.8,.1)
	var dead:=lethal(moving,100,Vector2.ONE,.8)
	if dead==null:return
	var entry: Dictionary=dead.snapshot();var death: Dictionary=entry.player_destruction
	check(entry.player_pose==expected and entry.angular_units==pilot.angular_units,"Lethal frame retained commands from the skipped late input pass")
	check(death.model_rotation==Vector3.ZERO and death.elapsed_ms==0 and death.player_updates==0,"Lethal poll advanced the newly created death tail")
	check(death.statistics_pose==expected*Transform3D(before.player_model_basis,Vector3.ZERO) and death.rendered_model_basis==entry.player_model_basis,"Death entry lost the preceding statistics or current bank")
	check(entry.camera_view==before.camera_view and not entry.camera_follow_enabled and not entry.player.active,"Death did not disable the current camera and statistics")
	check(entry.world_phase_elapsed_ms==before.world_phase_elapsed_ms+100 and entry.encounter.elapsed_ms==before.encounter.elapsed_ms+100,"Lethal contact skipped the remaining world phases")
	check(entry.cargo==before.cargo and entry.progress==before.progress and dead.prepare_station().is_empty(),"Death granted cargo, progress or station arrival")
	check(dead.request_game_over_exit()==null and dead.snapshot()==entry,"Early death accepted an exit")
	var paused: RefCounted=dead.evaluate(150,Vector2.ONE,0,true)
	check(paused!=null and paused.snapshot()==entry,"Pause advanced a live death owner")
	var a:=step(dead,100,Vector2.ONE,0)
	var b:=step(dead,100,-Vector2.ONE,1)
	if a==null or b==null:return
	check(a.snapshot()==b.snapshot(),"Dead manual flight accepted new steering or throttle")
	var after: Dictionary=a.snapshot()
	check(after.player_destruction.elapsed_ms==100 and after.player_destruction.model_rotation==Vector3.ONE*0.03 and after.player_model_basis.is_equal_approx(Vectors.local_xyz(Vector3.ONE*0.03)),"First death tail did not replace the bank with stored Euler spin")
	check(after.player_statistics_pose==after.player_pose*Transform3D(entry.player_model_basis,Vector3.ZERO),"Manual death motion sampled the new tumble before statistics")
	check(after.camera_view==entry.camera_view and after.player_pose!=entry.player_pose,"Manual death lost retained motion or moved its frozen camera")
	var invalid: RefCounted=a.fork_for_frame();invalid._targeting._field_identity=RefCounted.new()
	var saved: Dictionary=invalid.snapshot()
	check(invalid.evaluate(100)==null and invalid.snapshot()==saved and a.snapshot()==after,"Late failure partially committed death, player or world state")
	captures.manual_entry=dead;captures.manual_tumble=a

func verify_guidance():
	var flying: RefCounted=ready.start_station_autopilot()
	if flying==null:check(false,ready.error);return
	var dead:=lethal(flying,100)
	if dead==null:return
	var before: Dictionary=dead.snapshot()
	var guide: RefCounted=dead._autopilot.fork_for_frame()
	check(guide.advance(100,dead._pilot.angular_units.x,dead._throttle),guide.error)
	var next:=step(dead,100,Vector2.ONE,0)
	if next==null:return
	var after: Dictionary=next.snapshot()
	check(after.station_autopilot.active and after.player_pose==guide.snapshot().player_pose and after.player_pose!=before.player_pose,"Death cancelled or stopped existing station guidance")
	check(after.player_statistics_pose==after.player_pose*Transform3D(guide.snapshot().model_basis,Vector3.ZERO),"Guided death omitted the current bank's statistics write")
	check(after.player_model_basis.is_equal_approx(Vectors.local_xyz(after.player_destruction.model_rotation)) and after.camera_view==before.camera_view,"Guidance replaced death Euler spin or resumed camera follow")
	check(next.prepare_station().is_empty() and after.cargo==before.cargo and after.progress==before.progress,"Dead guidance fabricated a station transaction")
	captures.guided=next

func drilling() -> RefCounted:
	var world: RefCounted=ready.fork_for_frame();var asteroid:={}
	for body in world.snapshot().scenery.bodies.objects:
		if body.source_size_value==7:asteroid=body;break
	if asteroid.is_empty():check(false,"No source core asteroid is available");return null
	var distance:=float(int(asteroid.scale*2500))-.5
	world._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,distance))
	world._pilot.angular_units=Vector2.ZERO;world._targeting._selected=int(asteroid.index)
	world._autopilot.observe_manual(world._pose,Vector2.ZERO)
	var selected: RefCounted=world.start_mining()
	if selected==null:check(false,world.error);return null
	world=selected
	for i in 200:
		if world.drill_owner()!=null:return world
		world=step(world,100)
		if world==null:return null
	check(false,"Source mining approach did not reach the drill");return null

func verify_mining():
	var drill:=drilling()
	if drill==null:return
	drill=step(drill,0,Vector2.ZERO,1,Vector2(.5,-.5))
	if drill==null:return
	var before: Dictionary=drill.snapshot()
	var dead:=lethal(drill,100,Vector2.ONE,0,Vector2(-1,1))
	if dead==null:return
	var entry: Dictionary=dead.snapshot()
	check(entry.mining_session.drill.input==before.mining_session.drill.input and entry.mining_session.drill.point.distance_to(Vector2(3.75,-3.75))<.000001,"Lethal contact accepted new drill input or cancelled the current operation")
	check(entry.player_pose==before.player_pose and entry.player_statistics_pose==before.player_statistics_pose and entry.cargo==before.cargo,"Lethal mining resampled statistics, moved the ship or granted ore")
	var next:=step(dead,100,Vector2.ONE,0,-Vector2.ONE)
	if next==null:return
	var after: Dictionary=next.snapshot()
	check(after.mining_session.drill.command==Vector2(.5,-.5) and after.mining_session.drill.point.distance_to(Vector2(7.5,-7.5))<.000001,"Dead drilling lost its latched steering")
	check(after.mining_approach.model_basis==after.player_model_basis and after.player_model_basis==after.player_destruction.rendered_model_basis,"Death model changes were not fed back to the mining owner")
	check(after.camera_view==entry.camera_view and not after.camera_follow_enabled and after.player_statistics_pose==entry.player_statistics_pose,"Active drilling changed the frozen camera or retained statistics")
	captures.drilling=next
	for i in 100:
		before=next.snapshot()
		next=step(next,100)
		if next==null:return
		if next.drill_owner()==null:break
	after=next.snapshot()
	check(next.drill_owner()==null and after.mining_session.extraction.phase=="failed" and after.cargo.used==0 and after.scenery.mined_count==1,"Dead drilling did not reach its source failure transaction")
	check(after.camera_follow_enabled and after.player_destruction.camera_follow_enabled and after.camera_view!=before.camera_view and after.player_pose!=before.player_pose,"Mining release did not resume camera and retained physical motion on the same frame")
	check(after.player_destruction.camera_pose==after.camera_view.pose and after.progress==entry.progress and not after.cargo_objective_satisfied,"Death camera sample or mining campaign boundary diverged")
	captures.mining_released=next
	# Direct stop remains a separate action before full game-over. Zero earned
	# ore can retire the asteroid but cannot grant cargo or campaign completion.
	var stopped: RefCounted=dead.stop_mining()
	check(stopped!=null and stopped.snapshot().camera_follow_enabled and stopped.snapshot().player_destruction.camera_follow_enabled and stopped.snapshot().cargo.used==0 and dead.snapshot()==entry,"Death stopped-mining action lost atomic camera/cargo handoff")

func verify_early_return():
	var world:=drilling()
	if world==null:return
	world=lethal(world)
	if world==null:return
	world=world.fork_for_frame()
	var index: int=world.snapshot().mining_approach.object_index
	# Scenery keeps intact body pools shared until its own transaction mutates
	# them. This direct damage fixture must detach that copy-on-write boundary.
	world._scenery._bodies=world._scenery._bodies.fork_for_frame()
	check(world._scenery._bodies.normal_hit(index,100000).destroyed_now,"Could not make the selected asteroid unavailable")
	var before: Dictionary=world.snapshot()
	var next:=step(world,100)
	if next==null:return
	var after: Dictionary=next.snapshot()
	check(next.drill_owner()==null and after.mining_session.phase=="cancelled" and after.cargo==before.cargo,"Invalid death-mining target granted extraction")
	check(after.player_destruction.elapsed_ms==before.player_destruction.elapsed_ms and after.player_destruction.model_rotation==before.player_destruction.model_rotation and after.player_pose==before.player_pose,"Invalid target failed to return before the death tail")
	check(after.encounter.elapsed_ms==before.encounter.elapsed_ms+100 and after.world_phase_elapsed_ms==before.world_phase_elapsed_ms+100 and after.camera_follow_enabled,"Early player return incorrectly skipped the remaining weapon/camera/world phases")
	check(after.player_destruction.events.particle_events==[{"emitting":true}],"Early player return omitted the later death poll")

func verify_game_over():
	var world:=lethal(ready)
	if world==null:return
	var initial: Dictionary=world.snapshot()
	for i in 170:
		if world.game_over_waiting():break
		world=step(world,100)
		if world==null:return
		if world.snapshot().player_destruction.elapsed_ms==3800:captures.explosion=world
		if world.snapshot().player_destruction.fade_elapsed_ms==2000:captures.half_fade=world
	var before: Dictionary=world.snapshot()
	check(world.game_over_waiting() and before.player_destruction.phase=="game_over" and before.player_destruction.continue_enabled,"Live death never reached its source game-over fade")
	check(not before.player_destruction.body_visible and before.cargo==initial.cargo and before.progress==initial.progress and before.player.vitals.hull==0,"Death restored the player, cargo or campaign")
	var next:=step(world,100,Vector2.ONE,0,Vector2.ONE)
	if next==null:return
	var after: Dictionary=next.snapshot()
	check(after.player_pose==before.player_pose and after.player_statistics_pose==before.player_statistics_pose and after.player_destruction.elapsed_ms==before.player_destruction.elapsed_ms and after.player_destruction.model_rotation==before.player_destruction.model_rotation,"Completed fade continued player motion or tumble")
	check(after.world_phase_elapsed_ms==before.world_phase_elapsed_ms+100 and after.encounter.elapsed_ms==before.encounter.elapsed_ms+100,"Completed fade stopped the later weapon/world phases")
	check(next.start_mining()==null and next.stop_mining()==null and next.start_station_autopilot()==null and next.cancel_station_autopilot()==null and next.navigate("next")==null,"Completed game-over allowed ordinary flight actions")
	check(next.request_game_over_exit(true)==null and next.prepare_game_over().is_empty(),"Paused game-over accepted acknowledgement")
	var exited: RefCounted=next.request_game_over_exit()
	if exited==null:check(false,next.error);return
	var packet: Dictionary=exited.prepare_game_over()
	check(packet=={"base_content_id":after.base_content_id,"binding_id":after.binding_id,"campaign_cursor":4,"source_state":1} and exited.snapshot().boundary=="game_over_transition_required","Game-over acknowledgement invented a retry or changed campaign state")
	check(exited.evaluate(100).snapshot()==exited.snapshot() and exited.request_game_over_exit()==null and next.snapshot()==after,"Pending game-over transition advanced or changed its accepted parent")
	captures.game_over=next

func verify_render(args: PackedStringArray, lib: RefCounted, bindings: RefCounted, cat: RefCounted):
	var visuals:=Visuals.new()
	if not visuals.open(args[2],lib.manifest):check(false,visuals.error);return
	root.size=Vector2i(1280,720)
	var scene:=Scene.new();root.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,ready):check(false,scene.error);scene.free();return
	check(scene.player_destruction!=null and scene.game_over!=null and not scene.player_destruction.visible and not scene.game_over.visible,"Ready scene omitted death support or showed it early")
	var stages:=captures.keys();stages.erase("game_over");stages.append("game_over")
	for stage in stages:
		var world: RefCounted=captures[stage];var state: Dictionary=world.snapshot()
		if not scene.present(world,true,524):check(false,stage+": "+scene.error);continue
		var death: Dictionary=state.player_destruction
		var body_pose: Transform3D=state.player_pose*Transform3D(state.player_model_basis,Vector3.ZERO) if death.phase=="ready" else death.body_pose
		check(scene.geometry.player.transform==body_pose and scene.geometry.player.visible==death.body_visible,"Live player body pose/visibility diverged at "+stage)
		check(scene.player_destruction.visible==death.effect.active and scene.player_destruction.models.size()==2,"Live explosion visibility or model population diverged at "+stage)
		check(scene.camera.transform==state.camera_view.pose and scene.game_over.visible==death.game_over_visible,"Camera or game-over display diverged at "+stage)
		if death.phase!="ready":
			for control in [scene.target_frame,scene.reticle,scene.scan_animation,scene.mining_panel,scene.notice_panel]:
				if control!=null:check(not control.visible,"A dead flight displayed ordinary HUD at "+stage)
		if state.has("damage_particles"):
			check(scene.damage_particles.items.size()==5 and scene.damage_particles.frame.elapsed_ms==state.encounter.elapsed_ms,"Live particles lost their actual population or early clock")
			for item in scene.damage_particles.items:
				var emitter: Dictionary=state.damage_particles.owners[item.key][item.kind]
				var count:=active_slots(emitter) if emitter.visible else 0
				check(item.node.visible==(count>0) and (item.node.mesh==null if count==0 else item.node.mesh.surface_get_array_len(0)==count*4),"Sprite mesh lost a live slot at "+stage+" "+item.key+"/"+item.kind)
		check(world.snapshot()==state,"Scene presentation advanced death, cargo or world at "+stage)
		if args.size()==4:
			for i in 5:await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(args[3].path_join("live-player-"+stage+".png"))==OK,"Could not capture "+stage)
			if stage in ["npc_trail","npc_breakup"]:await capture_close_npc(scene,world,stage,args[3])
	var prior:=render_snapshot(scene)
	var invalid: RefCounted=captures.manual_tumble.fork_for_frame()
	invalid._notices._identity=invalid._notices._identity.duplicate()
	invalid._notices._identity.binding_id="foreign"
	check(not scene.present(invalid,true,900) and render_snapshot(scene)==prior,"Late notice failure failed to restore the accepted death scene")
	if ready.damage_particle_owner()!=null:
		invalid=captures.player_trail.fork_for_frame();invalid._particles._elapsed_ms+=1
		check(not scene.present(invalid,true,900) and render_snapshot(scene)==prior,"Particle/world clock mismatch changed accepted meshes")
		invalid=captures.player_trail.fork_for_frame();invalid._particles._presentation_identity=RefCounted.new()
		check(not scene.present(invalid,true,900) and render_snapshot(scene)==prior,"Foreign particle owner changed accepted meshes")
	check(not scene.present(captures.manual_tumble,false,-1) and render_snapshot(scene)==prior,"Invalid absolute time changed accepted death rendering")
	var clicks:=[]
	scene.game_over.continue_requested.connect(func():clicks.append(true))
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true
	scene.game_over.set_active(false)
	check(not scene.game_over.handle_event(enter) and clicks.is_empty(),"Inactive scene accepted game-over continuation")
	scene.game_over.set_active(true)
	check(scene.game_over.handle_event(enter) and clicks.size()==1 and captures.game_over.prepare_game_over().is_empty(),"Game-over display failed to emit intent or mutated flight state")
	scene.set_mobile_layout(true)
	check(scene.game_over.snapshot().composition_scale==1.0 and scene.game_over.snapshot().text_id==188,"Flight scene lost the mobile game-over layout")
	scene.clear()
	check(scene.game_over==null and scene.player_destruction==null and scene.get_child_count()==0,"Scene clear retained death nodes")
	scene.free()

func capture_close_npc(scene: Node3D,world: RefCounted,stage: String,directory: String):
	# Supplemental rendering-only camera: the source follow camera is still
	# settling after the disclosed close player placement. Retain all world,
	# owner, effect and particle state; restore the actual view afterwards.
	var state: Dictionary=world.snapshot();var actor: Dictionary=state.actors[0]
	var body: Transform3D=actor.get("body_pose",actor.pose)
	var close:=Transform3D(Basis.IDENTITY,body.origin+Vector3(0,0,6000))
	var view: Dictionary=state.camera_view.duplicate();view.pose=close;view.eye=close.origin;view.look=body.origin
	check(scene._projection.apply(scene.camera,view).is_empty() and scene.sky.apply_view(view) and scene.planets.apply_view(view),"Cannot prepare the disclosed NPC inspection camera")
	var sprites: Dictionary=scene.damage_particles.prepare_world(world.damage_particle_owner(),state,close)
	var ship: Dictionary=scene.encounter.prepare_world(world.encounter_owner(),close,state.ship_detail)
	check(not sprites.is_empty() and not ship.is_empty(),"NPC inspection camera lost its retained native geometry")
	if sprites.is_empty() or ship.is_empty():return
	scene.damage_particles.commit_world(sprites);scene.encounter.commit_world(ship)
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join("live-player-"+stage+"-close.png"))==OK,"Cannot capture the NPC inspection view")
	check(scene.present(world,false,524) and world.snapshot()==state,"Inspection camera changed native world state or failed to restore its actual view")

func verify_particles():
	var initial: Dictionary=ready.snapshot().damage_particles
	check(initial.owners.keys()==["player","npc0","world"] and initial.owners.player.keys()==["trail"],"Second trip fabricated opening actors or player smoke/fire")
	check(not initial.owners.player.trail.enabled and not initial.owners.npc0.trail.enabled and not initial.owners.npc0.smoke.enabled and not initial.owners.npc0.fire.enabled,"Healthy owners emitted death effects")
	var world:=lethal(ready,100)
	if world==null:return
	var state: Dictionary=world.snapshot()
	check(state.damage_particles.owners.player.trail.enabled and state.damage_particles.owners.player.trail.cursor==0,"Lethal poll emitted in the earlier particle phase")
	world=step(world,150)
	if world==null:return
	state=world.snapshot()
	check(active_slots(state.damage_particles.owners.player.trail)==1 and state.damage_particles.owners.player.trail.cursor==1,"First following player pass failed to emit the source trail")
	check(state.damage_particles.elapsed_ms==state.encounter.elapsed_ms and state.damage_particles.owners.player.trail.baseline==state.player_pose.origin,"Trail failed to sample the physical player in the early manager phase")
	for i in 3:
		world=step(world,150)
		if world==null:return
	captures.player_trail=world
	while world.snapshot().player_destruction.elapsed_ms<3000:
		world=step(world,mini(150,3000-int(world.snapshot().player_destruction.elapsed_ms)))
		if world==null:return
	state=world.snapshot();var particles: Dictionary=state.damage_particles
	check(particles.burst_count==1 and particles.owners.world.burst.cursor==1 and active_slots(particles.owners.world.burst)==1,"Breakup did not request exactly one world burst")
	check(particles.owners.world.burst.slots[0].position==state.player_statistics_pose.origin and particles.owners.world.burst.slots[0].appearance.age_ms==150,"Breakup burst did not use statistics before this frame's manager aging")
	check(particles.owners.player.trail.enabled and not particles.owners.player.trail.visible and active_slots(particles.owners.player.trail)==0,"Breakup reset/poll restored drawing or retained old trail sprites")
	captures.player_breakup=world
	var rng: Dictionary=particles.owners.world.burst.random
	for i in 11:
		world=step(world,150)
		if world==null:return
	state=world.snapshot()
	check(state.damage_particles.burst_count==1 and state.damage_particles.owners.world.burst.random==rng and active_slots(state.damage_particles.owners.world.burst)==0,"Following frames replayed the manual burst or failed to expire it")
	var invalid: RefCounted=world.fork_for_frame();invalid._particles._smoke._identity.binding_id="foreign"
	var before: Dictionary=invalid.snapshot()
	check(invalid.evaluate(100)==null and invalid.snapshot()==before,"A late particle-owner failure committed player or random state")
	check(world.evaluate(150,Vector2.ZERO,1,true).snapshot()==state,"Pause changed the retained particle managers")
	var fork: RefCounted=world.damage_particle_owner();var detached: Dictionary=fork.snapshot();detached.owners.world.burst.slots.clear()
	check(world.snapshot()==state and not fork.snapshot().owners.world.burst.slots.is_empty(),"Particle getter/snapshot exposed accepted storage")
	var mining:=drilling()
	if mining==null:return
	mining=lethal(mining,0)
	if mining==null:return
	while mining.snapshot().player_destruction.elapsed_ms<3000:
		mining=step(mining,150)
		if mining==null:return
	state=mining.snapshot()
	check(mining.drill_owner()!=null and state.player_statistics_pose.origin!=state.player_pose.origin,"Mining burst fixture lost the distinct retained statistics sample")
	check(state.damage_particles.owners.world.burst.slots[0].position==state.player_statistics_pose.origin,"Live mining death substituted the physical explosion position for the sprite burst")
	captures.mining_burst=mining
	verify_pirate_particles()

func verify_pirate_particles():
	# Disclosed close player placement beside the source's original dormant
	# pirate. Native proximity activation, damage, controller and death follow.
	var world: RefCounted=ready.fork_for_frame()
	world._pose=Transform3D(Basis(Vector3.UP,PI),world.snapshot().actors[0].pose.origin+Vector3(0,0,5000))
	world._pilot.angular_units=Vector2.ZERO
	world=step(world,100,Vector2.ZERO,0)
	if world==null:return
	var state: Dictionary=world.snapshot();var actor: Dictionary=state.actors[0]
	check(actor.active and actor.actor_mode==1,"Particle fixture failed to activate the source pirate")
	var hit: Dictionary=world._encounter._combat.normal_hit(0,int(actor.vitals.hull)-1,true)
	check(hit.get("accepted",false) or hit.get("hull_damage",0)>0,"Could not apply the synthetic nonlethal pirate hit")
	world=step(world,150,Vector2.ZERO,0)
	if world==null:return
	state=world.snapshot()
	check(state.damage_particles.owners.npc0.smoke.enabled and state.damage_particles.owners.npc0.fire.enabled and not state.damage_particles.owners.npc0.trail.enabled,"Low hull did not enable only the shared smoke/fire pair")
	world=step(world,150,Vector2.ZERO,0)
	if world==null:return
	state=world.snapshot()
	check(active_slots(state.damage_particles.owners.npc0.smoke)>0 and active_slots(state.damage_particles.owners.npc0.fire)>0,"Later managers omitted the low-hull pirate effects")
	check(world._encounter._combat.normal_hit(0,1,true).get("destroyed_now",false),"Could not exhaust the source pirate hull")
	world=step(world,0,Vector2.ZERO,0)
	if world==null:return
	state=world.snapshot()
	check(state.damage_particles.owners.npc0.trail.enabled and active_slots(state.damage_particles.owners.npc0.trail)==0,"NPC death emitted in the earlier particle phase")
	var retained: Transform3D=state.damage_particles.owners.npc0.root_pose
	world=step(world,150,Vector2.ZERO,0)
	if world==null:return
	state=world.snapshot()
	check(active_slots(state.damage_particles.owners.npc0.trail)>0 and state.damage_particles.owners.npc0.trail.baseline==retained.origin,"NPC trail did not use its preceding unbanked root")
	captures.npc_trail=world
	for i in 100:
		if not world.snapshot().damage_particles.owners.npc0.trail.enabled:break
		world=step(world,150,Vector2.ZERO,0)
		if world==null:return
	state=world.snapshot();var particles: Dictionary=state.damage_particles.owners.npc0
	check(not particles.trail.enabled and particles.trail.visible and not particles.smoke.enabled and not particles.fire.enabled,"NPC breakup used player drawing-reset behavior or left damage trails emitting")
	check(active_slots(particles.trail)>0 and state.damage_particles.burst_count==0,"NPC breakup reset surviving trail slots or borrowed the player's manual burst")
	captures.npc_breakup=world
	for i in 5:
		world=step(world,150,Vector2.ZERO,0)
		if world==null:return
	check(active_slots(world.snapshot().damage_particles.owners.npc0.trail)==0,"Disabled NPC death trail failed to expire")

func active_slots(emitter: Dictionary) -> int:
	var count:=0
	for slot in emitter.slots:
		if slot.appearance.age_ms>=0:count+=1
	return count

func render_snapshot(scene: Node3D) -> Dictionary:
	var result:={"last":scene._last.duplicate(true),"body":scene.geometry.player.transform,"visible":scene.geometry.player.visible,
		"camera":scene.camera.transform,"effect_visible":scene.player_destruction.visible,"game_over":scene.game_over.snapshot(),
		"sun":scene.sun.frame.duplicate(true),"pirate":scene.encounter.hull.transform}
	if scene.damage_particles!=null:
		var sprites:=[]
		for item in scene.damage_particles.items:
			sprites.append({"key":item.key,"kind":item.kind,"visible":item.node.visible,"arrays":[] if item.node.mesh==null else item.node.mesh.surface_get_arrays(0)})
		result.particles={"clock":scene.damage_particles.frame.elapsed_ms,"counts":scene.damage_particles.frame.counts.duplicate(),"pose":scene.damage_particles.transform,"sprites":sprites}
	return result

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",checks,": ",message)
