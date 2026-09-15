extends SceneTree
## Earned equipment prerequisite; explicit encounter-entry and lethal-hit
## fixtures. No campaign advancement or application arrival is supplied here.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Definitions=preload("res://src/content/convoy_world_definitions.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
const Motion=preload("res://src/simulation/freighter_motion.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const LegacyWeapons=preload("res://src/content/contract_ship_combat_definitions.gd")
const CONDITIONS={"companions_empty":true,"location_match":false,"special_placement":false}
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit content/bindings/visuals")
	if args.size()==3:verify(args)
	print("Convoy world construction: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,"station_id":79,"system_id":15,
		"rank":0,"difficulty":0.5,"mission_kind":4,"mission_story":true,"mission_completed":false}
	if not Definitions.available(bindings):
		check(not World.new().configure_convoy(bindings,cat,null,context,CONDITIONS),"Legacy content enabled an incomplete convoy factory")
		check(not Route.new().configure_convoy_generated(bindings,0),"Legacy content enabled convoy patrols")
		return
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	check(not Construction.new().configure_convoy(bindings,cat,equipment,context),"Convoy bypassed the equipment tutorial")
	if not equipment.prepare_training_completion(bindings,cat) or not equipment.complete_training(equipment.snapshot().cargo) or not equipment.apply_station_exchange(bindings,cat,9):check(false,equipment.error);return
	check(not Construction.new().configure_convoy(bindings,cat,equipment,context),"Convoy started with the ship at Var Hastra")
	var arrival:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":10,"from_station_id":78,"station_id":79,"system_id":15,"source_state":2,"world_type":3,"audio_selector":1}
	if not equipment.relocate_local_arrival(bindings,cat,arrival):check(false,equipment.error);return
	var retained: Dictionary=equipment.snapshot()
	for field in ["campaign_cursor","station_id","mission_kind","mission_story","mission_completed","rank","binding_id"]:
		var invalid:=context.duplicate();invalid[field]={"campaign_cursor":13,"station_id":75,"mission_kind":150,"mission_story":false,"mission_completed":true,"rank":21,"binding_id":"foreign"}[field]
		check(not World.new().configure_convoy(bindings,cat,equipment,invalid,CONDITIONS),"Convoy accepted a mismatched active story: "+field)
	var vectors: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GOF2_CONVOY_VECTORS")))
	if not vectors is Array or vectors.size()!=5:check(false,"Supply five independent vectors using GOF2_CONVOY_VECTORS");return
	var last: RefCounted
	for vector in vectors:
		var world:=World.new()
		if not world.configure_convoy(bindings,cat,equipment,context,CONDITIONS):check(false,world.error);return
		check(world.generate({"state":-1}).is_empty() and world.snapshot().is_empty(),"Invalid RNG partially constructed the convoy")
		var state:=world.generate({"state":int(vector.input_state)})
		if state.is_empty():check(false,world.error);return
		var built: Dictionary=state.npc_construction
		check(built.actors.size()==7 and built.random_state.state==int(vector.npc_state) and state.random_state.state==int(vector.world_state),"Independent convoy random stream changed for seed "+str(vector.seed))
		for id in 7:
			var actor: Dictionary=built.actors[id];var expected: Dictionary=vector.actors[id]
			check(actor.actor_id==id and actor.actor_kind==(8 if id<3 else 0) and actor.hull_catalogue_id==(0 if id<3 else 5 if id<5 else 14),"Convoy order, faction or original ship changed")
			check(actor.factory_position==point(expected.factory_position) and actor.body_pose.origin==point(expected.position) and actor.body_pose==actor.statistics_pose,"Convoy placement changed the factory or authored pose")
			check(actor.cargo==expected.cargo.map(func(item):return {"item_id":int(item[0]),"quantity":int(item[1])}) and actor.discarded_cargo.is_empty(),"Convoy cargo differs from the independent vector")
			check(actor.fragments.size()==int(expected.fragment_count),"Construction changed breakup allocation")
			if id<5:
				var route: RefCounted=world.route(id)
				check(route!=null and route.snapshot()==actor.route and actor.route.loop and actor.route.waypoints==expected.route.map(point),"Convoy fighter replaced its generated patrol")
				check(state.weapon_effects[id].discarded_default.flipped==vector.effects[id][0] and state.weapon_effects[id].primary.flipped==vector.effects[id][1],"Convoy weapon allocation changed shared RNG order")
				check(state.weapon_effects[id].primary.item_id==(19 if id<3 else 0),"Convoy selected the wrong faction weapon")
			else:
				check(world.route(id)==null and actor.route.is_empty() and actor.model_assembly_required and actor.assembly.body_resource_ids==[14311.0,14312.0,14313.0],"Capital ship inherited an ambient model or fighter patrol")
				check(state.weapon_effects[id]=={"actor_id":id,"unarmed":true},"Unarmed capital ship allocated a gun")
		check(world.generate({"state":0}).is_empty() and world.snapshot()==state,"A committed convoy regenerated")
		var fork: RefCounted=world.fork_for_frame();var detached: Dictionary=fork.snapshot();detached.npc_construction.actors[0].cargo.clear()
		check(world.snapshot()==state and fork.snapshot()==state,"A consumer changed retained construction")
		last=world
	check(equipment.snapshot()==retained,"Convoy preparation changed inventory, currency or location")
	verify_bodies(bindings,cat,equipment,context,last)
	if failures:return
	verify_capture(bindings,cat,library,last.npc_construction_owner())

func verify_bodies(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,context: Dictionary,world: RefCounted) -> void:
	for sample in [[0,0.5,76,1900,3],[0,1.0,114,2850,3],[8,0.5,188,4700,7],[8,1.0,282,7050,9],[20,0.5,356,8900,18],[20,1.0,534,13350,24]]:
		var selected:=context.duplicate();selected.rank=sample[0];selected.difficulty=sample[1]
		var construction:=Construction.new()
		if not construction.configure_convoy(bindings,cat,equipment,selected) or construction.generate({"state":42}).is_empty():check(false,construction.error);return
		var weapons:=Weapons.new()
		if not weapons.configure_convoy(bindings,cat,construction):check(false,weapons.error);return
		var data:=Definitions.population(bindings,construction.snapshot())
		check(data.player_weapon_targets==[0,1,2,3,4,5,6] and data.target_memberships==[[-1,3,4,5,6],[-1,3,4,5,6],[-1,3,4,5,6],[-1,0,1,2],[-1,0,1,2],[-1,0,1,2],[-1,0,1,2]],"Convoy target lists changed player or faction membership")
		for id in 7:
			var body:=Actor.new()
			if not body.configure_convoy(bindings,cat,construction,id):check(false,body.error);return
			var state:=body.snapshot()
			check(state.max_hull==sample[3 if id>=5 else 2] and state.vitals.hull==state.max_hull and state.vitals.armor==0 and state.vitals.shield==0.0,"Convoy factory changed rank/difficulty hull or invented shield pools")
			check(state.active and state.actor_mode==0 and not state.targeting_blocked,"Convoy used a hidden training actor's initial state")
			check(body.collision_context().path==("point_geometry" if id>=5 else "bounds"),"Convoy body uses the wrong contact geometry")
			var gun: Dictionary=weapons.snapshot().actors[id]
			if id>=5:check(gun.projectiles.is_empty() and gun.definition.unarmed,"Capital ship gained an ordinary weapon")
			else:check(gun.definition.damage==sample[4] and gun.definition.interval_ms==572 and gun.definition.speed_units_per_millisecond==16.0 and gun.definition.item_id==(19 if id<3 else 0),"Convoy changed original damage, rate or faction armament")
	var legacy:=LegacyWeapons.weapon_for(bindings.early_contracts.ship_combat,8,0.5,0,true)
	check(legacy.damage==15 and legacy.interval_ms==574 and legacy.speed_units_per_millisecond==28.0,"Shared weapon setup changed existing contract rivals")
	var malformed: Dictionary=world.npc_construction_owner().snapshot();malformed.actors[6].hull_catalogue_id=15
	check(Definitions.population(bindings,malformed).is_empty(),"A capital ship was replaced by an ambient freighter")

func verify_capture(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	if not library.select_language("gb"):check(false,library.error);return
	var resources:=RadioResources.new()
	if not resources.prepare(library,bindings,null,14):check(false,resources.error);return
	var radio:=Radio.new();var capture:=Capture.new();var motion:=Motion.new()
	if not radio.configure(bindings,library,resources.line_counts,14) or not capture.configure(bindings) or not motion.configure_convoy(bindings,6):check(false,radio.error+capture.error+motion.error);return
	var actors:=[]
	for id in 7:
		var actor:=Actor.new()
		if not actor.configure_convoy(bindings,cat,construction,id):check(false,actor.error);return
		actors.append(actor)
	var original: Array=actors.map(func(actor):return actor.snapshot())
	var initial: RefCounted=capture.fork_for_frame()
	var now:=0;var arrived:=false;var player:=Transform3D(Basis.IDENTITY,Vector3(40000,0,120000))
	while now<180000:
		now+=100
		if now==20000:
			var lethal: Dictionary=actors[1].normal_hit(actors[1].snapshot().vitals.hull,true)
			if lethal.is_empty():check(false,actors[1].error);return
			check(lethal.destroyed_now and actors[1].snapshot().nonplayer_kill,"Explicit NPC lethal fixture lost its attribution")
		if not capture.advance(100,radio.snapshot(),player,motion.snapshot().body_pose):check(false,capture.error);return
		for id in 7:
			var before: Dictionary=actors[id].snapshot();var next: RefCounted=actors[id].fork_for_frame()
			if not next.apply_convoy_capture(capture):check(false,next.error);return
			if actors[id].snapshot()!=before:check(false,"Prospective retirement changed the retained actor");return
			actors[id]=next
		if not motion.apply_capture(capture) or not motion.update(100,true):check(false,motion.error);return
		var targets:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,"player_targets":actors.map(func(actor):return {"scenery":false,"current_hull":int(actor.snapshot().vitals.hull)})}
		radio.step_convoy(now,targets)
		if not radio.error.is_empty():check(false,radio.error);return
		if capture.snapshot().phase==Capture.Stage.ARRIVAL_REQUIRED:arrived=true;break
	check(arrived and now==54800 and capture.snapshot().arrival.station_id==98,"Real body hulls did not drive the original capture/radio boundary")
	for id in 7:
		var state: Dictionary=actors[id].snapshot()
		if id<3:check(state.vitals.hull==0 and not state.active and state.actor_mode==4 and state.nonplayer_kill==(id==1),"Story retirement awarded a hit or failed to disable a pirate")
		else:check(state.vitals==original[id].vitals and state.active,"EMP retired or damaged the Terran convoy")
	check(motion.snapshot().body_pose.origin.z>37000,"Capture did not start actor6 cruise")
	var before: Dictionary=actors[0].snapshot()
	check(not actors[0].apply_convoy_capture(initial) and actors[0].snapshot()==before,"Earlier capture state revived or rewound a retired actor")
	check(construction.snapshot().actors[1].body_pose.origin==original[1].position,"Combat mutated original construction")

func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
