extends SceneTree
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0

func _initialize():call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected one Mac content/bindings/visual triple")
	if args.size()==3:verify_profile(args[0],args[1])
	print("Opening handoff: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_profile(content: String,pack: String):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var handoff:=Handoff.new()
	if bindings.opening_handoff.is_empty():
		check(handoff.prepare(bindings,cat,{}).is_empty() and handoff.error.contains("unavailable"),"Legacy pack fabricated handoff support")
		return
	var player:=Player.new();check(player.configure(bindings,cat),player.error)
	for credits in 4:
		var opening:=fixture(bindings,player,credits)
		var before:=opening.duplicate(true)
		var packet:=handoff.prepare(bindings,cat,opening)
		check(not packet.is_empty(),handoff.error)
		if packet.is_empty():continue
		check(opening==before and player.cache_snapshot()==opening.world_frame.player_cache,"Preparing entry consumed or changed the Opening")
		check(packet.progress.rank_score==credits*3+1 and packet.progress.rank==(0 if credits<2 else 1),"Retained kill totals selected the wrong rescue rank")
		check(packet.progress.player_kills==credits and packet.progress.pirate_kills==credits and packet.progress.other_score==0,"Handoff invented unsupported score or lost earned credit")
		check(packet.previous_cache.campaign_cursor==0 and packet.player_cache.campaign_cursor==1 and packet.campaign_cursor==1,"Handoff lost its scene cursor boundary")
		check(packet.player.vitals=={"hull":200,"armor":250,"shield":220.0} and packet.player.gamma==100.0,"Rescue used live cinematic damage instead of its retained cache")
		check(packet.entry_conditions=={"companions_empty":true,"location_match":false},"Handoff invented a free-roam preference or changed its location/companions")
		check(not packet.rescue_disposition.actor_hostile and packet.rescue_disposition.minimum==-credits*2 and packet.rescue_disposition.maximum==credits*2,"Neutral rescue actor was not established from source bounds")
		check(handoff.prepare(bindings,cat,opening)==packet,"Repeating preparation changed the resulting flight")
		packet.previous_cache.values.hull=1;packet.player_cache.values.hull=2;packet.progress.player_kills=99
		check(handoff.prepare(bindings,cat,opening).player.vitals.hull==200 and opening==before,"Caller mutation changed the retained world")
		if credits==3:
			packet=handoff.prepare(bindings,cat,opening)
			var scenery:=Scenery.new()
			check(scenery.configure_arrival(bindings,cat,packet.player_cache,packet.entry_conditions,1789100000) and scenery.complete_world_initialization(bindings,cat),scenery.error)
			check(scenery.snapshot().objects.size()==130 and scenery.arrival_motion_construction().actor_id==0,"Actual handoff did not initialize the rescue field and actor")
	var valid:=fixture(bindings,player,3)
	for scenario in ["early","missing_cache","foreign_cache","live_dead","duplicate","totals","attribution","radio","foreign_world","loadout"]:
		var bad:=valid.duplicate(true)
		match scenario:
			"early":bad.escape.boundary=""
			"missing_cache":bad.world_frame.erase("player_cache")
			"foreign_cache":bad.world_frame.player_cache.binding_id="foreign"
			"live_dead":bad.world_frame.player.vitals.hull=0
			"duplicate":bad.world_frame.controller.death_accounting.events[1]=bad.world_frame.controller.death_accounting.events[0]
			"totals":bad.world_frame.controller.death_accounting.counter_deltas.player_kills=4
			"attribution":bad.combat.actors[0].nonplayer_kill=true
			"radio":bad.radio.finished[22]=false
			"foreign_world":bad.world_frame.binding_id="foreign"
			"loadout":bad.world_frame.player.equipment_ids[0]=0
		var before:=bad.duplicate(true)
		check(handoff.prepare(bindings,cat,bad).is_empty() and not handoff.error.is_empty() and bad==before,"Invalid handoff changed or accepted "+scenario)
		check(not handoff.prepare(bindings,cat,valid).is_empty(),"Failed handoff poisoned later valid preparation")
	verify_packs(pack,lib.manifest)

func fixture(bindings: RefCounted,player: RefCounted,credits: int) -> Dictionary:
	var result:=Fixture.completed(bindings,player,credits)
	check(not result.is_empty(),"Opening handoff fixture could not complete its death accounting")
	return result

func verify_packs(pack: String,base: Dictionary):
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-handoff-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var scenarios:=["missing","threshold","extent","empty"]
	if original.has("arrival_session"):scenarios.append("empty_dependencies")
	for scenario in scenarios:
		var body:=original.duplicate(true);var header:=metadata.duplicate(true)
		match scenario:
			"missing":body.erase("opening_handoff")
			"threshold":body.opening_handoff.rank_thresholds[1]=6
			"extent":body.opening_handoff.provenance.rank_calculation.offset+=1
			"empty":body.opening_handoff={}
			"empty_dependencies":body.opening_handoff={};body.arrival_session={}
		var serialized:=JSON.stringify(body,"",true,true)
		header.records_sha256=serialized.sha256_text();header.records_bytes=serialized.to_utf8_buffer().size()
		header.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[header.base_content_id,header.source_executable_sha256,header.architecture,header.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(header));file.close()
		var reader:=Bindings.new();check(reader.open(pack,base),reader.error)
		var accepted:=reader.open(directory,base)
		var optional_empty: bool=scenario=="empty_dependencies" or (scenario=="empty" and original.get("arrival_session",{}).is_empty())
		check(accepted==optional_empty,"Binding reader mishandled handoff "+scenario+": "+reader.error)
		check(reader.opening_handoff.is_empty(),"Replacement retained an old handoff capability")
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(condition: bool,message: String):
	checks+=1
	if not condition:failures+=1;push_error(message)
