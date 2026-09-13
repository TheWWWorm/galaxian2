extends "res://tests/station_equipment.gd"
## Reaches the equipment completion through the native application, then checks
## detached encounter construction. No unsupported flight or mission is earned.
const TrainingRules=preload("res://src/content/combat_training_definitions.gd")
const TrainingNPC=preload("res://src/simulation/opening_npc_construction.gd")
const TrainingRoute=preload("res://src/simulation/npc_route.gd")
const TrainingWorld=preload("res://src/simulation/opening_world_initialization.gd")
const EmptyEquipment=preload("res://src/simulation/station_equipment.gd")
const Float32=preload("res://src/simulation/combat_vitals.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:await verify(args)
	if is_instance_valid(host):host.free()
	print("Combat-training construction: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_second_return(args: PackedStringArray):
	await super.after_second_return(args)
	var catalogues:=Catalogues.new()
	if not catalogues.open(lib):check(false,catalogues.error);return
	var before: Dictionary=host.session.snapshot()
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if header.reader=="resource-registration-v117":check(TrainingRules.parameters(bindings.combat_training),"Current Mac pack omitted combat-training construction")
	if not TrainingRules.parameters(bindings.combat_training):
		check(not TrainingNPC.new().configure_combat_training(bindings,catalogues,null,Vector3.ZERO) and not TrainingRoute.new().configure_training_generated(bindings,0),"Older pack invented combat-training actors")
		check(not TrainingWorld.new().configure_combat_training(bindings,catalogues,null,Vector3.ZERO,{}),"Older pack invented combat-training world setup")
		return
	check(before.campaign_cursor==7 and before.phase=="combat_departure_required","Encounter fixture did not reach acknowledged equipment completion")
	var equipment: RefCounted=host.session._world.equipment_owner()
	check(equipment!=null and equipment.requirements().satisfied,"Completed tutorial lost its equipment owner")
	if equipment==null:return
	check(TrainingRules.validate(bindings.combat_training,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_equipment,bindings.opening_actors).is_empty(),"Training declarations refused their source context")
	for key in TrainingRules.VALUES:
		var bad: Dictionary=bindings.combat_training.duplicate(true);bad[key]=null
		check(not TrainingRules.parameters(bad),"Changed training declaration was accepted: "+key)
	for key in TrainingRules.SPANS:
		var bad: Dictionary=bindings.combat_training.duplicate(true);bad.provenance[key].offset+=1
		check(not TrainingRules.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_equipment,bindings.opening_actors).is_empty(),"Disconnected training source span accepted: "+key)
	check(not TrainingNPC.new().configure_combat_training(bindings,catalogues,EmptyEquipment.new(),Vector3.ZERO),"Empty equipment could construct combat training")
	var detached: RefCounted=equipment.fork()
	check(detached.transact("unmount",55) and not TrainingNPC.new().configure_combat_training(bindings,catalogues,detached,Vector3.ZERO),"Cargo armor satisfied the installed-equipment prerequisite")
	check(equipment.requirements().satisfied and host.session.snapshot()==before,"Detached inventory mutation escaped into station ownership")
	check(not TrainingNPC.new().configure_combat_training(bindings,catalogues,equipment,Vector3(INF,0,0)),"Non-finite companion placement was accepted")
	var route:=TrainingRoute.new()
	for bad_id in [-1,4,0.0,true]:check(not route.configure_training_generated(bindings,bad_id),"Invalid route owner accepted")
	var saved_binding: String=bindings.binding_id;bindings.binding_id="a".repeat(64)
	check(not TrainingNPC.new().configure_combat_training(bindings,catalogues,equipment,Vector3.ZERO),"Equipment from another binding pack was accepted")
	bindings.binding_id=saved_binding
	var position:=Vector3(10,10,10000)
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	for key in conditions:
		var changed:=conditions.duplicate();changed[key]=not changed[key]
		check(not TrainingWorld.new().configure_combat_training(bindings,catalogues,equipment,position,changed),"Unsupported training entry context accepted: "+key)
	for fixture in TRAINING_GOLDEN:
		var constructor:=TrainingNPC.new()
		check(constructor.configure_combat_training(bindings,catalogues,equipment,position),constructor.error)
		check(constructor.generate({"state":-1}).is_empty() and constructor.snapshot().actors.is_empty(),"Rejected RNG generated partial actors")
		var generated:=constructor.generate({"state":int(fixture.input_state)})
		check(not generated.is_empty(),constructor.error)
		if generated.is_empty():continue
		check(generated.actors.size()==4 and generated.campaign_cursor==7 and generated.random_state.state==fixture.npc_state,"Four-actor construction changed its population or RNG boundary")
		for id in 4:
			var actor: Dictionary=generated.actors[id];var expected: Dictionary=fixture.actors[id]
			var generated_route: Dictionary=actor.discarded_route if id==3 else actor.route
			check(actor.factory_position==training_vec(expected.spawn)+(Vector3(10000,7000,160000) if id<3 else Vector3.ZERO),"Factory spawn lost the waypoint reference")
			check(generated_route.candidate_indices==expected.indices and generated_route.waypoints==expected.waypoints.map(training_vec) and generated_route.loop,"Generated patrol changed before its authored replacement")
			check(actor.cargo==expected.cargo and actor.discarded_cargo==[],"Training discarded or changed source-generated cargo")
			check(actor.fragments.size()==expected.fragments.size(),"Training fragment count differs from the source draw sequence")
			for index in expected.fragments.size():
				var raw: Array=expected.fragments[index];var rotation:=Vector3.ZERO
				for axis in 3:rotation[axis]=Float32.single(Float32.single(float(raw[axis])/180.0)*3.1415927410125732)
				check(actor.fragments[index].rotation_radians==rotation and actor.fragments[index].scale==Float32.single(float(raw[3])/100.0),"Fragment rotation or scale changed precision")
			check(actor.actor_id==id and actor.subtype==0 and actor.statistics_pose==actor.body_pose and actor.model_local_pose==Transform3D.IDENTITY,"Training actor lost its construction poses")
			if id<3:
				check(actor.actor_kind==8 and actor.hull_catalogue_id==2 and actor.body_pose.origin==actor.factory_position and actor.mode==5 and not actor.active and actor.targeting_blocked,"Training pirates were activated or placed outside the source factory")
			else:
				check(actor.actor_kind==3 and actor.hull_catalogue_id==30 and actor.body_pose.origin==Vector3(710,60,16000) and actor.friendly and actor.current_hull_override==9999999 and actor.name_text_id==1580,"Gunant's authored identity, hull or placement changed")
				check(actor.route.waypoints==[Vector3(-4000,-3000,80000),Vector3(10000,7000,160000)] and not actor.route.loop and actor.route.index==0 and not actor.route.completed,"Gunant did not replace his generated patrol with the authored route")
		var accepted:=constructor.snapshot()
		check(constructor.generate({"state":int(fixture.input_state)}).is_empty() and constructor.snapshot()==accepted,"Second generation replaced the retained encounter")
		generated.actors.clear();check(constructor.snapshot()==accepted,"Snapshot mutation escaped into construction")
		verify_authored_route(constructor.route(3))
		check(constructor.route(3).snapshot().index==0,"Route fork changed the retained construction")
		var world:=TrainingWorld.new()
		check(world.configure_combat_training(bindings,catalogues,equipment,position,conditions),world.error)
		var initialized:=world.generate({"state":int(fixture.input_state)})
		check(not initialized.is_empty(),world.error)
		if initialized.is_empty():continue
		check(initialized.npc_construction==accepted and initialized.weapon_effects.size()==4 and initialized.random_state.state==fixture.world_state,"Weapon setup changed actor construction or consumed draws in the wrong order")
		for id in 4:
			var weapon: Dictionary=initialized.weapon_effects[id]
			check(weapon.actor_id==id and weapon.discarded_default.item_id==0 and weapon.discarded_default.resource_id==14600 and weapon.discarded_default.flipped==fixture.effects[id][0],"Default weapon effect construction was skipped")
			check(weapon.primary.item_id==(25 if id==3 else 19) and weapon.primary.resource_id==(14606 if id==3 else 14605) and weapon.primary.flipped==fixture.effects[id][1],"Authored actor weapon replacement changed")
		check(world.route(3).snapshot().waypoints==accepted.actors[3].route.waypoints,"World initialization lost Gunant's authored route")
	# Swapping supported tutorial primaries cannot change this population's
	# cargo or procedural RNG sequence. The starter has one primary slot.
	detached=equipment.fork();check(detached.transact("unmount",22) and detached.transact("mount",0),detached.error)
	var alternate:=TrainingNPC.new();check(alternate.configure_combat_training(bindings,catalogues,detached,position),alternate.error)
	check(alternate.generate({"state":int(TRAINING_GOLDEN[0].input_state)}).random_state.state==TRAINING_GOLDEN[0].npc_state,"Supported primary swap changed NPC construction draws")
	check(host.session.snapshot()==before and not host.request_departure(),"Detached construction advanced campaign state or exposed an unfinished flight")

func verify_authored_route(route: RefCounted):
	check(route!=null,"Gunant route owner was not retained")
	if route==null:return
	var initial: Dictionary=route.snapshot();var point: Vector3=initial.waypoints[0]
	for axis in 3:
		for sign_value in [-1,1]:
			var boundary:=point;boundary[axis]+=sign_value*2000
			check(not route.advance(boundary).arrived and route.snapshot()==initial,"Waypoint accepted its excluded 2000-unit boundary")
	var reached: Dictionary=route.advance(point+Vector3(1999,-1999,1999))
	check(reached.arrived and not reached.wrapped and not reached.completed and reached.index==1,"First authored waypoint did not advance exactly once")
	var fork: RefCounted=route.fork_for_frame()
	reached=fork.advance(initial.waypoints[1])
	check(reached.arrived and reached.completed and reached.target==null and reached.index==2 and not reached.wrapped,"Final authored waypoint incorrectly looped or retained a target")
	var complete: Dictionary=fork.snapshot()
	reached=fork.advance(initial.waypoints[0])
	check(reached.completed and not reached.arrived and reached.target==null and fork.snapshot()==complete and route.snapshot().index==1,"Exhausted route restarted or fork mutation escaped")
	check(fork.advance(Vector3(NAN,0,0)).is_empty() and fork.snapshot()==complete,"Invalid completed-route input changed state")

static func training_vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])

