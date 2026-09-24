extends SceneTree
## Component fixtures: original capital-ship geometry, collision and capture
## motion. These do not imply an earned convoy flight or Alioth arrival.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Rules=preload("res://src/content/convoy_ship_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Geometry=preload("res://src/presentation/ship_geometry.gd")
const Detail=preload("res://src/presentation/ship_detail.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Motion=preload("res://src/simulation/freighter_motion.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
const Contact=preload("res://src/simulation/ordinary_hit_geometry.gd")
var checks:=0
var failures:=0
var legacy_capture: RefCounted

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var captures:=""
	if args.size()%3==1:captures=args[args.size()-1];args.resize(args.size()-1)
	check(args.size()>0 and args.size()%3==0,"Expected content, bindings and visuals triples")
	for i in range(0,args.size()-2,3):await verify(args[i],args[i+1],args[i+2],captures)
	print("Convoy capital ship: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String,visual_path: String,captures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not visuals.open(visual_path,library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	if not Rules.available(bindings):
		var geometry:=Geometry.new();var motion:=Motion.new()
		check(not geometry.build_convoy(library,visuals,bindings) and geometry.get_child_count()==0,"Legacy data enabled an unverified capital ship")
		check(not motion.configure_convoy(bindings,6) and motion.snapshot().is_empty(),"Legacy data enabled convoy cruise")
		geometry.free()
		legacy_capture=Capture.new();check(legacy_capture.configure(bindings),legacy_capture.error)
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in Rules.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.provenance[key].offset+=1
		check(not Travel.validate(changed,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Moved capital-ship declaration accepted: "+key)
	var invalid: Dictionary=bindings.mido_travel.duplicate(true)
	invalid.convoy_ship.assembly.body_resource_ids[0]=17014
	check(not Travel.parameters(invalid),"Ordinary catalogue mesh replaced the source special factory")
	verify_motion(bindings)
	verify_collision(bindings)
	await verify_geometry(library,bindings,visuals,captures)

func radio_flags(bindings: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,
		"started":[false,false,false,false,false],"finished":[false,false,false,false,false]}

func verify_motion(bindings: RefCounted) -> void:
	var left:=Motion.new();var right:=Motion.new();var capture:=Capture.new()
	if not left.configure_convoy(bindings,5) or not right.configure_convoy(bindings,6):check(false,left.error+right.error);return
	check(true,"Both original capital ships configured")
	var left_origin:=Vector3(47000,5000,30000);var right_origin:=Vector3(31000,7000,37000)
	check(left.snapshot().body_pose.origin==left_origin and right.snapshot().body_pose.origin==right_origin,"Authored convoy placement changed")
	check(capture.configure(bindings),capture.error)
	var initial: RefCounted=capture.fork_for_frame()
	var radio:=radio_flags(bindings)
	var player:=Transform3D(Basis.IDENTITY,Vector3(40000,0,120000))
	for phase in 3:
		if phase==1:radio.started[1]=true
		if phase==2:radio.finished[1]=true
		check(capture.advance(100,radio,player,right.snapshot().body_pose),capture.error)
		for owner in [left,right]:
			check(owner.apply_capture(capture) and owner.update(100,true),owner.error)
		check(right.snapshot().body_pose.origin==right_origin and left.snapshot().body_pose.origin==left_origin,"Capital ships cruised before capture view")
	radio.started[2]=true;radio.finished[2]=true;radio.started[3]=true;radio.finished[3]=true
	check(capture.advance(100,radio,player,right.snapshot().body_pose),capture.error)
	for owner in [left,right]:check(owner.apply_capture(capture),owner.error)
	var prior: Dictionary=right.snapshot()
	var staged: RefCounted=right.fork_for_frame()
	check(staged.update(150,true) and right.snapshot()==prior,"Prospective cruise mutated the retained frame")
	check(staged.snapshot().body_pose.origin==right_origin+Vector3(0,0,150),"Model scale doubled source cruise speed")
	check(staged.snapshot().source_position==Vector3i(31000,7000,37150),"Cruise lost its integer source position")
	check(left.update(150,true) and left.snapshot().body_pose.origin==left_origin,"Capture started the wrong capital ship")
	prior=staged.snapshot()
	check(staged.update(150,false) and staged.snapshot()==prior,"World pause advanced convoy motion")
	check(not staged.update(751 if not bindings.fast_forward.is_empty() else 151,true) and staged.snapshot()==prior,"Invalid frame partially moved the capital ship")
	check(not staged.apply_capture(initial) and staged.snapshot()==prior,"Older capture state reset cruise")
	if legacy_capture!=null:check(not staged.apply_capture(legacy_capture) and staged.snapshot()==prior,"Foreign content controlled convoy motion")
	check(not staged.apply_capture(Capture.new()) and staged.snapshot()==prior,"Unconfigured capture controlled convoy motion")
	var contact:=Contact.new()
	var bow: Vector3=staged.snapshot().body_pose.origin+Vector3(0,-2240,21608)
	check(contact.box_geometry(bow,staged.snapshot().body_pose.origin,Rules.boxes(bindings)).get("box_index")==0,"Moving capital ship lost its translated collision volumes")
	for id in [-1,0,4,7,5.5,true]:
		check(not staged.configure_convoy(bindings,id) and staged.snapshot().is_empty(),"An unauthored actor acquired capital-ship motion")

func verify_collision(bindings: RefCounted) -> void:
	var contact:=Contact.new();var boxes:=Rules.boxes(bindings)
	var center:=Vector3(31000,7000,37000)
	check(boxes.size()==11,"Capital ship lacks its eleven source volumes")
	# Independent samples at the narrow bow, both stern wings and outside the
	# hull distinguish this shape from an ambient freighter or coarse cube.
	for sample in [[Vector3(0,-2240,21608),0],[Vector3(7000,2004,-15852),9],[Vector3(-7000,-2610,-15852),10]]:
		var hit:=contact.box_geometry(center+sample[0],center,boxes)
		check(hit.get("hit",false) and hit.get("box_index")==sample[1],"Source capital-ship contact changed")
	for sample in [Vector3(380,-2240,21608),Vector3(381,-2240,21608),Vector3(0,-2240,25000),Vector3(9000,2004,-15852)]:
		check(not contact.box_geometry(center+sample,center,boxes).get("hit",true),"Capital ship included its strict surface or empty space")
	boxes[0].offset=Vector3.ZERO
	check(Rules.boxes(bindings)[0].offset==Vector3(0,-2240,21608),"A collision consumer mutated imported declarations")

func verify_geometry(library: RefCounted,bindings: RefCounted,visuals: RefCounted,captures: String) -> void:
	var shared:=Models.new();var paths:=[]
	for id in [14311,14312,14313,14315,14316]:paths.append(bindings.resolve(id,"mesh"))
	if not shared.prepare(paths,library,visuals,bindings,"high",true):check(false,shared.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=10;camera.far=250000
	camera.look_at_from_position(Vector3(31000,21000,-45000),Vector3(0,0,-1000))
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.65,-0.6,0);viewport.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	viewport.add_child(environment)
	var ship:=Geometry.new();viewport.add_child(ship)
	if not ship.build_convoy(library,visuals,bindings,"high",shared):check(false,ship.error);viewport.free();return
	check(ship.levels.size()==3 and ship.get_meta("source_ship_id")==14,"Convoy uses the wrong assembly or detail count")
	var detail:=Detail.new();check(detail.configure_convoy(bindings.mido_travel.convoy_ship,bindings.ship_lod),detail.error)
	for sample in [[0.0,0],[1224999936.0,0],[1225000192.0,1],[3600000000.0,1],[3600000256.0,2],[90000000000.0,2]]:
		check(detail.select(sample[0],1.0)=={"visible":true,"level":sample[1]},"Capital-ship detail thresholds or distance cull changed")
	for i in 3:
		var body: Node3D=ship.levels[i]
		check(body.get_meta("source_resource_id")==14311+i and body.scale==Vector3(2,2,2),"Special hull identity or source scale changed")
		var parts: Array=body.get_children().filter(func(node):return node.has_meta("source_resource_id"))
		check(parts.map(func(node):return node.get_meta("source_resource_id"))==([14316,14315] if i==0 else [14316]),"Capital ship lost its source light/engine children")
		check(ship.apply_selection({"visible":true,"level":i}) and ship.levels.filter(func(node):return node.visible).size()==1,ship.error)
		if DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image()
			var foreground:=0;var background:=image.get_pixel(0,0)
			for y in range(0,image.get_height(),3):
				for x in range(0,image.get_width(),3):
					var pixel:=image.get_pixel(x,y)
					if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.09:foreground+=1
			check(foreground>100,"Original convoy ship failed to render")
			if not captures.is_empty():
				DirAccess.make_dir_recursive_absolute(captures)
				check(image.save_png(captures.path_join("convoy-capital-ship-lod-%d.png"%i))==OK,"Capital ship capture failed")
	check(ship.apply_selection({"visible":false,"level":-1}) and ship.levels.all(func(node):return not node.visible),"Hidden capital ship retained floating geometry")
	viewport.free();shared.clear()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
