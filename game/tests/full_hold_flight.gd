extends SceneTree
const OpeningFixture=preload("res://tests/opening_handoff_fixture.gd")
## Detached Mac construction contracts. Packets below are disclosed synthetic
## departure fixtures; station_return.gd reaches one through the mining lifecycle.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/full_hold_flight_definitions.gd")
const Flight=preload("res://src/simulation/first_flight_construction.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const NPC=preload("res://src/simulation/opening_npc_construction.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const Numbers=preload("res://src/simulation/combat_vitals.gd")
const CONDITIONS={"companions_empty":true,"location_match":false,"special_placement":false}
var failures:=0
var checks:=0

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Full-hold flight: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(header.architecture=="x86_64","This test requires Mac content")
	if bindings.full_hold_flight.is_empty():
		check(not NPC.new().configure_full_hold(bindings,cat,{}) and not Route.new().configure_full_hold_generated(bindings),"Legacy pack invented the second pirate")
		if not bindings.full_hold_departure.is_empty():
			check(not Flight.new().prepare(bindings,cat,packet_fixture(bindings,cat,0),4096,1789100000),"Legacy pack reused the empty first world for cursor4")
		return
	var data: Dictionary=bindings.full_hold_flight
	check(Definitions.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_departure,bindings.first_flight,bindings.opening_actors).is_empty(),"Second-flight declaration refused")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed second-flight parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_departure,bindings.first_flight,bindings.opening_actors).is_empty(),"Detached source extent accepted: "+key)
	var packet:=packet_fixture(bindings,cat,0)
	if packet.is_empty():return
	verify_stream(bindings,cat,packet.player_cache)
	var flight:=Flight.new()
	for kills in 4:
		packet=packet_fixture(bindings,cat,kills)
		var untouched:=packet.duplicate(true)
		if not flight.prepare(bindings,cat,packet,4096,1789100000):check(false,flight.error);return
		var state:=flight.snapshot();var world: Dictionary=state.scenery.world_initialization
		check(packet==untouched and state.departure==packet and not state.activated and not state.entry_released,"Detached preparation changed the packet or activated gameplay")
		check(state.campaign_cursor==4 and state.location.campaign_cursor==4 and state.location.ship_id==0 and state.player.campaign_cursor==4,"Second flight lost its explicit cursor or starter ship")
		check(state.departure.progress.rank==int(kills>0) and state.departure.progress.rank_score==4+3*kills and state.departure.mission.source_parameter==25,"Second flight lost earned progress or its full-hold objective")
		check(state.scenery.departure_population.count==130 and state.scenery.departure_population.center==Vector3(12298,36830,77237) and state.scenery.departure_population.campaign_cursor==4,"Second trip changed source scenery or retained the first cursor")
		check(world.input_random_state.state==int(GOLDEN[0].input_state) and world.random_state.state==int(GOLDEN[0].world_state),"Full world differs from the verified field-to-NPC boundary")
		check(state.camera_input_random_state==world.random_state and state.random_state.state==int(GOLDEN[0].camera_state) and state.camera_offset==vec(GOLDEN[0].camera_offset),"Camera omitted the pirate or weapon draws")
		check(state.camera_view.eye.is_equal_approx(state.player_pose*state.camera_offset) and state.camera_view.look==state.player_pose.origin,"Second camera was not transformed by its player pose")
		var scenery: RefCounted=flight.scenery_owner();var route: RefCounted=scenery.initial_npc_route(0)
		check(route!=null and route.snapshot()==world.npc_construction.actors[0].route,"Second pirate lost its generated native route")
		if route!=null:route.advance(route.snapshot().waypoints[0])
		check(flight.snapshot()==state,"Route handoff mutated prepared flight")
		check(not Frame.new().configure(bindings,cat,lib,flight,"E",0.5),"Second construction entered the unsupported first-trip live frame")
		if kills==0:
			for key in packet:
				var bad:=packet.duplicate(true);bad.erase(key)
				check(not flight.prepare(bindings,cat,bad,4096,1789100000) and flight.snapshot()==state,"Incomplete departure partially committed: "+key)
			for scenario in ["rank","reward","mission","cache","cargo","foreign"]:
				var bad:=packet.duplicate(true)
				match scenario:
					"rank":bad.progress.rank=1
					"reward":bad.mission.reward=1
					"mission":bad.mission.source_parameter=10
					"cache":bad.player_cache.campaign_cursor=2
					"cargo":bad.cargo_used=1
					"foreign":bad.base_content_id="0".repeat(64)
				check(not flight.prepare(bindings,cat,bad,4096,1789100000) and flight.snapshot()==state,"Invalid second departure partially committed: "+scenario)
			for invalid in [-1,0.5,2147483648,"42"]:
				check(not flight.prepare(bindings,cat,packet,4096,invalid) and flight.snapshot()==state,"Invalid field time changed prepared world")
			var saved: Dictionary=bindings.full_hold_flight;bindings.full_hold_flight={}
			check(not flight.prepare(bindings,cat,packet,4096,1789100000) and flight.snapshot()==state,"Missing second capability reused the first flight")
			bindings.full_hold_flight=saved
	verify_reader(args[1],lib,header)

