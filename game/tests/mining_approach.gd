extends SceneTree
const Approach=preload("res://src/simulation/mining_approach.gd")
const Definitions=preload("res://src/content/mining_approach_definitions.gd")
const Targeting=preload("res://src/simulation/mining_targeting.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const TargetFrame=preload("res://src/presentation/flight_target_frame.gd")
const ScanAnimation=preload("res://src/presentation/flight_scan_animation.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var construction: RefCounted
var world: RefCounted
var selection: RefCounted
var bindings: RefCounted
var cat: RefCounted
var target:=Vector3(0,0,-100000)
var stand_off:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Mining approach: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify(args: Array):
	var lib:=Library.new();bindings=Bindings.new();cat=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	if bindings.mining_approach.is_empty():check(not Approach.new().configure(bindings,cat,Construction.new()),"Legacy pack invented approach");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.mining_approach,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.mining_targeting).is_empty(),"Approach declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.mining_approach.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed approach declaration accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.mining_approach.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.mining_targeting).is_empty(),"Detached approach provenance accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	var departure:=station.prepare_departure(bindings,cat)
	construction=Construction.new()
	if not construction.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects):check(false,construction.error);return
	world=construction.scenery_owner();world._bodies=world._bodies.fork_for_frame();world._motion=world._motion.fork_for_frame()
	for i in world._bodies._rows.size():
		var point:=target if i==0 else Vector3(10000+i,0,100000)
		world._bodies._rows[i].position=point;world._motion._field.objects[i].position=point
	stand_off=int(Approach.f32(world.snapshot().objects[0].scale*2500.0))
	var geometry:=TargetFrame.source_geometry(lib,bindings);var art:=ScanAnimation.source_geometry(lib,bindings,bindings.mining_targeting)
	selection=Targeting.new();check(selection.configure(bindings,cat,construction,TargetFrame.logical_radii(geometry.quarter_size,false),art.frames),selection.error)
	var aim:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400,300,-1000),"viewport_size":Vector2i(800,600)}
	for i in 39:
		if not selection.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true):check(false,selection.error);return
	check(selection.snapshot().selected_object_index==0,"Approach fixture did not acquire its actual target")
	var field: Dictionary=world.snapshot();var prepared: Dictionary=construction.snapshot();var selected: Dictionary=selection.snapshot()
	var owner:=fresh()
	check(not owner.advance(world,100) and owner.snapshot().phase=="idle","Idle approach advanced")
	check(owner.snapshot().guidance_gain==Approach.f32(3.9795455932617188),"Mining guidance used scaled pilot response instead of the source handling getter")
	var turn: Transform3D=owner.guided_pose(Transform3D.IDENTITY,Vector3(10000,0,10000),100,1.0)
	# Independent analytical 45-degree target vector, rounded to binary32.
	# NPC guidance normalizes the difference too and fails this small-turn case.
	check(turn.basis.z.distance_to(Vector3(0.0703631117939949,0.0,0.9975214600563049))<0.000001 and turn.origin.distance_to(Vector3(14.072622299194336,0.0,199.50428771972656))<0.00001,"Off-axis approach used an unsupported turn or travel formula")
	var held_turn: Transform3D=owner.guided_pose(Transform3D.IDENTITY,Vector3(10000,0,10000),100,0.0)
	check(held_turn.origin==Vector3.ZERO and held_turn.basis==turn.basis,"Zero throttle disabled source heading guidance or moved the ship")
	var start:=facing(float(stand_off+2000))
	check(owner.start(world,selection,start),owner.error)
	check(owner.snapshot().stand_off==stand_off and owner.snapshot().player_pose==start and owner.snapshot().phase=="approach","Starting approach moved the ship or changed source stand-off")
	var initial: Dictionary=owner.snapshot()
	check(owner.advance(world,150,true) and owner.snapshot()==initial,"Paused approach changed pose or alignment")
	check(owner.advance(world,100),owner.error)
	var outer: Dictionary=owner.snapshot()
	check(outer.player_pose.origin.distance_to(start.origin+start.basis.z*200.0)<0.01,"Aligned approach lost source cruise distance")
	check(outer.camera_update_enabled and outer.engine_visible and outer.tilt_units==0,"Close alignment used the post-movement distance or inclusive boundary")
	check(owner.advance(world,100),owner.error)
	var close: Dictionary=owner.snapshot()
	check(not close.camera_update_enabled and not close.engine_visible and close.throttle==1.0 and close.tilt_units==-35.0,"Close approach did not freeze camera, stop engines or apply source tilt")
	var expected_angle: float=Approach.f32(Approach.f32(-35.0/65536.0)*float(bindings.mining_approach.angle_tau))
	check(close.model_basis.z.y>0 and close.model_basis.z.distance_to(Vector3(0,-sin(expected_angle),cos(expected_angle)))<0.000001,"Local pitch has the wrong source sign or axis")
	check(close.presentation_pose.origin==close.player_pose.origin and close.presentation_pose.basis!=close.player_pose.basis,"Mining visual tilt changed the physical pose or was omitted")
	var local_tilt:=fresh();var yaw:=Basis(Vector3.UP,PI/4)
	check(local_tilt.start(world,selection,facing(float(stand_off+1000)),yaw) and local_tilt.advance(world,100),local_tilt.error)
	var expected_forward:=yaw.z*cos(expected_angle)-yaw.y*sin(expected_angle)
	check(local_tilt.snapshot().model_basis.z.distance_to(expected_forward)<0.000001,"Mining pitch was applied in world coordinates instead of the visual model's local axes")
	var fork: RefCounted=owner.fork_for_frame()
	check(fork.advance(world,99) and fork.snapshot()!=close and owner.snapshot()==close,"Prospective approach advanced its parent")
	var forbidden: RefCounted=selection.fork_for_frame();forbidden.clear_selection()
	var idle:=fresh();check(not idle.start(world,forbidden,start) and idle.snapshot().phase=="idle","Approach started without an acquired target")
	# A target just inside stand-off never attracts a position snap. Alignment
	# completes locally, then the separate settling clock requests a drill.
	owner=fresh();start=facing(float(stand_off)-0.25);check(owner.start(world,selection,start),owner.error)
	var entered_docking:=false;var ready:=false;var last_tilt:=0.0
	for i in 100:
		var before: Dictionary=owner.snapshot()
		if not owner.advance(world,100):check(false,owner.error);return
		var state: Dictionary=owner.snapshot()
		check(state.player_pose==start,"In-range alignment moved or teleported the logical ship")
		if state.phase=="docking":entered_docking=true
		if before.phase=="docking" and before.tilt_units<=-1024:
			check(state.phase=="drill_required" and state.events[0].kind=="drill_required","Settled docking omitted the drill creation boundary")
		if state.phase=="drill_required":ready=true;last_tilt=state.tilt_units;break
	check(entered_docking and ready and not owner.snapshot().spin_enabled and last_tilt<=-1024,"Approach did not complete alignment and its pre-drill wait")
	var waiting:=fresh();check(waiting.start(world,selection,start),waiting.error)
	waiting._state.phase="docking";waiting._state.tilt_units=-1023.0
	check(waiting.advance(world,3) and waiting.snapshot().phase=="docking" and waiting.snapshot().tilt_units==-1025.0,"Odd settling time did not use source signed half-step")
	check(waiting.advance(world,0) and waiting.snapshot().phase=="drill_required","Drill creation advanced on the threshold-crossing frame")
	check(not waiting.advance(world,100),"Approach impersonated the unfinished drilling owner")
	var completed: Dictionary=owner.snapshot();check(owner.cancel(),owner.error)
	check(owner.snapshot().camera_update_enabled and owner.snapshot().engine_visible and owner.snapshot().spin_enabled and owner.snapshot().aligned==completed.aligned and owner.snapshot().model_basis==completed.model_basis,"Cancel lost retained alignment or failed to restore view/effects/spin")
	check(owner.start(world,selection,start) and owner.snapshot().tilt_units==0 and owner.snapshot().aligned,"Restart lost source retained-alignment semantics")
	check(owner.advance(world,1) and owner.snapshot().phase=="docking","Retained alignment did not affect the next in-range attempt")
	var early:=fresh();early.start(world,selection,facing(float(stand_off+1000)));early.advance(world,100)
	check(early.snapshot().alignment_open and early.cancel() and early.snapshot().alignment_open and early.snapshot().reference_up==Vector3.ZERO,"Early cancel reset a source-retained capture flag")
	var good: Dictionary=owner.snapshot()
	for dt in [-1,151,0.5,"1"]:check(not owner.advance(world,dt) and owner.snapshot()==good,"Invalid frame changed an approach")
	check(not owner.configure(bindings,cat,Construction.new()) and owner.snapshot()==good,"Failed configuration replaced the current approach")
	var replaced:=Construction.new();check(replaced.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects),replaced.error)
	check(not owner.advance(replaced.scenery_owner(),100) and owner.snapshot()==good,"Approach crossed into a replacement field")
	var broken: RefCounted=world.fork_for_frame();broken._bodies=broken._bodies.fork_for_frame();broken._bodies._rows[0].position=Vector3(INF,0,0)
	check(not owner.advance(broken,100) and owner.snapshot()==good,"Invalid target pose changed approach state")
	var destroyed: RefCounted=world.fork_for_frame();destroyed._destruction[0]=destroyed._destruction[0].fork_for_frame();destroyed._destruction[0]._state.actor_state=3
	check(owner.advance(destroyed,100) and owner.snapshot().phase=="idle" and owner.snapshot().events[0].reason=="target_unavailable","Destroyed target did not cancel approach")
	check(world.snapshot()==field and construction.snapshot()==prepared and selection.snapshot()==selected and station.prepare_departure(bindings,cat)==departure,"Approach changed source owners, selection, cargo or mission progress")
	print("Approach sample: stand-off ",stand_off,"; gain ",owner.snapshot().guidance_gain,"; ready tilt ",last_tilt)
	verify_spin()
	await verify_flight(lib,args)

