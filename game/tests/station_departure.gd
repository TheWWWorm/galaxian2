extends SceneTree
const Station=preload("res://src/simulation/station_entry.gd")
const Definitions=preload("res://src/content/station_departure_definitions.gd")
const World=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected Mac content/bindings/visual arguments")
	if args.size()==3:verify(args)
	print("First station departure: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):
		check(false,lib.error+bindings.error+cat.error);return
	var station:=Station.new();var player:=Player.new()
	check(station.prepare_departure(bindings,cat).is_empty(),"Uninitialized station produced a departure")
	if bindings.station_departure.is_empty():
		check(not player.configure_departure(bindings,cat) and player.snapshot().is_empty(),"Legacy pack invented a mining player");return
	var source_bytes:=int(JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json"))).source_executable_bytes)
	var init: Dictionary=bindings.opening_actors.player_initialization
	check(Definitions.validate(bindings.station_departure,source_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,init).is_empty(),"Real departure source extents failed")
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.station_departure.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,source_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,init).is_empty(),"Disconnected source extent accepted: "+key)
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.station_departure.duplicate(true)
		bad[key]=false if key=="scope" else "unverified"
		check(not Definitions.parameters(bad),"Unverified departure declaration accepted: "+key)
	check(lib.strings[386]=="Depart the station?","Departure confirmation does not resolve to the original question")
	check(player.configure(bindings,cat),player.error)
	var initial:=player.snapshot()
	var handoff:=Handoff.new()
	var entry:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var world:=World.new()
	if not world.configure(bindings,cat,lib,entry,[1,1,1],1789100000):check(false,world.error);return
	for i in 500:
		var next: RefCounted=world.evaluate(100)
		if next==null:check(false,world.error);return
		world=next
		if not world.snapshot().boundary.is_empty():break
	var station_packet:=world.prepare_station()
	if station_packet.is_empty():check(false,world.error);return
	for credit in 4:
		station_packet.rescue_entry=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,credit))
		check(station.configure(bindings,cat,lib,station_packet),station.error)
		for i in 19:
			var before:=station.snapshot()
			check(station.prepare_departure(bindings,cat).is_empty() and station.snapshot()==before,"Conversation was skipped by departure")
			check(station.acknowledge(),station.error)
		var committed:=station.snapshot()
		var packet:=station.prepare_departure(bindings,cat)
		check(not packet.is_empty(),station.error)
		if packet.is_empty():return
		check(station.snapshot()==committed and station.prepare_departure(bindings,cat)==packet,"Repeated preparation changed station or awarded progress")
		check(packet.campaign_cursor==2 and packet.source_state==2 and packet.world_type==3 and packet.audio_selector==1,"Departure chose a wrong scene, world type or audio selector")
		check(packet.confirmation_required and packet.confirmation_text_id==386,"Preparation silently accepted departure confirmation")
		check(packet.loadout==committed.loadout and packet.loadout.ship_id==0 and packet.loadout.equipment_ids==[90,81],"Departure retained the opening ship or its weapons")
		check(packet.cargo_used==0 and packet.source_ship_configuration==8,"Replacement ship inherited cargo or lost its source configuration")
		check(packet.reset_cache.values=={"hull":-1,"armor":-1,"shield":-1,"gamma":-1},"Station failed to clear all four cached pools")
		check(Cache.matches(packet.reset_cache,packet.loadout,2) and Cache.matches(packet.player_cache,packet.loadout,2),"Departure caches lost identity, cursor or loadout")
		check(packet.player.ship_id==0 and packet.player.vitals.hull==cat.tables.ships[0].fields[1] and packet.player.max_hull==packet.player.vitals.hull,"Replacement ship inherited opening invulnerability or damage")
		check(packet.player.vitals.hull<initial.vitals.hull and packet.player.gamma==100 and packet.player.campaign_cursor==2,"Departure player retained opening special pools")
		check(packet.player.vitals.armor==packet.player.capacities.armor and packet.player.vitals.shield==packet.player.capacities.shield,"New ship did not enter with its equipped capacities")
		check(packet.progress==committed.progress and packet.progress.player_kills==credit and packet.mission==committed.mission,"Departure changed earned counters, rank, cursor or mission")
		check(packet.mission=={"kind":154,"station_id":78,"reward":0,"bonus":0,"source_parameter":10},"Departure fabricated a mining reward or objective")
		check(not player.configure_arrival(bindings,cat,packet.reset_cache) and player.snapshot().is_empty(),"First-departure cache was accepted as the rescue entry")
		check(player.configure_departure(bindings,cat) and player.snapshot()==packet.player and player.cache_snapshot()==packet.player_cache,"Departure player construction is not repeatable")
		var fork: RefCounted=player.fork_for_frame()
		check(fork.advance_recharge(150).size()>0 and fork.advance_repair(150).size()>0,"Replacement ship lost shared recharge/repair owners")
		check(player.snapshot()==packet.player,"Forked flight preparation mutated the committed player")
		if credit==0:print("Source departure player: ",packet.player,"; ship fields: ",cat.tables.ships[0].fields)
		packet.progress.rank=99;packet.loadout.equipment_ids.clear();packet.player.vitals.hull=0;packet.reset_cache.values.hull=500
		check(station.snapshot()==committed and station.prepare_departure(bindings,cat).player.vitals.hull>0,"Caller mutated station through departure packet")
		var saved_id: String=bindings.binding_id;bindings.binding_id="a".repeat(64)
		check(station.prepare_departure(bindings,cat).is_empty() and station.snapshot()==committed,"Foreign bindings altered station")
		bindings.binding_id=saved_id
		var rules: Dictionary=bindings.station_departure;bindings.station_departure={}
		check(station.prepare_departure(bindings,cat).is_empty() and not player.configure_departure(bindings,cat) and player.snapshot().is_empty(),"Missing declaration fabricated departure")
		bindings.station_departure=rules
		check(station.prepare_departure(bindings,cat).size()>0 and station.snapshot()==committed,"Failed preparation prevented retry")
		check(player.configure(bindings,cat),player.error)
	var source_state: Dictionary=station.snapshot()
	var clone: RefCounted=station.fork()
	check(clone.prepare_departure(bindings,cat)==station.prepare_departure(bindings,cat) and clone.snapshot()==source_state,"Station fork lost departure capability")

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