func verify_stream(bindings: RefCounted, cat: RefCounted, cache: Dictionary):
	var items: Array=cat.tables.items.duplicate(true)
	for fixture in GOLDEN:
		cat.tables.items=items.duplicate(true)
		if fixture.restricted:
			for item in cat.tables.items:item.arrays[0]=[1]
		var world:=World.new()
		if not world.configure_departure(bindings,cat,cache,CONDITIONS):check(false,world.error);continue
		check(world.generate({"state":-1}).is_empty() and world.snapshot().is_empty(),"Invalid RNG partially constructed the second world")
		var generated:=world.generate({"state":int(fixture.input_state)})
		if generated.is_empty():check(false,world.error);continue
		var npcs: Dictionary=generated.npc_construction
		check(npcs.actors.size()==1 and npcs.campaign_cursor==4 and generated.campaign_cursor==4,"Second world created a rescue or Opening population")
		var actor: Dictionary=npcs.actors[0]
		check(actor.actor_id==0 and actor.actor_kind==8 and actor.subtype==0 and actor.hull_catalogue_id==2 and actor.mode==5 and not actor.active and actor.targeting_blocked,"Second pirate factory state changed")
		check(actor.body_pose==Transform3D(Basis.IDENTITY,Vector3(0,0,-200000)) and actor.statistics_pose==actor.body_pose,"Second pirate placement changed")
		check(actor.factory_position==vec(fixture.spawn) and actor.route.candidate_indices==fixture.indices and actor.route.campaign_cursor==4,"Factory/route draw order changed")
		for i in fixture.waypoints.size():check(actor.route.waypoints[i]==vec(fixture.waypoints[i]),"Generated route coordinates changed")
		check(actor.discarded_cargo.is_empty() and actor.cargo==fixture.cargo,"Second pirate discarded cargo or generated it in a different order")
		check(actor.fragments.size()==fixture.fragments.size(),"Fragment count changed")
		for i in fixture.fragments.size():
			var f: Array=fixture.fragments[i];var rotation:=Vector3.ZERO
			for axis in 3:rotation[axis]=Numbers.single(Numbers.single(float(f[axis])/180.0)*3.1415927410125732)
			check(actor.fragments[i].rotation_radians==rotation and actor.fragments[i].scale==Numbers.single(float(f[3])/100.0),"Fragment construction changed float precision or draw order")
		check(npcs.random_state.state==int(fixture.npc_state) and generated.random_state.state==int(fixture.world_state),"NPC/effect boundary differs from independent arithmetic")
		var effects: Array=generated.weapon_effects
		check(effects.size()==1 and effects[0].discarded_default=={"item_id":0,"resource_id":14600,"flipped":fixture.flips[0]} and effects[0].primary=={"item_id":19,"resource_id":14605,"flipped":fixture.flips[1]},"Second pirate weapon effects changed")
		var held:=world.snapshot();generated.npc_construction.actors[0].cargo.clear();generated.weapon_effects.clear()
		check(world.snapshot()==held and world.generate({"state":0}).is_empty(),"World exposed mutable records or regenerated an existing pirate")
	cat.tables.items=items
	for key in CONDITIONS:
		var bad:=CONDITIONS.duplicate();bad[key]=not bad[key]
		check(not World.new().configure_departure(bindings,cat,cache,bad),"Unsupported world condition accepted: "+key)
	var first:=Player.new();check(first.configure_departure(bindings,cat),first.error)
	check(not NPC.new().configure_full_hold(bindings,cat,first.cache_snapshot()),"Second pirate accepted the first trip's cache")
	var original: int=cat.tables.items[90].arrays[2][5]
	for kind in [18,33,39]:
		cat.tables.items[90].arrays[2][5]=kind
		check(not World.new().configure_departure(bindings,cat,cache,CONDITIONS),"Changed starter equipment silently omitted extra cargo or actors")
	cat.tables.items[90].arrays[2][5]=original

func packet_fixture(bindings: RefCounted, cat: RefCounted, kills: int) -> Dictionary:
	var loadout:=Loadout.new();var player:=Player.new()
	if not loadout.configure_station(bindings,cat,bindings.base_content_id) or not player.configure_departure(bindings,cat,4):check(false,loadout.error+player.error);return {}
	var seed:=loadout.snapshot();var current:=player.snapshot();var rules: Dictionary=bindings.full_hold_departure
	var reset:=Cache.departure_cache(bindings.opening_actors.player_initialization.flight_cache,rules,seed,current.max_hull,current.capacities,true)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":4,
		"source_state":2,"world_type":3,"audio_selector":1,"confirmation_required":true,"confirmation_text_id":386,
		"loadout":seed,"reset_cache":reset,"player_cache":player.cache_snapshot(),"player":current,
		"progress":OpeningFixture.progress(bindings,4,kills),
		"mission":{"kind":154,"station_id":78,"reward":0,"bonus":0,"source_parameter":25},"cargo_used":0,"source_ship_configuration":8}

