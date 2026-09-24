extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Definitions=preload("res://src/content/post_sahi_definitions.gd")
const VoidEnvironment=preload("res://src/simulation/void_environment.gd")
const Geometry=preload("res://src/presentation/void_environment_geometry.gd")
const Generator=preload("res://src/simulation/seeded_random.gd")
const NPC=preload("res://src/simulation/opening_npc_construction.gd")
const Field=preload("res://src/simulation/scenery_field.gd")
const Story=preload("res://src/content/story_encounter_definitions.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, binding, textures and optional captures");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+cat.error+visuals.error);quit(1);return
	var random:=Generator.new();random.seed_from(7487)
	var environment:=VoidEnvironment.new()
	if not environment.configure(bindings,random.snapshot()):check(false,environment.error);quit(1);return
	var world:=environment.snapshot()
	check(world.station_id==-1 and world.system_id==-1 and not world.docking_available,"Void world substituted an ordinary station or enabled docking")
	check(world.objects.size()==2 and environment.object_state(1).is_empty() and environment.object_state(2).pose.origin==world.player_position,"Void entry added a normal-sector body or misplaced the incoming player")
	check(world.player_position.x==0 and world.player_position.y>=-10000 and world.player_position.y<10000 and world.player_position.z>=170000 and world.player_position.z<220000,"Void entry is outside the source gate region")
	check(environment.object_state(2).pose.basis.z.dot(-world.player_position.normalized())>.9999,"Void gate no longer faces the station")
	check(environment.object_state(0).models.values().all(func(path):return path.contains("station_void")),"Void station uses a normal faction model")
	var field:=Field.new()
	if not field.configure(bindings,cat,-1,true,false,25):check(false,field.error);quit(1);return
	var generated:=field.generate(Vector3(-30000,0,30000),world.random_state)
	if generated.is_empty():check(false,field.error);quit(1);return
	check(generated.system_id==-1 and generated.objects.size()>=80 and generated.objects.size()<160,"Void asteroid field used an ordinary system or population")
	check(not Field.new().configure(bindings,cat,-1,false,false,25) and not Field.new().configure(bindings,cat,-1,true,false,24),"Special-location permission escaped its source-selected Void world")
	verify_population(bindings,cat,world,generated.random_state,25)
	verify_population(bindings,cat,world,generated.random_state,26)
	check(Definitions.mission(bindings,25).result_events.size()==3 and Definitions.mission(bindings,26).briefing_events.size()==3 and Definitions.mission(bindings,27).result_events.size()==11,"Post-Sahi original conversations lost lines")
	var node:=Geometry.new();root.add_child(node)
	if not node.build(library,visuals,bindings,environment):check(false,node.error);node.free();quit(1);return
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.far=400000;camera.near=.5;root.size=Vector2i(1280,720)
	camera.position=world.player_position+Vector3(0,7000,-25000);camera.look_at(Vector3.ZERO)
	var view:={"pose":camera.global_transform}
	check(node.advance(100,view),node.error)
	if args.size()==4 and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(args[3]);await process_frame
		RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[3].path_join("void-world.png"))==OK,"Cannot capture the Void world")
	node.free();camera.free()
	print("Post-Sahi world: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_population(bindings: RefCounted,cat: RefCounted,world: Dictionary,random: Dictionary,cursor: int) -> void:
	var where:=Definitions.location(cursor)
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,
		"station_id":where.station_id,"system_id":where.system_id,"mission_kind":156 if cursor==25 else 4,
		"mission_story":true,"mission_failed":false,"rank":8,"difficulty":0.5,"player_pose":Transform3D(Basis(Vector3.UP,.73),world.player_position)}
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":where.station_id,"system_id":where.system_id,"ship_id":0,"equipment_ids":[2,86,81,68]}
	var owner:=NPC.new()
	if not owner.configure_sahi(bindings,cat,seed,context):check(false,owner.error);return
	var state:=owner.generate(random)
	if state.is_empty():check(false,owner.error);return
	check(state.actors.size()==(3 if cursor==25 else 2),"Post-Sahi selected the generic traffic population")
	for actor in state.actors:
		check(actor.actor_kind==9 and actor.hull_catalogue_id==8 and actor.subtype==0,"Post-Sahi cast changed its authored Void fighter")
		check(not actor.route.has("completed") and actor.route.waypoints.size()>=2 and actor.route.waypoints.size()<=4 and not actor.fragments.is_empty(),"Void fighter lost its generated patrol or debris")
		var position: Vector3=actor.body_pose.origin
		if cursor==25:
			for axis in 3:check(absf(position[axis])>=20000 and absf(position[axis])<100000,"Void cast is outside the source signed-axis region")
		else:
			var offset: Vector3=position-context.player_pose.origin-context.player_pose.basis.z*8000.0
			check(offset.x>=-701 and offset.x<701 and offset.y>=-700 and offset.y<700 and offset.z>=-701 and offset.z<701,"Return pursuers are not ahead of the actual player")
	var composed:=Story.compose(bindings,cat,state)
	check(not composed.is_empty() and composed.npc_weapons.size()==state.actors.size() and composed.target_memberships.all(func(ids):return ids==[-1]),"Post-Sahi did not connect the ordinary combat owners")
	var changed:=context.duplicate(true);changed.station_id=0
	check(not NPC.new().configure_sahi(bindings,cat,seed,changed),"Post-Sahi accepted another world under the same mission")
