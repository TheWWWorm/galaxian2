extends SceneTree
## Detached world factory with an earned App Store loadout. The selected Void
## observation is source context, not a fabricated mission33 save or admission.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Save=preload("res://src/simulation/station_save_file.gd")
const Population=preload("res://src/simulation/traffic_population.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const NPC=preload("res://src/simulation/opening_npc_construction.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Field=preload("res://src/simulation/scenery_field.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const ENTRY={"companions_empty":true,"location_match":true,"special_placement":false}
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=7:check(false,"Expected App196 and old195 triples plus an earned App196 station save");finish();return
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);finish();return
	var file:=Save.new();var saved: Dictionary=file.load_document(args[6],bindings,cat,library)
	if saved.is_empty():check(false,file.error);finish();return
	check(saved.base_content_id==bindings.base_content_id and saved.binding_id==bindings.binding_id and saved.station.campaign_cursor==32,"Earned save identity or pre-Void cursor changed")
	var loadout: Dictionary=saved.inventory.loadout
	check(loadout.ship_id==0 and loadout.equipment_ids==[2,41,81,91,55] and saved.career.rank==4,"The actual paid Alioth32 equipment/rank fixture changed")
	var context:=selected(int(saved.career.rank))
	var field:=Field.new();check(field.configure(bindings,cat,-1,true,false,33),field.error)
	var seed:=Random.new();seed.seed_from(1789100000)
	var incoming: Dictionary=seed.snapshot()
	var scenery: Dictionary=field.generate(Vector3(-30000,0,30000),incoming)
	if scenery.is_empty():check(false,field.error);finish();return
	check(scenery.objects.size()>=80 and scenery.objects.size()<=159 and scenery.objects.all(func(row):return row.item_id==164),"Source Void crystal field did not precede the actors")
	var post_field: Dictionary=scenery.random_state.duplicate(true)
	var world:=World.new()
	if not world.configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,context,ENTRY):check(false,world.error);finish();return
	var state: Dictionary=world.generate(post_field)
	if state.is_empty():check(false,world.error);finish();return
	check(seed.snapshot()==incoming and scenery.random_state==post_field and state.input_random_state==post_field,"World construction mutated or reseeded its post-field input")
	check(state.base_content_id==bindings.base_content_id and state.binding_id==bindings.binding_id and state.campaign_cursor==33 and state.station_id==-1 and state.system_id==-1 and state.void_context==context and state.entry_conditions==ENTRY,"World lost source selection and content identity")
	var built: Dictionary=state.npc_construction
	check(built.player_ship_id==loadout.ship_id and built.population.incoming_random_state==post_field and built.population.before_actors_random_state=={"state":11961205580603},"Count branch did not continue the post-field stream")
	check(built.population.rank_base==1.0 and built.population.first_count_draw==1 and built.population.second_count_draw==0 and built.population.actor_count==1 and built.actors.size()==1,"Earned rank4's one-actor source branch changed")
	if built.actors.size()==1:verify_actor(world,built.actors[0],state)
	var observed:=world.snapshot();observed.npc_construction.actors.clear();observed.weapon_effects.clear()
	check(world.snapshot()==state,"World observation aliases its owner")
	check(world.generate(post_field).is_empty() and world.snapshot()==state,"World generated twice or failed atomically")
	verify_two_actor_case(bindings,cat,loadout,context)
	verify_refusals(bindings,cat,loadout,context,post_field)
	verify_old_absence(args[3],args[4],loadout,context)
	print("Ordinary Void world: earned rank4, one- and two-actor branches; %d checks; %d failures"%[checks,failures])
	finish()

func verify_actor(world: RefCounted,actor: Dictionary,state: Dictionary) -> void:
	check(actor.actor_id==0 and actor.actor_kind==9 and actor.subtype==0 and actor.hull_catalogue_id==8 and actor.population_group=="void","Shared kind9/hull8 fighter construction changed")
	check(actor.factory_position_before_relocation==Vector3(4089,569,-8449) and actor.factory_position==Vector3(-55036,-669,-51339) and actor.placement_draws==[4964,39331,8661],"Constructor or post-constructor position draws changed order")
	check(actor.body_pose.origin==actor.factory_position and actor.statistics_pose==actor.body_pose and actor.model_local_pose==Transform3D.IDENTITY,"Void actor pose was not installed on the shared body")
	check(actor.route.campaign_cursor==33 and actor.route.candidate_indices==[3,2,1,0] and actor.route.waypoints==[Vector3(-16354,-8367,70863),Vector3(26020,-4138,75207),Vector3(29425,-8492,44448),Vector3(-17335,-5043,43445)] and actor.route.loop,"Shared generated route changed its draw order")
	check(actor.cargo==[{"item_id":48,"quantity":1}] and actor.discarded_cargo.is_empty() and actor.fragments.size()==9 and actor.fragments.all(func(row):return row.resource_id==14292),"Constructor cargo/debris was skipped or cleared")
	check(actor.activation_setter_argument==1 and actor.activation_fields=={"f8":1,"b60":1,"b61":0,"ec":1},"Source activation setter changed")
	check(state.weapon_effects==[{"actor_id":0,"discarded_default":{"item_id":0,"resource_id":14600,"flipped":[false,true,false,true]},"primary":{"item_id":5,"resource_id":14602,"flipped":[false,false,true,false]}}] and state.random_state=={"state":203343764783311},"Kind9 effect allocation or final stream changed")
	var route: RefCounted=world.route(0)
	check(route!=null and route.snapshot()==actor.route,"World did not retain the actor's generated route")
	if route!=null:
		var before: Dictionary=world.route(0).snapshot()
		check(not route.advance(actor.route.waypoints[0]).is_empty() and world.route(0).snapshot()==before,"Advancing a detached route changed the world owner")
	check(world.route(1)==null,"World offered a route for an actor that rank4 did not create")