func verify_spin():
	# This source tutorial field has stationary asteroid models. Explicit test
	# spin vectors make suppression/resumption observable without pretending
	# that the supplied first field rotates.
	var rotating: RefCounted=world.fork_for_frame();rotating._motion=rotating._motion.fork_for_frame()
	rotating._motion._field.objects[0].spin=Vector3(0.1,0.2,0.3)
	rotating._motion._field.objects[1].spin=Vector3(0.3,0.1,0.2)
	var original: Dictionary=rotating.snapshot()
	var stopped: RefCounted=rotating.fork_for_frame()
	check(stopped.set_spin_enabled(0,false) and stopped.update(100,Vector3.ZERO),stopped.error)
	var state: Dictionary=stopped.snapshot()
	check(state.objects[0].basis==original.objects[0].basis and state.objects[1].basis!=original.objects[1].basis and rotating.snapshot()==original,"A spin stop affected another asteroid or its parent")
	var resumed: RefCounted=stopped.fork_for_frame()
	check(resumed.set_spin_enabled(0,true) and resumed.update(100,Vector3.ZERO) and resumed.snapshot().objects[0].basis!=state.objects[0].basis and stopped.snapshot()==state,"Resuming asteroid spin changed an earlier frame or left rotation stopped")
	check(not resumed.set_spin_enabled(-1,false) and not resumed.set_spin_enabled(original.objects.size(),false),"Out-of-field spin index was accepted")

