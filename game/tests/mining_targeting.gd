extends SceneTree
const Targeting=preload("res://src/simulation/mining_targeting.gd")
const Definitions=preload("res://src/content/mining_targeting_definitions.gd")
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
const Visuals=preload("res://src/content/visual_library.gd")
const TargetFrame=preload("res://src/presentation/flight_target_frame.gd")
const ScanAnimation=preload("res://src/presentation/flight_scan_animation.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
var checks:=0
var failures:=0
var bindings: RefCounted
var cat: RefCounted
var construction: RefCounted
var world: RefCounted
var aim:={}
var radii:=Vector2.ZERO
var frames:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Mining targeting: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();bindings=Bindings.new();cat=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	if bindings.mining_targeting.is_empty():
		check(not Targeting.new().configure(bindings,cat,Construction.new(),Vector2.ONE,25),"Legacy pack invented asteroid selection");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.mining_targeting,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Source targeting declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.mining_targeting.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed targeting declaration accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.mining_targeting.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached targeting provenance accepted: "+key)
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
	var geometry:=TargetFrame.source_geometry(lib,bindings);var strip:=ScanAnimation.source_geometry(lib,bindings,bindings.mining_targeting)
	if geometry.has("error") or strip.has("error"):check(false,"Source target art unavailable");return
	radii=TargetFrame.logical_radii(geometry.quarter_size,false);frames=strip.frames
	check(frames==25 and strip.frame_size==40,"Mac acquisition filmstrip changed")
	aim={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400,300,-1000),"viewport_size":Vector2i(800,600)}
	world=arranged([10000.0,9000.0,8000.0,7000.0,1000.0])
	var original: Dictionary=construction.snapshot();var field: Dictionary=world.snapshot()
	var scanner:=fresh();var initial: Dictionary=scanner.snapshot()
	check(initial.duration_ms==4000 and initial.scanner_id==81 and initial.drill_id==90,"Starter scanner/drill were resolved from the wrong loadout")
	check(scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,0,true),scanner.error)
	var sample: Dictionary=scanner.snapshot()
	check(sample.candidate_indices==[0,1,2,3] and sample.nearest_index==3 and sample.candidate_object_index==3,"Query did not choose the nearest of the first four candidates")
	check(sample.selected_object_index==-1 and sample.elapsed_ms==0 and sample.animation_frame==-1,"Zero time acquired an asteroid or drew acquisition")
	check(elapse(scanner,500),scanner.error)
	check(scanner.snapshot().animation_frame==-1 and scanner.snapshot().selected_object_index==-1,"Acquisition animation began before 501 ms")
	check(elapse(scanner,1) and scanner.snapshot().animation_frame==0,"First acquisition frame did not appear at 501 ms")
	check(elapse(scanner,1299) and scanner.snapshot().animation_frame==8,"Acquisition filmstrip used the NPC timing formula")
	check(elapse(scanner,2000),scanner.error)
	check(scanner.snapshot().elapsed_ms==3800 and scanner.snapshot().selected_object_index==-1,"Asteroid lock completed at the strict 3800 ms boundary")
	check(elapse(scanner,1),scanner.error)
	var acquired: Dictionary=scanner.snapshot()
	check(acquired.selected_object_index==3 and acquired.elapsed_ms==3801 and acquired.animation_frame==24 and acquired.events==[{"kind":"sound","source_id":26,"unless_source_id_playing":0,"object_index":3}],"Asteroid acquisition lost its clock, last frame or one-shot cue")
	check(elapse(scanner,100) and scanner.snapshot().events.is_empty() and scanner.snapshot().selected_object_index==3,"Continuing lock repeated acquisition sound")
	var held: Dictionary=scanner.snapshot()
	check(scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,150,false),scanner.error)
	check(scanner.snapshot().elapsed_ms==held.elapsed_ms and scanner.snapshot().selected_object_index==3 and not scanner.snapshot().visible and scanner.snapshot().animation_frame==-1,"Hidden HUD advanced or discarded acquisition")
	check(elapse(scanner,0) and scanner.snapshot().selected_object_index==3 and scanner.snapshot().events.is_empty(),"Restoring the HUD restarted acquisition")
	var fork: RefCounted=scanner.fork_for_frame();fork.clear_selection()
	check(fork.snapshot().selected_object_index==-1 and fork.snapshot().elapsed_ms==scanner.snapshot().elapsed_ms and scanner.snapshot().selected_object_index==3,"Clearing a prospective selection altered the original or reset source time")
	check(elapse(fork,0) and fork.snapshot().selected_object_index==3,"Source clear-selection could not reacquire its retained candidate")
	var off:=aim.duplicate(true);off.point.x=600
	check(scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,off,1,true),scanner.error)
	check(scanner.snapshot().selected_object_index==-1 and scanner.snapshot().candidate_object_index==-1 and scanner.snapshot().elapsed_ms==0,"Moving the aim away retained the asteroid lock")
	check(elapse(scanner,100) and scanner.snapshot().elapsed_ms==100 and scanner.snapshot().selected_object_index==-1,"Returning aim skipped a fresh acquisition")
	check(scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true,true),scanner.error)
	check(scanner.snapshot().elapsed_ms==0 and scanner.snapshot().candidate_object_index==-1 and scanner.snapshot().selected_object_index==-1,"An active approach retained a competing selection")
	# Use a center-projected asteroid so exact integer window edges have an
	# independent expected pixel. No copy of projection arithmetic is needed.
	for offset in [Vector2(-44,0),Vector2(44,0),Vector2(0,-44),Vector2(0,44)]:
		var edge:=aim.duplicate(true);edge.point+=Vector3(offset.x,offset.y,0)
		check(scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,edge,1,true) and scanner.snapshot().candidate_indices.is_empty(),"Strict scan-window edge admitted an asteroid")
		var inside:=aim.duplicate(true);inside.point+=Vector3(offset.x,offset.y,0)*0.95
		check(scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,inside,1,true) and scanner.snapshot().candidate_object_index==3,"Interior of scan window excluded an asteroid")
	var tied: RefCounted=arranged([7000.75,7000.25,9000.0,10000.0,1000.0])
	check(scanner.advance(tied,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,1,true) and scanner.snapshot().candidate_object_index==0,"Truncated equal distances did not retain the first candidate")
	var distant: RefCounted=arranged([999999.0])
	check(scanner.advance(distant,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true) and scanner.snapshot().candidate_object_index==-1,"Source distance sentinel selected an out-of-range asteroid")
	var debris: RefCounted=arranged([1000.0]);debris._destruction[0]._state.actor_state=3
	var no_tractor:=fresh()
	for i in 39:
		if not no_tractor.advance(debris,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true):check(false,no_tractor.error);return
	check(no_tractor.snapshot().selected_object_index==-1 and no_tractor.snapshot().events==[{"kind":"notification","source_id":9,"object_index":0}],"Active debris became a mineable selection")
	debris._bodies.set_permissions(0,false,false)
	check(no_tractor.advance(debris,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true) and no_tractor.snapshot().candidate_indices.is_empty(),"Retired debris stayed selectable")
	# Missing equipment and default duration are isolated native owner fixtures;
	# the actual departure continues to require its source-defined loadout.
	var without_drill:=Construction.new();without_drill._state=construction._state.duplicate(true);without_drill._scenery=construction.scenery_owner();without_drill._camera=construction.camera_owner();without_drill._player=construction.player_owner()
	without_drill._state.departure.loadout.equipment_ids=[81]
	var missing:=Targeting.new();check(missing.configure(bindings,cat,without_drill,radii,frames),missing.error)
	check(elapse(missing,3900) and missing.snapshot().selected_object_index==-1 and missing.snapshot().events==[{"kind":"notification","source_id":20,"object_index":3}],"Missing drill granted a mining selection")
	without_drill._state.departure.loadout.equipment_ids=[90]
	check(missing.configure(bindings,cat,without_drill,radii,frames) and missing.snapshot().duration_ms==8000,"Absent scanner did not retain the source default duration")
	var replacement:=Construction.new();check(replacement.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects),replacement.error)
	var good: Dictionary=scanner.snapshot()
	check(not scanner.advance(replacement.scenery_owner(),Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true) and scanner.snapshot()==good,"Selection crossed into an identically seeded replacement world")
	for dt in [-1,151,0.5,"1"]:check(not scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,dt,true) and scanner.snapshot()==good,"Invalid frame partially changed acquisition")
	for bad_aim in [{"binding_id":"foreign"},{"point":Vector3(INF,0,0)},{"viewport_size":Vector2i(0,600)}]:
		var invalid:=aim.duplicate();invalid.merge(bad_aim,true)
		check(not scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,invalid,100,true) and scanner.snapshot()==good,"Invalid aim partially changed acquisition")
	var malformed: RefCounted=world.fork_for_frame();malformed._bodies=malformed._bodies.fork_for_frame();malformed._bodies._rows.back().position=Vector3(INF,0,0)
	check(not scanner.advance(malformed,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true) and scanner.snapshot()==good,"A bad late body partially committed a good early candidate")
	check(not scanner.configure(bindings,cat,construction,Vector2.ZERO,frames) and scanner.snapshot()==good,"Failed configuration replaced a good scanner")
	check(world.snapshot()==field and construction.snapshot()==original and station.prepare_departure(bindings,cat)==departure,"Selection changed scenery, random state or campaign progress")
	await verify_flight(lib,args)

