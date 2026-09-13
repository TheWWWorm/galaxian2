extends SceneTree
const Response = preload("res://src/presentation/surface_response.gd")
const Materials = preload("res://src/presentation/material_library.gd")
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var plane: MeshInstance3D
var cube: Cubemap
var response := Response.new()
var calibration: ShaderMaterial
var surface := {"ambient_rgb":[1,1,1],"diffuse_rgb":[1,1,1],"specular_rgb":[1,1,1],"specular_power":2}
var lighting := {"global_ambient":Vector3(0.1,0.1,0.1),"rim_color":Vector3(0.2,0.4,0.6),"lights":[
	{"direction_to_light":Vector3.BACK,"ambient":Vector3.ZERO,"diffuse":Vector3(0.2,0,0),"specular":Vector3(0,0,0.4)},
	{"direction_to_light":Vector3.BACK,"ambient":Vector3.ZERO,"diffuse":Vector3(0,0.3,0),"specular":Vector3(0.2,0,0)}]}

func _initialize() -> void:
	create_timer(60).timeout.connect(func():push_error("Surface response checks timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var faces: Array[Image] = []
	for color in [Color(0.1,0.1,0.1),Color(0.3,0.6,0.9),Color(0.2,0.2,0.2),Color(0.4,0.4,0.4),Color(0.7,0.2,0.1),Color(0.1,0.2,0.3)]:
		var image := Image.create(4,4,false,Image.FORMAT_RGBAF);image.fill(color);faces.append(image)
	cube=Cubemap.new();check(cube.create_from_images(faces)==OK,"Fixture cube creation failed")
	var pigment := texture(Color(0.2,0.4,0.6,1))
	var normal := texture(Color(0.5,0.5,1,0))
	check(response.build(surface,lighting,pigment,normal,cube,0,0,"two_light_cube"),response.error)
	for variant in ["", "reduced", "bump_only"]:
		check(not response.build(surface,lighting,pigment,normal,cube,0,0,variant) and response.material==null,"Unknown variant reused material")
	for bias in [null,NAN,INF,17,"0"]:
		check(not response.build(surface,lighting,pigment,normal,cube,bias,0,"two_light_cube") and response.material==null,"Invalid bias reused material")
	check(not response.build(surface,lighting,null,normal,cube,0,0,"two_light_cube"),"Missing texture accepted")
	var original := Materials.create(28,pigment,normal,false)
	original.set_shader_parameter("uv_scale",Vector2(2,3));original.set_shader_parameter("uv_offset",Vector2(0.1,0.2));original.set_shader_parameter("uv_angle",0.7)
	check(response.from_imported(original,surface,lighting,cube,-1,0,"two_light_cube"),response.error)
	for field in ["uv_scale","uv_offset","uv_angle","diffuse_texture","normal_specular_texture"]:
		check(response.material.get_shader_parameter(field)==original.get_shader_parameter(field),"Imported material conversion lost: "+field)
	check(original.shader==Response.ImportedShader,"Conversion mutated the original material")
	check(not response.from_imported(Materials.create(0,pigment,null,false),surface,lighting,cube,0,0,"two_light_cube") and response.material==null,"Unsupported material family retained conversion")
	if DisplayServer.get_name()!="headless":
		var reference_shader := Shader.new()
		reference_shader.code="shader_type spatial; render_mode unshaded; uniform vec3 value; void fragment(){ALBEDO=value;}"
		calibration=ShaderMaterial.new();calibration.shader=reference_shader
		viewport=SubViewport.new();viewport.size=Vector2i(65,65);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2;camera.current=true;viewport.add_child(camera)
		plane=MeshInstance3D.new();plane.mesh=QuadMesh.new();plane.mesh.size=Vector2(2,2);plane.position=Vector3(0,0,-4);viewport.add_child(plane)
		# Odd viewport puts the sampled pixel exactly on the camera axis. Each
		# expected RGB below is an independently calculated material contribution.
		# Compare through a constant-color reference to isolate Godot's own display
		# transfer (Compatibility uses approximate sRGB conversions).
		await probe(pigment,texture(Color(0.5,0.5,1,0)),Vector3(0.08,0.20,0.12),"raw diffuse and two ambient terms")
		await probe(pigment,texture(Color(0.5,0.5,1,0.5)),Vector3(0.205,0.25,0.395),"two specular lights and negative-Z cube")
		var vertex_half_squared := (1.0+4.0/sqrt(18.0))/2.0
		var tight_highlight := pow(vertex_half_squared,10)
		surface.specular_power=20
		await probe(pigment,texture(Color(0.5,0.5,1,0.5)),Vector3(0.105+0.1*tight_highlight,0.25,0.195+0.2*tight_highlight),"vertex half vectors remain interpolated")
		surface.specular_power=2
		await probe(pigment,texture(Color(0.5,0.5,0.75,0.5)),Vector3(0.26,0.19,0.195),"decoded normals retain their magnitude")
		await probe(pigment,texture(Color(0.5,0.5,0.5,0.5)),Vector3(0.79,0.38,0.37),"rim and positive-Z reflection")
		var rotation := Basis(Vector3.UP,PI/2)
		camera.basis=rotation;plane.transform=Transform3D(rotation,rotation*Vector3(0,0,-4))
		for light in lighting.lights:light.direction_to_light=rotation*Vector3.BACK
		await probe(pigment,texture(Color(0.5,0.5,1,0.5)),Vector3(0.255,0.35,0.545),"model rotation changes cube face")
		viewport.free()
	else:print("Surface response: GPU checks skipped in headless mode")
	print("Surface response checks: %d failures" % failures)
	quit(1 if failures else 0)

func probe(pigment: Texture2D, normal: Texture2D, expected: Vector3, label: String) -> void:
	check(response.build(surface,lighting,pigment,normal,cube,0,0,"two_light_cube"),response.error)
	if response.material==null:return
	plane.material_override=response.material
	var actual := await sample()
	calibration.set_shader_parameter("value",expected);plane.material_override=calibration
	var reference := await sample()
	check(actual.distance_to(reference)<0.012,"%s: calibrated expected %s, got %s" % [label,reference,actual])
	print(label,": ",actual," reference: ",reference)

func sample() -> Vector3:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var pixel := viewport.get_texture().get_image().get_pixel(32,32)
	return Vector3(pixel.r,pixel.g,pixel.b)

func texture(color: Color) -> Texture2D:
	var image := Image.create(4,4,false,Image.FORMAT_RGBAF);image.fill(color)
	return ImageTexture.create_from_image(image)

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
