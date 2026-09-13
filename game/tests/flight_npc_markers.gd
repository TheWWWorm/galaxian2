extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Markers=preload("res://src/presentation/flight_npc_markers.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size()-2,3):await verify(args[i],args[i+1],args[i+2])
	print("Flight NPC marker checks: %d failures"%failures)
	quit(1 if failures else 0)
func verify(content: String, pack: String, pixels: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(pixels,library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var hud:=Markers.new();root.add_child(hud);hud.size=Vector2(1120,720)
	if bindings.opening_staging.get("npc_scanner",{}).is_empty():
		check(not hud.prepare(library,bindings,visuals),"Legacy pack acquired scanner art");hud.free();return
	check(hud.prepare(library,bindings,visuals),hud.error)
	var source:=hud.source();var original: Image=visuals.load_image(source.resource)
	for row in source.regions:
		check(hud._textures[row.image_id].get_image().get_data()==original.get_region(row.rect).get_data(),"Marker altered original pixels")
	var strip_image: Image=visuals.load_image(source.animation.resource)
	for i in 25:
		var rect:=Rect2i(source.animation.rect.position+Vector2i(i*40,0),Vector2i(40,40))
		check(hud._frames[i].get_image().get_data()==strip_image.get_region(rect).get_data(),"Scanner frame lost original crop")
	var sample:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"visible":true,"markers":[],"animation_frame":12,"aim_pixels":Vector2i(560,450)}
	for near in [true,false]:
		for hostile in [true,false]:
			for selected in [false,true]:
				sample.markers.append({"pixels":Vector2i(320+int(hostile)*260+int(selected)*130,200 if near else 330),"near":near,"selected":selected,"hostile":hostile,"hull_percent":58})
	for mobile in [false,true]:
		hud.set_mobile_layout(mobile);check(hud.present(sample),hud.error)
		check(hud.visible and hud.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Markers hidden or intercept flight input")
		if DisplayServer.get_name()!="headless":
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var output:=OS.get_environment("GOF2_CAPTURE_DIR")
			if not output.is_empty():check(root.get_texture().get_image().save_png(output.path_join("npc-markers-%s-%s.png"%[library.manifest.profile.edition,"phone" if mobile else "desktop"]))==OK,"Marker capture failed")
	var before: Dictionary=hud._sample.duplicate(true);var bad:=sample.duplicate(true);bad.binding_id="0".repeat(64)
	check(not hud.present(bad) and hud._sample==before,"Foreign sample replaced marker art")
	bad=sample.duplicate(true);bad.animation_frame=25
	check(not hud.present(bad) and hud._sample==before,"Out-of-range animation replaced marker art")
	check(hud.present({}) and not hud.visible,"Missing capability retained markers")
	var records: Array=bindings.records[10062];bindings.records[10062]=[]
	check(not hud.prepare(library,bindings,visuals) and not hud.visible and not hud.prepared,"Unregistered scanner atlas retained markers")
	bindings.records[10062]=records
	hud.free()
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
