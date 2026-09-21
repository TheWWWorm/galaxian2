extends SceneTree
const World = preload("res://src/simulation/opening_scenery.gd")
const Session = preload("res://src/presentation/opening_session.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Bodies = preload("res://src/content/scenery_body_resources.gd")
const Effects = preload("res://src/content/scenery_effect_resources.gd")
const Response = preload("res://src/presentation/surface_response.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for offset in range(0,args.size()-2,3):
		var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new();var visuals := Visuals.new()
		var bodies := Bodies.new();var effects := Effects.new()
		if not library.open(args[offset]) or not library.select_language("gb") or not bindings.open(args[offset+1],library.manifest) or not catalogues.open(library) or not visuals.open(args[offset+2],library.manifest) or not bodies.configure(library,bindings) or not effects.configure(library,bindings):
			check(false,library.error+bindings.error+catalogues.error+visuals.error+bodies.error+effects.error);continue
		check_world(bindings,catalogues,bodies,effects)
		await check_session(library,bindings,visuals)
		print(library.manifest.profile.edition,": ordered world destruction, atomic failure, retirement, retained cargo and presentation verified")
	print("Scenery world checks: %d failures" % failures)
	quit(1 if failures else 0)

func candidates(field: Dictionary) -> Array:
	var indices := []
	for row in field.objects:
		if row.source_size_value!=7 and row.spin!=Vector3.ZERO:indices.append(row.index)
		if indices.size()==3:break
	return indices

func check_world(bindings: RefCounted, catalogues: RefCounted, bodies: RefCounted, effects: RefCounted) -> void:
	var world := World.new()
	if not world.configure(bindings,catalogues,1789100000,true,bodies,effects):check(false,world.error);return
	var initial := world.snapshot()
	var observed: Dictionary=world.read_snapshot()
	check(observed.is_read_only() and observed.objects.is_read_only() and observed.objects[0].is_read_only() and observed.bodies.objects[0].vitals.is_read_only(),"Shared scenery observations must be immutable at every depth")
	var branch: RefCounted=world.fork_for_frame()
	check(branch.update(100,Vector3.ZERO) and world.read_snapshot()==observed and branch.read_snapshot()!=observed,"A branch changed or reused an old scenery observation")
	var editable:=world.snapshot();editable.objects[0].position=Vector3.ZERO
	check(world.read_snapshot()==observed,"An editable snapshot changed the shared frame")
	check(world.update(0,Vector3.ZERO),world.error)
	var frozen := world.snapshot()
	check(frozen.objects==initial.objects and frozen.destruction==initial.destruction and frozen.random_state==initial.random_state,"Zero-time field advanced motion, lifecycle or RNG")
	check(world.update(100,Vector3.ZERO) and world.snapshot().random_state==initial.random_state,"Intact world consumed construction RNG")
	var selected := candidates(initial)
	if selected.size()!=3:check(false,"Fixture has too few spinning ordinary actors");return
	var a: int=selected[0];var b: int=selected[1];var survivor: int=selected[2]
	# Independent 48-bit fixture: roll 19, quantity 3, then roll 20. Reverse
	# damage delivery must still consume these values in world array order.
	world._random_state={"state":25214903899}
	check(world._bodies.normal_hit(b,2147483647).destroyed_now and world._bodies.normal_hit(a,2147483647).destroyed_now,"Could not prepare two destroyed actors")
	var pending := world.snapshot()
	check(world.has_pending_destruction() and world.update(0,Vector3.ZERO) and world.snapshot()==pending,"Zero time triggered pending destruction")
	world._bodies._rows[b].motion_scalar=1.0
	var invalid := world.snapshot()
	check(not world.update(100,Vector3.ZERO) and world.snapshot()==invalid and world.take_events().is_empty(),"Later actor failure committed earlier RNG, clock, detail, spin or accounting")
	world._bodies._rows[b].motion_scalar=0.0
	check(world.update(100,Vector3.ZERO),world.error)
	var triggered := world.snapshot();var events := world.take_events()
	check(events.size()==2 and events[0].object_index==a and events[1].object_index==b,"Destruction order followed damage delivery instead of the source array")
	check(triggered.random_state.state==82285143057300,"World reseeded or used a separate RNG for each actor")
	check(events[0].cargo.quantity==3 and events[1].cargo.is_empty(),"Ordered cargo draws differ from independent fixture")
	check(triggered.remaining_count==initial.objects.size()-2 and triggered.destroyed_count==2,"World did not apply destruction accounting once")
	check(not world.has_pending_destruction() and world.take_events().is_empty(),"Processed deaths remained pending or repeated events")
	for index in [a,b]:
		check(triggered.objects[index]==pending.objects[index] and triggered.destruction[index].effect.elapsed_ms==0,"Trigger tick ran spin or effect time")
		check(not world._bodies.collision_context(index).eligible,"Destroyed body remained a projectile target")
	check(triggered.objects[survivor].angles!=pending.objects[survivor].angles,"Another actor's trigger stopped intact spin")
	var cargo: Dictionary=triggered.destruction[a].lifecycle.cargo
	check(cargo.pose==Transform3D(Basis.IDENTITY,triggered.objects[a].position),"Dropped junk inherited asteroid scale/rotation")
	var previous := triggered
	for frame in 110:
		check(world.update(100,Vector3.ZERO),world.error)
		var next := world.snapshot()
		for index in [a,b]:
			var old: Dictionary=previous.destruction[index].lifecycle
			var current: Dictionary=next.destruction[index].lifecycle
			check(next.destruction[index].effect.pose==triggered.destruction[index].effect.pose,"Spinning hidden mesh rotated the captured breakup")
			if old.actor_state==4:
				check(not next.bodies.objects[index].active,"Expired actor statistics stayed active")
				if previous.bodies.objects[index].active:
					check(current.update_enabled and next.objects[index].angles!=previous.objects[index].angles,"Retirement skipped the final active spin tick")
				else:
					check(not current.update_enabled and next.objects[index]==previous.objects[index],"Retired actor continued spinning")
			elif current.actor_state==4:check(next.bodies.objects[index].active,"Effect expiry retired statistics on the same tick")
		check(next.destruction[a].lifecycle.cargo==cargo,"Effect expiry discarded or changed cargo")
		check(next.random_state==triggered.random_state and next.destroyed_count==2 and world.take_events().is_empty(),"Later effect frame consumed RNG or repeated accounting")
		previous=next
	check(not previous.destruction[a].lifecycle.update_enabled and not previous.destruction[b].lifecycle.update_enabled,"Actors did not reach retirement")
	var before_failure := world.snapshot()
	check(not world.update(100,Vector3.ZERO,1.0,Vector3.INF) and world.snapshot()==before_failure,"Invalid detail reference partially advanced the world")
	world.clear();check(world.snapshot().is_empty() and world.take_events().is_empty(),"World clear retained lifecycle state")

func check_session(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> void:
	var viewport := SubViewport.new();viewport.size=Vector2i(384,384);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var session := Session.new();viewport.add_child(session)
	if not session.configure(library,bindings,visuals,0,0.5,1789100000):check(false,session.error);viewport.free();return
	var renderer: Node3D=session.scenery.destruction
	check(renderer!=null and renderer._effects.is_empty() and renderer._cargo.is_empty(),"Scene eagerly instantiated hidden effects or cargo")
	var identity: RefCounted=session._scenery._presentation_identity
	session._scenery._presentation_identity=RefCounted.new()
	check(not session.present(),"Presentation switched to another logical world with matching content IDs")
	session._scenery._presentation_identity=identity
	check(session.present(),session.error)
	var field: Dictionary=session.snapshot().scenery
	for levels in session.scenery._levels:
		for model in levels:
			for material in model.materials:check(material.shader==Response.ShaderSource,"Scenery LOD retained an inconsistent material response")
	var chosen := candidates(field);var a: int=chosen[0];var b: int=chosen[1]
	await capture_session(session,viewport,a,library.manifest.profile.edition,"intact")
	session._scenery._random_state={"state":25214903899}
	if session._world_frame!=null:
		# Six independent inverse-LCG steps before the fixture above. Force all
		# three holding selections due: their six draws must precede scenery.
		session._scenery._random_state={"state":80674035714597}
		session._world_frame._random_state={"state":80674035714597}
		for guide in session._world_frame._controller._guidance:guide._state.selection_elapsed_ms=5000
	session._scenery._bodies.normal_hit(b,2147483647);session._scenery._bodies.normal_hit(a,2147483647)
	session._scenery._bodies._rows[b].motion_scalar=1.0
	var failed_frame := session.snapshot();var old_clock: int=session._clock._last_ms
	check(not session.step(100000) and session.snapshot()==failed_frame and session._clock._last_ms==old_clock,"World failure consumed the opening frame clock or timeline")
	session._scenery._bodies._rows[b].motion_scalar=0.0
	check(session.step(100000),session.error)
	check(session.snapshot().elapsed_ms==100,"Retry lost the failed frame's elapsed time")
	check(session.snapshot().scenery.random_state.state==82285143057300,"Actor refresh did not consume RNG before scenery destruction")
	check(not session.scenery.objects[a].visible and not session.scenery.objects[b].visible,"Destroyed intact models remained visible")
	check(renderer._effects.size()==2 and renderer._cargo.size()==1,"Lazy effect/cargo scene assembly is incorrect")
	var cargo: Node3D=renderer._cargo[a]
	check(cargo.transform==Transform3D(Basis.IDENTITY,field.objects[a].position) and cargo.get_meta("source_quantity")==3,"Rendered cargo pose or quantity differs from its owner")
	for material in cargo.materials:check(material.shader==Response.ShaderSource,"Cargo retained an inconsistent material response")
	var mesh: Mesh=renderer._effects[a].models[0].instances[0].mesh
	check(mesh==renderer._effects[b].models[0].instances[0].mesh,"Same effect geometry was decoded separately for each actor")
	check(session.step(200000),session.error)
	var paused := session.snapshot()
	check(session.set_pause("user",true,200000) and session.step(400000) and session.snapshot()==paused,"Pause advanced destruction clocks or world state")
	check(session.set_pause("user",false,400000) and session.step(500000),session.error)
	await capture_session(session,viewport,a,library.manifest.profile.edition,"breakup")
	# Corrupt only the second actor's candidate clock after the first can sample.
	# The first effect and all existing nodes must retain the preceding frame.
	var first: Node3D=renderer._effects[a]
	var before: Dictionary=first._samplers[0].snapshot()
	var before_pose: Transform3D=first.models[0].instances[0].transform
	var saved_time: int=session._scenery._destruction[b]._effect._state.models[1].time_ms
	session._scenery._destruction[b]._effect._state.models[1].time_ms=-1
	check(not session.scenery.apply_destruction(session._scenery,session.camera.transform,PackedByteArray([255,255,255,255]),Vector4(1,1,1,1),1.0),"Invalid later actor was presented")
	check(first._samplers[0].snapshot()==before and first.models[0].instances[0].transform==before_pose and renderer._effects.size()==2,"Failed field presentation partially committed an earlier actor")
	session._scenery._destruction[b]._effect._state.models[1].time_ms=saved_time
	var now := 500000
	for frame in 110:
		now+=100000;check(session.step(now),session.error)
	check(renderer._effects.is_empty() and renderer._cargo.size()==1 and renderer._cargo[a]==cargo and cargo.is_visible_in_tree(),"Effect cleanup removed retained cargo or kept expired geometry")
	check(not session.scenery.objects[a].visible,"LOD refresh resurrected a retired asteroid")
	await capture_session(session,viewport,a,library.manifest.profile.edition,"cargo")
	var resources: RefCounted=renderer._models
	session.clear();check(resources._prototypes.is_empty(),"Scene teardown leaked cached model prototypes")
	viewport.free()

func capture_session(session: Node3D, viewport: SubViewport, object_index: int, edition: String, stage: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var field: Dictionary=session.snapshot().scenery
	var row: Dictionary=field.objects[object_index]
	var extent: float=field.bodies.objects[object_index].model_radius*row.scale
	var camera: Camera3D=session.camera
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=extent*4.0
	camera.near=0.1;camera.far=100000;camera.transform=Transform3D(Basis.IDENTITY,row.position+Vector3.BACK*extent*5.0)
	check(session.scenery.apply_destruction(session._scenery,camera.transform,PackedByteArray([255,255,255,255]),Vector4(1,1,1,1),1.0),session.scenery.error)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	check(image!=null and not image.is_empty(),"Scenery world GPU capture is empty")
	var subject: Node3D=session.scenery.objects[object_index] if stage=="intact" else session.scenery.destruction._effects[object_index] if stage=="breakup" else session.scenery.destruction._cargo[object_index]
	subject.visible=false
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var hidden: Image=viewport.get_texture().get_image();subject.visible=true
	var changed := 0
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x,y);var b := hidden.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>0.03:changed+=1
	check(changed>8,"World presentation layer produced no visible pixels: "+stage)
	var path := OS.get_environment("GOF2_SCENERY_WORLD_CAPTURE")
	if not path.is_empty():check(image.save_png(path.path_join("%s-%s.png" % [edition,stage]))==OK,"Could not save private world capture")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
