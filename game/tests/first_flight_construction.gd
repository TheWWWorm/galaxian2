extends SceneTree
const Flight=preload("res://src/simulation/first_flight_construction.gd")
const Definitions=preload("res://src/content/first_flight_definitions.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Location=preload("res://src/simulation/arrival_location.gd")
const Population=preload("res://src/simulation/scenery_population.gd")
const Initialization=preload("res://src/simulation/opening_world_initialization.gd")
const BodyResources=preload("res://src/content/scenery_body_resources.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const GOLDEN := [{"environment_seconds":0,"position":[21360,5948,68029],"before_yaw_state":67704983304270,"yaw_state":170671006977345,"yaw_units":-1600,"yaw_radians":-0.1533980816602707,"eye":[-2570.84912109375,-2342,18707.90625]},{"environment_seconds":4096,"position":[23459,14479,42339],"before_yaw_state":221433343379534,"yaw_state":90899605331265,"yaw_units":1600,"yaw_radians":0.1533980816602707,"eye":[179.5003662109375,-2342,19080.73046875]},{"environment_seconds":12345,"position":[-33749,9080,68241],"before_yaw_state":262614317937313,"yaw_state":258144839677080,"yaw_units":-1600,"yaw_radians":-0.1533980816602707,"eye":[-2570.84912109375,-2342,18707.90625]},{"environment_seconds":1789100000,"position":[-3286,-8199,56915],"before_yaw_state":48304870645230,"yaw_state":219906188857953,"yaw_units":-1600,"yaw_radians":-0.1533980816602707,"eye":[-2570.84912109375,-2342,18707.90625]}]
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected Mac content, bindings and visual arguments")
	if args.size()==3:verify(args)
	print("First flight construction: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var flight:=Flight.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):
		check(false,lib.error+bindings.error+cat.error);return
	check(flight.snapshot().is_empty() and flight.scenery_owner()==null and flight.camera_owner()==null and flight.player_owner()==null,"Unprepared flight exposed owners")
	if bindings.first_flight.is_empty():
		check(not flight.prepare(bindings,cat,{}, 1,1789100000) and flight.snapshot().is_empty(),"Legacy pack invented first-flight construction");return
	var source_bytes:=int(JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json"))).source_executable_bytes)
	check(validate(bindings.first_flight,bindings,source_bytes).is_empty(),"Imported construction extents failed")
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.first_flight.duplicate(true);bad.provenance[key].offset+=1
		check(not validate(bad,bindings,source_bytes).is_empty(),"Disconnected construction extent accepted: "+key)
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.first_flight.duplicate(true);bad[key]="unverified"
		check(not Definitions.parameters(bad),"Unverified construction parameter accepted: "+key)
	var population:=Population.new();check(population.configure(bindings),population.error)
	for invalid in [78.0,"78",null,-1,77]:
		check(population.for_departure(invalid,{"companions_empty":true,"location_match":false,"special_placement":false}).is_empty(),"Invalid first-flight station accepted")
	var initial:=Player.new();check(initial.configure(bindings,cat),initial.error)
	var handoff:=Handoff.new();var entry:=handoff.prepare(bindings,cat,Fixture.completed(bindings,initial,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,entry,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		var next: RefCounted=arrival.evaluate(100)
		if next==null:check(false,arrival.error);return
		arrival=next
		if not arrival.snapshot().boundary.is_empty():break
	var station_packet:=arrival.prepare_station()
	if station_packet.is_empty():check(false,arrival.error);return
	var bodies:=BodyResources.new();check(bodies.configure(lib,bindings),bodies.error)
	var random:=Random.new();var yaws:=[]
	for credit in 4:
		station_packet.rescue_entry=handoff.prepare(bindings,cat,Fixture.completed(bindings,initial,credit))
		var station:=Station.new()
		check(station.configure(bindings,cat,lib,station_packet),station.error)
		for i in 19:check(station.acknowledge(),station.error)
		var before:=station.snapshot();var packet:=station.prepare_departure(bindings,cat)
		var input: int=[0,4096,12345,1789100000][credit];random.seed_from(input)
		check(flight.prepare(bindings,cat,packet,input,1789100000,true,bodies),flight.error)
		var state:=flight.snapshot()
		if state.is_empty():return
		check(station.snapshot()==before and state.departure==packet and not state.activated,"Construction advanced station, accepted confirmation or altered departure")
		check(state.location.ship_id==0 and state.location.campaign_cursor==2 and state.world_type==3,"Flight selected the rescue hull or cursor")
		check(state.location.station_id==78 and state.location.system_id==15 and state.location.sky_index==cat.tables.systems[15].sky_index,"Departure location differs from its catalogues")
		check(state.player_pose.origin==Vector3(10,10,10000) and state.player_yaw_units in [-1600,1600],"Initial player placement differs from source")
		if state.player_yaw_units not in yaws:yaws.append(state.player_yaw_units)
		var expected_environment:=Vector3(random.next_int(80000)-40000,random.next_int(40000)-20000,random.next_int(40000)+40000)
		check(state.environment_object=={"resource_id":16994,"position":expected_environment} and state.before_yaw_random_state==random.snapshot(),"Environment draws were omitted or reordered before yaw")
		var expected_yaw:=1 if random.next_int(2)==0 else -1
		check(state.player_yaw_units==1600*expected_yaw and state.yaw_random_state==random.snapshot(),"Yaw consumed a wrong random stream")
		var radians:=float(state.player_yaw_units)/65536.0*6.2831854820251465
		check(state.player_pose.basis.is_equal_approx(Basis(Vector3.UP,radians)),"Initial yaw was dropped or used as degrees")
		check(state.scenery.objects.size()==130 and state.scenery.center==Vector3(12298,36830,77237),"Departure did not use its ordinary station-seeded field")
		check(state.scenery.bodies.objects.size()==130,"First field lacks source collision bodies")
		var world: Dictionary=state.scenery.world_initialization
		check(world.campaign_cursor==2 and world.npc_construction.actors.is_empty() and world.weapon_effects.is_empty(),"First field recreated the rescue NPC or its effects")
		check(world.input_random_state==world.random_state and state.camera_input_random_state==world.random_state,"Empty NPC population consumed random draws")
		check(not state.entry_released and state.entry_elapsed_ms==0 and not state.briefing_started,"Construction skipped the entry sequence")
		random.restore(world.random_state)
		var offset:=Vector3(500+random.next_int(2000),500+random.next_int(2000),9000)
		if random.next_int(2)==0:offset.x=-offset.x
		if random.next_int(2)==0:offset.y=-offset.y
		check(state.camera_offset==offset and state.random_state==random.snapshot(),"Camera draw order differs from the source")
		check(state.camera_view.eye.is_equal_approx(state.player_pose*offset) and state.camera_view.look==state.player_pose.origin,"Camera offset was not transformed by player pose")
		var golden: Dictionary=GOLDEN[credit]
		check(state.environment_object.position==Vector3(golden.position[0],golden.position[1],golden.position[2]) and state.before_yaw_random_state.state==int(golden.before_yaw_state) and state.yaw_random_state.state==int(golden.yaw_state),"Entry differs from independently calculated source vector")
		check(state.camera_view.eye.distance_to(Vector3(golden.eye[0],golden.eye[1],golden.eye[2]))<0.005,"Source-coordinate camera transform differs from the numeric oracle")
		check(state.camera_view.pose.basis.is_equal_approx(state.camera_view.pose.basis.orthonormalized()),"Departure camera is not a proper view")
		check(state.camera_shot.mode=="follow" and state.camera_shot.target=="player","Entry selected a fixed rather than ordinary follow mode")
		var camera: RefCounted=flight.camera_owner();var scene:={"base_content_id":state.base_content_id,"binding_id":state.binding_id,"player_pose":state.player_pose}
		check(camera.update(100,state.camera_shot,scene) and camera.snapshot().mode=="follow",camera.error)
		check(camera.snapshot().eye.distance_to(state.player_pose*Vector3(0,600,-1338))<state.camera_view.eye.distance_to(state.player_pose*Vector3(0,600,-1338)),"Camera did not converge toward the ordinary follow position")
		var scenery: RefCounted=flight.scenery_owner()
		check(scenery.initial_npc_route(0)==null and scenery.arrival_motion_construction().is_empty(),"First flight exposed a rescue NPC route or pose")
		check(not scenery.complete_world_initialization(bindings,cat),"First world initialized twice")
		check(scenery.update(100,state.camera_view.eye,1.0,null,state.random_state),scenery.error)
		check(flight.snapshot()==state,"Detached owner update mutated the prepared flight")
		var reset_owner:=flight.player_owner();reset_owner.advance_recharge(100)
		check(flight.snapshot()==state,"Detached player update changed prepared progress")
		if credit==0:print("First-flight source vector: yaw=",state.player_yaw_units," offset=",state.camera_offset," field_rng=",state.camera_input_random_state," camera_rng=",state.random_state)
		for key in packet:
			var bad:=packet.duplicate(true);bad.erase(key)
			check(not flight.prepare(bindings,cat,bad,input,1789100000) and flight.snapshot()==state,"Missing departure field altered last good construction: "+key)
		var bad:=packet.duplicate(true);bad.progress.rank_score+=1
		check(not flight.prepare(bindings,cat,bad,input,1789100000) and flight.snapshot()==state,"Unearned rank accepted")
		bad=packet.duplicate(true);bad.mission.reward=100
		check(not flight.prepare(bindings,cat,bad,input,1789100000) and flight.snapshot()==state,"Invented mining reward accepted")
		bad=packet.duplicate(true);bad.player.vitals.hull=999
		check(not flight.prepare(bindings,cat,bad,input,1789100000) and flight.snapshot()==state,"Opening hull persisted on replacement ship")
		for invalid in [-1,2147483648,0.5,"1"]:
			check(not flight.prepare(bindings,cat,packet,invalid,1789100000) and flight.snapshot()==state,"Invalid environment seed altered construction")
		for invalid in [-1,2147483648,0.5]:
			check(not flight.prepare(bindings,cat,packet,input,invalid) and flight.snapshot()==state,"Invalid field seed altered construction")
		var location:=Location.new()
		check(location.resolve(bindings,cat,packet.player_cache).is_empty(),"Departure cache was accepted by rescue location")
		check(location.resolve_departure(bindings,cat,entry.player_cache).is_empty(),"Rescue cache was accepted by departure location")
		for key in state.entry_conditions:
			var conditions: Dictionary=state.entry_conditions.duplicate();conditions[key]=not conditions[key]
			var initializer:=Initialization.new()
			check(not initializer.configure_departure(bindings,cat,packet.player_cache,conditions),"Unsupported world condition accepted: "+key)
		var item: Dictionary=cat.tables.items[90];var saved: int=item.arrays[2][5];item.arrays[2][5]=39
		var initializer:=Initialization.new()
		check(not initializer.configure_departure(bindings,cat,packet.player_cache,state.entry_conditions),"Optional population was ignored on changed replacement equipment")
		item.arrays[2][5]=saved
		check(flight.prepare(bindings,cat,packet,input,1789100000,true,bodies) and flight.snapshot()==state,"Retry changed the prepared flight")
		var rules: Dictionary=bindings.first_flight;bindings.first_flight={}
		check(not flight.prepare(bindings,cat,packet,input,1789100000) and flight.snapshot()==state,"Missing capability changed prepared flight")
		bindings.first_flight=rules
	check(yaws.size()==2,"Fixtures did not cover both source yaw signs")
	flight.clear();check(flight.snapshot().is_empty() and flight.scenery_owner()==null,"Clear retained a prepared world")

func validate(data: Dictionary, bindings: RefCounted, bytes: int) -> String:
	return Definitions.validate(data,bytes,"x86_64",bindings.arrival_staging,bindings.station_departure,bindings.arrival_environment,bindings.arrival_world_initialization)
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
