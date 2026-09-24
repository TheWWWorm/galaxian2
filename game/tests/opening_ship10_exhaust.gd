extends SceneTree
## A source-identified detached declaration fixture validates opening ship 10
## without rewriting or relabelling the accepted content/binding pack.
const Library=preload("res://src/content/library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Exhaust=preload("res://src/simulation/player_engine_particles.gd")
const Engines=preload("res://src/content/engine_particle_definitions.gd")
const Owners=preload("res://src/content/engine_particle_owner_definitions.gd")
const Geometry=preload("res://src/presentation/opening_geometry.gd")
const Session=preload("res://src/presentation/opening_session.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("Opening ship exhaust checks timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:
		await verify_connected(args)
	elif args.size()==4:
		await verify(args)
	else:
		check(false,"Expected content, bindings and visuals, optionally followed by a detached source declaration fixture")
	print("Opening ship10 exhaust: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_connected(args: PackedStringArray) -> void:
	# The live opening must attach the renderer from this pack's own declarations.
	# The older saved imports lack ship10 ownership even when the executable and
	# Betty exhaust artwork are present, so they cannot satisfy this path.
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	if not library.select_language("gb"):
		check(false,library.error);return
	check(Exhaust.Definitions.available_for(bindings,10),"Binding pack has no source-identified opening ship10 engine owner")
	if failures:return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var session:=Session.new();viewport.add_child(session)
	check(session.configure(library,bindings,visuals,0,0.5,73,true,true,false),session.error)
	if failures:viewport.free();return
	var state: Dictionary=session.snapshot()
	check(session.geometry.player.get_meta("source_ship_id")==10,"Live opening used another player hull")
	check(state.world_frame.get("engine_particles",{}).get("owners",{}).size()==3,"Live opening omitted the three player nozzles")
	check(session.geometry.engine_particles!=null and session.geometry.engine_particles.items.size()==3,"Live opening omitted the original sprite surfaces")
	if failures:viewport.free();return
	# The first manager update records its movement baseline; the next moving
	# update emits. Both passes are ordinary source time, without fixture state.
	check(session.step(100000) and session.step(200000),session.error)
	if failures:viewport.free();return
	state=session.snapshot()
	var particle_state: Dictionary=state.world_frame.engine_particles
	var counts: Array=session.geometry.engine_particles.frame.get("counts",[])
	check(particle_state.elapsed_ms==state.elapsed_ms and particle_state.engine_enabled and particle_state.draw_enabled and not particle_state.player_hidden,"Live opening engine manager did not advance visibly")
	check(counts.size()==3 and counts.all(func(count):return int(count)>0),"Live opening did not render three active exhaust populations: "+str(counts))
	if DisplayServer.get_name()!="headless" and failures==0:
		var pose: Transform3D=state.scene.player_pose
		session.camera.look_at_from_position(pose.origin+pose.basis*Vector3(0,100,-900),pose.origin+pose.basis*Vector3(0,0,-450))
		session.camera.near=1;session.camera.far=100000
		var visible:=await rendered(viewport)
		session.geometry.engine_particles.hide()
		var hidden:=await rendered(viewport)
		var changed:=0
		for y in visible.get_height():
			for x in visible.get_width():
				var a:=visible.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
				if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
		check(changed>100,"Connected opening exhaust added too few visible pixels: "+str(changed))
		print("Connected opening ship10 additive pixels: ",changed)
		var captures:=OS.get_environment("GOF2_CAPTURE_DIR")
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			check(visible.save_png(captures.path_join("opening-ship10-connected-visible.png"))==OK and hidden.save_png(captures.path_join("opening-ship10-connected-hidden.png"))==OK,"Connected opening exhaust capture failed")
	viewport.free()

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var catalogues:=Catalogues.new();var mounts:=Mounts.new()
	var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not catalogues.open(library) or not mounts.open(library,catalogues) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+catalogues.error+mounts.error+bindings.error+visuals.error);return
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	var fixture: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[3]))
	if not metadata is Dictionary or not fixture is Dictionary or fixture.get("scope")!="detached_opening_ship10_exhaust_fixture" or fixture.get("base_content_id")!=bindings.base_content_id or fixture.get("binding_id")!=bindings.binding_id or fixture.get("source_executable_sha256")!=metadata.get("source_executable_sha256"):
		check(false,"Detached opening proof belongs to another source or pack");return
	var engine: Variant=fixture.get("engine_particles")
	var owner_data: Variant=fixture.get("engine_particle_owners")
	var source_bytes:=int(metadata.source_executable_bytes)
	var engine_error:=Engines.validate(engine,source_bytes,bindings.source_architecture,bindings.arrival_staging,bindings.damage_particles)
	var owner_error:=Owners.validate(owner_data,source_bytes,bindings.source_architecture,bindings.arrival_staging,engine)
	check(engine_error.is_empty(),"Opening nozzle proof failed native source-extent validation: "+engine_error)
	check(owner_error.is_empty(),"Opening owner proof failed native source-extent validation: "+owner_error)
	if failures:return
	bindings.engine_particles=engine.duplicate(true)
	bindings.engine_particle_owners=owner_data.duplicate(true)
	var resolved:=Engines.resolve(bindings,mounts,10)
	check(not resolved.has("error"),str(resolved.get("error","")))
	if resolved.has("error"):return
	check(resolved.presets.size()==3,"Opening hull did not resolve three source nozzles")
	var positions: Array=[Vector3(45,-54,-455),Vector3(-45,-54,-455),Vector3(0,18,-455)]
	for index in 3:
		var row: Dictionary=resolved.presets[index]
		check(row.preset_id==29+index and is_equal_approx(float(row.size),149.999984741211) and row.lifetime_ms==71 and is_equal_approx(float(row.local_velocity_z),-3599.99975585938),"Opening nozzle scale, time, velocity or slot differs from source")
		check(row.uv_rect==Engines.OPENING_SHIP.uv_rect,"Opening ship inherited Betty's atlas rectangle")
		check(Vector3(row.local_offset_x,row.local_offset_y,row.local_offset_z)==positions[index],"Opening nozzle lost its weapons table mount")
	check(Engines.resolve(bindings,mounts,0).presets.size()==4,"Opening addition changed Betty's four nozzles")
	var exhaust:=Exhaust.new()
	check(exhaust.configure(bindings,mounts,10,73),exhaust.error)
	if failures:return
	check(exhaust.snapshot().owners.size()==3 and exhaust.snapshot().engine_enabled and exhaust.snapshot().draw_enabled,"Opening manager did not start with three enabled nozzles")
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0.025,0.03,0.04)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=0.6
	viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);viewport.add_child(light)
	var camera:=Camera3D.new();viewport.add_child(camera)
	var geometry:=Geometry.new();viewport.add_child(geometry)
	check(geometry.build(library,visuals,bindings,catalogues) and geometry.player.get_meta("source_ship_id")==10,geometry.error)
	if failures:viewport.free();return
	var source_pose: Transform3D=geometry.player.global_transform
	camera.look_at_from_position(source_pose.origin+Vector3(0,150,-1800),source_pose.origin+Vector3(0,0,-450))
	camera.near=1;camera.far=10000;camera.current=true
	check(exhaust.advance(source_pose,10) and exhaust.advance(Transform3D(source_pose.basis,source_pose.origin+Vector3(0,0,100)),40),exhaust.error)
	check(exhaust.snapshot().births.values()==[12,12,12],"Opening manager did not emit each source nozzle")
	check(geometry.prepare_player_exhaust(null,{},camera.global_transform).is_empty() and geometry.error.is_empty(),"Legacy opening frame without exhaust became an error")
	check(geometry.build_player_exhaust(exhaust,library,visuals,bindings),geometry.error)
	if failures:viewport.free();return
	check(geometry.engine_particles.items.size()==3,"Opening renderer did not attach three original sprite surfaces")
	for item in geometry.engine_particles.items:
		check(item.node.get_meta("source_material_id")==20090 and item.node.get_meta("source_texture_id")==24202,"Opening renderer replaced original additive material or atlas")
	var world:=frame(exhaust)
	var prepared:=geometry.prepare_player_exhaust(exhaust,world,camera.global_transform)
	check(prepared.get("counts")==[12,12,12],geometry.error)
	if prepared.is_empty():viewport.free();return
	geometry.commit_player_exhaust(prepared)
	var visible: Image
	if DisplayServer.get_name()!="headless":visible=await rendered(viewport)
	var accepted:=exhaust.snapshot()
	check(geometry.prepare_player_exhaust(exhaust,world,camera.global_transform).get("counts")==[12,12,12] and exhaust.snapshot()==accepted,"Opening presentation advanced exhaust simulation")
	var stale:=world.duplicate(true);stale.elapsed_ms+=1
	check(geometry.prepare_player_exhaust(exhaust,stale,camera.global_transform).is_empty(),"Opening renderer accepted stale exhaust time")
	var foreign:=world.duplicate(true);foreign.binding_id="0".repeat(64)
	check(geometry.prepare_player_exhaust(exhaust,foreign,camera.global_transform).is_empty(),"Opening renderer accepted foreign binding")
	check(exhaust.set_player_hidden(true),exhaust.error)
	prepared=geometry.prepare_player_exhaust(exhaust,frame(exhaust),camera.global_transform)
	check(prepared.get("counts")==[0,0,0],geometry.error)
	geometry.commit_player_exhaust(prepared)
	if DisplayServer.get_name()!="headless":
		var hidden:=await rendered(viewport)
		var changed:=0
		for y in visible.get_height():
			for x in visible.get_width():
				var a:=visible.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
				if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
		check(changed>100,"Opening source exhaust added too few visible pixels: "+str(changed))
		print("Opening ship10 additive pixels: ",changed)
		var captures:=OS.get_environment("GOF2_CAPTURE_DIR")
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			check(visible.save_png(captures.path_join("opening-ship10-exhaust-visible.png"))==OK and hidden.save_png(captures.path_join("opening-ship10-exhaust-hidden.png"))==OK,"Opening exhaust capture failed")
	exhaust.set_player_hidden(false)
	prepared=geometry.prepare_player_exhaust(exhaust,frame(exhaust),camera.global_transform)
	check(prepared.get("counts")==[12,12,12],geometry.error)
	geometry.commit_player_exhaust(prepared)
	geometry.clear()
	check(geometry.engine_particles==null and geometry.get_child_count()==0,"Clearing opening scene retained exhaust sprites")
	viewport.free()

func frame(exhaust: RefCounted) -> Dictionary:
	var state: Dictionary=exhaust.snapshot()
	return {"base_content_id":state.base_content_id,"binding_id":state.binding_id,
		"elapsed_ms":state.elapsed_ms,"engine_particles":state}

func rendered(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
