extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Frame=preload("res://src/presentation/flight_target_frame.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):await verify_profile(args[i],args[i+1],args[i+2])
	print("Flight target frame checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify_profile(content: String,pack: String,pixels: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(pixels,library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	var frame:=Frame.new();root.add_child(frame);frame.size=Vector2(801,601)
	if not frame.prepare(library,bindings,visuals):check(false,frame.error);frame.free();return
	var source: Dictionary=frame.source()
	var mac: bool=library.manifest.profile.edition=="mac-full-hd"
	check(source.image_id==1223 and source.texture_id==(10063 if mac else 10062) and source.region==(6 if mac else 122),"Frame borrowed another edition's image mapping")
	var original: Image=visuals.load_image(source.resource)
	check(original!=null,"Frame original pixels are missing")
	if original!=null:
		var crop: Image=original.get_region(Rect2i(source.source_rect))
		var actual: Image=frame.quarters[0].texture.get_image()
		check(actual.get_size()==crop.get_size() and actual.get_data()==crop.get_data(),"Frame changed the original atlas pixels")
	check(not frame.visible and frame.quarters.size()==4,"Frame appeared before ordinary flight")
	for phone in [false,true]:
		frame.set_mobile_layout(phone)
		for viewport_size in [Vector2(801,601),Vector2(1280,720),Vector2(99,71)]:
			frame.size=viewport_size;frame.reflow()
			var center: Vector2=(viewport_size*0.5).floor()
			var extent: Vector2=source.quarter_size*(152.0/source.quarter_size.x)*(1.0 if phone else 0.5)
			check(frame.marker_radii().is_equal_approx(extent),"Marker ellipse differs from frame composition")
			var projection:=TargetProjection.new()
			check(projection.configure(bindings.flight_projection,Vector2i(viewport_size),frame.marker_radii()),projection.error)
			var projected:=projection.project(Transform3D.IDENTITY,Vector3(center.x+extent.x*4,center.y,bindings.flight_projection.near+1))
			check(not projected.has("error") and projected.ellipse_clamped and absf(projected.pixels.x-center.x-extent.x)<=1 and projected.pixels.y==int(center.y),"Offscreen marker does not meet its original frame ellipse")
			check(frame.quarters[0].get_rect().end.is_equal_approx(center) and frame.quarters[3].position.is_equal_approx(center),"Quarter edges do not meet at the integer viewport center")
			check(frame.quarters[1].position.is_equal_approx(center-Vector2(0,extent.y)) and frame.quarters[2].position.is_equal_approx(center-Vector2(extent.x,0)),"Frame transposed its source quadrants")
			for index in 4:
				var part: TextureRect=frame.quarters[index]
				check(part.size.is_equal_approx(extent) and part.flip_h==bool(index&1) and part.flip_v==bool(index&2),"Frame mirror or desktop/phone size differs from its source composition")
	frame.size=Vector2(801,601);frame.set_mobile_layout(false);frame.set_active(true)
	check(frame.visible and frame.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Prepared frame is hidden or intercepts flight input")
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var output:=OS.get_environment("GOF2_CAPTURE_DIR")
		if not output.is_empty():
			DirAccess.make_dir_recursive_absolute(output)
			check(root.get_texture().get_image().save_png(output.path_join("target-frame-"+library.manifest.profile.edition+".png"))==OK,"Frame capture failed")
	var id: String=visuals.base_content_id;visuals.base_content_id="bad"
	check(not frame.prepare(library,bindings,visuals) and not frame.visible and frame.quarters.is_empty() and frame.source().is_empty(),"Cross-edition pixels were accepted or retained an earlier frame")
	visuals.base_content_id=id
	var aliases: Dictionary=bindings.image_regions.duplicate(true)
	bindings.image_regions.records.append({"id":1223,"texture_id":10063 if not mac else 10062,"region":0})
	check(not frame.prepare(library,bindings,visuals),"Ambiguous frame alias was silently selected")
	bindings.image_regions=aliases
	var registrations: Array=bindings.records[source.texture_id]
	bindings.records[source.texture_id]=[]
	check(not frame.prepare(library,bindings,visuals),"Unregistered baseline pixels were accepted")
	bindings.records[source.texture_id]=registrations
	check(frame.prepare(library,bindings,visuals),frame.error)
	frame.set_active(true);frame.clear();frame.set_active(true)
	check(not frame.visible and not frame.prepared and frame.get_child_count()==0,"Clear retained stale frame artwork")
	frame.free()
	print(library.manifest.profile.edition,": original atlas, mirrored geometry, responsive sizing and safe reset verified")

func check(condition: bool,message: String) -> void:
	if not condition:failures+=1;push_error(message)
