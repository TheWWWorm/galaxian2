extends SceneTree
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const FlightCamera = preload("res://src/presentation/flight_camera.gd")
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Opening geometry checks timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size() % 3 == 0, "Expected content/bindings/visuals triples")
	for i in range(0, args.size()-2, 3): await verify_source(args[i], args[i+1], args[i+2])
	print("Opening geometry checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String, texture_pack: String) -> void:
	var library := Library.new(); var bindings := Bindings.new(); var catalogues := Catalogues.new(); var visuals := Visuals.new()
	check(library.open(content) and library.select_language("gb"), library.error)
	check(bindings.open(pack,library.manifest), bindings.error)
	check(catalogues.open(library), catalogues.error)
	check(visuals.open(texture_pack,library.manifest), visuals.error)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	# Neutral inspection lighting, explicitly not the authored location sky/light.
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025,0.03,0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	viewport.add_child(light)
	var geometry := Geometry.new()
	viewport.add_child(geometry)
	check(geometry.build(library,visuals,bindings,catalogues), geometry.error)
	if geometry.player == null:
		viewport.free()
		return
	check(geometry.actors.size()==3 and geometry.player.get_meta("source_ship_id")==10, "Wrong opening hull set")
	check(geometry.actors[0].instances[0].mesh == geometry.actors[2].instances[0].mesh, "Repeated hull geometry was not shared")
	check(geometry.actors[0].materials[0] != geometry.actors[2].materials[0], "Actor materials were shared mutably")
	for body in [geometry.player]+geometry.actors.values():
		var selected := bindings.resolve_ship_layers(body.get_meta("source_ship_id"))
		var count := 0
		for child in body.get_children():
			if not child.has_meta("source_light_slot"): continue
			count += 1
			check(child.transform==Transform3D.IDENTITY, "Light offset inherited hangar placement or pivot")
		check(count==selected.lights.size(), "Opening body omitted a source light layer")
	var timeline := Timeline.new()
	var counts := []; counts.resize(23); counts.fill(1)
	check(timeline.configure(bindings,catalogues,library,counts), timeline.error)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	var projection := FlightCamera.new()
	# Explicit projection fixture; the world-owned location comparison is unbound.
	check(projection.configure(bindings.flight_projection,0,false).is_empty(), "Projection unavailable")
	var phases := {}
	for frame in 800:
		check(timeline.update(100,true,false), timeline.error)
		var state := timeline.snapshot()
		check(geometry.apply_state(state.scene), geometry.error)
		check(projection.apply(camera,state.camera.view).is_empty(), "Opening camera apply failed")
		check(geometry.player.transform==state.scene.player_pose, "Player presentation changed source placement")
		for actor in state.scene.actors:
			check(geometry.actors[actor.actor_id].visible==actor.visible, "Actor visibility differs from simulation")
			if actor.visible:
				check(geometry.actors[actor.actor_id].transform==actor.pose, "Actor pose differs from simulation")
		var phase: int = state.camera.shot.phase
		if not phases.has(phase):
			phases[phase] = true
			if DisplayServer.get_name() != "headless":
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				check(not image.is_empty(), "Opening viewport did not render")
				if phase==2:
					var background := image.get_pixel(0,0)
					var foreground := 0
					for y in range(0,image.get_height(),2):
						for x in range(0,image.get_width(),2):
							var pixel := image.get_pixel(x,y)
							if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.03: foreground+=1
					check(foreground>100, "Actor cut rendered no appreciable geometry")
				var output := OS.get_environment("GOF2_CAPTURE_DIR")
				if not output.is_empty():
					DirAccess.make_dir_recursive_absolute(output)
					check(image.save_png(output.path_join("%s-phase-%d.png" % [library.manifest.profile.edition,phase]))==OK, "Capture failed")
		if phase==4: break
	check(phases.size()==5, "Geometry did not exercise all recovered camera phases")
	var valid: Dictionary = timeline.snapshot().scene
	var before := poses(geometry)
	for bad in ["identity","duplicate","hull","missing_pose","nan","scaled","mismatch","visibility"]:
		var copy: Dictionary = valid.duplicate(true)
		copy.player_pose.origin.x += 5000 # Must not partially commit this valid move.
		match bad:
			"identity": copy.binding_id="unrelated"
			"duplicate": copy.actors[2].actor_id=0
			"hull": copy.actors[2].hull_catalogue_id=10
			"missing_pose": copy.actors[2].erase("pose")
			"nan": copy.actors[2].position.x=NAN
			"scaled": copy.actors[2].pose.basis=Basis.IDENTITY.scaled(Vector3(2,2,2))
			"mismatch": copy.actors[2].pose.origin.x+=100
			"visibility": copy.actors[2].visible=1
		check(not geometry.apply_state(copy) and poses(geometry)==before, "Invalid scene partially changed presentation: "+bad)
	var saved_identity: String = visuals.base_content_id
	visuals.base_content_id="unrelated"
	check(not geometry.build(library,visuals,bindings,catalogues), "Mixed content resources were accepted")
	visuals.base_content_id=saved_identity
	check(geometry.get_child_count()==0 and geometry.actors.is_empty() and geometry.player==null, "Cleared geometry retained nodes")
	check(not geometry.apply_state(valid), "Unbuilt geometry accepted scene state")
	print(library.manifest.profile.edition+": shared hulls, original light layers, hidden/revealed poses and five camera phases verified")
	viewport.free()

func poses(geometry: Node3D) -> Array:
	var result := [geometry.player.transform]
	for body in geometry.actors.values(): result.append([body.transform,body.visible])
	return result

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