func verify_flight(lib: RefCounted,args: Array):
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5,Vector2i(960,720)):check(false,flight.error);return
	check(not flight.snapshot().player_aim.visible and not flight.snapshot().mining_targeting.visible,"Entry camera exposed the ordinary targeting HUD")
	for i in 130:
		var next: RefCounted=flight.evaluate(100)
		if next==null:check(false,flight.error);return
		flight=next
	var briefing: Dictionary=flight.snapshot()
	check(briefing.dialogue.visible and not briefing.player_aim.visible and not briefing.mining_targeting.visible,"Modal briefing did not own the targeting HUD")
	check(flight.evaluate(150,Vector2.ONE,0.0).snapshot()==briefing,"Modal input advanced aim or acquisition")
	for i in 5:flight=flight.navigate("next")
	var prior: Dictionary=flight.snapshot();var next: RefCounted=flight.evaluate(100,Vector2(0.2,0.3),0.0)
	if next==null:check(false,flight.error);return
	var reference: RefCounted=flight._aim.fork_for_frame()
	check(reference.advance(next.snapshot().player_pose,prior.camera_view.pose,Vector2i(960,720)) and next.snapshot().player_aim.point==reference.snapshot().point,"Aim did not sample current movement with the preceding camera")
	check(next.snapshot().player_aim.visible and next.snapshot().mining_targeting.visible,"Acknowledged flight did not expose targeting")
	check(next.evaluate(150,Vector2.ZERO,0.0,true).snapshot()==next.snapshot(),"Pause advanced aiming or selection")
	check(next.evaluate(100,Vector2.ZERO,0.0,false,Vector2i(-1,600))==null and flight.snapshot()==prior,"Invalid viewport partially committed a flight")
	var bad: RefCounted=next.fork_for_frame();bad._targeting._field_identity=RefCounted.new();var held: Dictionary=bad.snapshot()
	check(bad.evaluate(100)==null and bad.snapshot()==held,"Late selection failure committed player, scenery or camera state")
	var resized: RefCounted=next.evaluate(100,Vector2.ZERO,0.0,false,Vector2i(420,800))
	check(resized!=null and resized.snapshot().player_aim.viewport_size==Vector2i(420,800) and resized.snapshot().mining_targeting.viewport_size==Vector2i(420,800),"Viewport resize left aim and selection in different coordinates")
	# A test-only pilot position puts the actual source asteroid in view. This
	# proves live acquisition and HUD rendering, not the unfinished approach.
	flight=next.fork_for_frame();flight._pilot.angular_units=Vector2.ZERO
	var asteroid: Dictionary=construction.snapshot().scenery.bodies.objects[0]
	flight._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,asteroid.model_radius*asteroid.scale*4.0+4000.0))
	var camera_data: Dictionary=bindings.camera_follow
	var eye: Vector3=flight._pose*Vector3(camera_data.eye_offset[0],camera_data.eye_offset[1],camera_data.eye_offset[2])
	var look: Vector3=flight._pose*Vector3(camera_data.look_offset[0],camera_data.look_offset[1],camera_data.look_offset[2])
	flight._camera._state.eye=eye;flight._camera._state.look=look;flight._camera._state.pose=Transform3D.IDENTITY.looking_at(look-eye,Vector3.UP);flight._camera._state.pose.origin=eye
	flight._aim=Aim.new();flight._aim.configure(bindings)
	flight._targeting=fresh()
	var captures:={}
	for i in 55:
		var advanced: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0)
		if advanced==null:check(false,flight.error);return
		flight=advanced
		if i in [4,19,54]:captures[str(i+1)]=flight
	if flight.snapshot().mining_targeting.selected_object_index!=0:
		var query: Dictionary=flight.snapshot().mining_targeting
		print("Live acquisition diagnostic: ",{"aim":query.aim_pixels,"candidate":query.candidate_object_index,"selected":query.selected_object_index,"elapsed":query.elapsed_ms,"asteroid":query.markers[0],"eye_offset":eye-flight._pose.origin})
	check(flight.snapshot().mining_targeting.selected_object_index==0 and flight.snapshot().mining_targeting.elapsed_ms>3800,"Live first-flight aim failed to acquire the visible source asteroid")
	for key in ["mission","progress","cargo_used","campaign_cursor","mining_completed","reward_credits"]:check(flight.snapshot()[key]==prior[key],"Asteroid selection granted unearned progress: "+key)
	if args.size()==4:await render(lib,args[2],args[3],captures)

