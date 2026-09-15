extends SceneTree
## Original Terran freighter assembly, detail and collision component checks.
## The lit inspection scene is a fixture, not Alioth flight lighting.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Rules=preload("res://src/content/alioth_attack_definitions.gd")
const Geometry=preload("res://src/presentation/ship_geometry.gd")
const Detail=preload("res://src/presentation/ship_detail.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Contact=preload("res://src/simulation/ordinary_hit_geometry.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):await verify(args[i],args[i+1],args[i+2])
	print("Alioth freighter geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String,visual_path: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(visual_path,library.manifest):check(false,library.error+bindings.error+visuals.error);return
	if not Rules.available(bindings):
		var geometry:=Geometry.new()
		check(not geometry.build_alioth_freighter(library,visuals,bindings) and geometry.get_child_count()==0,"Legacy content enabled the Alioth freighter")
		geometry.free();return
	var data: Dictionary=bindings.mido_travel.alioth_attack
	var boxes: Array=data.population.freighter_combat.boxes.map(func(box):return {"offset":point(box.offset),"half_extents":point(box.half_extents)})
	var contact:=Contact.new();var origin:=Vector3(0,0,170000)
	for sample in [[Vector3(0,-73,123),0],[Vector3(1600,-280,-4257),1],[Vector3(2000,-770,-4279),2]]:
		var hit:=contact.box_geometry(origin+sample[0],origin,boxes)
		check(hit.get("hit",false) and hit.get("box_index")==sample[1],"Terran freighter lost an original collision region")
	for sample in [Vector3(1500,-73,123),Vector3(1501,-73,123),Vector3(0,1357,123),Vector3(2610,-770,-4279),Vector3(0,0,5500)]:
		check(not contact.box_geometry(origin+sample,origin,boxes).get("hit",true),"Freighter included a strict surface or empty space")
	var detail:=Detail.new()
	check(detail.configure_alioth_freighter(data,bindings.ship_lod),detail.error)
	for sample in [[0.0,0],[625000000.0,0],[625000064.0,1],[2025000000.0,1],[2025000064.0,2],[90000000000.0,2]]:
		check(detail.select(sample[0],1.0)=={"visible":true,"level":sample[1]},"Terran freighter detail threshold or maximum distance changed")
	var shared:=Models.new();var paths:=[]
	for id in [17065,17066,17067,17070,17074,17069]:paths.append(bindings.resolve(id,"mesh"))
	if not shared.prepare(paths,library,visuals,bindings,"high",true):check(false,shared.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=10;camera.far=100000
	camera.look_at_from_position(Vector3(11000,7000,-13500),Vector3.ZERO)
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	viewport.add_child(environment)
	var ship:=Geometry.new();viewport.add_child(ship)
	if not ship.build_alioth_freighter(library,visuals,bindings,"high",shared):check(false,ship.error);viewport.free();return
	check(ship.levels.size()==3 and ship.get_meta("source_ship_id")==15,"Alioth freighter assembly has the wrong source ship")
	for i in 3:
		var body: Node3D=ship.levels[i]
		check(body.get_meta("source_resource_id")==17065+i and body.scale==Vector3.ONE,"Terran freighter replaced the original body or scale")
		var parts: Array=body.get_children().filter(func(node):return node.has_meta("source_resource_id"))
		check(parts.map(func(node):return node.get_meta("source_resource_id"))==([17070,17074,17069] if i==0 else [17070]),"Terran freighter lost its original light/engine children")
		check(ship.apply_selection({"visible":true,"level":i}) and ship.levels.filter(func(node):return node.visible).size()==1,ship.error)
		if DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image()
			var foreground:=0;var background:=image.get_pixel(0,0)
			for y in range(0,image.get_height(),3):
				for x in range(0,image.get_width(),3):
					var pixel:=image.get_pixel(x,y)
					if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
			check(foreground>100,"Original Terran freighter failed to render")
			var captures:=OS.get_environment("GOF2_ALIOTH_GEOMETRY_CAPTURES")
			if not captures.is_empty():
				DirAccess.make_dir_recursive_absolute(captures)
				check(image.save_png(captures.path_join("alioth-freighter-lod-%d.png"%i))==OK,"Terran freighter capture failed")
	check(ship.apply_selection({"visible":false,"level":-1}) and ship.levels.all(func(node):return not node.visible),"Hidden freighter retained floating children")
	viewport.free();shared.clear()

func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
