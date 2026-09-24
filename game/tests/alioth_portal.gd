extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Portal=preload("res://src/simulation/alioth_portal.gd")
const AEM=preload("res://src/content/aem.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Geometry=preload("res://src/presentation/alioth_portal_geometry.gd")
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");quit(1);return
	var lib:=Library.new();var bindings:=Bindings.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest):check(false,lib.error+bindings.error);quit(1);return
	var entry:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,"environment_object":{"resource_id":16994,"position":Vector3(0,0,210000)}}
	var portal:=Portal.new()
	if not portal.configure(bindings,entry,lib):check(false,portal.error);quit(1);return
	var camera:=Transform3D(Basis.IDENTITY,Vector3(100,200,180000))
	for tick in 400:
		if not portal.advance(150,camera):check(false,portal.error);quit(1);return
	check(portal.snapshot().elapsed_ms==60000 and portal.snapshot().extent==4096 and portal.snapshot().visible,"Portal closed at the inclusive lifetime boundary")
	for tick in 20:portal.advance(150,camera)
	check(portal.snapshot().elapsed_ms==63000 and portal.snapshot().extent==0 and portal.snapshot().visible,"Portal hid at the inclusive closing boundary")
	portal.advance(1,camera)
	check(not portal.snapshot().visible,"Closed portal remained visible")
	var closed: Dictionary=portal.snapshot()
	portal.advance(150,camera)
	check(portal.snapshot().elapsed_ms==closed.elapsed_ms and portal.snapshot().animation_elapsed_ms==closed.animation_elapsed_ms+150,"Hidden portal advanced its appearance clock or stopped asset animation")
	var before: Dictionary=portal.snapshot()
	check(not portal.advance(751 if not bindings.fast_forward.is_empty() else 151,camera) and portal.snapshot()==before,"Invalid frame changed the portal")
	var model:=AEM.new();var path: String=bindings.resolve(16994,"mesh")
	var parsed: Dictionary=model.decode(lib.read_resource(path,AEM.MAX_BYTES))
	check(not parsed.is_empty(),model.error)
	check(parsed.surfaces.size()==2 and portal.snapshot().animation.end_ms==20000 and portal.snapshot().animation.start_ms==50,"Portal lost its original animation tracks")
	if failures==0:await verify_geometry(lib,bindings,args[2],entry)
	print("Alioth portal: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_geometry(lib: RefCounted,bindings: RefCounted,path: String,entry: Dictionary) -> void:
	var visuals:=Visuals.new()
	if not visuals.open(path,lib.manifest):check(false,visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=10;camera.far=100000
	camera.look_at_from_position(Vector3(0,0,195000),Vector3(0,0,210000))
	var owner:=Portal.new();var geometry:=Geometry.new();viewport.add_child(geometry)
	if not owner.configure(bindings,entry,lib) or not geometry.build(lib,visuals,bindings):check(false,owner.error+geometry.error);viewport.free();return
	for tick in 20:
		if not owner.advance(150,camera.transform):check(false,owner.error);viewport.free();return
	var frame: Dictionary=geometry.prepare_state(owner.snapshot())
	if frame.is_empty():check(false,geometry.error);viewport.free();return
	geometry.commit_state(frame)
	check(geometry.model.instances.size()==2 and geometry.model.instances.all(func(node):return node.is_visible_in_tree()),"The original portal lost an additive surface")
	var before: Array=geometry.model.instances.map(func(node):return node.transform)
	var wrong: Dictionary=owner.snapshot();wrong.binding_id="f".repeat(64)
	check(geometry.prepare_state(wrong).is_empty() and geometry.model.instances.map(func(node):return node.transform)==before,"Rejected portal presentation changed accepted surfaces")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		var picture:=viewport.get_texture().get_image();var background:=picture.get_pixel(0,0);var count:=0
		for y in range(0,picture.get_height(),3):
			for x in range(0,picture.get_width(),3):
				var pixel:=picture.get_pixel(x,y)
				if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>.09:count+=1
		check(count>100,"The original portal failed to render")
		var directory:=OS.get_environment("GOF2_PORTAL_CAPTURES")
		if not directory.is_empty():
			DirAccess.make_dir_recursive_absolute(directory)
			check(picture.save_png(directory.path_join("alioth-portal.png"))==OK,"Portal capture failed")
	viewport.free()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
