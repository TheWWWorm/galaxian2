extends RefCounted
## Fit one already isolated source model and capture its actual GPU output.
static func arguments() -> PackedStringArray:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	return args

static func capture(tree: SceneTree, model: Node3D, path: String) -> Dictionary:
	var bounds:=AABB();var first:=true
	for mesh in model.instances:
		var extent: AABB=mesh.transform*mesh.mesh.get_aabb()
		bounds=extent if first else bounds.merge(extent);first=false
	var aspect:=float(tree.root.size.x)/tree.root.size.y
	var size:=maxf(bounds.size.y,bounds.size.x/aspect)*1.25
	if first or not is_finite(size) or size<=0:return {"error":"Model has no finite visible extent"}
	var camera:=Camera3D.new();tree.root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=100000;camera.current=true
	camera.position=Vector3(bounds.get_center().x,bounds.get_center().y,bounds.end.z+bounds.size.length()+1000)
	camera.size=size
	var background:=WorldEnvironment.new();background.environment=Environment.new()
	background.environment.background_mode=Environment.BG_COLOR;background.environment.background_color=Color.BLACK
	tree.root.add_child(background)
	await tree.process_frame;await tree.process_frame;await RenderingServer.frame_post_draw
	var pixels:=tree.root.get_texture().get_image()
	var saved:=pixels.save_png(path)
	var lit:=0
	for y in pixels.get_height():
		for x in pixels.get_width():
			var pixel:=pixels.get_pixel(x,y)
			if maxf(pixel.r,maxf(pixel.g,pixel.b))>0.03:lit+=1
	camera.free();background.free()
	return {"saved":saved==OK,"lit_pixels":lit,"bounds":bounds}