func render(lib: RefCounted, pixels: String, directory: String,captures: Dictionary):
	var visuals:=Visuals.new()
	if not visuals.open(pixels,lib.manifest):check(false,visuals.error);return
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,captures["5"]):check(false,scene.error);canvas.free();return
	var art: Dictionary=scene.scan_animation.source();var original: Image=visuals.load_image(art.resource)
	for i in frames:
		var rect:=Rect2i(art.rect.position+Vector2i(i*art.frame_size,0),Vector2i.ONE*art.frame_size)
		check(scene.scan_animation._frames[i].get_image().get_data()==original.get_region(rect).get_data(),"Acquisition frame differs from original pixels")
	for label in captures:
		var flight: RefCounted=captures[label];var held: Dictionary=flight.snapshot()
		check(scene.present(flight),scene.error)
		for i in 3:await process_frame
		check(canvas.get_texture().get_image().save_png(directory.path_join("scan-"+label+"-desktop.png"))==OK,"Could not save desktop scan capture")
		check(scene.reticle.visible and scene.target_frame.visible and flight.snapshot()==held,"Rendering hid the reticle or advanced acquisition")
		if label=="55":
			check(scene.scan_animation.frame_rect().size==Vector2(20,20),"Desktop acquisition is not compact")
			canvas.size=Vector2i(420,800);scene.set_mobile_layout(true)
			var phone: RefCounted=flight
			for i in 60:
				phone=phone.evaluate(100,Vector2.ZERO,0.0,false,canvas.size)
				if phone==null:check(false,"Phone viewport acquisition failed");canvas.free();return
			check(scene.present(phone),scene.error)
			for i in 3:await process_frame
			check(scene.scan_animation.frame_rect().size==Vector2(40,40),"Phone acquisition lost its original size")
			check(canvas.get_texture().get_image().save_png(directory.path_join("scan-acquired-phone.png"))==OK,"Could not save phone scan capture")
	var accepted: Dictionary=scene.scan_animation._sample.duplicate(true)
	var malformed: RefCounted=captures["55"].fork_for_frame();malformed._targeting._sample.animation_frame=9999
	check(not scene.present(malformed) and scene.scan_animation._sample==accepted,"Rejected target presentation replaced the last good frame")
	canvas.free()

func fresh() -> RefCounted:
	var scanner:=Targeting.new();check(scanner.configure(bindings,cat,construction,radii,frames),scanner.error);return scanner
func arranged(distances: Array) -> RefCounted:
	var result: RefCounted=construction.scenery_owner()
	# Live scenery uses copy-on-write updates. Private fixture edits must detach
	# the inner owners too, since they bypass those update methods.
	result._bodies=result._bodies.fork_for_frame();result._motion=result._motion.fork_for_frame()
	for i in result._destruction.size():result._destruction[i]=result._destruction[i].fork_for_frame()
	for i in result._bodies._rows.size():
		var point:=Vector3(10000+i,0,100000)
		if i<distances.size():point=Vector3(0,0,-float(distances[i]))
		result._bodies._rows[i].position=point;result._motion._field.objects[i].position=point
	return result
func elapse(scanner: RefCounted, milliseconds: int) -> bool:
	if milliseconds==0:return scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,0,true)
	while milliseconds>0:
		var step:=mini(100,milliseconds)
		if not scanner.advance(world,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,step,true):return false
		milliseconds-=step
	return true
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
