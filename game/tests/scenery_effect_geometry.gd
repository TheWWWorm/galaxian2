extends SceneTree
const Geometry = preload("res://src/presentation/scenery_effect_geometry.gd")
const Clock = preload("res://src/simulation/scenery_effect_clock.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Lighting = preload("res://src/presentation/opening_lighting.gd")
const Reflection = preload("res://src/presentation/environment_reflection.gd")
const Sampler = preload("res://src/presentation/scenery_animation.gd")
const Poses = preload("res://src/presentation/scenery_effect_pose.gd")
const RESPONSE := {"variant":"unfogged_two_light_cube","diffuse_bias":-1,"normal_bias":0}
const WHITE := Vector4(1,1,1,1)
var failures := 0
var viewport: SubViewport
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_tint()
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	if DisplayServer.get_name()!="headless":
		viewport=SubViewport.new();viewport.size=Vector2i(384,384);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.near=0.1;camera.far=100000;viewport.add_child(camera)
		await check_shader()
	for index in range(0,args.size()-2,3):await check_profile(args[index],args[index+1],args[index+2])
	if viewport!=null:viewport.free()
	else:print("Scenery effects: GPU checks skipped in headless mode")
	print("Scenery effect geometry checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_tint() -> void:
	var bytes := PackedByteArray([255,128,64,1])
	check(Geometry.tint(bytes,WHITE).value==Vector4(1,128.0/255,64.0/255,1.0/255),"Unanimated tint lost source bytes")
	check(Geometry.tint(bytes,WHITE,255).value==Vector4(254.0/255,127.0/255,63.0/255,0),"Animated white used divide-by-255 instead of shift-by-eight")
	check(Geometry.tint(bytes,Vector4(2,1,0.5,1),128).value==Vector4(254.0/255,64.0/255,16.0/255,0),"Packed modulation order or independent channels changed")
	check(Geometry.tint(bytes,WHITE,0).value==Vector4.ZERO,"Zero tint became visible")
	for bad in [PackedByteArray(),PackedByteArray([255]),PackedByteArray([1,2,3,4,5])]:
		check(Geometry.tint(bad,WHITE).is_empty(),"Malformed parent color accepted")
	check(Geometry.tint(bytes,Vector4(INF,0,0,0)).is_empty() and Geometry.tint(bytes,WHITE,256).is_empty(),"Invalid tint accepted")
	var raw := [{"pivot":Vector3.ZERO,"tracks":{"translation":[{"dimensions":3,"keys":PackedFloat32Array([0.5,0,0,0,10,10,0,0])}]}}]
	var sampler := Sampler.new();check(sampler.configure(raw),sampler.error)
	var original := sampler.snapshot();var fork: RefCounted=sampler.fork_for_frame()
	check(not fork.sample(10,Transform3D.IDENTITY).is_empty() and sampler.snapshot()==original,"Candidate sampling changed its original owner")

func check_profile(content: String, pack: String, texture_pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new()
	var catalogues := Catalogues.new();var resources := Resources.new();var lighting := Lighting.new();var reflection := Reflection.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(texture_pack,library.manifest) or not catalogues.open(library) or not resources.configure(library,bindings):
		check(false,library.error+bindings.error+visuals.error+catalogues.error+resources.error);lighting.free();return
	if not lighting.build(bindings,catalogues,bindings.base_content_id,0,3,false) or not reflection.build(library,bindings,catalogues,lighting.state.system_id,false):
		check(false,lighting.error+reflection.error);lighting.free();return
	var edition: String=library.manifest.profile.edition
	for variant in bindings.scenery_effects.variants:
		var descriptor := resources.effect_for_model(int(variant.base_model_id))
		var clock := Clock.new();var geometry := Geometry.new()
		(viewport if viewport!=null else root).add_child(geometry)
		geometry.transform=Transform3D(Basis.from_euler(Vector3(0.2,-0.3,0.4)).scaled(Vector3.ONE*3),Vector3(200,-70,90))
		if not clock.configure(bindings,descriptor,0.5) or not geometry.build(library,visuals,bindings,descriptor,lighting.state,reflection,RESPONSE):
			check(false,clock.error+geometry.error);geometry.free();continue
		var expected_samplers := []
		for model in geometry.models:
			var sampler := Sampler.new();check(sampler.configure(model.surfaces),sampler.error);expected_samplers.append(sampler)
			for surface_index in model.surfaces.size():
				var raw_uvs: PackedVector2Array=model.surfaces[surface_index].uvs
				var prepared_uvs: PackedVector2Array=model.instances[surface_index].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
				check(prepared_uvs.size()==raw_uvs.size(),"UV preparation changed vertex count")
				for vertex in raw_uvs.size():check(prepared_uvs[vertex]==Vector2(raw_uvs[vertex].x,1.0-raw_uvs[vertex].y),"Shader-path V conversion changed or was applied twice")
		check(geometry.apply_effect(clock,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),WHITE,0.6) and not geometry.visible,"Untriggered effect became visible")
		var initial: Dictionary=geometry._samplers[0].snapshot()
		var pose := Transform3D(Basis.from_euler(Vector3(0.2,0.5,-0.3)).scaled(Vector3.ONE*0.5),Vector3(13,-9,-40))
		check(clock.trigger(pose),clock.error)
		var invalid: RefCounted=clock.fork_for_frame()
		check(invalid.update(100),invalid.error)
		# Inject a corrupt second-model time after the first model can advance.
		# No malformed candidate may commit renderer state or change the live clock.
		invalid._state.models[1].time_ms=-1
		var live := clock.snapshot()
		check(not geometry.apply_effect(invalid,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),WHITE,1),"Invalid breakup time accepted")
		check(not geometry.visible and geometry._samplers[0].snapshot()==initial and clock.snapshot()==live,"Second-model failure committed first-model or live clock state")
		for tick in [0,100,100,100,100]:
			clock=clock.fork_for_frame()
			check(clock.update(tick),clock.error)
			var before := clock.snapshot()
			check(geometry.apply_effect(clock,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),WHITE,0.6),geometry.error)
			check(clock.snapshot()==before and geometry.visible,"Presentation advanced or hid an active clock")
			var roots := Poses.for_effect(clock,Transform3D.IDENTITY)
			for model_index in 2:
				var sampled: Dictionary=expected_samplers[model_index].sample(before.models[model_index].time_ms,roots.alpha if model_index==0 else roots.breakup)
				for surface_index in sampled.surfaces.size():
					var instance: MeshInstance3D=geometry.models[model_index].instances[surface_index]
					check(instance.global_transform==sampled.surfaces[surface_index].pose,"Container transform or effect scale was applied twice")
					var material: ShaderMaterial=geometry.models[model_index].materials[surface_index]
					if model_index==0:
						check(material.shader==Geometry.Alpha,"Alpha effect retained provisional material")
						check(material.get_shader_parameter("effect_tint")==Geometry.tint(PackedByteArray([255,255,255,255]),WHITE,sampled.surfaces[surface_index].get("color_byte",-1)).value,"Animated alpha material tint differs from the sampled color")
						check(is_equal_approx(material.get_shader_parameter("darken_value"),0.6 if edition=="mac-full-hd" else 1.0),"Edition-specific RGB darkening was lost")
					else:check(material.shader==Geometry.Response.ShaderSource,"Solid fragment retained provisional PBR material")
		var shown: Transform3D=geometry.models[0].instances[0].transform
		var color: Variant=geometry.models[0].materials[0].get_shader_parameter("effect_tint")
		check(not geometry.apply_effect(clock,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),PackedByteArray([255,255,255,255]),WHITE,1),"Nonfinite camera accepted")
		check(geometry.visible and geometry.models[0].instances[0].transform==shown and geometry.models[0].materials[0].get_shader_parameter("effect_tint")==color,"Failed update changed rendered state")
		var unrelated := Clock.new()
		check(unrelated.configure(bindings,descriptor,0.5) and unrelated.trigger(pose),unrelated.error)
		check(not geometry.apply_effect(unrelated,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),WHITE,1),"Geometry switched between unrelated effects with identical source identifiers")
		if viewport!=null:await capture_effect(geometry,clock,edition,int(variant.effect_type))
		while clock.snapshot().active:check(clock.update(100),clock.error)
		check(geometry.apply_effect(clock,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),WHITE,1) and not geometry.visible,"Expired effect stayed visible")
		check(clock.configure(bindings,descriptor,0.5),clock.error)
		check(not geometry.apply_effect(clock,Transform3D.IDENTITY,PackedByteArray([255,255,255,255]),WHITE,1),"Reconfigured clock reused an old effect identity")
		var bad := RESPONSE.duplicate();bad.variant="automatic"
		check(not geometry.build(library,visuals,bindings,descriptor,lighting.state,reflection,bad) and geometry.models.is_empty(),"Unsupported material selection reused old geometry")
		geometry.free()
	lighting.free()
	print(edition,": all four effect pairs, transforms, materials, clock ownership and expiry verified")