func verify_flight(lib: RefCounted,args: Array):
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5,Vector2i(960,720)):check(false,flight.error);return
	check(flight.start_mining()==null,"Unreleased entry started mining")
	for i in 130:
		flight=flight.evaluate(100)
		if flight==null:check(false,"Could not prepare live entry");return
	check(flight.start_mining()==null,"Modal briefing started mining")
	for i in 5:flight=flight.navigate("next")
	check(flight.start_mining()==null,"Flight invented a selected asteroid")
	# Place the test pilot near the ACTUAL constructed asteroid, then acquire
	# it through live aim/camera/selection. Only this starting position is a
	# fixture; all subsequent guidance, alignment and settling are simulated.
	var asteroid: Dictionary=construction.snapshot().scenery.bodies.objects[0]
	var distance:=float(stand_off+10000)
	flight._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,distance))
	flight._pilot.angular_units=Vector2.ZERO
	var camera_data: Dictionary=bindings.camera_follow
	var eye: Vector3=flight._pose*Vector3(camera_data.eye_offset[0],camera_data.eye_offset[1],camera_data.eye_offset[2])
	var look: Vector3=flight._pose*Vector3(camera_data.look_offset[0],camera_data.look_offset[1],camera_data.look_offset[2])
	flight._camera._state.eye=eye;flight._camera._state.look=look;flight._camera._state.pose=Transform3D.IDENTITY.looking_at(look-eye,Vector3.UP);flight._camera._state.pose.origin=eye
	flight._aim=Aim.new();flight._aim.configure(bindings)
	for i in 55:
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0)
		if next==null:check(false,flight.error);return
		flight=next
	if flight.snapshot().mining_targeting.selected_object_index!=0:check(false,"Actual asteroid was not acquired for live approach");return
	flight=flight.evaluate(0,Vector2.ZERO,1.0)
	var original: Dictionary=flight.snapshot()
	var full: RefCounted=flight.fork_for_frame()
	check(full._cargo.add_entries([{"item_id":asteroid.item_id,"quantity":full.snapshot().cargo.capacity}]),full._cargo.error)
	var refused: RefCounted=full.start_mining()
	if original.has("flight_notices"):
		check(refused!=null and refused.snapshot().mining_approach.phase=="idle" and refused.snapshot().flight_notices.current.source_id==27 and flight.snapshot()==original,"A full hold started approach or lost its source notice")
	else:check(refused==null and flight.snapshot()==original,"A full hold started approach or changed its parent")
	check(flight.start_mining(true)==null and flight.snapshot()==original,"Paused input started approach")
	var running: RefCounted=flight.start_mining()
	if running==null:check(false,flight.error);return
	check(running.snapshot().player_pose==original.player_pose and flight.snapshot()==original,"Approach start teleported or mutated the previous frame")
	check(running.start_mining()==null,"Active approach started a second target")
	var captures:={"approach-start":running};var camera_froze:=false;var spin_stopped:=false
	for i in 200:
		var before: Dictionary=running.snapshot()
		var next: RefCounted=running.evaluate(100,Vector2.ONE,0.0)
		if next==null:check(false,running.error);return
		var state: Dictionary=next.snapshot()
		if i==0:
			check(state.player_pose.origin.distance_to(before.player_pose.origin+before.player_pose.basis.z*200)<0.1 and state.angular_units==before.angular_units,"Approach also ran manual steering or took a throttle change")
			check(state.mining_targeting.selected_object_index==-1 and state.mining_targeting.elapsed_ms==0,"Approach kept acquiring targets")
		if not state.mining_approach.camera_update_enabled:
			check(state.camera_view==before.camera_view,"Close approach moved its frozen camera")
			if not camera_froze:
				camera_froze=true;captures["approach-close"]=next
				check(next.evaluate(150,Vector2.ONE,0.0,true).snapshot()==state,"Pause advanced approach, camera or scenery")
				var late: RefCounted=next.fork_for_frame();late._targeting._field_identity=RefCounted.new()
				var held: Dictionary=late.snapshot()
				check(late.evaluate(100)==null and late.snapshot()==held and next.snapshot()==state,"Late failure partly committed approach/world motion")
		if not state.mining_approach.spin_enabled:
			check(state.scenery.objects[0].basis==before.scenery.objects[0].basis,"Docking asteroid spun during its stop frame")
			check(state.scenery.spin_disabled_indices==[0],"Mining stopped another asteroid's spin")
			if not spin_stopped:spin_stopped=true;captures["approach-docking"]=next
		running=next
		if state.mining_approach.phase=="drill_required":break
	var ready: Dictionary=running.snapshot();captures["approach-ready"]=running
	check(camera_froze and spin_stopped and ready.mining_approach.phase=="drill_required","Live approach did not reach its drill handoff")
	if ready.has("mining_session"):
		check(ready.mining_boundary.is_empty() and ready.mining_session.drill.elapsed_ms==0,"Approach did not hand off to a fresh, unadvanced drill")
	else:check(running.evaluate(150,Vector2.ONE,0.0).snapshot()==ready,"Unsupported drill boundary advanced the world or mined cargo")
	check(ready.scenery.mined_count==0 and ready.scenery.remaining_count==original.scenery.remaining_count and ready.random_state==original.random_state,"Approach mined its target or consumed source RNG")
	for key in ["mission","progress","cargo","campaign_cursor","mining_completed","reward_credits"]:check(ready[key]==original[key],"Approach granted unearned progress: "+key)
	var cancel_source: RefCounted=captures["approach-docking"] if ready.has("mining_session") else running
	var cancel_state: Dictionary=cancel_source.snapshot()
	var cancelled: RefCounted=cancel_source.cancel_mining()
	if cancelled==null:check(false,cancel_source.error);return
	check(cancelled.snapshot().mining_boundary.is_empty() and cancelled.snapshot().mining_approach.camera_update_enabled and not cancelled.snapshot().scenery.has("spin_disabled_indices") and cancelled.snapshot().player_model_basis==cancel_state.player_model_basis,"Cancel did not restore the camera/spin or changed the existing visual tilt")
	var resumed: RefCounted=cancelled.evaluate(100,Vector2.ZERO,0.0)
	check(resumed!=null and resumed.snapshot().camera_view!=ready.camera_view and not resumed.snapshot().scenery.has("spin_disabled_indices"),"Cancelled approach did not resume camera and asteroid motion")
	check(running.snapshot()==ready and flight.snapshot()==original,"A prospective cancellation changed the accepted approach")
	if args.size()==4:await render(lib,args[2],args[3],captures)

