extends "res://tests/secondary_retention.gd"
## Render original imported projectile bodies after actual detached launches.
## This does not claim detonation effects or a playable Kappa campaign.
const Geometry=preload("res://src/presentation/secondary_geometry.gd")
const Visuals=preload("res://src/content/visual_library.gd")

func _initialize() -> void:call_deferred("render_secondary")

func render_secondary() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await verify_geometry(args)
	else:check(false,"Expected content, bindings, visuals and optional capture path")
	await process_frame
	print("Original EMP body geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_geometry(args: PackedStringArray) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	if not OwnershipRules.available(bindings):
		var unavailable:=Geometry.new();check(not unavailable.build(Ownership.new(),lib,visuals,bindings),"Legacy pack enabled EMP geometry");unavailable.free();return
	var built:=construction(bindings,cat,0.5)
	if built==null:return
	var group:=active_group(bindings,cat,built,0)
	if group==null:return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=0.1;camera.far=100000
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4;viewport.add_child(environment)
	var owner:=Ownership.new();var initial:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":1}])
	var geometry:=Geometry.new();viewport.add_child(geometry)
	if not owner.configure(bindings,cat,initial) or not geometry.build(owner,lib,visuals,bindings):check(false,owner.error+geometry.error);viewport.free();return
	var empty:=geometry.prepare_world(owner)
	if empty.is_empty():check(false,geometry.error);viewport.free();return
	geometry.commit_world(empty)
	check(geometry.bodies.size()==1 and not geometry.bodies[0].visible and geometry.bodies[0].get_meta("source_resource_id")==14684,"Unlaunched EMP lost its original model or became visible")
	var operation:=owner.evaluate_advance(1,group,[0,1,2,3])
	if operation.is_empty():check(false,owner.error);viewport.free();return
	owner=operation.owner
	operation=owner.evaluate_trigger(Transform3D.IDENTITY,41,group,[0,1,2,3])
	if operation.is_empty():check(false,owner.error);viewport.free();return
	owner=operation.owner;group=operation.combat
	var before: Dictionary=owner.snapshot()
	var prepared:=geometry.prepare_world(owner)
	if prepared.is_empty():check(false,geometry.error);viewport.free();return
	check(not geometry.bodies[0].visible and owner.snapshot()==before,"Geometry preparation drew early or changed weapon state")
	geometry.commit_world(prepared)
	check(geometry.bodies[0].visible and geometry.bodies[0].position==Vector3(0,0,400) and geometry.bodies[0].basis.is_equal_approx(Basis.IDENTITY),"Launched EMP body lost its source muzzle or orientation")
	check(owner.snapshot().guns[0].ammunition==0,"Geometry fixture did not exercise a last-round launch")
	var flying_owner: RefCounted=owner
	var flying_frame: Dictionary=prepared
	var pose: Transform3D=geometry.bodies[0].transform
	var invalid:=owner.fork();invalid._guns[0].bomb._shot.position=Vector3(NAN,0,0)
	check(geometry.prepare_world(invalid).is_empty() and geometry.bodies[0].transform==pose and geometry.bodies[0].visible,"Failed geometry validation changed the visible projectile")
	var foreign:=Ownership.new()
	check(foreign.configure(bindings,cat,initial) and geometry.prepare_world(foreign).is_empty(),"Geometry accepted a reset launcher generation")
	var was_paused:=paused
	paused=true
	for frame in 3:await process_frame
	paused=was_paused
	check(geometry.bodies[0].transform==pose and geometry.bodies[0].visible and owner.snapshot()==before,"Paused EMP body advanced independently of its retained weapon owner")
	prepared=geometry.prepare_world(owner)
	if prepared.is_empty():check(false,geometry.error);viewport.free();return
	geometry.commit_world(prepared)
	check(geometry.bodies[0].transform==pose and geometry.bodies[0].visible,"Resuming an unchanged EMP frame moved or hid its live body")
	var bounds: AABB=geometry.bodies[0].source_bounds
	check(bounds.size.length()>0,"The original EMP mesh is empty")
	print("EMP body resource: ",geometry._launchers[0].resource,"; bounds: ",bounds)
	var center:=geometry.bodies[0].transform*bounds.get_center()
	var radius:=maxf(bounds.size.length(),1.0)
	camera.look_at_from_position(center+Vector3(1.2,0.7,1.8)*radius,center)
	if DisplayServer.get_name()!="headless":
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image();var background:=image.get_pixel(0,0);var foreground:=0
		for y in range(0,image.get_height(),2):
			for x in range(0,image.get_width(),2):
				var pixel:=image.get_pixel(x,y)
				if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
		check(foreground>100,"Original EMP body did not render")
		if args.size()==4:
			DirAccess.make_dir_recursive_absolute(args[3])
			check(image.save_png(args[3].path_join("emp-original-body.png"))==OK,"Could not save the EMP diagnostic capture")
	operation=owner.evaluate_trigger(Transform3D.IDENTITY,41,group,[0,1,2,3])
	if operation.is_empty():check(false,owner.error);viewport.free();return
	owner=operation.owner
	prepared=geometry.prepare_world(owner)
	if prepared.is_empty():check(false,geometry.error);viewport.free();return
	geometry.commit_world(prepared)
	check(not geometry.bodies[0].visible and owner.snapshot().guns[0].bomb.shot.phase=="detonated","Detonation retained the flying body or altered the bomb state")
	geometry.commit_world(flying_frame)
	check(not geometry.bodies[0].visible,"A retained pre-detonation frame revived the consumed projectile")
	var old_body: WeakRef=weakref(geometry.bodies[0])
	var old_material: WeakRef=weakref(geometry.bodies[0].materials[0])
	var old_mesh: WeakRef=weakref(geometry.bodies[0].instances[0].mesh)
	if not geometry.build(flying_owner,lib,visuals,bindings):check(false,geometry.error);viewport.free();return
	check(old_body.get_ref()==null and old_material.get_ref()==null and old_mesh.get_ref()==null and geometry.get_child_count()==1,"Repeated EMP build retained replaced mesh resources")
	geometry.commit_world(flying_frame)
	check(not geometry.bodies[0].visible,"A frame from the previous EMP build redrew its replaced body")
	prepared=geometry.prepare_world(flying_owner)
	if prepared.is_empty():check(false,geometry.error);viewport.free();return
	var previous_build_frame: Dictionary=prepared
	if not geometry.build(flying_owner,lib,visuals,bindings):check(false,geometry.error);viewport.free();return
	geometry.commit_world(previous_build_frame)
	check(not geometry.bodies[0].visible,"Rebuilding the same EMP owner reused a pending geometry frame")
	prepared=geometry.prepare_world(flying_owner)
	if prepared.is_empty():check(false,geometry.error);viewport.free();return
	geometry.commit_world(prepared)
	check(geometry.bodies[0].visible and geometry.bodies[0].transform==pose,"Rebuilt EMP geometry rejected its new accepted frame")
	old_body=weakref(geometry.bodies[0]);old_material=weakref(geometry.bodies[0].materials[0]);old_mesh=weakref(geometry.bodies[0].instances[0].mesh)
	geometry.clear();check(geometry.get_child_count()==0 and geometry.bodies.is_empty(),"Clearing EMP geometry leaked model instances")
	geometry.commit_world(prepared)
	check(old_body.get_ref()==null and old_material.get_ref()==null and old_mesh.get_ref()==null and geometry.bodies.is_empty(),"A pending EMP frame retained cleared projectile resources")
	geometry.clear();check(geometry.get_child_count()==0,"Repeated EMP cleanup recreated child resources")
	viewport.free()
