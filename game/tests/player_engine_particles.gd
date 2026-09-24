extends SceneTree
## Original nozzle assets with isolated particle motion. This is a component
## fixture; it does not establish live flight visibility or boost behavior.
const Engines=preload("res://src/content/engine_particle_definitions.gd")
const Damage=preload("res://src/content/damage_particle_definitions.gd")
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
const Sprites=preload("res://src/presentation/opening_damage_geometry.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Geometry=preload("res://src/presentation/ship_geometry.gd")
const Materials=preload("res://src/presentation/material_library.gd")
const Library=preload("res://src/content/library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var library:=Library.new()
var catalogues:=Catalogues.new()
var mounts:=Mounts.new()
var bindings:=Bindings.new()
var visuals:=Visuals.new()
var checks:=0
var failures:=0

func _initialize():
	create_timer(40).timeout.connect(func():push_error("Engine particle checks timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	if args.size() not in [3,4]:check(false,"Expected Mac content, bindings, visuals and optional captures")
	elif not library.open(args[0]) or not catalogues.open(library) or not mounts.open(library,catalogues) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+catalogues.error+mounts.error+bindings.error+visuals.error)
	elif bindings.engine_particles.is_empty():check(false,"This fixture requires the Mac engine-particle capability")
	else:
		verify_attachments()
		verify_motion()
		verify_lifecycle()
		verify_ring_overflow()
		verify_invalid()
		if DisplayServer.get_name()!="headless":await render_probe(args[3] if args.size()==4 else "")
	print("Player engine particles: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func nozzle(index: int=0) -> RefCounted:
	var emitter:=Emitter.new()
	check(emitter.configure_nozzle(bindings,mounts,0,index,73),emitter.error)
	return emitter

func verify_attachments():
	var resolved:=Engines.resolve(bindings,mounts,0)
	check(not resolved.has("error"),str(resolved.get("error")))
	if resolved.has("error"):return
	check(resolved.presets.size()==4,"Betty must retain all four authored nozzles")
	var original: Array=mounts.snapshot().ships[0].groups[3]
	for index in 4:
		var row: Dictionary=resolved.presets[index]
		check(row.preset_id==29+index and row.material_id==20090,"Wrong engine manager preset or material")
		check(Vector3(row.local_offset_x,row.local_offset_y,row.local_offset_z)==original[index].position,"Nozzle offsets differ from the original attachment table")
		check(row.size==[125,125,250,250][index] and row.lifetime_ms==[60,60,80,80][index] and row.local_velocity_z==[-3000,-3000,-4000,-4000][index],"Nozzle X scale did not drive size, lifetime and local speed")
		check(not Damage.preset(row),"Engine row was accepted as an animated damage preset")
		var first:=Appearance.start(row,0,0)
		var last:=Appearance.advance(row,first,int(row.lifetime_ms))
		for slot in 20:
			last.slot=slot
			var sample:=Appearance.sample(row,last)
			check(sample.active and sample.frame==0 and sample.uv_rect==Vector4(0.005859375,0.005859375,0.119140625,0.119140625),"Static exhaust rectangle animated or mirrored")
		check(Appearance.sample(row,last).color==Color(0,0,0,0),"Exhaust failed to fade at the inclusive lifetime boundary")
		check(Appearance.advance(row,last,1).age_ms==-1,"Exhaust survived its source lifetime")
	resolved.presets[0].size=1
	check(Engines.resolve(bindings,mounts,0).presets[0].size==125,"Resolved nozzle state aliases imported definitions")
	check(Engines.resolve(bindings,mounts,1).has("error"),"Another hull inherited Betty's nozzle settings")

func verify_motion():
	# The same path emits the same count regardless of elapsed time. A faster
	# ship traversing twice the distance emits twice as many sprites.
	for example in [[80.0,40,10],[80.0,20,10],[160.0,40,20]]:
		var emitter:=nozzle()
		check(emitter.advance(Transform3D.IDENTITY,1,1).get("births")==0,"Initial nozzle baseline emitted")
		var pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,example[0]))
		var result: Dictionary=emitter.advance(pose,example[1],example[1])
		check(result.get("births")==example[2],"Distance emission used a time-based rate: "+str(result))
		var state: Dictionary=emitter.snapshot()
		var random:=Random.new();random.seed_from(73)
		for index in int(example[2]):
			var scatter:=Vector3(random.next_int(200)-100,random.next_int(200)-100,random.next_int(200)-100)
			var slot: Dictionary=state.slots[index]
			var inherited: float=float(example[0])/float(example[1])*1000.0*0.8
			check(slot.velocity.is_equal_approx(scatter+Vector3(0,0,-3000+inherited)),"Exhaust velocity lost its local or inherited contribution")
		check(state.random==random.snapshot(),"Nozzle births consumed unexpected random draws")
		var last: Dictionary=state.slots[int(example[2])-1]
		check(last.appearance.age_ms==0 and last.appearance.size==125,"Newest nozzle particle was aged before its birth")
		check(last.position.distance_to(pose.origin+Vector3(-160,99,-256))<0.4,"Nozzle origin was omitted or transformed twice")
		check(state.slots[0].appearance.age_ms>0 and state.slots[0].appearance.size<125,"Older births did not receive residual travel and shrinking")
	var rotated:=nozzle()
	var basis:=Basis(Vector3.FORWARD,Vector3.UP,Vector3.RIGHT)
	rotated.advance(Transform3D(basis,Vector3.ZERO),1,1)
	check(rotated.advance(Transform3D(basis,Vector3(80,0,0)),40,40).get("births")==10,"Rotated nozzle changed its emission count")
	var last: Dictionary=rotated.snapshot().slots[9]
	check(last.position.distance_to(Vector3(80,0,0)+basis*Vector3(-160,99,-256))<0.4,"Nozzle local X/Y/Z offsets did not follow the supplied statistics basis")
	var random:=Random.new();random.seed_from(73);var scatter:=Vector3.ZERO
	for index in 10:scatter=Vector3(random.next_int(200)-100,random.next_int(200)-100,random.next_int(200)-100)
	check(last.velocity.is_equal_approx(scatter+Vector3(-1400,0,0)),"Local plume velocity did not follow the supplied statistics basis")
	var partial:=nozzle();partial.advance(Transform3D.IDENTITY,1,1)
	for step in 4:
		var result: Dictionary=partial.advance(Transform3D(Basis.IDENTITY,Vector3(0,0,(step+1)*4)),10,10)
		check(result.get("births")==[0,1,0,1][step],"Sub-spacing movement lost its retained fraction")
	check(partial.snapshot().cursor==2,"Fractional distance produced extra particles")

func verify_lifecycle():
	var emitter:=nozzle();var pose:=Transform3D.IDENTITY
	check(emitter.advance(pose,0,0).get("births")==0 and emitter.snapshot().dirty,"Paused frame consumed a nozzle baseline")
	emitter.advance(pose,1,1)
	var before: Dictionary=emitter.snapshot()
	check(emitter.advance(pose,1000,1000).get("births")==0,"Stationary nozzle emitted a plume")
	pose.origin.z=0.5
	check(emitter.advance(pose,1000,1000).get("births")==0,"Below-threshold nozzle speed emitted")
	check(emitter.snapshot().random==before.random and emitter.snapshot().remainder_ms==0,"Below-threshold movement consumed emission time or random draws")
	pose.origin.z=80.5;emitter.advance(pose,40,40)
	before=emitter.snapshot()
	check(emitter.advance(pose,0,0).get("births")==0 and emitter.snapshot()==before,"Pause changed live exhaust")
	var fork: RefCounted=emitter.fork_for_frame();fork.set_emitting(false)
	check(emitter.snapshot()==before and fork.advance(pose,80,80).get("births")==0,"Staged exhaust flags changed the accepted emitter")
	check(fork.snapshot().slots.all(func(slot):return slot.appearance.age_ms==-1),"Emission stop froze old exhaust particles")
	emitter.set_visible(false)
	check(emitter.snapshot().dirty and emitter.snapshot().slots.all(func(slot):return slot.appearance.age_ms==-1),"Hiding an emitter did not reset its old sprites")
	check(emitter.snapshot().random==before.random and emitter.snapshot().cursor==before.cursor,"Visibility reset changed RNG or insertion order")
	emitter.set_visible(true);pose.origin=Vector3(700000,20000,-100000)
	check(emitter.advance(pose,100,100).get("births")==0,"Relocation emitted across the discarded path")
	before=emitter.snapshot()
	pose.origin.z+=2e10
	check(emitter.advance(pose,1000,1000).has("error") and emitter.snapshot()==before,"Excessive birth work changed accepted state")

func verify_ring_overflow():
	# The opening jump can request more births than the old fixed work guard,
	# while only the last 20 original nozzle slots can remain visible.
	var emitter:=nozzle();check(emitter.advance(Transform3D.IDENTITY,10,10).get("births")==0,"Overflow fixture lost its baseline")
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,136000))
	var result: Dictionary=emitter.advance(pose,100,100)
	check(not result.has("error") and int(result.get("births",0))>Emitter.MAX_BIRTHS_PER_FRAME,"Source jump failed its bounded ring rollover: "+str(result))
	if result.has("error"):return
	var count: int=int(result.births)
	var state: Dictionary=emitter.snapshot()
	check(state.cursor==count%20 and state.slots.all(func(slot):return slot.appearance.age_ms>=0),"Jump did not retain the final 20 ring slots")
	var random:=Random.new();random.seed_from(73)
	var tail: Array=[]
	for birth in count:
		var scatter:=Vector3(random.next_int(200)-100,random.next_int(200)-100,random.next_int(200)-100)
		if birth>=count-20:tail.append(scatter)
	check(state.random==random.snapshot(),"Overwritten births failed to consume the original random stream")
	var inherited: Vector3=state.velocity*0.8
	for index in 20:
		var slot: Dictionary=state.slots[(count-20+index)%20]
		check(slot.velocity.is_equal_approx(tail[index]+Vector3(0,0,-3000)+inherited),"A retained tail birth changed its inherited velocity")
	# The original fast inverse-square-root spacing approximation drifts by
	# several dozen units over this synthetic 136,000-unit movement.
	check(state.slots[(count-1)%20].position.distance_to(pose.origin+Vector3(-160,99,-256))<100,"The final source birth was not near the new nozzle pose")
	# A longer but finite flight must not hit a second arbitrary distance cap.
	var farther:=nozzle();farther.advance(Transform3D.IDENTITY,10,10)
	var farther_result: Dictionary=farther.advance(Transform3D(Basis.IDENTITY,Vector3(0,0,2096000)),100,100)
	check(int(farther_result.get("births",0))>262144,"Longer source jump hit a replacement birth cap: "+str(farther_result))
	if not farther_result.has("error"):
		var farther_state: Dictionary=farther.snapshot()
		check(farther_state.cursor==int(farther_result.births)%20 and farther_state.slots.all(func(slot):return slot.appearance.age_ms>=0),"Longer jump lost its bounded final ring")