func verify_reader(pack: String, lib: RefCounted, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-flight-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","extent","departure_absent","first_absent","npc_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_flight")
			"wrong_type":changed.full_hold_flight=false
			"changed":changed.full_hold_flight.actor_count=0
			"extent":changed.full_hold_flight.provenance.actor_dispatch.offset+=1
			"departure_absent":changed.full_hold_departure={}
			"first_absent":changed.first_flight={}
			"npc_absent":changed.opening_actors.npc_initialization.construction={}
			"empty":
				changed.full_hold_flight={}
				if changed.has("player_destruction"):changed.player_destruction={}
				if changed.has("game_over_presentation"):changed.game_over_presentation={}
				if changed.has("full_hold_pirate"):changed.full_hold_pirate={}
				if changed.has("full_hold_control"):changed.full_hold_control={}
				if changed.has("full_hold_destruction"):changed.full_hold_destruction={};changed.full_hold_appearance={}
				if changed.has("full_hold_story"):changed.full_hold_story={};changed.full_hold_appearance={};changed.full_hold_return={}
				# Remove dependent optional capabilities when testing a pack that
				# deliberately omits the entire second-flight construction.
				for key in ["full_hold_particles","station_equipment","combat_training","combat_training_control","combat_training_weapons","combat_training_destruction","combat_training_story","combat_training_visuals","mido_travel","ambient_population","ambient_combat","ambient_lifecycle","freighter_destruction","early_contracts"]:
					if changed.has(key):changed[key]={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		if scenario=="empty":check(accepted and reader.full_hold_flight.is_empty() and not reader.full_hold_departure.is_empty(),"Optional empty capability was not preserved: "+reader.error)
		else:check(not accepted and reader.binding_id.is_empty() and reader.full_hold_flight.is_empty() and reader.first_flight.is_empty(),"Invalid reopen exposed stale or partially staged declarations: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])
func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
const GOLDEN := [{"input_state":153548941033574,"restricted":false,"spawn":[14720,13852,-11917],"indices":[3,2],"waypoints":[[-22286,-6119,67295],[28952,-5937,64869]],"cargo":[{"item_id":112,"quantity":1},{"item_id":118,"quantity":8}],"fragments":[[113,108,66,93],[268,200,15,94],[148,13,186,83],[250,100,287,53],[262,126,191,94],[194,134,327,91],[322,246,15,94],[271,285,40,62]],"npc_state":266336588563691,"flips":[[true,false,false,false],[false,true,true,false]],"world_state":205194410392979,"camera_offset":[1725,-1418,9000],"camera_state":94536913334471,"draws":95},{"input_state":25214903917,"restricted":false,"spawn":[1360,5948,8029],"indices":[3,0,1,2],"waypoints":[[-17527,-5738,61095],[-13553,-6485,26053],[9491,-239,38719],[12854,-8923,62677]],"cargo":[{"item_id":124,"quantity":3}],"fragments":[[195,200,295,55],[290,118,291,74],[16,352,222,69],[237,176,246,57],[16,88,17,93],[187,107,268,55]],"npc_state":203325453775594,"flips":[[false,false,true,true],[true,true,true,true]],"world_state":1262582287474,"camera_offset":[572,-1957,9000],"camera_state":98071573474966,"draws":75},{"input_state":25214903916,"restricted":false,"spawn":[8985,-15412,-18153],"indices":[3,1,0],"waypoints":[[-14683,-8737,75562],[9434,-3394,34978],[-9687,-5746,34904]],"cargo":[{"item_id":109,"quantity":8},{"item_id":118,"quantity":3}],"fragments":[[0,151,286,83],[358,156,308,64],[185,128,19,66],[55,58,162,87],[312,211,81,97],[128,162,161,58],[165,29,299,95]],"npc_state":76365784130308,"flips":[[false,true,false,true],[true,false,false,false]],"world_state":165014251136460,"camera_offset":[-1601,-1101,9000],"camera_state":74634579166096,"draws":100},{"input_state":25214903917,"restricted":true,"spawn":[1360,5948,8029],"indices":[3,0,1,2],"waypoints":[[-17527,-5738,61095],[-13553,-6485,26053],[9491,-239,38719],[12854,-8923,62677]],"cargo":[{"item_id":156,"quantity":4}],"fragments":[[113,9,5,91],[310,125,302,94],[99,277,191,71],[263,217,178,66],[311,35,101,86]],"npc_state":273579637062338,"flips":[[true,false,true,false],[false,false,false,true]],"world_state":71923982694218,"camera_offset":[1575,655,9000],"camera_state":238769734758126,"draws":163}]
