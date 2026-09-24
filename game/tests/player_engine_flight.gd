extends SceneTree
## Detached second-mining departure, close-approach and lethal-contact fixtures.
## Source capture radio flags exercise the exact Frame cue adapter separately;
## this component test neither earns nor publishes a convoy career.
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Fixture=preload("res://tests/full_hold_control.gd")
const DeathFixture=preload("res://tests/player_death_flight.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
var checks:=0
var failures:=0
var captures:={}

func _initialize() -> void:call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit content, bindings and visuals")
	if args.size()==3:await verify(args)
	print("Player engine flight: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not library.select_language("gb") or not visuals.open(args[2],library.manifest) or not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,library.error+bindings.error+cat.error+visuals.error+bodies.error+effects.error);return
	var fixture:=Fixture.new();var construction:=Construction.new()
	var prepared:=construction.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000,true,bodies,effects)
	fixture.free()
	if not prepared:check(false,construction.error);return
	var world:=Frame.new()
	if not world.configure(bindings,cat,library,construction,"E",.5):check(false,world.error);return
	var initial:=world.snapshot()
	if bindings.engine_particles.is_empty():
		check(world.engine_particle_owner()==null and not initial.has("engine_particles"),"Pack without nozzle declarations invented exhaust capability")
		var next:=step(world,100)
		check(next!=null and next.engine_particle_owner()==null,"Missing nozzle capability changed after advancing")
		await render(library,bindings,visuals,cat,{"legacy":world})
		return
	if bindings.engine_particle_owners.is_empty():
		check(world.engine_particle_owner()!=null and initial.engine_particles.owners.size()==4,"Older Mac binding lost Betty's verified exhaust manager")
		check(not Frame.Engines.Definitions.available_for(bindings,10),"Legacy Betty fallback invented opening ship exhaust")
	check(initial.engine_particles.engine_enabled and initial.engine_particles.draw_enabled and not initial.engine_particles.player_hidden,"Cursor4 inherited the source cursor1-only engine disable")
	check(initial.engine_particles.elapsed_ms==0 and initial.engine_particles.owners.size()==4,"Fresh flight retained another manager or clock")
	var identity: RefCounted=world.engine_particle_owner().presentation_identity()
	var detached: RefCounted=world.engine_particle_owner()
	check(detached.set_engine_enabled(false) and world.snapshot()==initial,"External exhaust fork changed the accepted flight")
	check(world.evaluate(100,Vector2.ONE,0,true).snapshot()==initial,"Paused entry changed exhaust age or RNG")
	check(not world.configure(bindings,cat,library,construction,"E",INF) and world.snapshot()==initial and world.engine_particle_owner().presentation_identity()==identity,"Failed configuration replaced the accepted manager")
	world=step(world,10)
	if world==null:return
	var reference: RefCounted=world.engine_particle_owner()
	world=step(world,40)
	if world==null:return
	check(reference.advance(world.snapshot().player_statistics_pose,40) and reference.snapshot()==world.snapshot().engine_particles,"Live manager did not consume the current retained statistics pose")
	check(world.snapshot().engine_particles.births.values()==[10,10,10,10],"Normal cruise changed source movement-based births")
	for i in 160:
		if world.dialogue_visible():break
		world=step(world,100)
		if world==null:return
	check(world.dialogue_visible() and world.snapshot().entry_released and world.snapshot().engine_particles.engine_enabled,"Ordinary entry release disabled exhaust or omitted its briefing")
	var modal: Dictionary=world.snapshot().engine_particles
	check(world.evaluate(100).snapshot().engine_particles==modal,"Modal briefing aged exhaust")
	world=world.navigate("next")
	if world==null:check(false,"Could not acknowledge the detached second-flight briefing");return
	check(world.snapshot().engine_particles==modal and not world.dialogue_visible(),"Action-only acknowledgement advanced exhaust")
	var accepted:=world.snapshot()
	var rejected: RefCounted=world.fork_for_frame();rejected._shot.target="unsupported"
	var held: Dictionary=rejected.snapshot()
	check(rejected.evaluate(100)==null and rejected.snapshot()==held and world.snapshot()==accepted,"Late failure committed prospective exhaust or RNG")
	var banking: RefCounted=world.fork_for_frame();banking._model_basis=Basis(Vector3.BACK,.4)
	reference=banking.engine_particle_owner()
	banking=step(banking,100,Vector2(.5,-.5),.7)
	if banking==null:return
	check(reference.advance(banking.snapshot().player_statistics_pose,100) and reference.snapshot()==banking.snapshot().engine_particles,"Exhaust sampled the new rendered bank instead of statistics")
	captures.flight=banking
	verify_mining(world)
	verify_death(world)
	verify_capture(bindings,world)
	check(world.snapshot()==accepted and world.engine_particle_owner().presentation_identity()==identity,"Detached transition checks modified the accepted flight")
	if failures==0:await render(library,bindings,visuals,cat,captures)
	var old: WeakRef=weakref(world._engine_particles)
	check(world.configure(bindings,cat,library,construction,"E",.5) and world.engine_particle_owner().presentation_identity()!=identity and world.snapshot().engine_particles.elapsed_ms==0 and old.get_ref()==null,"Repeated configure retained its former owner or simulation clock")
	old=weakref(world._engine_particles);world.clear()
	check(world.snapshot().is_empty() and world.engine_particle_owner()==null and old.get_ref()==null,"Flight clear retained exhaust resources")

func step(world: RefCounted,milliseconds: int,command:=Vector2.ZERO,throttle:=1.0) -> RefCounted:
	var next: RefCounted=world.evaluate(milliseconds,command,throttle)
	if next==null:check(false,world.error)
	return next

func verify_mining(ready: RefCounted) -> void:
	var fixture:=DeathFixture.new();fixture.ready=ready
	var drilling: RefCounted=fixture.drilling()
	check(fixture.failures==0 and drilling!=null,"Native close-approach fixture failed")
	fixture.free()
	if drilling==null:return
	var held: Dictionary=drilling.snapshot().engine_particles
	check(not held.engine_enabled and not held.draw_enabled and held.owners.values().all(func(row):return not row.exhaust.enabled and row.exhaust.visible),"Mining capture confused draw/emission with destructive visibility")
	var later:=step(drilling,100)
	if later==null:return
	check(later.snapshot().engine_particles.elapsed_ms==held.elapsed_ms+100 and later.snapshot().engine_particles.births.values()==[0,0,0,0],"Stopped mining exhaust failed to age or kept birthing")
	captures.mining=drilling
	var released: RefCounted=drilling.stop_mining()
	if released==null:check(false,drilling.error);return
	var enabled: Dictionary=released.snapshot().engine_particles
	check(enabled.engine_enabled and enabled.draw_enabled and enabled.elapsed_ms==held.elapsed_ms,"Manual drill release failed to enable exhaust without advancing its clock")
	for key in held.owners:
		check(enabled.owners[key].exhaust.slots==held.owners[key].exhaust.slots and enabled.owners[key].exhaust.random==held.owners[key].exhaust.random,"Mining release erased live particles or consumed RNG: "+key)
	captures.released=released

func verify_death(ready: RefCounted) -> void:
	var fixture:=DeathFixture.new();fixture.ready=ready
	var before: Dictionary=ready.snapshot().engine_particles
	var reference: RefCounted=ready.engine_particle_owner()
	var dead: RefCounted=fixture.lethal(ready,100)
	check(fixture.failures==0 and dead!=null,"Native lethal-contact fixture failed")
	fixture.free()
	if dead==null:return
	var state: Dictionary=dead.snapshot()
	check(reference.advance(state.player_statistics_pose,100) and reference.set_engine_enabled(false) and reference.snapshot()==state.engine_particles,"Death disabled exhaust before its early manager pass")
	check(state.engine_particles.elapsed_ms==before.elapsed_ms+100 and not state.engine_particles.draw_enabled and state.engine_particles.owners.values().all(func(row):return row.exhaust.visible),"Death deleted live slots or left its manager drawing")
	var later:=step(dead,100)
	if later==null:return
	check(later.snapshot().engine_particles.births.values()==[0,0,0,0] and later.snapshot().engine_particles.elapsed_ms==before.elapsed_ms+200,"Death tail stopped the exhaust clock or resumed emission")
	captures.death=dead

func verify_capture(bindings: RefCounted,ready: RefCounted) -> void:
	var capture:=Capture.new();check(capture.configure(bindings),capture.error)
	var radio:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,"started":[false,true,false,false,false],"finished":[false,false,false,false,false]}
	var pose: Transform3D=ready.snapshot().player_pose
	check(capture.advance(0,radio,pose,pose),capture.error)
	radio.finished[1]=true;check(capture.advance(0,radio,pose,pose),capture.error)
	var frame: RefCounted=ready.fork_for_frame()
	var before: Dictionary=frame.snapshot().engine_particles
	check(frame._apply_convoy_engine_cue(capture.snapshot().frame) and frame.snapshot().engine_particles==before,"Convoy disabled exhaust before its capture-view cue")
	radio.started[2]=true;radio.finished[2]=true;radio.started[3]=true;radio.finished[3]=true
	check(capture.advance(0,radio,pose,pose) and capture.snapshot().frame.stop_nozzle_emitters,"Source capture-view cue was not produced")
	check(frame._apply_convoy_engine_cue(capture.snapshot().frame),frame.error)
	var stopped: Dictionary=frame.snapshot().engine_particles
	check(stopped.engine_enabled and stopped.draw_enabled and not stopped.player_hidden,"Foreign handle stop changed player or manager flags")
	for i in 4:
		var key:="player_nozzle%d"%i;var emitter: Dictionary=stopped.owners[key].exhaust
		check(emitter.enabled==(i>=2) and emitter.visible and emitter.slots==before.owners[key].exhaust.slots and emitter.random==before.owners[key].exhaust.random,"Capture stopped the wrong nozzle or erased retained slots: "+key)
	var owner: RefCounted=frame.engine_particle_owner()
	for bad in [-1,4,.5,"0"]:check(not owner.set_nozzle_emitting(bad,false) and owner.snapshot()==stopped,"Invalid nozzle changed the accepted manager")
	check(not owner.set_nozzle_emitting(0,1) and owner.snapshot()==stopped,"Non-boolean emission changed the manager")
	pose.origin+=pose.basis.z*200
	check(owner.advance(pose,100),owner.error)
	var births: Dictionary=owner.snapshot().births
	check(births.player_nozzle0==0 and births.player_nozzle1==0 and births.player_nozzle2>0 and births.player_nozzle3>0,"Stopped and continuing convoy nozzles were conflated")
	check(ready.snapshot().engine_particles==before,"Capture fixture modified the accepted flight")

