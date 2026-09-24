extends SceneTree
## Destination construction from native travel and inventory owners. Station
## conversation release is an explicit fixture, not an earned full journey.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/mido_travel_definitions.gd")
const Travel=preload("res://src/simulation/local_travel.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Planets=preload("res://src/simulation/opening_planet_layout.gd")
const Exterior=preload("res://src/content/station_exterior_resources.gd")
const Volumes=preload("res://src/content/station_collision_volumes.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Briefing=preload("res://src/simulation/mining_briefing.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const StationEntry=preload("res://src/simulation/station_entry.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	verify_spheres()
	if args.size()==3:verify(args)
	print("Mido arrival: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_spheres() -> void:
	var center:=Vector3(19,20,30)
	check(Volumes.contains_sphere(center,center,1902),"Sphere rejected its center")
	for axis in 3:
		for direction in [-1,1]:
			var point:=center;point[axis]+=direction*1902
			check(not Volumes.contains_sphere(point,center,1902),"Sphere included its exact boundary")
			point[axis]-=direction*0.01
			check(Volumes.contains_sphere(point,center,1902),"Sphere excluded an interior point")
			point[axis]+=direction*0.02
			check(not Volumes.contains_sphere(point,center,1902),"Sphere included an outside point")
	check(not Volumes.contains_sphere(Vector3(NAN,0,0),center,1902),"Sphere accepted a nonfinite point")
	check(not Volumes.contains_sphere(center,center,0),"An empty sphere accepted a point")
	var values:=[79,12,2,1,20,30,40,-2,-3,-4,0,-5955,5918,0,-3804]
	var bytes:=PackedByteArray();bytes.resize(values.size()*4)
	for i in values.size():bytes.encode_s32(i*4,values[i])
	var reader:=Volumes.new()
	check(reader.decode(bytes,79,136).is_empty(),"An earlier box-only profile accepted spheres")
	var shapes:=reader.decode(bytes,79,136,0.5)
	check(not shapes.is_empty(),reader.error)
	if shapes.is_empty():return
	check(shapes.shapes.size()==2 and shapes.boxes.size()==1 and shapes.spheres.size()==1,"Mixed records lost their shape order")
	check(shapes.shapes[1]=={"kind":0,"center":Vector3(5955,0,5918),"radius":1902.0},"Sphere coordinate mapping or source half-radius differs")
	for changed in [bytes.slice(0,bytes.size()-4),bytes+PackedByteArray([0,0,0,0])]:
		check(reader.decode(changed,79,136,0.5).is_empty(),"Malformed mixed collision extent accepted")
	var changed:=bytes.duplicate();changed.encode_s32(8,3)
	check(reader.decode(changed,79,136,0.5).is_empty(),"Collision shape count overran its record")
	changed=bytes.duplicate();changed.encode_s32(40,2)
	check(reader.decode(changed,79,136,0.5).is_empty(),"An unsupported collision kind was guessed")

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):
		check(false,library.error+bindings.error+cat.error);return
	if bindings.mido_travel.is_empty():
		check(Definitions.flight(bindings,79).is_empty(),"Earlier bindings invented the destination world");return
	check(not Definitions.flight(bindings,78).has("actor_count") and Definitions.flight(bindings,78).scope=="mido_var_hastra_traffic","Var Hastra received the empty Kernstal story population")
	var scenario:=Scenario.new()
	var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	if not equipment.prepare_training_completion(bindings,cat) or not equipment.complete_training(equipment.snapshot().cargo) or not equipment.apply_station_exchange(bindings,cat,9):check(false,equipment.error);return
	var original: Dictionary=equipment.snapshot()
	# This component enters cursor ten explicitly. The session integration
	# separately earns the training return and narrator exchange before travel.
	var earned: Dictionary=scenario.document.station_after.progress
	var progress:=Career.calculate_progress(bindings.opening_handoff,10,earned.player_kills,earned.pirate_kills,earned.other_score)
	progress.reputation=earned.reputation.duplicate(true)
	var objective:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":10,
		"mission":{"kind":11,"station_id":79,"reward":0,"bonus":0,"source_parameter":0},"progress":progress,"station_response_flags":{78:false}}
	var source_player:=Player.new()
	if not source_player.configure_local_travel(bindings,cat,equipment):check(false,source_player.error);return
	var travel:=Travel.new()
	if not travel.configure(bindings,cat,equipment,10,{"kind":11,"station_id":79,"reward":0,"bonus":0,"source_parameter":0}):check(false,travel.error);return
	var construction:=Construction.new()
	check(not construction.prepare_local_arrival(bindings,cat,travel,source_player,equipment,4096,1789100000) and construction.snapshot().is_empty(),"Arrival bypassed the travel clock")
	for i in 27:
		if not travel.sample_acquisition(150,79,79,true):check(false,travel.error);return
	for i in 21:
		if not travel.advance_launch(150):check(false,travel.error);return
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	check(not construction.prepare_local_arrival(bindings,cat,travel,source_player,equipment,4096,1789100000,true,bodies,effects),"Arrival accepted an omitted career")
	if not construction.prepare_local_arrival(bindings,cat,travel,source_player,equipment,4096,1789100000,true,bodies,effects,objective):check(false,construction.error);return
	var state:=construction.snapshot()
	var briefing:=Briefing.new();var cargo:=Cargo.new()
	check(briefing.configure(bindings,library,construction,"D"),briefing.error)
	check(cargo.configure_departure(bindings,cat,construction),cargo.error)
	check(state.departure.progress==progress and state.departure.mission==objective.mission and state.departure.cargo==original.cargo,"Arrival lost its pending mission or retained career and hold")
	check(state.campaign_cursor==10 and state.world_type==3 and state.location.station_id==79 and state.location.system_id==15,"Arrival changed the objective or destination")
	check(state.location.sky_index==9 and state.player_pose.origin==Vector3(10,10,10000),"Arrival changed the destination background or ordinary placement")
	check(state.scenery.objects.size()==156 and state.scenery.center==Vector3(-29062,30649,31103),"Kernstal scenery differs from independent source RNG vectors")
	check(state.scenery.world_initialization.npc_construction.actors.is_empty(),"Arrival invented a training or ordinary traffic cast")
	check(state.scenery.world_initialization.input_random_state==state.scenery.world_initialization.random_state,"The empty story population consumed constructor draws")
	check(not state.activated and not state.entry_released and state.entry_elapsed_ms==0,"Preparation activated or skipped the entry camera")
	check(equipment.snapshot()==original,"Detached arrival mutated the departing inventory")
	var arrived: RefCounted=construction.equipment_owner()
	var retained: Dictionary=arrived.snapshot()
	check(retained.loadout.station_id==79,"Prepared destination did not relocate its retained loadout")
	var expected:=original.duplicate(true);expected.loadout.station_id=79
	check(retained==expected,"Arrival refilled, repriced or changed cargo and equipment")
	check(not arrived.relocate_local_arrival(bindings,cat,travel.prepare_arrival()) and arrived.snapshot()==retained,"Arrival applied twice")
	check(not construction.prepare_local_arrival(bindings,cat,travel,source_player,equipment,-1,1789100000,true,bodies,effects,objective) and construction.snapshot()==state,"A failed destination replaced a valid prepared world")
	var changed:=objective.duplicate(true);changed.progress.rank_score+=1
	check(not construction.prepare_local_arrival(bindings,cat,travel,source_player,equipment,4096,1789100000,true,bodies,effects,changed) and construction.snapshot()==state,"Arrival accepted unearned rank")
	# Independent component vector: ordinary faction kills count separately
	# from pirate kills. This is not a claim that the fixture earned them.
	var advanced:=objective.duplicate(true)
	advanced.progress=Career.calculate_progress(bindings.opening_handoff,10,4,3,0)
	advanced.progress.reputation={"axes":[30,12],"override":-1}
	advanced.station_response_flags[78]=true
	var retained_world:=Construction.new()
	check(retained_world.prepare_local_arrival(bindings,cat,travel,source_player,equipment,4096,1789100000,true,bodies,effects,advanced),retained_world.error)
	check(retained_world.snapshot().departure.progress==advanced.progress and retained_world.snapshot().departure.station_response_flags=={78:true,79:false},"Arrival reset distinct counters, reputation or the departed station response")
	var retained_frame:=Frame.new()
	check(retained_frame.configure(bindings,cat,library,retained_world,"D",1.0),retained_frame.error)
	if not retained_frame.snapshot().is_empty():check(retained_frame.snapshot().station_response_flags=={78:true,79:false},"Destination reassigned the prior station's response")
	var world: Dictionary=state.scenery.world_initialization
	check(Definitions.population(bindings,world,20,.5).actor_count==0,"Empty population imposed an NPC rank range")
	for key in ["station_id","campaign_cursor","binding_id","weapon_effects"]:
		var invalid:=world.duplicate(true)
		invalid[key]={"station_id":78,"campaign_cursor":7,"binding_id":"wrong","weapon_effects":[{}]}[key]
		check(Definitions.population(bindings,invalid,1,.5).is_empty(),"Invalid empty-world context accepted: "+key)
	var planet_reader:=Planets.new()
	var layout:=planet_reader.for_departure(bindings,cat,construction.player_owner().cache_snapshot(),"high",arrived)
	check(not layout.is_empty(),planet_reader.error)
	if not layout.is_empty():
		check(layout.station_id==79 and layout.entries[5].current and layout.entries[5].scale==0.581512451171875,"Kernstal's source planet size was replaced")
	var exterior:=Exterior.new()
	if not exterior.configure(library,bindings,cat,construction):check(false,exterior.error);return
	var station:=exterior.snapshot()
	check(station.station_id==79 and station.name=="Kernstal" and station.faction==3,"Arrival reused Var Hastra's station identity")
	check(station.layers.map(func(layer):return layer.resource_id)==[21079,21879,22079],"Kernstal's original station layers were replaced")
	check(station.collision.source_offset==23352 and station.collision.source_bytes==340 and station.collision.shapes.size()==14,"Kernstal collision record lost its source extent")
	check(station.collision.boxes.size()==6 and station.collision.spheres.size()==8,"Kernstal lost its mixed collision volumes")
	check(exterior.point_volume(Vector3(5955,0,5918))==2,"Mixed collision order changed the first matching volume")
	verify_cache(bindings,source_player,original.loadout,arrived,cat)
	verify_frame(bindings,cat,library,construction)
	print("Kernstal source geometry: ",station.layers.map(func(layer):return layer.path),"; bounds ",station.bounds_half_extent)

func verify_frame(bindings: RefCounted, cat: RefCounted, library: RefCounted, construction: RefCounted) -> void:
	var frame:=Frame.new()
	if not frame.configure(bindings,cat,library,construction,"D",1.0):check(false,frame.error);return
	var initial: Dictionary=frame.snapshot()
	check(initial.actors.is_empty() and initial.encounter.weapons.actors.is_empty(),"Kernstal invented NPCs or weapons")
	check(not initial.entry_released and not initial.player.damage_allowed,"Arrival skipped its ordinary entry controller")
	check(frame.evaluate(150,Vector2.ONE,0.0,true).snapshot()==initial,"Paused arrival advanced")
	check(frame.start_station_autopilot()==null and frame.select_planet(78)==null,"Arrival accepted premature or unsupported travel")
	for i in 70:
		var next: RefCounted=frame.evaluate(100)
		if next==null:check(false,frame.error);return
		frame=next
	check(not frame.snapshot().entry_released and frame.snapshot().entry_elapsed_ms==7000,"Arrival released at exactly 7000 milliseconds")
	var released: RefCounted=frame.evaluate(1)
	if released==null:check(false,frame.error);return
	frame=released
	var current: Dictionary=frame.snapshot()
	check(current.entry_released and current.player.damage_allowed and current.phase=="flight" and not current.dialogue.visible,"Kernstal failed to release ordinary flight")
	check(current.progress==initial.progress and current.cargo==initial.cargo and current.mission==initial.mission,"Entry changed progress or inventory")
	check(current.actors.is_empty() and current.npc_scanner.markers.is_empty() and current.radio.last_serial==0,"Empty destination created targets or faction radio")
	check(not current.combat_objective_satisfied and not current.cargo_objective_satisfied and frame.prepare_station().is_empty(),"Arrival completed the visit before docking")
	var fired: RefCounted=frame.evaluate(150,Vector2(.2,-.3),.5,false,Vector2i.ZERO,Vector2.ZERO,true)
	if fired==null:check(false,frame.error);return
	check(not fired.snapshot().encounter.primary_fire.is_empty(),"Empty population disabled player weapons")
	check(fired.snapshot().progress==initial.progress and fired.snapshot().equipment.cargo==initial.cargo,"Firing awarded kills or changed the retained hold")
	var guided: RefCounted=fired.start_station_autopilot()
	check(guided!=null,fired.error)
	if guided==null:return
	check(guided.snapshot().station_autopilot.station_id==79,"Destination guidance selected Var Hastra")
	for i in 600:
		if guided.snapshot().get("boundary")=="station_transition_required":break
		var next: RefCounted=guided.evaluate(100)
		if next==null:check(false,guided.error);return
		guided=next
	var packet: Dictionary=guided.prepare_station()
	check(not packet.is_empty(),guided.error)
	if packet.is_empty():return
	check(packet.docking.station_id==79 and packet.source_state==5 and packet.progress==initial.progress and packet.cargo==initial.cargo,"Kernstal docking lost current state")
	check(guided.evaluate(100).snapshot()==guided.snapshot(),"Pending station kept advancing flight")
	var station:=StationEntry.new()
	check(station.configure_return(bindings,cat,library,guided),station.error)
	if station.snapshot().is_empty():return
	var entered: Dictionary=station.snapshot()
	check(entered.campaign_cursor==10 and entered.dialogue.count==12 and entered.dialogue.text_id==int(bindings.mido_travel.conversations[1].events[0].text_id) and entered.equipment==packet.equipment,"Kernstal station started another conversation")
	for i in 12:
		check(station.snapshot().campaign_cursor==10 and station.snapshot().cargo==initial.cargo,"An unfinished station line granted completion or discarded cargo")
		check(station.acknowledge(),station.error)
	var finished: Dictionary=station.snapshot()
	check(finished.campaign_cursor==11 and finished.mission=={"kind":11,"station_id":76,"reward":0,"bonus":0,"source_parameter":0},"Kernstal acknowledgement lost the authored next visit")
	check(finished.cargo==entered.cargo and finished.equipment==entered.equipment and finished.reward_credits==0 and finished.station_response_flags==entered.station_response_flags,"Kernstal acknowledgement granted rewards or changed retained inventory/history")
	after_local_visit(bindings,cat,library,station)

func after_local_visit(bindings: RefCounted,cat: RefCounted,_library: RefCounted,station: RefCounted) -> void:
	if bindings.mido_travel.get("continuation",{}).is_empty():
		check(station.prepare_departure(bindings,cat).is_empty(),"Unimplemented Yrdal Gedal flight was invented")
	else:check(not station.prepare_departure(bindings,cat).is_empty(),station.error)

func verify_cache(bindings: RefCounted, source_player: RefCounted, source: Dictionary, arrived: RefCounted, cat: RefCounted) -> void:
	var destination: Dictionary=arrived.snapshot().loadout
	var snapshot: Dictionary=source_player.snapshot()
	# Explicit incoming damage fixture exercises capture and restoration; it is
	# not represented as damage earned while flying the currently unsupported leg.
	snapshot.vitals.hull=31;snapshot.vitals.armor=7;snapshot.vitals.shield=0.75;snapshot.gamma=45.9
	var captured:=Cache.capture_local_arrival(bindings.mido_travel,source,destination,snapshot)
	check(not captured.is_empty() and captured.values=={"hull":31,"armor":7,"shield":0,"gamma":45},"Local arrival lost or rounded current pools incorrectly")
	var player:=Player.new()
	check(player.configure_local_travel(bindings,cat,arrived,captured),player.error)
	if player.snapshot().is_empty():return
	check(player.snapshot().vitals.hull==31 and player.snapshot().vitals.armor==7 and player.snapshot().gamma==100.0,"Ordinary arrival repaired damage or omitted its source gamma reset")
	var invalid:=captured.duplicate(true);invalid.station_id=78
	check(not Player.new().configure_local_travel(bindings,cat,arrived,invalid),"Arrival accepted the departing station cache")
	invalid=captured.duplicate(true);invalid.campaign_cursor=7
	check(not Player.new().configure_local_travel(bindings,cat,arrived,invalid),"Arrival accepted the training cursor cache")
	snapshot.vitals.hull=0
	check(Cache.capture_local_arrival(bindings.mido_travel,source,destination,snapshot).is_empty(),"A dead player entered local arrival")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr(message)
