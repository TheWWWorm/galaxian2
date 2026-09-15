extends SceneTree
## Run with a graphics backend: verifies pixels, depth behavior and float colors.
const Model = preload("res://src/presentation/imported_model.gd")
const Materials = preload("res://src/presentation/material_library.gd")
var failures := 0
var viewport: SubViewport
var nodes: Array = []

func _initialize() -> void:
	# Bound GPU failures as well as assertion failures; a script error must not
	# leave a failed verification process running indefinitely.
	create_timer(30.0).timeout.connect(func(): push_error("Material render checks timed out"); quit(1))
	call_deferred("run_checks")

func surface(colors := PackedColorArray()) -> Dictionary:
	return {"positions": PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(0, 1, 0)]),
		"indices": PackedInt32Array([0, 1, 2]), "normals": PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]),
		"uvs": PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2(0.5, 1)]), "colors": colors,
		"tracks": {}, "pivot": Vector3.ZERO}

func quad(color: Color, mode: int, z := 0.0, priority := 0, colors := PackedColorArray()) -> Node3D:
	var texture := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	texture.fill(color)
	var model := Model.new()
	viewport.add_child(model)
	model.build({"surfaces": [surface(colors)]}, texture, null, mode)
	model.position.z = z
	model.materials[0].render_priority = priority
	nodes.append(model)
	return model

func pixel() -> Color:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_pixel(32, 32)

func clear_models() -> void:
	for node in nodes: node.free()
	nodes.clear()

