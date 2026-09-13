extends SceneTree
const Sun=preload("res://src/presentation/opening_sun_frame.gd")
const Definitions=preload("res://src/content/sun_flare_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Atlas=preload("res://src/content/atlas_region.gd")
const Target=preload("res://src/presentation/flight_target_frame.gd")
var failures:=0
func _initialize() -> void:
	var vectors: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/opening_sun_frame_vectors.json"))
	for row in vectors:
		var basis:=Basis.IDENTITY if row.up==[0.0,1.0,0.0] else Basis(Vector3.DOWN,Vector3.RIGHT,Vector3.BACK)
		var camera:=Transform3D(basis,vector(row.camera))
		var got:=Sun.poses_for_view(vector(row.origin),15000.0/65536.0,camera,row.prior)
		check(not got.has("error"),"Valid mathematical sun pose rejected")
		if got.has("error"):continue
		check(got.delta==row.delta and got.primary.origin==vector(row.position) and got.secondary.origin==vector(row.position),"Sun position or preceding intensity changed")
		for column in 3:
			check(got.primary.basis[column]==vector(row.primary[column]),"Primary sun pose differs from independent binary32 vector")
			check(got.secondary.basis[column]==vector(row.secondary[column]),"Secondary sun lost the first scale multiplication")
	var size:=Vector2i(960,640)
	for color in 6:
		check(Sun.intensity_at(Vector2(480,320),-1,size,color).intensity==(80.0 if color==5 else 64.0),"Wrong center flare intensity")
	check(Sun.intensity_at(Vector2(480,320),-1,Vector2i(961,641),3).intensity==64.0,"Odd viewport lost integer center")
	check(Sun.intensity_at(Vector2(800,320),-1,size,3).intensity==0.0,"Wrong radial zero intensity")
	check(Sun.intensity_at(Vector2(0,320),-1,size,3).intensity==-32.0,"Negative source intensity was clamped")
	for point in [Vector2(-960,320),Vector2(1920,320),Vector2(480,-640),Vector2(480,1280)]:
		check(Sun.intensity_at(point,-1,size,3).intensity==0.0,"Strict flare guard accepted its boundary")
	for depth in [0,1,100]:check(Sun.intensity_at(Vector2(480,320),depth,size,3).intensity==0,"Rear flare accepted")
	for bad in [null,"0",INF,NAN,81.0,1e80]:check(Sun.poses_for_view(Vector3(0,0,-20000),0.25,Transform3D.IDENTITY,bad).has("error"),"Invalid prior intensity accepted")
	check(Sun.poses_for_view(Vector3(INF,0,0),0.25,Transform3D.IDENTITY,0).has("error"),"Invalid sun origin accepted")
	check(Sun.poses_for_view(Vector3.ZERO,0.0,Transform3D.IDENTITY,0).has("error"),"Zero sun scale accepted")
	var args:=OS.get_cmdline_user_args()
	for index in range(0,args.size(),3):verify(args[index],args[index+1],args[index+2])
	print("Opening sun frame: ",vectors.size()," mathematical vectors; ",failures," failures");quit(0 if failures==0 else 1)
func verify(content: String,pack: String,textures: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new();var sun:=Sun.new()
	check(lib.open(content),lib.error);check(bindings.open(pack,lib.manifest),bindings.error)
	check(cat.open(lib),cat.error);check(visuals.open(textures,lib.manifest),visuals.error)
	if bindings.opening_sky.get("sun_flares",{}).is_empty():
		check(not sun.configure(bindings,cat,lib.manifest.content_id),"Legacy pack fabricated sun flare capability")
		print("Sun flares unavailable in legacy ",lib.manifest.profile.edition);return
	check(sun.configure(bindings,cat,lib.manifest.content_id),sun.error)
	if sun.selection.is_empty():return
	check(sun.selection.system_id==15 and sun.selection.color_type==3 and sun.selection.color==[255.0,255.0,255.0],"Wrong fresh system sun color")
	check(visuals.load_image(sun.selection.texture_path)!=null,visuals.error)
	var atlas:=Atlas.new();var regions:=[]
	for row in sun.selection.images:
		check(Target.BASELINE_ATLASES.has(int(row.texture_id)),"Flare uses an unsupported baseline atlas")
		if not Target.BASELINE_ATLASES.has(int(row.texture_id)):continue
		var path: String=Target.BASELINE_ATLASES[int(row.texture_id)]
		var registered:=false
		for record in bindings.records.get(int(row.texture_id),[]):
			if record.resource==path and record.kind=="texture" and int(record.registration_type)==2:registered=true
		check(registered,"Flare atlas is absent from original registrations")
		var texture:=atlas.load(lib,visuals,path,int(row.region))
		check(texture!=null,atlas.error)
		if texture!=null:regions.append({"image_id":row.id,"region":row.region,"rect":texture.region})
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack+"/bindings.json"))
	var data: Dictionary=bindings.opening_sky.sun_flares
	check(Definitions.validate(data,int(header.source_executable_bytes),header.architecture).is_empty(),"Valid sun declaration provenance rejected")
	for bad in ["images","color","types","overlap","extent"]:
		var copy:=data.duplicate(true)
		match bad:
			"images":copy.images[0].id=0
			"color":copy.colors[0][0]=256
			"types":copy.system_types[0]=6
			"overlap":copy.provenance.image_0.offset=copy.provenance.image_1.offset
			"extent":copy.provenance.image_0.bytes=63
		check(not Definitions.validate(copy,int(header.source_executable_bytes),header.architecture).is_empty(),"Malformed sun declaration accepted: "+bad)
	var camera:=Transform3D.IDENTITY
	var center: Vector3=sun._layout.sun.direction_to_sun
	camera.basis=Basis.looking_at(center,Vector3.UP)
	var view:={"pose":camera}
	var first:=sun.evaluate(view,Vector2i(960,640),0)
	check(not first.has("error"),sun.error)
	if first.has("error"):return
	check(first.in_view and absf(first.next_intensity-64.0)<0.0001 and first.delta==0.0,"Centered sun did not retain the preceding intensity")
	var next:=sun.evaluate(view,Vector2i(960,640),first.next_intensity)
	check(next.delta>0.8 and next.secondary_pose.basis.x.length()>first.secondary_pose.basis.x.length(),"Previous screen intensity did not expand the second 3D sun pass")
	check(sun.evaluate(view,Vector2i(960,640),0)==first,"Repeated sun preparation advanced retained state")
	camera.basis=Basis.looking_at(-center,Vector3.UP)
	var rear:=sun.evaluate({"pose":camera},Vector2i(960,640),64)
	check(not rear.in_view and rear.next_intensity==0 and rear.delta>0.8,"Rear sun lost reset or previous-pass ordering")
	check(sun.evaluate(view,Vector2i.ZERO,0).has("error"),"Invalid viewport accepted")
	check(sun.evaluate({"pose":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))},Vector2i(960,640),0).has("error"),"Invalid camera accepted")
	check(sun.evaluate(view,Vector2i(960,640),0)==first,"Failed frame contaminated later preparation")
	check(not sun.configure(bindings,cat,"foreign") and sun.selection.is_empty(),"Foreign base configured a sun")
	print("Sun resources ",lib.manifest.profile.edition," ",regions)
func vector(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
