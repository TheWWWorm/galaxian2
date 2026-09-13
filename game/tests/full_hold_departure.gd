extends SceneTree
## Mac-only departure contracts. The station-return integration separately
## reaches this state through native drilling, docking and acknowledgement.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/full_hold_departure_definitions.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
var failures:=0
var checks:=0

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==2,"Expected explicit Mac content and bindings")
	if args.size()==2:verify(args)
	print("Full-hold departure: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(header.architecture=="x86_64","This test requires the Mac profile")
	var player:=Player.new()
	if bindings.full_hold_departure.is_empty():
		check(not player.configure_departure(bindings,cat,4) and player.snapshot().is_empty(),"Legacy import invented second departure")
		check(player.configure_departure(bindings,cat) and player.snapshot().campaign_cursor==2,"Legacy first departure regressed")
		return
	var data: Dictionary=bindings.full_hold_departure
	check(Definitions.validate(data,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.station_departure,bindings.station_return).is_empty(),"Second departure declarations were refused")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed second departure parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.station_departure,bindings.station_return).is_empty(),"Detached second departure provenance accepted: "+key)
	check(not Definitions.validate(data,header.source_executable_bytes,header.architecture,{},bindings.station_departure,bindings.station_return).is_empty(),"Missing source anchor accepted")
	check(not Definitions.validate(data,header.source_executable_bytes,header.architecture,bindings.arrival_staging,{},bindings.station_return).is_empty(),"Missing first departure accepted")
	check(not Definitions.validate(data,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.station_departure,{}).is_empty(),"Missing acknowledged return accepted")
	var first:=Player.new();check(first.configure_departure(bindings,cat),first.error)
	check(player.configure_departure(bindings,cat,4),player.error)
	var actual:=player.snapshot();var previous:=first.snapshot();previous.campaign_cursor=4
	check(actual==previous and actual.vitals=={"hull":95,"armor":0,"shield":0.0} and actual.gamma==100.0,"Second departure changed the native starter capacities or loadout")
	var loadout:=Loadout.new();check(loadout.configure_station(bindings,cat,bindings.base_content_id),loadout.error)
	var seed:=loadout.snapshot();var pools: Dictionary=bindings.opening_actors.player_initialization.flight_cache
	var reset:=Cache.departure_cache(pools,data,seed,actual.max_hull,actual.capacities,true)
	check(Cache.matches(reset,seed,4) and reset.values=={"hull":-1,"armor":-1,"shield":-1,"gamma":-1},"Second departure did not clear every retained pool")
	check(Cache.matches(player.cache_snapshot(),seed,4) and player.cache_snapshot().values=={"hull":95,"armor":0,"shield":0,"gamma":100},"Second departure did not refresh its normal player cache")
	var restored:=Cache.restore_values(pools,actual.max_hull,actual.capacities,reset.values)
	check(restored=={"hull":95,"armor":0,"shield":0.0,"gamma":100.0,"max_hull":95},"Source negative-cache semantics were not retained")
	var detached:=player.cache_snapshot();detached.values.hull=1
	check(player.cache_snapshot().values.hull==95,"Player cache exposed mutable state")
	for cursor in [0,1,3,5,6]:
		check(not Player.new().configure_departure(bindings,cat,cursor),"Unsupported mining departure cursor accepted")
	verify_reader(args[1],lib,header)

func verify_reader(pack: String, lib: RefCounted, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-departure-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","extent","first_departure_absent","return_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_departure")
			"wrong_type":changed.full_hold_departure=false
			"changed":changed.full_hold_departure.campaign_cursor=2
			"extent":changed.full_hold_departure.provenance.negative_pool_restore.offset+=1
			"first_departure_absent":changed.station_departure={}
			"return_absent":changed.station_return={}
			"empty":
				changed.full_hold_departure={}
				if changed.has("player_destruction"):changed.player_destruction={}
				if changed.has("game_over_presentation"):changed.game_over_presentation={}
				if changed.has("full_hold_flight"):changed.full_hold_flight={}
				if changed.has("full_hold_pirate"):changed.full_hold_pirate={}
				if changed.has("full_hold_control"):changed.full_hold_control={}
				if changed.has("full_hold_destruction"):changed.full_hold_destruction={};changed.full_hold_appearance={}
				if changed.has("full_hold_story"):changed.full_hold_story={};changed.full_hold_appearance={};changed.full_hold_return={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		if scenario=="empty":check(accepted and reader.full_hold_departure.is_empty() and not reader.station_return.is_empty(),"Explicit unsupported second departure rejected: "+reader.error)
		else:check(not accepted and reader.binding_id.is_empty() and reader.full_hold_departure.is_empty() and reader.station_return.is_empty() and reader.station_departure.is_empty(),"Invalid pack retained stale or partially committed declarations: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