func verify_two_actor_case(bindings: RefCounted,cat: RefCounted,loadout: Dictionary,context: Dictionary) -> void:
	# A second fixed post-field stream exercises the other earned-rank branch.
	var field:=Field.new();check(field.configure(bindings,cat,-1,true,false,33),field.error)
	var seed:=Random.new();seed.seed_from(1789100001)
	var scenery: Dictionary=field.generate(Vector3(-30000,0,30000),seed.snapshot())
	if scenery.is_empty():check(false,field.error);return
	var world:=World.new()
	if not world.configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,context,ENTRY):check(false,world.error);return
	var state: Dictionary=world.generate(scenery.random_state)
	if state.is_empty():check(false,world.error);return
	var built: Dictionary=state.npc_construction
	check(scenery.random_state=={"state":9241660016390} and built.population.first_count_draw==0 and not built.population.has("second_count_draw") and built.population.before_actors_random_state=={"state":43967032336793} and built.population.actor_count==2 and built.actors.size()==2,"Earned rank4 two-actor count branch or post-field stream changed")
	var vectors:=[[Vector3(4928,19937,-19320),Vector3(33208,14057,-29457),[93208,54057,30543],[2,1],[{"item_id":106,"quantity":2}],8],
		[Vector3(17994,16372,7544),Vector3(51719,31552,16015),[111719,71552,76015],[1,0],[{"item_id":113,"quantity":5}],9]]
	for id in state.npc_construction.actors.size():
		var actor: Dictionary=state.npc_construction.actors[id]
		check(actor.actor_id==id and actor.actor_kind==9 and actor.subtype==0 and actor.hull_catalogue_id==8 and actor.route.actor_id==id and actor.route.campaign_cursor==33 and actor.activation_setter_argument==1 and world.route(id)!=null,"Repeated shared construction lost its actor order or route")
		var vector: Array=vectors[id]
		check(actor.factory_position_before_relocation==vector[0] and actor.factory_position==vector[1] and actor.placement_draws==vector[2] and actor.route.candidate_indices==vector[3] and actor.cargo==vector[4] and actor.fragments.size()==vector[5],"Two-actor constructor/relocation draw order changed for actor "+str(id))
	check(state.weapon_effects.size()==2 and state.weapon_effects[0].primary.flipped==[true,true,true,false] and state.weapon_effects[1].primary.flipped==[false,true,true,true] and state.random_state=={"state":36891336720963},"Two-actor effect allocation or final stream changed")

func verify_refusals(bindings: RefCounted,cat: RefCounted,loadout: Dictionary,context: Dictionary,stream: Dictionary) -> void:
	var owner:=World.new()
	for change in [{"campaign_cursor":32},{"selected_station_id":91},{"retained_system_id":18},{"selected_mission_kind":8},{"selected_mission_story":true},{"location_match":false},{"rank":-1}]:
		var wrong: Dictionary=context.duplicate(true);wrong.merge(change,true)
		check(not owner.configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,wrong,ENTRY) and owner.snapshot().is_empty(),"Invalid selected Void context opened a world: "+str(change))
	for change in [{"companions_empty":false},{"location_match":false},{"special_placement":true}]:
		var wrong: Dictionary=ENTRY.duplicate(true);wrong.merge(change,true)
		check(not owner.configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,context,wrong),"Invalid ordinary placement opened Void actors: "+str(change))
	check(not owner.configure_void_factory(bindings,cat,-1,loadout.equipment_ids,context,ENTRY),"Unowned player hull opened Void actors")
	check(not owner.configure_void_factory(bindings,cat,int(loadout.ship_id),[999],context,ENTRY),"Unowned equipment opened Void actors")
	var route:=Route.new()
	check(route.configure_void_generated(bindings,0,context) and route.configure_void_generated(bindings,1,context) and not route.configure_void_generated(bindings,2,context),"Rank4 route owner bounds changed")
	check(not NPC.new().configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,context.merged({"campaign_cursor":32},true)),"Actor factory bypassed source selection")
	check(owner.configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,context,ENTRY),owner.error)
	check(owner.generate({"state":-1}).is_empty() and owner.snapshot().is_empty() and not owner.generate(stream).is_empty(),"Invalid stream committed the world or poisoned a valid retry")

func verify_old_absence(content: String,pack: String,loadout: Dictionary,context: Dictionary) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	check(not bindings.mido_travel.has("void_crystals"),"Older195 control unexpectedly gained cursor33 declarations")
	check(not World.new().configure_void_factory(bindings,cat,int(loadout.ship_id),loadout.equipment_ids,context,ENTRY) and not Route.new().configure_void_generated(bindings,0,context),"Older195 declarations opened the new world/route")

func selected(rank: int) -> Dictionary:
	return {"campaign_cursor":33,"selected_system_id":-1,"selected_station_id":-1,"retained_system_id":-1,"retained_station_id":-1,
		"selected_mission_kind":-1,"selected_mission_story":false,"location_match":true,"rank":rank}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func finish() -> void:quit(1 if failures else 0)