func capture_effect(geometry: Node3D, clock: RefCounted, edition: String, effect_type: int) -> void:
	var bounds := AABB();var first := true
	for model in geometry.models:
		for instance in model.instances:
			var box: AABB=instance.global_transform*instance.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
	camera.size=maxf(bounds.size.x,bounds.size.y)*1.15
	camera.position=bounds.get_center()+Vector3.BACK*(bounds.size.z+camera.size)
	check(geometry.apply_effect(clock,camera.global_transform,PackedByteArray([255,255,255,255]),WHITE,1),geometry.error)
	var captures := OS.get_environment("GOF2_SCENERY_EFFECT_CAPTURE")
	for layer in ["combined","alpha","solid"]:
		geometry.models[0].visible=layer!="solid";geometry.models[1].visible=layer!="alpha"
		var image := await capture()
		check(variation(image)>8,"Effect layer did not render: %s/%d/%s" % [edition,effect_type,layer])
		if not captures.is_empty():check(image.save_png(captures.path_join("%s-%d-%s.png" % [edition,effect_type,layer]))==OK,"Could not save private effect capture")
	geometry.models[0].visible=true;geometry.models[1].visible=true

func check_shader() -> void:
	var plane := MeshInstance3D.new();plane.mesh=QuadMesh.new();plane.position=Vector3(0,0,-4);viewport.add_child(plane)
	camera.size=2
	var image := Image.create(2,2,false,Image.FORMAT_RGBAF);image.fill(Color(0.8,0.4,0.2,0.5))
	var material := ShaderMaterial.new();material.shader=Geometry.Alpha
	material.set_shader_parameter("diffuse_texture",ImageTexture.create_from_image(image))
	material.set_shader_parameter("effect_tint",Vector4(0.25,0.5,0.75,0.5));material.set_shader_parameter("darken_value",0.5)
	plane.material_override=material
	# Force a farther transparent surface to draw after the effect. A mistaken
	# depth write would hide it and break the independent reference comparison.
	var behind := MeshInstance3D.new();behind.mesh=QuadMesh.new();behind.position=Vector3(0,0,-5);viewport.add_child(behind)
	var backdrop_shader := Shader.new()
	backdrop_shader.code="shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, fog_disabled; void fragment(){ALBEDO=vec3(0.2,0.4,0.7);ALPHA=0.6;}"
	var backdrop := ShaderMaterial.new();backdrop.shader=backdrop_shader;backdrop.render_priority=10;behind.material_override=backdrop
	var actual := (await capture()).get_pixel(192,192)
	# Independent constant RGB/alpha follows the same Godot transfer and blending,
	# isolating material arithmetic without claiming original framebuffer parity.
	var shader := Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, fog_disabled; void fragment(){ALBEDO=vec3(0.1,0.1,0.075);ALPHA=0.25;}"
	var reference := ShaderMaterial.new();reference.shader=shader;plane.material_override=reference
	var expected := (await capture()).get_pixel(192,192)
	check(Vector3(actual.r,actual.g,actual.b).distance_to(Vector3(expected.r,expected.g,expected.b))<0.012,"Alpha shader lost tint, opacity, transparent depth behavior or RGB-only darkening")
	plane.free();behind.free()

func capture() -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func variation(image: Image) -> int:
	var colors := {}
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):colors[image.get_pixel(x,y).to_rgba32()]=true
	return colors.size()

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
