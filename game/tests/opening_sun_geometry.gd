extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Sun=preload("res://src/presentation/opening_sun_geometry.gd")
const Layout=preload("res://src/presentation/sun_flare_layout.gd")
var failures:=0
var captures:=""
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var sizes:=[Vector2i(64,64),Vector2i(64,64),Vector2i(64,64)]
	var layout:=Layout.compose(Vector2(640,320),-1,Vector2i(960,640),3,sizes)
	check(layout.intensity==32 and layout.wash_alpha==32 and layout.sprites.size()==7,"Wrong source screen flare count or wash")
	var centers:=[560,520,600,500,494,360,448];var widths:=[64,48,32,80,32,128,32]
	for i in mini(7,layout.sprites.size()):
		var row: Dictionary=layout.sprites[i]
		check(row.rect==Rect2i(centers[i]-(widths[i]>>1),320-(widths[i]>>1),widths[i],widths[i]),"Wrong centered flare geometry")
		check(row.alpha_byte==(72 if i==3 else 102),"Wrong flare opacity family")
	var negative:=Layout.compose(Vector2(1000,320),-1,Vector2i(960,640),3,sizes)
	check(negative.intensity==-40 and negative.wash_alpha==0 and negative.sprites.size()==6,"Conditional sprite threshold or wash changed")
	var wrapped:=Layout.compose(Vector2(1280,320),-1,Vector2i(960,640),3,sizes)
	check(wrapped.intensity==-96 and wrapped.sprites[0].alpha_byte==230,"Source low-byte opacity wrapping changed")
	check(Layout.compose(Vector2(480,320),-1,Vector2i(960,640),5,sizes).wash_alpha==80,"Special palette intensity factor changed")
	check(Layout.compose(Vector2(480,320),0,Vector2i(960,640),3,sizes).sprites.is_empty(),"Rear screen flare emitted")
	check(Layout.compose(Vector2(480,320),-1,Vector2i(960,640),3,[]).has("error"),"Missing image sizes accepted")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--captures="):captures=args[0].trim_prefix("--captures=");args.remove_at(0)
	for i in range(0,args.size(),3):await verify(args[i],args[i+1],args[i+2])
	print("Opening sun geometry: ",failures," failures");quit(0 if failures==0 else 1)
func verify(content: String,pack: String,textures: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	check(lib.open(content),lib.error);check(bindings.open(pack,lib.manifest),bindings.error)
	check(cat.open(lib),cat.error);check(visuals.open(textures,lib.manifest),visuals.error)
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,640);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.current=true;camera.near=1;camera.far=100000;camera.fov=60;viewport.add_child(camera)
	var sun:=Sun.new();viewport.add_child(sun)
	if bindings.opening_sky.get("sun_flares",{}).is_empty():
		check(not sun.build(lib,visuals,bindings,cat) and sun.get_child_count()==0,"Legacy pack rendered invented flare resources");viewport.free();return
	check(sun.build(lib,visuals,bindings,cat),sun.error)
	if sun.selection.is_empty():viewport.free();return
	camera.look_at(sun._owner._layout.sun.direction_to_sun,Vector3.UP)
	var view:={"pose":camera.transform}
	var first:=sun.prepare_frame(view,viewport.size,0)
	check(not first.has("error"),sun.error)
	if first.has("error"):viewport.free();return
	check(sun.frame.is_empty(),"Preparing sun frame mutated presentation")
	sun.commit_frame(first)
	check(not sun.secondary.visible and first.composition.sprites.size()==7,"Zero-width sun strip or centered sprite composition changed")
	var before:=sun.frame.duplicate(true);var pose: Transform3D=sun.primary.transform
	check(sun.prepare_frame(view,Vector2i.ZERO,0).has("error") and sun.frame==before and sun.primary.transform==pose,"Invalid frame mutated visible sun")
	var expanded:=sun.prepare_frame(view,viewport.size,64)
	check(not expanded.has("error"),sun.error)
	if DisplayServer.get_name()!="headless":
		sun.flares.visible=false
		var image:=await capture(viewport);save(image,lib.manifest.profile.edition+"-primary")
		check(variation(image)>30,"Original sun plane did not render")
		sun.commit_frame(expanded)
		var brighter:=await capture(viewport);save(brighter,lib.manifest.profile.edition+"-expanded")
		check(image.get_data()!=brighter.get_data(),"Retained flare intensity did not change the original sun image")
		sun.flares.visible=true
		var flares:=await capture(viewport);save(flares,lib.manifest.profile.edition+"-center-flares")
		check(flares.get_data()!=brighter.get_data(),"Original screen flare images or color wash did not render")
		sun.flares.visible=false
		var cube:=MeshInstance3D.new();cube.mesh=BoxMesh.new();cube.mesh.size=Vector3(30,30,30)
		cube.transform=camera.transform*Transform3D(Basis.IDENTITY,Vector3(0,0,-100))
		var red:=StandardMaterial3D.new();red.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;red.albedo_color=Color.RED;cube.material_override=red;viewport.add_child(cube)
		var occluded:=await capture(viewport);var center:=occluded.get_pixel(480,320)
		check(center.r>0.9 and center.g<0.02 and center.b<0.02,"Sun planes shone through the foreground world")
		save(occluded,lib.manifest.profile.edition+"-occluded");cube.free()
		camera.rotate_object_local(Vector3.UP,0.3);view.pose=camera.transform
		var offset:=sun.prepare_frame(view,viewport.size,64);check(not offset.has("error"),sun.error)
		sun.commit_frame(offset);sun.flares.visible=true
		var off_center:=await capture(viewport);save(off_center,lib.manifest.profile.edition+"-offset-flares")
		check(offset.composition.sprites.size()==7 and off_center.get_data()!=flares.get_data(),"Off-center flare train did not respond to projection")
		sun.primary.visible=false;sun.secondary.visible=false
		var screen_only:=await capture(viewport);save(screen_only,lib.manifest.profile.edition+"-screen-only")
		check(variation(screen_only)>20,"Original atlas flares did not produce a visible screen composition")
		sun.primary.visible=true;sun.secondary.visible=true
		camera.look_at(-sun._owner._layout.sun.direction_to_sun,Vector3.UP);view.pose=camera.transform
		var rear:=sun.prepare_frame(view,viewport.size,64);sun.commit_frame(rear)
		check(rear.next_intensity==0 and rear.composition.sprites.is_empty(),"Rear sun kept current screen flares")
		save(await capture(viewport),lib.manifest.profile.edition+"-rear")
	viewport.free()
func capture(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func save(value: Image,name: String) -> void:
	if not captures.is_empty():check(value.save_png(captures.path_join(name+".png"))==OK,"Unable to save sun capture")
func variation(value: Image) -> int:
	var seen:={}
	for y in range(0,value.get_height(),4):
		for x in range(0,value.get_width(),4):seen[value.get_pixel(x,y).to_rgba32()]=true
	return seen.size()
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
