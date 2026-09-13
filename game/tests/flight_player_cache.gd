extends SceneTree
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Definitions=preload("res://src/content/flight_player_cache_definitions.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0

func _initialize():
	verify_numbers()
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visual triples")
	for i in range(0,args.size()-2,3):verify_profile(args[i],args[i+1])
	print("Flight player cache: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_numbers():
	var parameters:=Definitions.VALUES.duplicate(true);parameters.provenance={}
	var capacities:={"armor":250,"shield":220}
	var cached:={"hull":-1,"armor":-1,"shield":-1,"gamma":-1}
	check(Cache.restore_values(parameters,200,capacities,cached)=={"hull":200,"max_hull":200,"armor":250,"shield":220.0,"gamma":100.0},"Negative cache overwrote fresh pools")
	for key in cached:cached[key]=0
	check(Cache.restore_values(parameters,200,capacities,cached)=={"hull":0,"max_hull":200,"armor":0,"shield":0.0,"gamma":0.0},"Zero cache was treated as absent")
	cached={"hull":500,"armor":300,"shield":300,"gamma":200}
	check(Cache.restore_values(parameters,200,capacities,cached)=={"hull":500,"max_hull":500,"armor":250,"shield":220.0,"gamma":100.0},"Pool-specific clamp or hull maximum differs")
	cached={"hull":199,"armor":249,"shield":219,"gamma":9999999}
	check(Cache.restore_values(parameters,200,capacities,cached)=={"hull":199,"max_hull":200,"armor":249,"shield":219.0,"gamma":9999999.0},"Restoration lost partial pools or the gamma sentinel")
	capacities.shield=16777219;cached.shield=16777217
	check(Cache.restore_values(parameters,200,capacities,cached).shield==16777216.0,"Shield conversion lost binary32 rounding")
	capacities.shield=16777217;cached.shield=16777219
	check(Cache.restore_values(parameters,200,capacities,cached).shield==16777216.0,"Shield clamp used unrounded integer capacity")
	for key in cached:
		for value in [true,0.0,NAN,INF,-2147483649,2147483648,null]:
			var bad:=cached.duplicate();bad[key]=value
			check(Cache.restore_values(parameters,200,capacities,bad).is_empty(),"Invalid cached field accepted: "+key)
		var missing:=cached.duplicate();missing.erase(key)
		check(Cache.restore_values(parameters,200,capacities,missing).is_empty(),"Missing cached field accepted")
	cached={"hull":2147483647,"armor":2147483647,"shield":2147483647,"gamma":2147483647}
	check(Cache.restore_values(parameters,200,capacities,cached).hull==2147483647,"Valid signed hull maximum rejected")
	for key in cached:cached[key]=-2147483648
	check(Cache.restore_values(parameters,200,capacities,cached).hull==200,"Signed minimum was not an absent cache value")
	parameters.hull_cache_raises_max=false
	check(Cache.restore_values(parameters,200,capacities,cached).is_empty(),"Unknown cache rule accepted")

func verify_profile(content: String, pack: String):
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);return
	var owner:=Player.new();check(owner.configure(bindings,catalogues),owner.error)
	var original: Dictionary=owner.snapshot()
	if bindings.opening_actors.player_initialization.get("flight_cache",{}).is_empty():
		check(owner.cache_snapshot().is_empty(),"Legacy player invented cache values")
		check(not owner.configure_arrival(bindings,catalogues,{}) and owner.snapshot().is_empty(),"Legacy profile entered unsupported rescue")
		return
	var cached: Dictionary=owner.cache_snapshot();var arrival:=Player.new()
	check(original.vitals.hull==9999999 and original.max_hull==9999999 and cached.values=={"hull":200,"armor":250,"shield":220,"gamma":100},"Opening override leaked into the ordinary ship cache")
	check(cached.campaign_cursor==0 and cached.station_id==78 and cached.ship_id==10,"Fresh cache has the wrong scene, ship or location")
	check(arrival.configure_arrival(bindings,catalogues,cached),arrival.error)
	var restored: Dictionary=arrival.snapshot()
	check(restored.vitals=={"hull":200,"armor":250,"shield":220.0} and restored.max_hull==200 and restored.gamma==100.0 and restored.campaign_cursor==1,"Rescue did not rebuild the normal player pools")
	check(restored.repair.max_hull==200 and restored.recharge.capacity==220,"Repair/recharge retained opening capacities")
	check(arrival.cache_snapshot().campaign_cursor==1 and arrival.cache_snapshot().values==cached.values,"Rescue entry did not refresh its cache from the retained ship")
	check(owner.snapshot()==original and owner.cache_snapshot()==cached,"Restoring rescue changed the opening owner")
	var fork: RefCounted=owner.fork_for_frame()
	var detached: Dictionary=owner.cache_snapshot();detached.values.hull=0;detached.equipment_ids.clear()
	check(owner.cache_snapshot()==cached and fork.cache_snapshot()==cached,"Cache snapshots or forks alias their source")
	var damaged:=cached.duplicate(true);damaged.values={"hull":123,"armor":42,"shield":17,"gamma":0}
	check(arrival.configure_arrival(bindings,catalogues,damaged),arrival.error)
	check(arrival.snapshot().vitals=={"hull":123,"armor":42,"shield":17.0} and arrival.snapshot().gamma==100.0 and arrival.cache_snapshot().values.hull==200,"Restoration, gamma reset and subsequent cache refresh lost their separate values")
	var earlier: Dictionary=arrival.snapshot()
	check(arrival.advance_recharge(0).size()>0 and arrival.advance_repair(0).size()>0 and arrival.snapshot().vitals==earlier.vitals,"Shared ordinary update owners cannot use restored pools")
	for key in ["base_content_id","binding_id","ship_id","station_id","system_id","equipment_ids","campaign_cursor","values"]:
		var wrong:=cached.duplicate(true)
		match key:
			"base_content_id","binding_id":wrong[key]="f".repeat(64)
			"ship_id","station_id","system_id","campaign_cursor":wrong[key]+=1
			"equipment_ids":wrong.equipment_ids.reverse()
			"values":wrong.values.shield=0.5
		check(not arrival.configure_arrival(bindings,catalogues,wrong) and arrival.snapshot().is_empty() and arrival.cache_snapshot().is_empty(),"Rejected cache retained a player: "+key)
	check(not arrival.configure_arrival(bindings,catalogues,[]) and arrival.snapshot().is_empty(),"Non-object cache accepted")
	check(fork.cache_snapshot()==cached and fork.snapshot()==original,"Failed rescue attempt changed another frame")
	check(owner.configure(bindings,catalogues) and owner.cache_snapshot()==cached,"Fresh run retained a changed cache")
	verify_definitions(pack,library,bindings)
	owner.clear();check(owner.snapshot().is_empty() and owner.cache_snapshot().is_empty(),"Clear retained flight cache")

func verify_definitions(pack: String, library: RefCounted, bindings: RefCounted):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var data: Dictionary=bindings.opening_actors.player_initialization.flight_cache
	check(Definitions.validate(data,header.source_executable_bytes,header.architecture,bindings.opening_loadout,bindings.opening_actors,bindings.arrival_staging).is_empty(),"Source cache declarations rejected")
	for key in data.provenance:
		var changed:=data.duplicate(true);changed.provenance[key].offset+=2
		check(not Definitions.validate(changed,header.source_executable_bytes,header.architecture,bindings.opening_loadout,bindings.opening_actors,bindings.arrival_staging).is_empty(),"Detached cache provenance accepted")
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-flight-cache-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var scenarios:=["missing","wrong_type","changed","no_arrival","empty"]
	if not body.get("station_departure",{}).is_empty():scenarios.append("departure_without_context")
	for scenario in scenarios:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.opening_actors.player_initialization.erase("flight_cache")
			"wrong_type":changed.opening_actors.player_initialization.flight_cache=false
			"changed":changed.opening_actors.player_initialization.flight_cache.gamma_full=101
			"no_arrival":changed.arrival_staging={}
			"empty","departure_without_context":
				changed.opening_actors.player_initialization.flight_cache={}
				# Remove the complete dependent progression branch. Retaining new
				# mining or combat declarations would make this an inconsistent
				# pack instead of an explicitly unsupported-cache fixture.
				var departure: Dictionary=changed.get("station_departure",{}).duplicate(true)
				for key in changed:
					if key in ["opening_handoff","arrival_session","arrival_environment","arrival_actor_motion","arrival_actor_construction","arrival_world_initialization","player_destruction","game_over_presentation","flight_notices"] or str(key).begins_with("station_") or str(key).begins_with("first_flight") or str(key).begins_with("mining_") or str(key).begins_with("full_hold_") or str(key).begins_with("combat_training"):
						changed[key]={}
				if scenario=="departure_without_context":changed.station_departure=departure

		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,library.manifest),reader.error)
		var accepted:=reader.open(directory,library.manifest)
		if scenario=="empty":check(accepted and reader.opening_actors.player_initialization.flight_cache.is_empty(),"Explicit unsupported cache rejected: "+reader.error)
		else:check(not accepted and reader.opening_actors.is_empty() and reader.arrival_staging.is_empty(),"Failed pack retained cache: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(value: bool, message: String):
	checks+=1
	if not value:failures+=1;printerr(message)
