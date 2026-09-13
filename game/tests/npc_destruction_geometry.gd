extends SceneTree
const Geometry = preload("res://src/presentation/npc_death_effect_geometry.gd")
const Poses = preload("res://src/presentation/npc_destruction_pose.gd")
const Death = preload("res://src/simulation/npc_destruction.gd")
const Resources = preload("res://src/content/npc_destruction_resources.gd")
const Construction = preload("res://src/simulation/opening_npc_construction.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Sampler = preload("res://src/presentation/scenery_animation.gd")
const Session = preload("res://src/presentation/opening_session.gd")
const WHITE := Vector4(1,1,1,1)
var BYTES := PackedByteArray([255,255,255,255])
var failures := 0
var viewport: SubViewport
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/binding/visual triples")
	if DisplayServer.get_name()!="headless":
		viewport=SubViewport.new();viewport.size=Vector2i(384,384);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		# The source alpha layer is dark smoke. A lit backdrop makes its opacity
		# measurable independently of the additive flash and black space.
		var background := WorldEnvironment.new();background.environment=Environment.new()
		background.environment.background_mode=Environment.BG_COLOR
		background.environment.background_color=Color(0.16,0.23,0.32)
		viewport.add_child(background)
		camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.near=0.1;camera.far=100000;viewport.add_child(camera)
		await check_additive_shader()
	for i in range(0,args.size()-2,3): await check_profile(args[i],args[i+1],args[i+2])
	if viewport!=null: viewport.free()
	else: print("NPC destruction GPU checks skipped in headless mode")
	print("NPC destruction geometry checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, binding_path: String, texture_path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new();var catalogues := Catalogues.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(binding_path,library.manifest) or not visuals.open(texture_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+visuals.error+catalogues.error);return
	if bindings.opening_actors.npc_initialization.get("destruction",{}).is_empty():
		var legacy := Session.new();root.add_child(legacy)
		check(legacy.configure(library,bindings,visuals,0,0.5,1789100000) and legacy.npc_deaths==null,"Legacy session fabricated NPC effects")
		legacy.free();return
	var resources := Resources.new();var constructor := Construction.new()
	if not resources.configure(library,bindings) or not constructor.configure(bindings,catalogues):
		check(false,resources.error+constructor.error);return
	var constructed: Dictionary=constructor.generate({"state":280936762154123})
	if constructed.is_empty(): check(false,constructor.error);return
	var death := Death.new();var geometry := Geometry.new()
	(viewport if viewport!=null else root).add_child(geometry)
	geometry.transform=Transform3D(Basis.from_euler(Vector3(0.2,0.3,-0.4)).scaled(Vector3.ONE*3),Vector3(800,100,600))
	var pose := Transform3D(Basis(Vector3(0,0,-1),Vector3.UP,Vector3.RIGHT),Vector3(100,-50,70))
	if not death.configure(bindings,resources,0,pose,0.375,constructed.actors[0].fragments) or not geometry.build(library,visuals,bindings,death):
		check(false,death.error+geometry.error);geometry.free();return
	check(geometry.models.size()==constructed.actors[0].fragments.size()+2,"Retained fragments were omitted or regenerated")
	var expected_samplers := []
	for index in geometry.models.size():
		var model: Node3D=geometry.models[index]
		var sampler := Sampler.new();check(sampler.configure(model.surfaces),sampler.error);expected_samplers.append(sampler)
		check(model.surfaces.size()==([3,10][index] if index<2 else 2),"Wrong source explosion surface population")
		for surface_index in model.surfaces.size():
			check(model.materials[surface_index].shader==(Geometry.Alpha if index==0 else Geometry.Additive),"Wrong effect material")
			check(model.materials[surface_index].render_priority==(1 if index==0 else 0),"Source late alpha pass lost ordering after additive geometry")
			var uv: PackedVector2Array=model.surfaces[surface_index].uvs
			var prepared: PackedVector2Array=model.instances[surface_index].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			for vertex in uv.size(): check(prepared[vertex]==Vector2(uv[vertex].x,1-uv[vertex].y),"Missing or double source UV conversion")
	check(geometry.models[2].instances[0].mesh==geometry.models[3].instances[0].mesh,"Fragment meshes were not shared")
	check(geometry.models[2].materials[0]!=geometry.models[3].materials[0],"Independent fragment animation shared mutable material")
	var camera_pose := Transform3D(Basis(Vector3.UP,Vector3.LEFT,Vector3.BACK),Vector3(0,0,5000))
	check(geometry.apply_effect(death,camera_pose,BYTES,WHITE,0.6) and not geometry.visible and geometry.body_visible,"Fresh effect visibility changed")
	var rng := {"state":25214903917}
	while death.snapshot().phase!="explosion":
		var result := death.advance(100,rng)
		if result.is_empty(): check(false,death.error);geometry.free();return
		rng=result.random_state
		if death.snapshot().phase=="tumble": check(geometry.apply_effect(death,camera_pose,BYTES,WHITE,1) and not geometry.visible and geometry.body_visible,"Tumble hid its body")
	var trigger: Dictionary=death.snapshot()
	check(trigger.effect.elapsed_ms==0 and trigger.effect.position!=trigger.pose.origin,"Fixture lost the source pre-motion effect position")
	for elapsed in [0,100,299,300,800,1800,4467,4468,4500]:
		advance(death,elapsed-int(death.snapshot().effect.elapsed_ms),rng)
		var state: Dictionary=death.snapshot()
		var expected_roots: Array[Transform3D]=[Transform3D(camera_pose.basis,trigger.effect.position),Transform3D(camera_pose.basis,trigger.effect.position)]
		for fragment in state.fragments:
			expected_roots.append(Transform3D(analytic_xyz(fragment.rotation_radians).scaled(Vector3.ONE*fragment.scale),trigger.effect.position))
		var actual_roots := Poses.for_death(death,camera_pose)
		check(actual_roots.effect_visible and actual_roots.body_visible==(elapsed<300),"Intact body or effect boundary changed")
		for index in expected_roots.size(): check(pose_near(actual_roots.roots[index],expected_roots[index]),"Billboard child or independent fragment pose changed")
		var before := death.snapshot()
		check(geometry.apply_effect(death,camera_pose,BYTES,WHITE,0.6),geometry.error)
		check(death.snapshot()==before,"Rendering advanced the native death owner")
		check(geometry.visible and geometry.body_visible==(elapsed<300),"Body did not hide at 300 ms independently of effect")
		for index in geometry.models.size():
			var sampled: Dictionary=expected_samplers[index].sample(state.effect.models[index].time_ms,expected_roots[index])
			for surface in sampled.surfaces.size():
				var instance: MeshInstance3D=geometry.models[index].instances[surface]
				check(pose_near(instance.global_transform,sampled.surfaces[surface].pose),"Container transform, pivot or root applied twice")
				var material: ShaderMaterial=geometry.models[index].materials[surface]
				check(is_equal_approx(material.get_shader_parameter("darken_value"),0.6 if library.manifest.profile.edition=="mac-full-hd" else 1.0),"Edition darkening changed")
				var byte: int=sampled.surfaces[surface].get("color_byte",-1)
				var expected_tint: float=float((255*byte)>>8)/255.0 if byte>=0 else 1.0
				check(material.get_shader_parameter("effect_tint").is_equal_approx(Vector4.ONE*expected_tint),"Animated fragment or flash tint changed")
		if elapsed==800:
			check_atomic(geometry,death,camera_pose)
			if viewport!=null: await capture_layers(geometry,death,library.manifest.profile.edition)
	advance(death,1,rng)
	check(geometry.apply_effect(death,camera_pose,BYTES,WHITE,1) and not geometry.visible and not geometry.body_visible,"Expired death geometry stayed visible")
	check(not death.advance(0,rng).is_empty(),death.error)
	check(geometry.apply_effect(death,camera_pose,BYTES,WHITE,1) and not geometry.visible and not geometry.body_visible,"Retired body reappeared")
	var unrelated := Death.new();check(unrelated.configure(bindings,resources,0,pose,0.375,constructed.actors[0].fragments),unrelated.error)
	check(not geometry.apply_effect(unrelated,camera_pose,BYTES,WHITE,1),"An unrelated owner reused old geometry")
	check(not geometry.build(library,visuals,bindings,null) and geometry.models.is_empty(),"Failed build retained partial models")
	geometry.free()
	check_session(library,bindings,visuals)
	print(library.manifest.profile.edition,": native roots, alpha/additive models, body cutoff, retirement and atomic world presentation verified")

func check_atomic(geometry: Node3D, death: RefCounted, camera_pose: Transform3D) -> void:
	var before := rendered(geometry)
	for field in ["time_ms","resource"]:
		var bad: RefCounted=death.fork_for_frame()
		bad._state.effect.models[-1][field]=-1 if field=="time_ms" else "missing"
		check(not geometry.apply_effect(bad,camera_pose,BYTES,WHITE,1) and rendered(geometry)==before,"Last fragment failure committed earlier surfaces")
	check(not geometry.apply_effect(death,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),BYTES,WHITE,1) and rendered(geometry)==before,"Invalid camera changed presentation")
	check(not geometry.apply_effect(death,camera_pose,BYTES,WHITE,INF) and rendered(geometry)==before,"Invalid tint changed presentation")

func check_session(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> void:
	var session := Session.new();root.add_child(session)
	if not session.configure(library,bindings,visuals,0,0.5,1789100000): check(false,session.error);session.free();return
	check(session.npc_deaths!=null and session.npc_deaths.effects.size()==3,"Opening did not prepare death geometry")
	var now := 0
	for tick in 2000:
		now+=100000
		if not session.step(now): check(false,session.error);session.free();return
		if session.snapshot().combat.actors.all(func(actor):return actor.active): break
	check(session.snapshot().camera.shot.phase==3,"Death fixture missed source activation")
	var timeline: RefCounted=session._timeline
	check(timeline.begin_frame(0,false,1.0),timeline.error)
	var combat: RefCounted=timeline.combat_owner()
	for id in 3: check(combat.normal_hit(id,150).destroyed_now,"Could not prepare ordinary lethal hits")
	check(timeline.adopt_combat_pass(combat) and timeline.finish_frame(false),timeline.error)
	var frozen_radio: Dictionary=timeline.snapshot().radio
	var saw_body := false;var saw_explosion := false;var checked_atomic := false;var retired := 0
	for tick in 100:
		var frame: Dictionary=session._world_frame.evaluate(session._timeline,session._scenery,100,false)
		if frame.is_empty(): check(false,session._world_frame.error);break
		session._world_frame=frame.world_frame;session._timeline=frame.timeline;session._scenery=frame.scenery
		check(session.present(),session.error)
		retired=0
		for id in 3:
			var life: Dictionary=session._world_frame.npc_destruction_owner(id).snapshot()
			var should_show: bool=life.phase in ["ready","tumble"] or (life.phase=="explosion" and life.countdown_ms<300)
			check(session.geometry.actors[id].visible==(session.snapshot().scene.actors[id].visible and should_show),"Cinematic and death body visibility disagree")
			check(session.npc_deaths.effects[id].visible==life.effect.active,"World omitted or retained an inactive explosion")
			check(pose_near(session.geometry.actors[id].transform,life.pose),"Rendered body lost native death pose")
			saw_body=saw_body or life.phase=="tumble"
			saw_explosion=saw_explosion or life.effect.active
			if life.phase=="retired": retired+=1
		if not checked_atomic and session.npc_deaths.effects.all(func(effect):return effect.visible):
			var before := [];for effect in session.npc_deaths.effects: before.append(rendered(effect))
			var bad: RefCounted=session._world_frame.fork_for_frame()
			for id in 3:
				var owner: RefCounted=bad._controller._destruction[id]
				check(not owner.advance(100,bad.snapshot().random_state).is_empty(),owner.error)
			bad._controller._destruction[2]._state.effect.models[-1].time_ms=-1
			check(not session.npc_deaths.apply_world(bad,session.camera.transform,BYTES,WHITE,1),"Last NPC failure was accepted")
			for id in 3: check(rendered(session.npc_deaths.effects[id])==before[id],"Last NPC failure committed earlier effects")
			checked_atomic=true
		if retired==3: break
	check(saw_body and saw_explosion and retired==3 and checked_atomic,"Incomplete three-actor presentation lifecycle")
	check(session.snapshot().radio==frozen_radio and session.status=="running","Test deaths invented campaign advancement")
	session.clear();check(session.npc_deaths==null and session.get_child_count()==0,"Session clear retained death resources")
	session.free()

func rendered(geometry: Node3D) -> Dictionary:
	var rows := [];var samplers := []
	for model in geometry.models:
		for index in model.instances.size(): rows.append([model.instances[index].global_transform,model.materials[index].get_shader_parameter("effect_tint"),model.materials[index].get_shader_parameter("darken_value")])
	for sampler in geometry._samplers: samplers.append(sampler.snapshot())
	return {"visible":geometry.visible,"body":geometry.body_visible,"rows":rows,"samplers":samplers}

func advance(death: RefCounted, amount: int, rng: Dictionary) -> void:
	while amount>0:
		var delta := mini(100,amount)
		if death.advance(delta,rng).is_empty(): check(false,death.error);return
		amount-=delta

static func analytic_xyz(angles: Vector3) -> Basis:
	var x := angles.x;var y := angles.y;var z := angles.z
	return Basis(Vector3(cos(y)*cos(z),cos(x)*sin(z)+sin(x)*sin(y)*cos(z),sin(x)*sin(z)-cos(x)*sin(y)*cos(z)),Vector3(-cos(y)*sin(z),cos(x)*cos(z)-sin(x)*sin(y)*sin(z),sin(x)*cos(z)+cos(x)*sin(y)*sin(z)),Vector3(sin(y),-sin(x)*cos(y),cos(x)*cos(y)))

func pose_near(actual: Transform3D, expected: Transform3D) -> bool:
	if not actual.is_finite() or actual.origin.distance_to(expected.origin)>0.003: return false
	for axis in 3:
		if actual.basis[axis].distance_to(expected.basis[axis])>0.0001: return false
	return true

func capture_layers(geometry: Node3D, death: RefCounted, edition: String) -> void:
	var bounds := AABB();var first := true
	for model in geometry.models:
		for instance in model.instances:
			var box: AABB=instance.global_transform*instance.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
	camera.basis=Basis.IDENTITY;camera.size=maxf(bounds.size.x,bounds.size.y)*1.2
	camera.position=bounds.get_center()+Vector3.BACK*(bounds.size.z+camera.size)
	check(geometry.apply_effect(death,camera.transform,BYTES,WHITE,1),geometry.error)
	var images := []
	for layer in ["combined","alpha","additive","debris"]:
		for index in geometry.models.size(): geometry.models[index].visible=layer=="combined" or (layer=="alpha" and index==0) or (layer=="additive" and index==1) or (layer=="debris" and index>1)
		var image := await capture();images.append(image)
		var colors := {}
		for y in range(0,384,3):
			for x in range(0,384,3): colors[image.get_pixel(x,y).to_rgba32()]=true
		check(colors.size()>8,"NPC layer failed to render: "+edition+"/"+layer)
		var output := OS.get_environment("GOF2_NPC_DEATH_CAPTURE")
		if not output.is_empty(): check(image.save_png(output.path_join(edition+"-"+layer+".png"))==OK,"Could not save private capture")
	for model in geometry.models: model.visible=true
	check(images[1].get_data()!=images[2].get_data() and images[2].get_data()!=images[3].get_data(),"Isolated effect layers are identical")

func check_additive_shader() -> void:
	camera.size=2;camera.transform=Transform3D.IDENTITY
	var plane := MeshInstance3D.new();plane.mesh=QuadMesh.new();plane.position=Vector3(0,0,-4);viewport.add_child(plane)
	var image := Image.create(2,2,false,Image.FORMAT_RGBAF);image.fill(Color(0.8,0.4,0.2,0.0))
	var material := ShaderMaterial.new();material.shader=Geometry.Additive
	material.set_shader_parameter("diffuse_texture",ImageTexture.create_from_image(image))
	material.set_shader_parameter("effect_tint",Vector4(0.25,0.5,0.75,0.0));material.set_shader_parameter("darken_value",0.5)
	plane.material_override=material
	var behind := MeshInstance3D.new();behind.mesh=QuadMesh.new();behind.position=Vector3(0,0,-5);viewport.add_child(behind)
	var background := Shader.new();background.code="shader_type spatial; render_mode unshaded, blend_mix, depth_draw_never, fog_disabled; void fragment(){ALBEDO=vec3(0.2,0.4,0.7);ALPHA=0.6;}"
	var back_material := ShaderMaterial.new();back_material.shader=background;back_material.render_priority=10;behind.material_override=back_material
	var actual := (await capture()).get_pixel(192,192)
	var shader := Shader.new();shader.code="shader_type spatial; render_mode unshaded, blend_add, depth_draw_never, fog_disabled; void fragment(){ALBEDO=vec3(0.1,0.1,0.075);ALPHA=1.0;}"
	var reference := ShaderMaterial.new();reference.shader=shader;plane.material_override=reference
	var expected := (await capture()).get_pixel(192,192)
	check(Vector3(actual.r,actual.g,actual.b).distance_to(Vector3(expected.r,expected.g,expected.b))<0.012,"Additive shader used alpha as a blend factor, wrote depth or lost RGB tint")
	plane.visible=false
	var absent := (await capture()).get_pixel(192,192)
	check(Vector3(actual.r,actual.g,actual.b).distance_to(Vector3(absent.r,absent.g,absent.b))>0.02,"Zero texture/tint alpha incorrectly removed additive RGB")
	plane.free();behind.free()

func capture() -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)
