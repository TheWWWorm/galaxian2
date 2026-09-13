extends SceneTree
const Frame=preload("res://src/simulation/opening_world_frame.gd")
const Timeline=preload("res://src/simulation/opening_detail_timeline.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Deaths=preload("res://src/content/npc_destruction_resources.gd")
const Definitions=preload("res://src/content/projectile_impact_definitions.gd")
const State=preload("res://src/simulation/ordinary_impact_state.gd")
const Geometry=preload("res://src/presentation/ordinary_impact_geometry.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):await verify_profile(args[i],args[i+1],args[i+2])
	print("Ordinary impact geometry checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify_profile(content: String, pack: String, textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not visuals.open(textures,library.manifest):check(false,library.error+bindings.error+catalogues.error+visuals.error);return
	var bodies:=Bodies.new();var effects:=Effects.new();var deaths:=Deaths.new();var scenery:=Scenery.new();var owner:=Frame.new();var timeline:=Timeline.new()
	var counts:=[];counts.resize(23);counts.fill(1)
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not deaths.configure(library,bindings):check(false,bodies.error+effects.error+deaths.error);return
	if not scenery.configure(bindings,catalogues,1789100000,true,bodies,effects) or not scenery.complete_world_initialization(bindings,catalogues):check(false,scenery.error);return
	if not owner.configure(bindings,catalogues,scenery,0.5,deaths) or not timeline.configure(bindings,catalogues,library,counts,1.0,0.5):check(false,owner.error+timeline.error);return
	if not owner.configure_player_flight(bindings,catalogues,library,scenery,1.0) or not owner.configure_projectile_visuals(bindings,library):check(false,owner.error);return
	if bindings.opening_staging.get("projectile_impacts",{}).is_empty():
		check(owner.impact_visual_owner()==null,"Legacy world fabricated impact clocks")
		var unavailable:=State.new();check(not unavailable.configure(bindings,library,owner.snapshot()),"Legacy pack provided impact capability")
		return
	var clock: RefCounted=owner.impact_visual_owner()
	check(clock!=null,"World omitted impact ownership")
	if clock==null:return
	var rules: Dictionary=bindings.opening_staging.projectile_impacts
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in rules.provenance:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.opening_staging).is_empty(),"Disconnected impact provenance accepted")
	var initial: Dictionary=clock.snapshot()
	check(initial.weapons.size()==5,"Impact population omitted a weapon")
	for i in initial.weapons.size():
		check(initial.weapons[i].model_id==(14600 if i<2 else 14605),"Wrong original impact model")
		for slot in initial.weapons[i].slots:check(not slot.playing and slot.time_ms==33 and slot.end_ms==466 and slot.sample_time_ms==33,"Fresh impact model did not start disabled at source time")
	var geometry:=Geometry.new();root.add_child(geometry)
	if not geometry.build(clock,library,visuals,bindings):check(false,geometry.error);geometry.free();return
	var prepared:=geometry.prepare_world(clock,owner.snapshot(),Transform3D.IDENTITY)
	check(not prepared.is_empty(),geometry.error)
	if prepared.is_empty():geometry.free();return
	geometry.commit_world(prepared)
	for gun in geometry.guns:
		for slot in gun.slots:check(not slot.visible,"Unused impact slot rendered")
	check_slot_lifecycle(clock,owner.snapshot(),geometry)
	await capture_models(clock,owner.snapshot(),geometry,library.manifest.profile.edition)
	check_world_contacts({"world_frame":owner,"timeline":timeline,"scenery":scenery},geometry)
	geometry.clear();check(geometry.guns.is_empty() and geometry.get_child_count()==0,"Impact reset retained geometry");geometry.free()
	print(library.manifest.profile.edition,": impact slots, sample-before-hit timing, camera roots, contact scheduling and rollback verified")

func check_slot_lifecycle(original: RefCounted, world: Dictionary, geometry: Node3D) -> void:
	var clock: RefCounted=original.fork_for_frame();var before: Dictionary=clock.snapshot()
	for delta in [-1,151,0.5,NAN,true]:check(not clock.advance(delta) and clock.snapshot()==before,"Invalid impact time changed a clock")
	var fixture:=world.duplicate(true)
	fixture.primaries.guns[0].projectiles.slots[0]={"id":7,"position":Vector3(1,2,3)}
	var events:=empty_events(fixture);events.primary[0].contacts=[hit(0,7),hit(0,7)]
	check(clock.advance(100) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
	check(clock.snapshot().hits.size()==2,"Overlapping target contacts were deduplicated")
	var slot: Dictionary=clock.snapshot().weapons[0].slots[0]
	check(slot.playing and slot.time_ms==33 and slot.sample_time_ms==33 and slot.position==Vector3(1,2,3),"New impact advanced or lost the original shot position")
	var after: Dictionary=clock.snapshot();check(not clock.apply_contacts(fixture,events.primary,events.npc) and clock.snapshot()==after,"Impact pass replayed without a new frame")
	fixture.elapsed_ms=100;events=empty_events(fixture)
	check(clock.advance(100) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
	slot=clock.snapshot().weapons[0].slots[0];check(slot.time_ms==133 and slot.sample_time_ms==133,"Impact did not sample its next update")
	fixture.elapsed_ms=200;fixture.impact_visuals=clock.snapshot()
	var camera:=Transform3D(Basis.from_euler(Vector3(0.2,0.3,-0.4)),Vector3(50,60,70))
	var prepared: Dictionary=geometry.prepare_world(clock,fixture,camera)
	check(not prepared.is_empty(),geometry.error)
	if prepared.is_empty():return
	geometry.commit_world(prepared)
	var local_sampler: RefCounted=geometry._samplers[0][0].fork_for_frame()
	var local: Dictionary=local_sampler.sample(133,Transform3D.IDENTITY)
	check(geometry.guns[0].slots[0].instances[0].transform==Sampler.multiply(Transform3D(camera.basis,Vector3(1,2,3)),local.surfaces[0].pose),"Impact root did not copy camera basis and shot position")
	var retained:=rendered(geometry);var samples:=sampler_states(geometry)
	var broken: RefCounted=clock.fork_for_frame();broken._state.weapons[4].slots[0].position=Vector3(NAN,0,0)
	var invalid:=fixture.duplicate(true);invalid.impact_visuals=broken.snapshot()
	check(geometry.prepare_world(broken,invalid,camera).is_empty() and rendered(geometry)==retained and sampler_states(geometry)==samples,"Failed late impact slot changed earlier geometry")
	events.primary[0].contacts=[hit(0,7)]
	check(clock.advance(0) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
	slot=clock.snapshot().weapons[0].slots[0]
	check(slot.time_ms==33 and slot.sample_time_ms==133,"Hit restart reset already sampled animation")
	fixture.impact_visuals=clock.snapshot();prepared=geometry.prepare_world(clock,fixture,camera)
	check(not prepared.is_empty(),geometry.error)
	if not prepared.is_empty():geometry.commit_world(prepared)
	check(rendered(geometry)==retained,"Repeated zero-time hit prematurely erased an active flash")
	for delta in [150,150,133,0,1]:
		fixture.elapsed_ms=clock.snapshot().elapsed_ms;events=empty_events(fixture)
		check(clock.advance(delta) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
		if delta==133 or delta==0:check(clock.snapshot().weapons[0].slots[0].playing and clock.snapshot().weapons[0].slots[0].time_ms==466,"Impact hid before its exact final key")
	slot=clock.snapshot().weapons[0].slots[0]
	check(not slot.playing and slot.time_ms==466 and slot.sample_time_ms==466,"Impact did not stop and sample its final key after overshoot")
	fixture.elapsed_ms=clock.snapshot().elapsed_ms;fixture.impact_visuals=clock.snapshot()
	prepared=geometry.prepare_world(clock,fixture,camera);check(not prepared.is_empty(),geometry.error)
	if not prepared.is_empty():geometry.commit_world(prepared)
	check(not geometry.guns[0].slots[0].visible,"Stopped impact still rendered")
	var old_sample: Dictionary=geometry._samplers[0][0].snapshot()
	events.primary[0].contacts=[hit(0,7)]
	check(clock.advance(0) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
	fixture.impact_visuals=clock.snapshot();prepared=geometry.prepare_world(clock,fixture,camera)
	check(not prepared.is_empty(),geometry.error)
	if not prepared.is_empty():geometry.commit_world(prepared)
	check(geometry._samplers[0][0].snapshot()==old_sample,"Slot reuse discarded the final sampled model pose")
	fixture.elapsed_ms=clock.snapshot().elapsed_ms;events=empty_events(fixture)
	check(clock.advance(10),clock.error);var pending: Dictionary=clock.snapshot()
	events.npc[2].contacts=[hit(0,999)]
	check(not clock.apply_contacts(fixture,events.primary,events.npc) and clock.snapshot()==pending,"Invalid late contact partially committed impacts")

func check_world_contacts(state: Dictionary, geometry: Node3D) -> void:
	for tick in 1000:
		if state.timeline.snapshot().camera.shot.phase==4:break
		var next: Dictionary=state.world_frame.evaluate(state.timeline,state.scenery,100,true)
		check(not next.is_empty(),state.world_frame.error)
		if next.is_empty():return
		state=next
	check(state.timeline.snapshot().camera.shot.phase==4,"Impact fixture did not reach ordinary flight")
	var frame: RefCounted=state.world_frame.fork_for_frame()
	var primary: RefCounted=frame._primaries._guns[0].projectiles
	primary._elapsed_ms=int(primary.snapshot().weapon.interval_ms)+1
	var actor_pose: Transform3D=state.timeline.snapshot().combat.actors[0].pose
	check(primary.fire(actor_pose.origin,Vector3.BACK,true).get("fired",false),primary.error)
	var npc: RefCounted=frame._weapons._guns[0]
	npc._elapsed_ms=int(npc.snapshot().weapon.interval_ms)+1
	var motion: Dictionary=frame._flight.motion(state.timeline.snapshot().scene,4,100)
	check(npc.fire(motion.pose.origin,Vector3.BACK,true).get("fired",false),npc.error)
	state.world_frame=frame
	var saved:=snapshot(state)
	check(frame.evaluate(state.timeline,state.scenery,100,"invalid").is_empty() and snapshot(state)==saved,"Late radio failure committed impact clocks, positions or damage")
	var result: Dictionary=frame.evaluate(state.timeline,state.scenery,100,true)
	check(not result.is_empty(),frame.error)
	if result.is_empty():return
	var impacts: Dictionary=result.world_frame.snapshot().impact_visuals
	check(impacts.hits.any(func(row):return row.key=="player:0") and impacts.hits.any(func(row):return row.key=="npc:0"),"Real player/NPC contacts did not enter impact ownership")
	for row in impacts.hits:
		var index: int=impacts.weapons.find(impacts.weapons.filter(func(weapon):return weapon.key==row.key)[0])
		check(impacts.weapons[index].slots[row.slot].time_ms==33,"Impact advanced in its contact frame")
	var prepared: Dictionary=geometry.prepare_world(result.world_frame.impact_visual_owner(),result.world_frame.snapshot(),result.timeline.snapshot().camera.view.pose)
	check(not prepared.is_empty(),geometry.error)
	if not prepared.is_empty():geometry.commit_world(prepared)
	check(result.world_frame.snapshot().impact_visuals.elapsed_ms==result.world_frame.snapshot().elapsed_ms,"Impact clocks diverged from combat")

func capture_models(original: RefCounted, world: Dictionary, geometry: Node3D, edition: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var output:=OS.get_environment("GOF2_CAPTURE_DIR")
	if output.is_empty():return
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=100000;camera.current=true
	var background:=WorldEnvironment.new();background.environment=Environment.new();background.environment.background_mode=Environment.BG_COLOR;background.environment.background_color=Color.BLACK;root.add_child(background)
	for index in [0,2]:
		var clock: RefCounted=original.fork_for_frame();var fixture:=world.duplicate(true);var events:=empty_events(fixture)
		if index==0:fixture.primaries.guns[0].projectiles.slots[0]={"id":1,"position":Vector3.ZERO};events.primary[0].contacts=[hit(0,1)]
		else:fixture.weapons.actors[0].projectiles.slots[0]={"id":1,"position":Vector3.ZERO};events.npc[0].contacts=[hit(0,1)]
		check(clock.advance(0) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
		events=empty_events(fixture)
		check(clock.advance(100) and clock.apply_contacts(fixture,events.primary,events.npc),clock.error)
		fixture.elapsed_ms=100;fixture.impact_visuals=clock.snapshot()
		var prepared: Dictionary=geometry.prepare_world(clock,fixture,Transform3D.IDENTITY)
		check(not prepared.is_empty(),geometry.error)
		if prepared.is_empty():continue
		geometry.commit_world(prepared)
		var model: Node3D=geometry.guns[index].slots[0];var bounds:=AABB();var first:=true
		for mesh in model.instances:
			var extent: AABB=mesh.transform*mesh.mesh.get_aabb();bounds=extent if first else bounds.merge(extent);first=false
		var extent:=maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		camera.position=Vector3(bounds.get_center().x,bounds.get_center().y,bounds.end.z+extent+1000)
		camera.size=maxf(bounds.size.y,bounds.size.x/(float(root.size.x)/root.size.y))*1.25
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var pixels:=root.get_texture().get_image();var name:="impact-%s-%s.png"%[edition,"player" if index==0 else "npc"]
		check(pixels.save_png(output.path_join(name))==OK,"Impact screenshot failed")
		var lit:=0
		for y in pixels.get_height():
			for x in pixels.get_width():
				var pixel:=pixels.get_pixel(x,y)
				if maxf(pixel.r,maxf(pixel.g,pixel.b))>0.03:lit+=1
		check(lit>40,"Source impact model was not independently visible: "+name)
		print(name,": ",lit," lit pixels")
	camera.free();background.free()

func empty_events(world: Dictionary) -> Dictionary:
	var result:={"primary":[],"npc":[]}
	for gun in world.get("primaries",{}).get("guns",[]):result.primary.append({"mount_id":gun.mount_id,"contacts":[]})
	for actor in world.weapons.actors:result.npc.append({"actor_id":actor.actor_id,"contacts":[]})
	return result
func hit(slot: int, id: int) -> Dictionary:return {"slot":slot,"projectile_id":id,"geometry":{"hit":true}}
func snapshot(state: Dictionary) -> Dictionary:return {"world":state.world_frame.snapshot(),"timeline":state.timeline.snapshot(),"scenery":state.scenery.snapshot()}
func sampler_states(geometry: Node3D) -> Array:
	var result:=[]
	for gun in geometry._samplers:
		for sampler in gun:result.append(sampler.snapshot())
	return result
func rendered(geometry: Node3D) -> Array:
	var result:=[]
	for gun in geometry.guns:
		for slot in gun.slots:
			var row:={"visible":slot.visible,"poses":[]}
			for mesh in slot.instances:row.poses.append(mesh.transform)
			result.append(row)
	return result
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