func render(lib: RefCounted,pixels: String,directory: String,captures: Dictionary):
	var visuals:=Visuals.new()
	if not visuals.open(pixels,lib.manifest):check(false,visuals.error);return
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,captures["approach-start"]):check(false,scene.error);canvas.free();return
	for label in captures:
		var flight: RefCounted=captures[label];var state: Dictionary=flight.snapshot()
		check(scene.present(flight),scene.error)
		check(scene.geometry.player.transform.is_equal_approx(state.player_pose*Transform3D(state.player_model_basis,Vector3.ZERO)) and scene.camera.global_transform.is_equal_approx(state.camera_view.pose),"Approach renderer disagrees with the owned model or camera: "+label)
		for i in 3:await process_frame
		check(canvas.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Could not save approach capture")
		check(flight.snapshot()==state,"Rendering changed the approach")
	var good: Transform3D=scene.geometry.player.transform
	var bad: RefCounted=captures["approach-ready"].fork_for_frame();bad._model_basis=Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
	check(not scene.present(bad) and scene.geometry.player.transform==good,"Invalid model orientation changed the visible frame")
	canvas.size=Vector2i(800,450);scene.set_mobile_layout(true);check(scene.present(captures["approach-ready"]),scene.error)
	for i in 3:await process_frame
	check(canvas.get_texture().get_image().save_png(directory.path_join("approach-ready-phone.png"))==OK,"Could not save phone approach capture")
	canvas.free()
func fresh() -> RefCounted:
	var owner:=Approach.new();check(owner.configure(bindings,cat,construction),owner.error);return owner
func facing(distance: float) -> Transform3D:return Transform3D(Basis(Vector3.UP,PI),target+Vector3(0,0,distance))
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
