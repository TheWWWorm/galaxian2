extends SceneTree
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const SkyGeometry = preload("res://src/presentation/opening_sky.gd")
const Definitions = preload("res://src/content/opening_sky_definitions.gd")
const OpeningLighting = preload("res://src/presentation/opening_lighting.gd")
const Reflection = preload("res://src/presentation/environment_reflection.gd")
const MaterialLights = preload("res://src/presentation/material_light_state.gd")
const Geometry = preload("res://src/presentation/opening_geometry.gd")
const Timeline = preload("res://src/simulation/opening_detail_timeline.gd")
const FlightCamera = preload("res://src/presentation/flight_camera.gd")
var failures := 0
var native_response := false

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Opening sky checks timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--surface-response"):
		native_response=true
		args.remove_at(args.find("--surface-response"))
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): await verify_source(args[index],args[index+1],args[index+2])
	print("Opening sky checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String, texture_pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new();var visuals := Visuals.new()
	check(library.open(content) and library.select_language("gb"),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(catalogues.open(library),catalogues.error)
	check(visuals.open(texture_pack,library.manifest),visuals.error)
	if bindings.opening_sky.is_empty(): return
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in ["star_mesh_base","star_texture_base","sky_mesh_id","sky_texture_id","star_variants","world_type","campaign_cursor","location_match","provenance"]:
		var bad := bindings.opening_sky.duplicate(true);bad.erase(key)
		check(not Definitions.validate(bad,int(header.source_executable_bytes),header.architecture).is_empty(),"Missing sky field accepted: "+key)
	var bad := bindings.opening_sky.duplicate(true)
	bad.provenance.opening.offset+=1
	check(not Definitions.validate(bad,int(header.source_executable_bytes),header.architecture).is_empty(),"Disconnected sky provenance accepted")
	check(catalogues.tables.systems[15].sky_index==9,"Source system sky field mismatch")
	var viewport := SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();camera.current=true;camera.near=1;camera.far=1000;camera.fov=60
	viewport.add_child(camera)
	var sky := SkyGeometry.new();viewport.add_child(sky)
	check(sky.build(library,visuals,bindings,catalogues,0,3,false),sky.error)
	if sky.selection.is_empty():viewport.free();return
	check(sky.selection.station_id==78 and sky.selection.system_id==15 and sky.selection.star_variant==0,"Wrong opening location or star alternative")
	check(sky.layers.size()==2 and sky.layers[0].get_meta("source_resource_id")==17850 and sky.layers[1].get_meta("source_resource_id")==17803,"Wrong opening background mesh set")
	check(sky.layers[0].get_meta("source_texture_id")==10086 and sky.layers[1].get_meta("source_texture_id")==10068,"Wrong opening texture override")
	check(bindings.material_for_mesh(bindings.resolve(17850,"mesh")).is_empty(),"Ambiguous star path material was silently chosen")
	check(sky.apply_view({"pose":camera.global_transform}),sky.error)
	var initial := sky.global_transform
	check(not sky.apply_view({"pose":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))}) and sky.global_transform==initial,"Invalid view changed the sky")
	if DisplayServer.get_name()!="headless":
		var first := await capture(viewport)
		check(variation(first)>100,"Background layers produced a flat image")
		sky.layers[0].hide()
		var nebula := await capture(viewport)
		check(variation(nebula)>100,"Nebula layer did not contribute to the background")
		sky.layers[0].show()
		sky.layers[1].hide()
		var stars := await capture(viewport)
		check(first.get_data()!=stars.get_data() and first.get_data()!=nebula.get_data(),"Background composition lost one of its layers")
		sky.layers[1].show()
		camera.position=Vector3(300000,-120000,500000)
		check(sky.apply_view({"pose":camera.global_transform}),sky.error)
		var moved := await capture(viewport)
		check(first.get_data()==moved.get_data(),"Translation changed the infinite sky")
		camera.rotation.y=1.0
		check(sky.apply_view({"pose":camera.global_transform}),sky.error)
		var turned := await capture(viewport)
		check(first.get_data()!=turned.get_data(),"Camera orientation did not change the background")
		camera.transform=Transform3D.IDENTITY
		check(sky.apply_view({"pose":camera.global_transform}),sky.error)
		var cube := MeshInstance3D.new();cube.mesh=BoxMesh.new();cube.mesh.size=Vector3(50,50,50);cube.position=Vector3(0,0,-100)
		var red := StandardMaterial3D.new();red.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;red.albedo_color=Color.RED
		cube.material_override=red;viewport.add_child(cube)
		var foreground := await capture(viewport)
		var center := foreground.get_pixel(480,270)
		check(center.r>0.9 and center.g<0.02 and center.b<0.02,"Sky layers covered foreground geometry")
		cube.free()
	# Compose the actual recovered pre-combat timeline with the source background.
	var lighting := OpeningLighting.new();viewport.add_child(lighting)
	check(lighting.build(bindings,catalogues,library.manifest.content_id,0,3,false),lighting.error)
	var material_lights := MaterialLights.new()
	check(material_lights.build(bindings.surface_material,lighting.state),material_lights.error)
	check(material_lights.state.get("specular_power")==20,"Opening material did not use the source exponent")
	var reflection := Reflection.new()
	check(reflection.build_opening(library,bindings,catalogues,0,3,false),reflection.error)
	check(reflection.texture!=null and reflection.selection.get("texture_id")==12039,"Opening reflection selection did not follow the source system")
	check(lighting.lights.size()==2,"Opening did not create both source lights")
	for i in lighting.lights.size():
		check(lighting.lights[i].basis.z.is_equal_approx(lighting.state.lights[i].direction_to_light),"Light travel points toward rather than away from its source")
	var geometry := Geometry.new();viewport.add_child(geometry)
	check(geometry.build(library,visuals,bindings,catalogues,"high",true),geometry.error)
	if native_response:
		var wrong_identity := lighting.state.duplicate(true);wrong_identity.base_content_id="0".repeat(64)
		check(not geometry.apply_surface_response(bindings,wrong_identity,reflection,-1,0,"two_light_cube") and geometry.surface_materials.is_empty(),"Mixed surface identity changed the opening")
		check(not geometry.apply_surface_response(bindings,lighting.state,reflection,-1,0,"unverified") and geometry.surface_materials.is_empty(),"Unknown source shader variant changed the opening")
		# Explicit supplied-fixture settings, independently verified in both static
		# binaries. Automatic settings/variant import is still a separate task.
		check(geometry.apply_surface_response(bindings,lighting.state,reflection,-1,0,"two_light_cube"),geometry.error)
		check(geometry.surface_materials.size()>=4,"Opening did not replace all supported ship materials")
	var counts := [];counts.resize(23);counts.fill(1)
	var timeline := Timeline.new();check(timeline.configure(bindings,catalogues,library,counts,1.0),timeline.error)
	var projection := FlightCamera.new();check(projection.configure(bindings.flight_projection,0,false).is_empty(),"Flight projection missing")
	var phases := {}
	for frame in 800:
		check(timeline.update(100,true,false,false,1.0),timeline.error)
		var state := timeline.snapshot()
		check(geometry.apply_state(state.scene),geometry.error)
		check(projection.apply(camera,state.camera.view).is_empty(),"Camera application failed")
		check(sky.apply_view(state.camera.view),sky.error)
		var phase: int = state.camera.shot.phase
		if not phases.has(phase):
			phases[phase]=true
			if DisplayServer.get_name()!="headless":
				var image := await capture(viewport)
				check(variation(image)>100,"Opening scene did not render varied geometry/background")
				if phase==2:
					if native_response:
						for material in geometry.surface_materials:material.set_shader_parameter("reflection_enabled",false)
						var without_reflection := await capture(viewport)
						check(image.get_data()!=without_reflection.get_data(),"Native reflection/rim did not affect opening geometry")
						for material in geometry.surface_materials:material.set_shader_parameter("reflection_enabled",true)
					else:
						for lamp in lighting.lights: lamp.hide()
						var without_lamps := await capture(viewport)
						check(image.get_data()!=without_lamps.get_data(),"Source lights did not affect opening geometry")
						for lamp in lighting.lights: lamp.show()
				var output := OS.get_environment("GOF2_CAPTURE_DIR")
				if not output.is_empty():
					DirAccess.make_dir_recursive_absolute(output)
					check(image.save_png(output.path_join("%s-phase-%d.png" % [library.manifest.profile.edition,phase]))==OK,"Sky capture failed")
		if phase==4:break
	check(phases.size()==5,"Opening sky did not cover all recovered phases")
	# Unknown contexts and mixed profiles must leave an empty scene.
	for context in [[1,3,false],[0,4,false],[0,3,true],[0.5,3,false]]:
		check(not sky.build(library,visuals,bindings,catalogues,context[0],context[1],context[2]) and sky.get_child_count()==0,"Unsupported sky context retained scenery")
	var original_id: String = visuals.base_content_id;visuals.base_content_id="f".repeat(64)
	check(not sky.build(library,visuals,bindings,catalogues,0,3,false) and sky.get_child_count()==0,"Cross-profile sky textures accepted")
	visuals.base_content_id=original_id
	viewport.free()
	print(library.manifest.profile.edition+": opening sky layers, deterministic rotation, camera translation and pre-combat composition verified")

func capture(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func variation(image: Image) -> int:
	var background := image.get_pixel(0,0);var count := 0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			var pixel := image.get_pixel(x,y)
			if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.03:count+=1
	return count

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