func verify_invalid():
	var emitter:=Emitter.new()
	check(not emitter.configure_nozzle(bindings,mounts,0,4,73) and emitter.snapshot().is_empty(),"Missing nozzle created a partial emitter")
	var original: Dictionary=bindings.engine_particles.duplicate(true)
	for key in ["distance_spacing","animation_frames","minimum_squared_speed","material_id"]:
		bindings.engine_particles=original.duplicate(true)
		bindings.engine_particles.preset[key]+=1
		check(not emitter.configure_nozzle(bindings,mounts,0,0,73) and emitter.snapshot().is_empty(),"Changed nozzle declarations accepted: "+key)
	bindings.engine_particles={}
	check(not emitter.configure_nozzle(bindings,mounts,0,0,73),"Older content silently received invented exhaust parameters")
	bindings.engine_particles=original
	var content_id: String=bindings.base_content_id;bindings.base_content_id="0".repeat(64)
	check(Engines.resolve(bindings,mounts,0).has("error"),"Foreign nozzle table accepted")
	bindings.base_content_id=content_id

func render_probe(captures: String):
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0,320,-1400),Vector3(0,30,0));camera.near=1;camera.far=10000;camera.current=true
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.3,PI,0);viewport.add_child(light)
	var ship:=Geometry.new();viewport.add_child(ship)
	check(ship.build(0,library,visuals,bindings,"high",null,true) and ship.apply_selection({"visible":true,"level":0}),ship.error)
	var without:=await rendered(viewport)
	var descriptor: Dictionary=bindings.resolve_material(20090)
	check(Materials.supports(descriptor) and descriptor.render_type==3 and descriptor.texture_ids[0]==24202,"Original exhaust material or sprite atlas changed")
	var image: Image=visuals.load_image(descriptor.texture_paths[0])
	if image==null:check(false,visuals.error);viewport.free();return
	var material:=Materials.create(3,ImageTexture.create_from_image(image),null,true)
	for index in 4:
		var emitter:=nozzle(index)
		emitter.advance(Transform3D(Basis.IDENTITY,Vector3(0,0,-40)),1,1)
		check(emitter.advance(Transform3D.IDENTITY,20,20).get("births")==5,"Nozzle render fixture lost its distance births")
		var state: Dictionary=emitter.snapshot()
		var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var colors:=PackedFloat32Array();var indices:=PackedInt32Array()
		for slot in state.slots:
			var appearance:=Appearance.sample(state.preset,slot.appearance)
			if not appearance.get("active",false):continue
			var quad:=Sprites.sprite(camera.transform.affine_inverse()*slot.position,appearance)
			var start:=vertices.size();vertices.append_array(quad.vertices);uvs.append_array(quad.uvs);colors.append_array(quad.colors)
			indices.append_array(PackedInt32Array([start,start+2,start+1,start,start+3,start+2]))
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_CUSTOM0]=colors;arrays[Mesh.ARRAY_INDEX]=indices
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.transform=camera.transform;viewport.add_child(node)
	var with_exhaust:=await rendered(viewport)
	var changed:=0
	for y in with_exhaust.get_height():
		for x in with_exhaust.get_width():
			var a:=with_exhaust.get_pixel(x,y);var b:=without.get_pixel(x,y)
			if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
	check(changed>100,"Original exhaust sprites contributed too few pixels: "+str(changed))
	check((await rendered(viewport)).get_data()==with_exhaust.get_data(),"Rendering advanced plume simulation or RNG")
	if not captures.is_empty():
		DirAccess.make_dir_recursive_absolute(captures)
		check(with_exhaust.save_png(captures.path_join("betty-original-exhaust-component.png"))==OK,"Exhaust capture failed")
		check(without.save_png(captures.path_join("betty-nozzle-mesh-only.png"))==OK,"Nozzle-only comparison capture failed")
	print("Original exhaust additive pixels: ",changed)
	viewport.free()

func rendered(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
