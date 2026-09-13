extends SceneTree
const Cube = preload("res://src/content/cube_texture.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Cubemap checks timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var reader := Cube.new()
	var raw := fixture()
	var faces := reader.decode_faces(raw)
	check(faces.size()==6,reader.error)
	if faces.size()!=6: quit(1); return
	# Independently specified expected source row for each native axis.
	var rows := [3,1,0,5,2,4]
	for face in 6:
		check(faces[face].get_size()==Vector2i(8,8) and not faces[face].has_mipmaps(),"Cube face dimensions/mips changed")
		for y in 8:
			for x in 8: check(close(faces[face].get_pixel(x,y),pixel(rows[face],x,y)),"Cube face rows were rotated/flipped")
	for bad in ["magic","ordinary","unverified_format","zero","strip","large","region_count","cross","fonts","extra"]:
		var broken := raw.duplicate()
		match bad:
			"magic": broken[0]=0
			"ordinary": broken[8]=1
			"unverified_format": broken[8]=166
			"zero": broken.encode_u16(9,0)
			"strip": broken.encode_u16(11,47)
			"large": broken.encode_u16(9,8192);broken.encode_u16(11,49152)
			"region_count": broken.encode_u16(13,65535)
			"cross": broken.encode_u16(15,33)
			"fonts": broken.encode_u16(broken.size()-2,1)
			"extra": broken.append(0)
		check(reader.decode_faces(broken).is_empty() and not reader.error.is_empty(),"Malformed cube accepted: "+bad)
	for length in raw.size():check(reader.decode_faces(raw.slice(0,length)).is_empty(),"Truncated cube accepted")
	check(reader.decode_faces(raw).size()==6 and reader.error.is_empty(),"Failed load poisoned later decoding")
	check(reader.load(null,"anything")==null,"Missing content base accepted")
	verify_provenance(raw)
	if DisplayServer.get_name()!="headless": await verify_gpu(reader.create(raw),faces)
	for path in OS.get_cmdline_user_args(): await verify_source(path)
	print("Cubemap checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_provenance(raw: PackedByteArray) -> void:
	var directory := "user://tests/cube-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory.path_join("resources"))
	var name := "resources/fixture.aei";var path := directory.path_join(name)
	var file := FileAccess.open(path,FileAccess.WRITE);file.store_buffer(raw);file.close()
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw)
	var library := Library.new();library.root=directory
	library.manifest={"content_id":"a".repeat(64),"files":{name:{"kind":"texture","bytes":raw.size(),"sha256":hash.finish().hex_encode()}}}
	var reader := Cube.new()
	if DisplayServer.get_name()!="headless":check(reader.load(library,name)!=null,reader.error)
	library.manifest.files[name].kind="mesh"
	check(reader.load(library,name)==null,"Wrong resource kind accepted as cubemap")
	library.manifest.files[name].kind="texture"
	var altered := raw.duplicate();altered[30]^=1
	file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(altered);file.close()
	check(reader.load(library,name)==null and "checksum" in reader.error,"Changed source pixels accepted")
	DirAccess.remove_absolute(path)
	check(reader.load(library,name)==null,"Missing source pixels accepted")
	DirAccess.remove_absolute(directory.path_join("resources"));DirAccess.remove_absolute(directory)

func verify_source(path: String) -> void:
	var library := Library.new();var reader := Cube.new()
	check(library.open(path),library.error)
	var supported := 0;var unsupported := 0
	for name in library.manifest.get("files",{}):
		if not name.ends_with(".aei"): continue
		var raw: PackedByteArray = library.read_resource(name,Cube.MAX_BYTES)
		if raw.size()<17 or raw[8]&128==0:continue
		var faces := reader.decode_faces(raw)
		if raw[8]!=129:
			check(faces.is_empty(),"Unverified original cube format accepted");unsupported+=1;continue
		check(faces.size()==6,reader.error)
		if faces.size()!=6:continue
		var side := raw.decode_u16(9);var start := 15+raw.decode_u16(13)*8
		var source_rows := [3,1,0,5,2,4]
		for index in 6:
			var at: int = start+source_rows[index]*side*side*4
			check(faces[index].get_data()==raw.slice(at,at+side*side*4),"Source cube pixels changed")
		if DisplayServer.get_name()!="headless":
			var cube := reader.load(library,name)
			check(cube!=null,reader.error)
			if cube!=null:
				await verify_rendered_faces(cube,faces)
		supported+=1
	check(supported>0,"No source cubes were exercised")
	print("Cubemaps ",library.manifest.profile.edition,": ",supported," supported; ",unsupported," unsupported formats")

func verify_rendered_faces(cube: Cubemap,faces: Array[Image]) -> void:
	# Direct Cubemap.get_layer_data() returned zeroes on the tested GL backend.
	# Sample every texel through the actual GPU sampler instead of relying on it.
	var side := faces[0].get_width()
	var viewport := SubViewport.new();viewport.size=Vector2i(side*6,side)
	viewport.disable_3d=true;viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var rect := ColorRect.new();rect.size=viewport.size;viewport.add_child(rect)
	var shader := Shader.new()
	shader.code="""shader_type canvas_item;
render_mode blend_disabled;
uniform samplerCube source_cube : filter_nearest;
void fragment() {
 float face=floor(UV.x*6.0);
 vec2 p=vec2(fract(UV.x*6.0),UV.y)*2.0-1.0;
 vec3 d;
 if (face<0.5) d=vec3(1.0,-p.y,-p.x);
 else if (face<1.5) d=vec3(-1.0,-p.y,p.x);
 else if (face<2.5) d=vec3(p.x,1.0,p.y);
 else if (face<3.5) d=vec3(p.x,-1.0,-p.y);
 else if (face<4.5) d=vec3(p.x,-p.y,1.0);
 else d=vec3(-p.x,-p.y,-1.0);
 COLOR=texture(source_cube,d);
}"""
	var material := ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("source_cube",cube);rect.material=material
	await process_frame;await process_frame
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	for face in 6:
		check(result.get_region(Rect2i(face*side,0,side,side)).get_data()==faces[face].get_data(),"GPU sampler changed original cube face texels")
	viewport.free()

func verify_gpu(cube: Cubemap,faces: Array[Image]) -> void:
	check(cube!=null,"Synthetic cube upload failed")
	if cube==null:return
	var viewport := SubViewport.new();viewport.size=Vector2i(16,16);viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var rect := ColorRect.new();rect.size=Vector2(16,16);viewport.add_child(rect)
	var shader := Shader.new()
	shader.code="shader_type canvas_item; uniform samplerCube source_cube : filter_nearest; uniform vec3 direction; void fragment() { COLOR=texture(source_cube,direction); }"
	var material := ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("source_cube",cube);rect.material=material
	# GL cube face coordinates: each pair is local horizontal/vertical direction.
	var centers := [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
	var horizontal := [Vector3.FORWARD,Vector3.BACK,Vector3.RIGHT,Vector3.RIGHT,Vector3.RIGHT,Vector3.LEFT]
	var vertical := [Vector3.DOWN,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD,Vector3.DOWN,Vector3.DOWN]
	for face in 6:
		for point in [Vector2i(4,4),Vector2i(1,1),Vector2i(6,1),Vector2i(1,6),Vector2i(6,6)]:
			var uv := (Vector2(point)+Vector2(0.5,0.5))/8.0*2.0-Vector2.ONE
			if point==Vector2i(4,4): uv=Vector2.ZERO
			material.set_shader_parameter("direction",centers[face]+horizontal[face]*uv.x+vertical[face]*uv.y)
			await process_frame;await process_frame
			var rendered := viewport.get_texture().get_image().get_pixel(8,8)
			check(close(rendered,faces[face].get_pixelv(point)),"GPU cubemap sampling selected wrong face/pixel: %d %s got %s" % [face,point,rendered])
	viewport.free()
	print("GPU cube sampling: six axes and 24 off-axis probes checked")

func fixture() -> PackedByteArray:
	var bytes := PackedByteArray();bytes.resize(25+8*48*4)
	bytes.set(0,65);bytes.set(1,69);bytes.set(2,105);bytes.set(3,109);bytes.set(4,97);bytes.set(5,103);bytes.set(6,101)
	bytes[8]=129;bytes.encode_u16(9,8);bytes.encode_u16(11,48);bytes.encode_u16(13,1)
	bytes.encode_u16(19,32);bytes.encode_u16(21,24)
	for face in 6:
		for y in 8:
			for x in 8:
				var at := 23+((face*8+y)*8+x)*4
				var color := pixel(face,x,y)
				bytes[at]=color.r8;bytes[at+1]=color.g8;bytes[at+2]=color.b8;bytes[at+3]=255
	return bytes

func pixel(face: int,x: int,y: int) -> Color:
	return Color8(20+face*35,16+x*29,20+y*27,255)

func close(a: Color,b: Color) -> bool:
	return abs(a.r-b.r)<0.012 and abs(a.g-b.g)<0.012 and abs(a.b-b.b)<0.012 and abs(a.a-b.a)<0.012

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1;push_error(message)