const TRAINING_GOLDEN := [{"input_state":153548941033574,"npc_state":15406184250047,"world_state":29269289608543,"effects":[[[false,false,true,false],[true,true,false,true]],[[false,true,true,true],[true,false,true,false]],[[true,true,true,false],[false,true,true,true]],[[false,false,true,false],[true,true,true,true]]],"actors":[{"spawn":[14720,13852,-11917],"indices":[3,2],"waypoints":[[-22286,-6119,67295],[28952,-5937,64869]],"cargo":[{"item_id":112,"quantity":1},{"item_id":118,"quantity":8}],"fragments":[[113,108,66,93],[268,200,15,94],[148,13,186,83],[250,100,287,53],[262,126,191,94],[194,134,327,91],[322,246,15,94],[271,285,40,62]]},{"spawn":[-11613,-13158,14031],"indices":[3,1,2,0],"waypoints":[[-15055,-8286,62935],[19966,-888,28225],[28918,-5494,64409],[-10526,-7289,29624]],"cargo":[{"item_id":127,"quantity":8}],"fragments":[[2,192,113,73],[50,34,124,67],[131,225,37,91],[211,336,232,59]]},{"spawn":[7509,-19191,-2576],"indices":[0,3],"waypoints":[[-24504,-8257,34128],[-13743,-8002,70270]],"cargo":[{"item_id":126,"quantity":4},{"item_id":44,"quantity":2}],"fragments":[[84,255,23,99],[55,272,102,72],[330,104,83,51],[178,155,130,66]]},{"spawn":[14776,2818,-920],"indices":[2,0],"waypoints":[[24331,-1339,57437],[-23452,-789,33803]],"cargo":[{"item_id":140,"quantity":6},{"item_id":162,"quantity":2}],"fragments":[[147,323,54,71],[50,2,230,65],[24,157,183,98],[213,286,108,70],[346,156,155,74],[228,281,16,57]]}]},{"input_state":25214903917,"npc_state":125832945769669,"world_state":166006209675877,"effects":[[[true,true,true,true],[false,true,true,false]],[[true,false,false,false],[false,false,true,false]],[[false,false,true,true],[true,false,false,false]],[[true,false,false,true],[false,true,false,false]]],"actors":[{"spawn":[1360,5948,8029],"indices":[3,0,1,2],"waypoints":[[-17527,-5738,61095],[-13553,-6485,26053],[9491,-239,38719],[12854,-8923,62677]],"cargo":[{"item_id":124,"quantity":3}],"fragments":[[195,200,295,55],[290,118,291,74],[16,352,222,69],[237,176,246,57],[16,88,17,93],[187,107,268,55]]},{"spawn":[-14742,17408,6517],"indices":[3,2,0],"waypoints":[[-17420,-7703,63662],[21457,-1449,56726],[-16549,-8282,39358]],"cargo":[{"item_id":102,"quantity":1}],"fragments":[[45,239,293,67],[67,51,177,88],[283,130,245,98],[61,37,277,86]]},{"spawn":[-19359,-1710,-9849],"indices":[1,2],"waypoints":[[16865,-3014,24004],[5984,-7238,61792]],"cargo":[{"item_id":140,"quantity":6}],"fragments":[[312,345,105,63],[33,48,77,70],[346,182,185,76],[339,183,352,57],[50,335,334,66],[314,248,89,88]]},{"spawn":[-3272,-11065,5096],"indices":[3,0,1,2],"waypoints":[[-19214,-9026,56155],[-10874,-6153,33324],[15924,-9611,37643],[5253,-477,71292]],"cargo":[{"item_id":154,"quantity":5}],"fragments":[[55,222,8,91],[191,136,72,53],[153,138,210,88]]}]},{"input_state":25214903916,"npc_state":119416672120630,"world_state":221973899206998,"effects":[[[true,false,true,true],[false,false,false,true]],[[true,false,false,false],[true,true,true,false]],[[false,false,true,true],[true,true,false,false]],[[true,true,false,false],[true,false,false,false]]],"actors":[{"spawn":[8985,-15412,-18153],"indices":[3,1,0],"waypoints":[[-14683,-8737,75562],[9434,-3394,34978],[-9687,-5746,34904]],"cargo":[{"item_id":109,"quantity":8},{"item_id":118,"quantity":3}],"fragments":[[0,151,286,83],[358,156,308,64],[185,128,19,66],[55,58,162,87],[312,211,81,97],[128,162,161,58],[165,29,299,95]]},{"spawn":[-15241,-19190,-5383],"indices":[1,0,2],"waypoints":[[13053,-1175,37101],[-6474,-7626,20620],[20601,-4564,71650]],"cargo":[{"item_id":125,"quantity":9}],"fragments":[[46,137,185,50],[169,88,203,90],[76,276,256,71],[139,314,59,78],[231,110,25,95]]},{"spawn":[-18144,-15136,-13709],"indices":[3,2,0,1],"waypoints":[[-20905,-8108,66463],[18863,-3410,67679],[-5984,-4564,25288],[17028,-8489,34362]],"cargo":[{"item_id":69,"quantity":2},{"item_id":133,"quantity":5}],"fragments":[[7,243,138,52],[307,292,57,68],[65,334,111,86],[219,28,338,83]]},{"spawn":[-10237,-14626,-6200],"indices":[1,3,0],"waypoints":[[11972,-5060,35158],[-18732,-6334,61675],[-13046,-6111,42969]],"cargo":[{"item_id":118,"quantity":3},{"item_id":157,"quantity":7}],"fragments":[[5,29,216,58],[161,48,4,78],[236,51,16,89],[303,281,14,60],[95,284,87,55]]}]}]
