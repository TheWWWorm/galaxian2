extends SceneTree
const Timeline = preload("res://src/simulation/opening_detail_timeline.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const Detail = preload("res://src/presentation/ship_detail.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Camera = preload("res://src/presentation/flight_camera.gd")
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Opening detail timeout");quit(1))
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): await verify_source(args[i],args[i+1],args[i+2])
	print("Opening detail timeline checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String,pack: String,texture_pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new();var catalogues := Catalogues.new()
	check(library.open(content) and library.select_language("gb"),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(visuals.open(texture_pack,library.manifest),visuals.error)
	check(catalogues.open(library),catalogues.error)
	var counts := [];counts.resize(23);counts.fill(1)
	var timeline := Timeline.new()
	check(timeline.configure(bindings,catalogues,library,counts,1),timeline.error)
	var state := timeline.snapshot()
	if state.is_empty(): return
	check(state.detail_reference==Vector3.ZERO and state.scene.ship_detail.counter_ms==1001,"Fresh renderer initialization changed")
	check(state.scene.ship_detail.selections==select(bindings,state.scene,Vector3.ZERO,1),"Constructor refresh used authored controller eye too early")
	var before := state.duplicate(true)
	check(not timeline.update(100,true,false,false,NAN) and timeline.snapshot()==before,"Invalid first selection partially advanced opening or radio")
	check(timeline.update(100,true,true,false,NAN) and timeline.snapshot()==before,"Paused detail demanded unused inputs or advanced state")
	var zero := Timeline.new()
	check(zero.configure(bindings,catalogues,library,counts,1),zero.error)
	check(zero.update(0,true,false,false,1),zero.error)
	var zero_state := zero.snapshot()
	check(zero_state.detail_reference==Vector3.ZERO and zero_state.camera.view.is_empty() and zero_state.scene.ship_detail.counter_ms==0,"Zero-time update invented a camera view or skipped the due refresh")
	var viewport := SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var geometry := Geometry.new();viewport.add_child(geometry)
	check(geometry.build(library,visuals,bindings,catalogues,"high",true),geometry.error)
	if geometry.player==null: viewport.free();return
	check(geometry.apply_state(state.scene),geometry.error)
	check(geometry.actors[0].levels[0].instances[0].mesh==geometry.actors[2].levels[0].instances[0].mesh,"LOD assembly stopped sharing repeated hulls")
	check(geometry.actors[0].levels[0].materials[0]!=geometry.actors[2].levels[0].materials[0],"LOD assembly shared mutable materials")
	var camera := Camera3D.new();camera.current=true;viewport.add_child(camera)
	var projection := Camera.new();check(projection.configure(bindings.flight_projection,0,false).is_empty(),"Projection unavailable")
	var world := WorldEnvironment.new();world.environment=Environment.new()
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=0.8;viewport.add_child(world)
	var phases := {};var forced := 0;var periodic := 0;var held := 0
	for frame in 800:
		before=timeline.snapshot()
		var suppressed: bool = frame%7==3 or (before.radio.finished[int(bindings.opening_staging.formation.after_event_finished)] and not before.scene.formation_revealed)
		var setting := 0.2 if frame%2==0 else 1.0
		check(timeline.update(100,true,false,suppressed,setting),timeline.error)
		state=timeline.snapshot()
		var expected: Dictionary = before.scene.ship_detail.selections
		var counter: int = before.scene.ship_detail.counter_ms
		if not suppressed:
			counter+=100
			if counter>=1001:
				expected=select(bindings,before.scene,before.detail_reference,setting);counter=0;periodic+=1
			else: held+=1
		if state.scene.formation_revealed and not before.scene.formation_revealed:
			expected=select(bindings,state.scene,state.scene.camera_position_parameter,setting);forced+=1
			check(suppressed,"Formation fixture failed to exercise independent forced refresh")
		check(state.scene.ship_detail.counter_ms==counter and state.scene.ship_detail.selections==expected,"Opening detail timing/reference/order mismatch")
		check(state.detail_reference==state.camera.view.eye,"Latest renderer reference was not retained for the next world update")
		check(geometry.apply_state(state.scene),geometry.error)
		check(projection.apply(camera,state.camera.view).is_empty(),"Opening camera unavailable")
		for id in expected:
			var body: Node3D = geometry.actors[id] if id is int else geometry.player
			check(body.selection==expected[id],"Scheduled selection did not reach opening geometry")
			for j in body.levels.size(): check(body.levels[j].visible==(expected[id].visible and expected[id].level==j),"Opening rendered overlapping or stale detail levels")
		var phase: int = state.camera.shot.phase
		if not phases.has(phase):
			phases[phase]=true
			if DisplayServer.get_name()!="headless":
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				var picture := viewport.get_texture().get_image()
				check(not picture.is_empty(),"Opening detail viewport empty")
				var output := OS.get_environment("GOF2_CAPTURE_DIR")
				if not output.is_empty():
					DirAccess.make_dir_recursive_absolute(output)
					check(picture.save_png(output.path_join("%s-phase-%d.png" % [library.manifest.profile.edition,phase]))==OK,"Opening detail capture failed")
		if phase==4: break
	check(forced==1 and periodic>5 and held>10 and phases.size()==5,"Opening did not exercise formation and periodic/held detail")
	var pose := geometry.player.transform;var selection: Dictionary = geometry.player.selection.duplicate(true)
	for invalid in ["identity","missing","level","actor"]:
		var copy: Dictionary = state.scene.duplicate(true);copy.player_pose.origin.x+=4000
		match invalid:
			"identity": copy.ship_detail.binding_id="bad"
			"missing": copy.erase("ship_detail")
			"level": copy.ship_detail.selections.player.level=99
			"actor": copy.ship_detail.selections.erase(2)
		check(not geometry.apply_state(copy) and geometry.player.transform==pose and geometry.player.selection==selection,"Invalid detail partially committed opening geometry")
	print(library.manifest.profile.edition+": initial renderer origin, previous-frame checks, forced formation refresh and five rendered phases verified")
	viewport.free()

func select(bindings: RefCounted,scene: Dictionary,reference: Vector3,setting: float) -> Dictionary:
	var result := {};var selector := Detail.new()
	check(selector.configure(bindings.ship_lod,10),selector.error)
	result.player=selector.select(scene.player_pose.origin.distance_squared_to(reference),setting)
	for actor in scene.actors:
		check(selector.configure(bindings.ship_lod,actor.hull_catalogue_id),selector.error)
		result[actor.actor_id]=selector.select(actor.position.distance_squared_to(reference),setting)
	return result

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
