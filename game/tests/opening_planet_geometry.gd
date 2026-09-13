extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Planets=preload("res://src/presentation/opening_planet_geometry.gd")
var failures:=0
var captures:=""
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--captures="):captures=args[0].trim_prefix("--captures=");args.remove_at(0)
	for i in range(0,args.size(),3):await verify(args[i],args[i+1],args[i+2])
	print("Opening planet geometry: ",failures," failures");quit(0 if failures==0 else 1)
func verify(content: String, pack: String, textures: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	check(lib.open(content),lib.error);check(bindings.open(pack,lib.manifest),bindings.error)
	check(cat.open(lib),cat.error);check(visuals.open(textures,lib.manifest),visuals.error)
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,640);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.current=true;camera.near=1;camera.far=1000;camera.fov=60;viewport.add_child(camera)
	var planets:=Planets.new();viewport.add_child(planets)
	if bindings.opening_sky.get("planet_resources",{}).is_empty():
		check(not planets.build(lib,visuals,bindings,cat,"high",true),"Legacy pack rendered unavailable planets");viewport.free();return
	check(planets.build(lib,visuals,bindings,cat,"high",true),planets.error)
	if planets.selection.is_empty():viewport.free();return
	check(planets.models.size()==5,"Wrong fresh planet count")
	var escape:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"phase":9}
	check(planets.apply_view({"pose":camera.transform},escape),planets.error)
	var initial:=planets.selection.duplicate(true)
	var current:=int(initial.selected_index)-1
	check(initial.planets[current].scale==planets._layout.entries[current+1].scale,"Identity camera changed constructor scale")
	var before:=planets.models.map(func(model):return model.transform)
	check(not planets.apply_view({"pose":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))},escape) and planets.selection==initial and planets.models.map(func(model):return model.transform)==before,"Invalid view changed prepared planets")
	var wrong:=escape.duplicate();wrong.binding_id="foreign"
	check(not planets.apply_view({"pose":camera.transform},wrong) and planets.selection==initial,"Foreign frame changed planets")
	var base: float=initial.planets[current].scale
	for z in [-800000.0,-160000.0,-10000.0,0.0,160000.0,800000.0]:
		camera.position.z=z
		check(planets.apply_view({"pose":camera.transform},escape),planets.error)
		var adjustment:=clampf(PackedFloat32Array([z/-800000.0])[0],PackedFloat32Array([-0.2])[0],PackedFloat32Array([0.2])[0])
		check(planets.selection.planets[current].scale==PackedFloat32Array([base+adjustment])[0],"Wrong source camera-Z scale clamp")
		for j in planets.models.size():
			check(planets.models[j].position==planets._layout.entries[j+1].origin+camera.position,"Wrong source float32 camera-relative planet position")
	camera.transform=Transform3D.IDENTITY
	check(planets.apply_view({"pose":camera.transform},escape),planets.error)
	if DisplayServer.get_name()!="headless":
		var first:=await capture(viewport)
		check(variation(first)>100,"Current planet did not render")
		save(first,lib.manifest.profile.edition+"-initial")
		camera.position=Vector3(80000,-20000,0)
		check(planets.apply_view({"pose":camera.transform},escape),planets.error)
		var moved:=await capture(viewport)
		check(first.get_data()==moved.get_data(),"Horizontal camera movement changed background planet")
		camera.position=Vector3.ZERO;escape.phase=10
		check(planets.apply_view({"pose":camera.transform},escape),planets.error)
		check(planets.selection.planets[current].scale==base,"Escape doubling incorrectly survived the source draw setter")
		var arrival:=await capture(viewport)
		check(arrival.get_data()!=first.get_data() and variation(arrival)>100,"Arrival texture replacement did not render")
		save(arrival,lib.manifest.profile.edition+"-arrival")
		escape.phase=9;check(planets.apply_view({"pose":camera.transform},escape),planets.error)
		check((await capture(viewport)).get_data()==first.get_data(),"Planet texture rollback changed its earlier image")
		var cube:=MeshInstance3D.new();cube.mesh=BoxMesh.new();cube.mesh.size=Vector3(30,30,30);cube.position=Vector3(0,0,-100)
		var red:=StandardMaterial3D.new();red.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;red.albedo_color=Color.RED;cube.material_override=red;viewport.add_child(cube)
		var foreground:=await capture(viewport);var center:=foreground.get_pixel(480,320)
		check(center.r>0.9 and center.g<0.02 and center.b<0.02,"Planet covered foreground world geometry")
		cube.free()
		for index in planets.models.size():
			if index==current:continue
			for other in planets.models.size():planets.models[other].visible=other==index
			camera.look_at(planets._layout.entries[index+1].origin,Vector3.UP)
			check(planets.apply_view({"pose":camera.transform},escape),planets.error)
			var distant:=await capture(viewport)
			check(variation(distant)>15,"Distant source planet did not render from its constructor orientation")
			save(distant,lib.manifest.profile.edition+"-station-"+str(planets.selection.planets[index].station_id))
		for model in planets.models:model.visible=true
	print("Planet geometry ",lib.manifest.profile.edition," source faces: ",planets.models[0].surfaces[0].indices)
	var system_id: int=planets.selection.system_id
	var sky: int=cat.tables.systems[system_id].sky_index
	cat.tables.systems[system_id].sky_index=11
	check(not planets.build(lib,visuals,bindings,cat) and planets.get_child_count()==0,"Unsupported fogged planet mode retained a partial scene")
	cat.tables.systems[system_id].sky_index=sky
	viewport.free()
func capture(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func save(value: Image,name: String) -> void:
	if not captures.is_empty():check(value.save_png(captures.path_join(name+".png"))==OK,"Unable to save planet capture")
func variation(value: Image) -> int:
	var seen:={}
	for y in range(0,value.get_height(),4):
		for x in range(0,value.get_width(),4):seen[value.get_pixel(x,y).to_rgba32()]=true
	return seen.size()
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