func run_checks() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Material render checks require a graphics backend")
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 2.0
	camera.current = true
	viewport.add_child(camera)
	quad(Color(0, 0, 0.25, 1), 0, -0.1)
	var background := await pixel()
	var foreground = quad(Color(0.25, 0, 0, 0), 2)
	var additive := await pixel()
	check(additive.r > background.r + 0.15 and absf(additive.b - background.b) < 0.04, "ONE/ONE additive color or texture-alpha behavior failed")
	foreground.hide()
	var alpha = quad(Color(1, 0, 0, 0.25), 1)
	var mixed := await pixel()
	check(mixed.r > 0.15 and mixed.r < 0.4 and mixed.b < background.b - 0.02, "Source-alpha blend failed")
	alpha.materials[0].render_priority = -1
	quad(Color(0, 1, 0, 0.5), 1, -0.05, 1)
	var behind := await pixel()
	check(behind.g > 0.3, "Transparent layer incorrectly wrote depth and blocked a later layer")
	clear_models()
	var colors := PackedColorArray([Color(1.125, 0.123456, 0.5, 0.75), Color.WHITE, Color.WHITE])
	var colored = quad(Color.WHITE, 0, 0, 0, colors)
	var stored: PackedFloat32Array = colored.instances[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	check(stored.size() == 12 and absf(stored[0] - 1.125) < 0.000001 and absf(stored[1] - 0.123456) < 0.000001, "Source float colors were clamped or quantized")
	var color_pixel := await pixel()
	check(color_pixel.r > color_pixel.g, "Float vertex colors did not reach the shader")
	clear_models()
	var light := DirectionalLight3D.new()
	light.light_specular = 0.0
	viewport.add_child(light)
	quad(Color(1, 0, 0, 1), 28)
	var lit_pixel := await pixel()
	check(lit_pixel.r > 0.1 and lit_pixel.g < 0.05, "Diffuse/normal material failed to render: %s" % lit_pixel)
	check(Materials.create(999, null, null, false) == null, "Unsupported material mode accepted")
	clear_models()
	await check_engine_blending()
	await check_map_lighting()
	await check_visitor_cutouts()
	await check_source_uvs()
	print("Material render checks: %d failures; pixels %s %s %s %s" % [failures, background, additive, mixed, behind])
	clear_models()
	quit(1 if failures else 0)

func check_engine_blending() -> void:
	quad(Color(0, 0, 0.25, 1), 0, -0.1)
	var background := await pixel()
	var glow := quad(Color(0.25, 0, 0, 0), 3)
	var front := await pixel()
	check(front.r > background.r + 0.15 and absf(front.b - background.b) < 0.04, "Engine sprites must add RGB independently of texture alpha")
	glow.rotation.y = PI
	check((await pixel()).is_equal_approx(front), "Engine sprites incorrectly culled their reverse face")
	var rear := quad(Color(0, 0.25, 0, 0), 3, -0.05, 1)
	check((await pixel()).g > 0.15, "Engine sprites incorrectly wrote depth before a later sprite")
	var opaque := quad(Color.BLUE, 0, 0.05)
	check((await pixel()).is_equal_approx(Color.BLUE), "Engine sprites ignored the opaque depth buffer")
	opaque.hide();rear.hide();glow.hide()
	var ordinary := quad(Color(0.25, 0, 0, 0), 2)
	ordinary.rotation.y = PI
	check((await pixel()).is_equal_approx(background), "Ordinary additive surfaces lost their back-face culling")
	clear_models()

func check_map_lighting() -> void:
	quad(Color.BLUE, 0, -0.1)
	# Map type 6 is opaque even when its texture has zero alpha. Its light is
	# explicitly configured by the map, independently of Godot scene lights.
	var planet := quad(Color(1, 0, 0, 0), 6)
	var material: ShaderMaterial = planet.materials[0]
	material.set_shader_parameter("ambient_color", Vector3.ONE * 0.2)
	material.set_shader_parameter("diffuse_color", Vector3.ONE * 0.6)
	material.set_shader_parameter("light_position", Vector3(0, 0, -10))
	var shadow := await pixel()
	check(shadow.r > 0.15 and shadow.r < 0.25 and shadow.b < 0.03, "Map ambient lighting or opaque texture alpha failed: %s" % shadow)
	material.set_shader_parameter("light_position", Vector3(0, 0, 10))
	var facing := await pixel()
	check(facing.r > shadow.r + 0.5 and facing.r < 0.85, "Map surface normal or point-light direction failed: %s" % facing)
	quad(Color.GREEN, 1, -0.05, 1)
	check((await pixel()).is_equal_approx(facing), "Map planet failed to write depth before the alpha pass")
	planet.rotation.y = PI
	check((await pixel()).g > 0.9, "Map planet back-face culling failed")
	clear_models()

func check_visitor_cutouts() -> void:
	quad(Color.BLUE,0,-0.1)
	var cutout:=quad(Color(1,0,0,0.49),10)
	check((await pixel()).is_equal_approx(Color.BLUE),"Transparent visitor texels blocked the room")
	cutout.hide()
	var body:=quad(Color(1,0,0,0.51),10)
	check((await pixel()).is_equal_approx(Color.RED),"Visitor cutouts blended instead of retaining the original RGB")
	quad(Color.GREEN,1,-0.05,1)
	check((await pixel()).is_equal_approx(Color.RED),"Visitor body failed to write depth")
	body.rotation.y=PI
	check((await pixel()).g>0.9,"Visitor cutouts lost their original back-face culling")
	body.rotation.y=0
	body.materials[0].set_shader_parameter("surface_tint",Vector4.ZERO)
	check((await pixel()).g>0.9,"Source zero-opacity animation covered the room")
	clear_models()

func check_source_uvs() -> void:
	var texture := Image.create(4,4,false,Image.FORMAT_RGBA8)
	for y in 4:
		for x in 4:texture.set_pixel(x,y,Color.RED if y<2 else Color.BLUE)
	var input := surface()
	input.uvs=PackedVector2Array([Vector2(0.1,0.1),Vector2(0.9,0.1),Vector2(0.5,0.4)])
	var original_uvs: PackedVector2Array=input.uvs.duplicate()
	for version in [2,3,4,5]:
		for mode in [0,1,2,3,6,10,18,28]:
			var model := Model.new();viewport.add_child(model)
			model.build({"version":version,"surfaces":[input]},texture,null,mode)
			if mode==6:
				model.materials[0].set_shader_parameter("ambient_color",Vector3.ONE)
				model.materials[0].set_shader_parameter("diffuse_color",Vector3.ZERO)
			var sample := await pixel()
			check(sample.b>sample.r+0.2 if version>=4 else sample.r>sample.b+0.2,"Wrong default UV convention for V%d material %d: %s" % [version,mode,sample])
			check(input.uvs==original_uvs,"Rendering mutated raw decoded UV data")
			if version==4 and mode==0:
				var copy := Model.new();copy.copy_from(model);viewport.add_child(copy);model.hide()
				check((await pixel()).is_equal_approx(sample),"Model copy lost its prepared UV convention")
				copy.free()
			model.free()
	var prepared := Model.new();var raw := Model.new()
	prepared.build({"version":4,"surfaces":[input]},texture,null,0)
	raw.build({"version":4,"surfaces":[input]},texture,null,0,{},false)
	var prepared_tangents: PackedFloat32Array=prepared.instances[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
	var raw_tangents: PackedFloat32Array=raw.instances[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
	for vertex in 3:
		check(prepared_tangents[vertex*4+3]==-raw_tangents[vertex*4+3],"V conversion was applied after tangent generation")
	viewport.add_child(raw)
	var raw_pixel := await pixel()
	check(raw_pixel.r>raw_pixel.b+0.2,"Explicit raw UV inspection was not preserved")
	prepared.free();raw.free()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