func render(library: RefCounted,bindings: RefCounted,visuals: RefCounted,cat: RefCounted,frames: Dictionary):
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var scene:=Scene.new();viewport.add_child(scene)
	var first: RefCounted=frames.values()[0]
	if not scene.build(library,bindings,visuals,cat,first):check(false,scene.error);viewport.free();return
	if first.engine_particle_owner()==null:
		check(scene.engine_particles==null,"Legacy scene invented exhaust surfaces");viewport.free();return
	check(scene.engine_particles.items.size()==4,"Live scene omitted the four original nozzle surfaces")
	for item in scene.engine_particles.items:check(item.node.get_meta("source_material_id")==20090 and item.node.get_meta("source_texture_id")==24202,"Live exhaust changed original art")
	var directory:=OS.get_environment("GOF2_CAPTURE_DIR")
	if not directory.is_empty():DirAccess.make_dir_recursive_absolute(directory)
	for label in frames:
		var frame: RefCounted=frames[label];var state: Dictionary=frame.snapshot()
		check(scene.present(frame,true,987654321),scene.error)
		check(scene.engine_particles.frame.elapsed_ms==state.engine_particles.elapsed_ms,"Scene used wall time or the NPC clock for exhaust: "+label)
		if label in ["mining","death"]:check(scene.engine_particles.frame.counts==[0,0,0,0],"Disabled manager remained visible: "+label)
		if DisplayServer.get_name()!="headless":
			var picture: Image=await rendered(viewport)
			if not directory.is_empty():check(picture.save_png(directory.path_join("engine-flight-"+label+".png"))==OK,"Live exhaust capture failed")
	check(scene.present(first),scene.error)
	var accepted: Dictionary=scene.engine_particles.frame
	var wrong: Dictionary=first.snapshot();wrong.engine_particles.elapsed_ms+=1
	check(not scene.present(first,false,0,wrong) and scene.engine_particles.frame.counts==accepted.counts and scene.engine_particles.frame.elapsed_ms==accepted.elapsed_ms,"Stale exhaust packet changed the accepted scene")
	var foreign: RefCounted=first.fork_for_frame();foreign._engine_particles._presentation_identity=RefCounted.new()
	check(not scene.present(foreign) and scene.engine_particles.frame.counts==accepted.counts,"Another exhaust generation changed the accepted scene")
	if DisplayServer.get_name()!="headless":
		var visible: Image=await rendered(viewport)
		var hidden: RefCounted=first.fork_for_frame();hidden._engine_particles.set_player_hidden(true)
		check(scene.present(hidden),scene.error)
		var hidden_image: Image=await rendered(viewport)
		check(scene.engine_particles.frame.counts==[0,0,0,0],"Presentation-only hidden fixture failed")
		var changed:=0
		for y in visible.get_height():
			for x in visible.get_width():
				var a:=visible.get_pixel(x,y);var b:=hidden_image.get_pixel(x,y)
				if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
		check(changed>10,"Live flight exhaust contributed too few visible pixels: "+str(changed))
		print("Live original exhaust additive pixels: ",changed)
		if not directory.is_empty():hidden_image.save_png(directory.path_join("engine-flight-hidden.png"))
	var material: WeakRef=weakref(scene.engine_particles.items[0].node.material_override)
	scene.clear();check(scene.engine_particles==null and material.get_ref()==null,"Scene clear retained exhaust materials")
	viewport.free()

func rendered(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
