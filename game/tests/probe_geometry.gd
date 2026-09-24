extends SceneTree
## Detached source-model presentation; no mission progress is produced here.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const AEM=preload("res://src/content/aem.gd")
const Geometry=preload("res://src/presentation/probe_geometry.gd")
const Lit=preload("res://src/presentation/imported_material.gdshader")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<3 or args.size()>4:check(false,"Expected content, bindings, visuals and optional capture folder");finish();return
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);finish();return
	var path: String=bindings.resolve(Geometry.MODEL_ID,"mesh")
	check(path==Geometry.PATH,"Probe model14290 lost its original resource binding")
	var reader:=AEM.new();var source:=reader.decode(library.read_resource(path,AEM.MAX_BYTES))
	check(not source.is_empty(),reader.error)
	if source.is_empty():finish();return
	check(source.version==4 and source.surfaces.size()==1 and source.keyframes==0,"Probe mesh acquired an unsupported internal launch animation")
	var surface: Dictionary=source.surfaces[0]
	check(surface.positions.size()==3438 and surface.indices.size()==3438 and surface.uvs.size()==3438 and surface.normals.size()==3438 and surface.colors.size()==3438,"Probe surface lost its original vertices or lit attributes")
	check(Geometry._has_no_keys(surface),"Probe source unexpectedly carries model animation keys")
	var geometry:=Geometry.new();root.add_child(geometry)
	if not geometry.build(library,visuals,bindings):check(false,geometry.error);geometry.free();finish();return
	check(not geometry.visible and geometry.model.instances.size()==1,"Probe became visible before its mission phase")
	check(geometry.model.materials[0].shader==Lit,"Probe did not use its imported lit material")
	var pose:=Transform3D(Basis(Vector3.UP,0.7),Vector3(125,35,-405))
	var state:=frame(bindings,pose,true,0)
	var prepared: Dictionary=geometry.prepare_state(state)
	check(not prepared.is_empty(),geometry.error)
	if prepared.is_empty():geometry.free();finish();return
	check(not geometry.visible and geometry.model.transform==Transform3D.IDENTITY,"Preparing a probe frame changed the scene before commit")
	check(prepared.surfaces.size()==1 and not prepared.surfaces[0].animated and prepared.surfaces[0].pose==Transform3D.IDENTITY,"Static source probe unexpectedly generated launch motion")
	check(geometry.commit_state(prepared) and geometry.visible and geometry.model.transform==pose and geometry.model.instances[0].transform==Transform3D.IDENTITY,"Accepted probe frame lost its rigid pose")
	var accepted:=geometry.model.transform
	for changes in [{"binding_id":"foreign"},{"base_content_id":"foreign"},{"model_id":14291},
		{"pose":Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*2),Vector3.ZERO)},
		{"pose":Transform3D(Basis.IDENTITY,Vector3(INF,0,0))},
		{"visible":1},{"model_time_ms":-1},{"model_time_ms":1.5}]:
		var bad: Dictionary=state.duplicate(true);bad.merge(changes,true)
		check(geometry.prepare_state(bad).is_empty() and geometry.visible and geometry.model.transform==accepted,"Rejected probe candidate changed the accepted scene: "+str(changes))
	var missing: Dictionary=state.duplicate();missing.erase("model_time_ms")
	check(geometry.prepare_state(missing).is_empty(),"Probe accepted an implicit animation clock")
	check(not geometry.commit_state({}) and geometry.visible and geometry.model.transform==accepted,"Unprepared probe frame changed the scene")
	var later: Dictionary=geometry.prepare_state(frame(bindings,pose,true,2500))
	check(not later.is_empty() and later.surfaces[0].pose==Transform3D.IDENTITY,"Explicit later model time invented source launch animation")
	var altered: Dictionary=later.duplicate(true);altered.visible=false
	check(not geometry.commit_state(altered) and geometry.visible,"Modified candidate bypassed frame acceptance")
	check(geometry.commit_state(later) and geometry.visible and geometry.model.transform==pose,"Rejected candidate consumed the valid prepared frame")
	check(not geometry.commit_state(later) and geometry.visible,"Probe committed the same frame twice")
	var hidden: Dictionary=geometry.prepare_state(frame(bindings,pose,false,2600))
	check(not hidden.is_empty() and geometry.commit_state(hidden) and not geometry.visible and geometry.model.transform==pose,"Explicit phase end failed to hide the original probe")
	geometry.free()
	if failures==0 and args.size()==4 and DisplayServer.get_name()!="headless":await capture(library,visuals,bindings,args[3])
	finish()

func capture(library: RefCounted,visuals: RefCounted,bindings: RefCounted,directory: String) -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(0.025,0.035,0.055)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=0.45
	var world_environment:=WorldEnvironment.new();world_environment.environment=environment;viewport.add_child(world_environment)
	var light:=DirectionalLight3D.new();viewport.add_child(light)
	light.position=Vector3(800,1000,1300);light.look_at(Vector3(0,-200,0));light.light_energy=1.35
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=1;camera.far=20000
	camera.look_at_from_position(Vector3(0,100,1050),Vector3(0,-300,0))
	var geometry:=Geometry.new();viewport.add_child(geometry)
	if not geometry.build(library,visuals,bindings):check(false,geometry.error);viewport.free();return
	var prepared: Dictionary=geometry.prepare_state(frame(bindings,Transform3D.IDENTITY,true,0))
	if prepared.is_empty() or not geometry.commit_state(prepared):check(false,geometry.error);viewport.free();return
	await process_frame;await RenderingServer.frame_post_draw
	var picture: Image=viewport.get_texture().get_image()
	var background: Color=picture.get_pixel(0,0);var pixels:=0
	for y in range(0,picture.get_height(),3):
		for x in range(0,picture.get_width(),3):
			var pixel: Color=picture.get_pixel(x,y)
			if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>.09:pixels+=1
	check(pixels>100,"Source probe did not render in the detached landscape view")
	DirAccess.make_dir_recursive_absolute(directory)
	check(picture.save_png(directory.path_join("probe-model14290.png"))==OK,"Probe landscape capture failed")
	viewport.free()

func frame(bindings: RefCounted,pose: Transform3D,shown: bool,model_time: int) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"model_id":Geometry.MODEL_ID,"pose":pose,"visible":shown,"model_time_ms":model_time}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)

func finish() -> void:
	print("Probe geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
