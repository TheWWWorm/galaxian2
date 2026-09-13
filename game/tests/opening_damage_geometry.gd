extends SceneTree
const Geometry=preload("res://src/presentation/opening_damage_geometry.gd")
const Particles=preload("res://src/simulation/opening_damage_particles.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Materials=preload("res://src/presentation/material_library.gd")
var failures:=0
var checks:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	verify_square()
	var args:=OS.get_cmdline_user_args()
	for index in range(0,args.size(),3):verify_source(args[index],args[index+1],args[index+2])
	print("Opening damage geometry: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func verify_square() -> void:
	var appearance:={"size":5,"uv_rect":Vector4(0.5,0.25,0.25,0.5),"color":Color(0.8,0.7,0.6,0.123456)}
	var quad:=Geometry.sprite(Vector3(10,20,-30),appearance)
	check(quad.vertices==PackedVector3Array([Vector3(8,18,-30),Vector3(12,18,-30),Vector3(12,22,-30),Vector3(8,22,-30)]),"Odd source size did not use arithmetic half-size")
	check(quad.uvs==PackedVector2Array([Vector2(0.5,0.25),Vector2(0.25,0.25),Vector2(0.25,0.5),Vector2(0.5,0.5)]),"Sprite UVs were subjected to the mesh-loader row flip")
	check(quad.colors[3]==PackedFloat32Array([0.123456])[0],"Source alpha was quantized to a vertex byte")
	appearance["size"]=-3
	check(Geometry.sprite(Vector3.ZERO,appearance).vertices[0]==Vector3(2,2,0),"Negative odd source size used truncating division")

func verify_source(content: String,pack: String,textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(textures,library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var combat:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actors":[]}
	for id in 3:combat.actors.append({"actor_id":id,"pose":Transform3D.IDENTITY,"actor_mode":int(bindings.opening_actors.npc_initialization.holding.actor_mode),"max_hull":100,"vitals":{"hull":100}})
	var group:=Particles.new();var geometry:=Geometry.new();root.add_child(geometry)
	if bindings.damage_particles.get("owners",{}).is_empty():
		check(not group.configure(bindings,combat,42),"Legacy geometry fabricated an emitter owner")
		check(not geometry.build(group,library,visuals,bindings) and geometry.get_child_count()==0,"Unavailable particle owner retained surfaces")
		geometry.free();return
	check(group.configure(bindings,combat,42),group.error)
	if not geometry.build(group,library,visuals,bindings):check(false,geometry.error);geometry.free();return
	check(geometry.items.size()==8,"Opening omitted a source smoke/fire registration")
	for item in geometry.items:
		var smoke: bool=item.kind=="smoke"
		check(item.node.get_meta("source_material_id")==int(20101 if smoke else 27250),"Wrong per-profile sprite material")
		check(item.node.get_meta("source_texture_id")==int(11602 if smoke else 11599),"Wrong per-profile sprite texture")
		check(item.node.material_override.shader==Materials.SHADERS[1 if smoke else 2],"Smoke/fire used the wrong alpha/additive blend family")
	var camera_pose:=Transform3D(Basis(Vector3.UP,0.3),Vector3(40,80,100))
	var empty:=geometry.prepare_world(group,world(group),camera_pose)
	check(not empty.is_empty() and empty.counts==[0,0,0,0,0,0,0,0],"Fresh unused particle slots were drawn")
	geometry.commit_world(empty)
	var cue:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"frame":{"ship_restore":true}}
	check(group.apply_controller(cue) and group.advance(Transform3D.IDENTITY,1) and group.advance(Transform3D.IDENTITY,100),group.error)
	var retained: Dictionary=group.snapshot()
	var prepared:=geometry.prepare_world(group,world(group),camera_pose)
	check(not prepared.is_empty() and prepared.counts==[1,0,0,0,1,0,0,0],"Player births were not batched into both sprite families")
	check(group.snapshot()==retained,"Sprite preparation changed simulation or random streams")
	geometry.commit_world(prepared)
	check(geometry.global_transform==camera_pose,"Sprites did not retain the current camera-space basis")
	for i in [0,4]:
		var mesh: ArrayMesh=geometry.items[i].node.mesh
		check(mesh.surface_get_array_len(0)==4 and mesh.surface_get_array_index_len(0)==6,"Source square did not produce one native quad")
	check(not geometry.prepare_world(group,world(group),camera_pose).is_empty() and group.snapshot()==retained,"Repeated presentation consumed a frame")
	var alien:=Particles.new();check(alien.configure(bindings,combat,42),alien.error)
	check(geometry.prepare_world(alien,world(alien),camera_pose).is_empty(),"Same-pack geometry accepted another session owner")
	var before: Dictionary=geometry.frame
	var id: int=geometry.items[-1].node.get_meta("source_material_id")
	geometry.items[-1].node.set_meta("source_material_id",-1)
	check(geometry.prepare_world(group,world(group),camera_pose).is_empty() and geometry.frame==before,"Late surface rejection partially committed sprites")
	geometry.items[-1].node.set_meta("source_material_id",id)
	geometry.free()

func world(group: RefCounted) -> Dictionary:
	var state: Dictionary=group.snapshot()
	return {"base_content_id":state.base_content_id,"binding_id":state.binding_id,"elapsed_ms":state.elapsed_ms,"damage_particles":state}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
