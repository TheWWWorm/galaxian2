extends SceneTree
const Station=preload("res://src/simulation/station_entry.gd")
const Definitions=preload("res://src/content/station_entry_definitions.gd")
const World=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
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
	print("First station entry: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):
		check(false,lib.error+bindings.error+cat.error);return
	var source_bytes:=int(JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json"))).source_executable_bytes)
	var station:=Station.new()
	if bindings.station_entry.is_empty():
		check(not station.configure(bindings,cat,lib,{}),"Legacy pack fabricated a first station");return
	check(Definitions.validate(bindings.station_entry,source_bytes,"x86_64",bindings.arrival_staging,bindings.arrival_session).is_empty(),"Real station declaration schema failed")
	var player:=Player.new();var handoff:=Handoff.new()
	check(player.configure(bindings,cat),player.error)
	var entry:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var world:=World.new()
	if not world.configure(bindings,cat,lib,entry,[1,1,1],1789100000):check(false,world.error);return
	check(world.prepare_station().is_empty(),"Rescue entered station before its first frame")
	for i in 500:
		var next: RefCounted=world.evaluate(100)
		if next==null:check(false,world.error);return
		world=next
		if not world.snapshot().boundary.is_empty():break
	var end:=world.snapshot()
	var packet:=world.prepare_station()
	check(not packet.is_empty(),world.error)
	if packet.is_empty():return
	check(world.prepare_station()==packet and world.snapshot()==end,"Preparing station changed the committed rescue")
	for credit in 4:
		packet.rescue_entry=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,credit))
		var before:=packet.duplicate(true)
		check(station.configure(bindings,cat,lib,packet),station.error)
		var initial:=station.snapshot()
		check(initial.loadout.ship_id==0 and initial.loadout.station_id==78 and initial.loadout.system_id==15,"Station selected an incorrect starter ship or location")
		check(initial.loadout.equipment_ids==[90,81] and initial.source_marked_item_ids==[90,81],"Station retained the damaged ship's equipment or lost source markings")
		check(initial.loadout.slots.filter(func(slot):return slot!=null).all(func(slot):return slot.category==3 and slot.quantity==1),"Starter items were assigned to the wrong slot categories")
		check(initial.source_ship_configuration==8 and initial.display_ship_configuration==3,"Source ship configuration parameters were discarded")
		check(initial.campaign_cursor==1 and initial.progress==before.rescue_entry.progress and initial.reward_credits==0 and not initial.mining_completed,"Entering the station fabricated progression or rewards")
		check(initial.dialogue.text_id==1678 and initial.dialogue.speaker_id==0 and initial.dialogue.count==19,"Station conversation began with the wrong source line")
		check(not station.previous() and station.snapshot()==initial,"First line allowed backwards underflow")
		for i in 19:
			var line:=station.snapshot()
			check(line.dialogue.text_id==1678+i and line.dialogue.text==lib.strings[1678+i],"Station reordered or invented a dialogue line")
			check(line.campaign_cursor==1 and not line.acknowledged,"Story progressed before the final acknowledgement")
			if i==1:
				check(station.previous() and station.snapshot().dialogue.text_id==1678,"Previous line did not restore the source text")
				check(station.acknowledge() and station.snapshot().dialogue.text_id==1679,"Revisiting a line skipped a conversation step")
				line=station.snapshot()
				check(line.dialogue.speaker_name=="Gunant Breh","Speaker name came from another content binding")
			check(station.acknowledge(),station.error)
		var done:=station.snapshot()
		check(done.campaign_cursor==2 and done.acknowledged and done.phase=="ready_to_launch" and not done.dialogue.visible,"Final acknowledgement did not retire the first conversation")
		check(done.mission=={"kind":154,"station_id":78,"reward":0,"bonus":0,"source_parameter":10},"Next mission does not match its source declaration")
		check(done.progress.player_kills==credit and done.progress.pirate_kills==credit and done.progress.rank_score==initial.progress.rank_score+1 and done.progress.rank==initial.progress.rank,"Station acknowledgement lost kill credit or miscomputed story score")
		check(done.reward_credits==0 and not done.mining_completed and done.loadout==initial.loadout and packet==before,"Dialogue granted unearned rewards, changed the loadout or mutated the rescue")
		check(not station.acknowledge() and not station.previous() and station.snapshot()==done,"Repeated acknowledgement granted progression twice")
		done.loadout.equipment_ids.clear();done.progress.player_kills=999
		check(station.snapshot().loadout.equipment_ids==[90,81] and station.snapshot().progress.player_kills==credit,"Caller mutated owned station state")
	for key in ["foreign","state","cursor","early","fade","cache","progress","missing","extra"]:
		var bad:=packet.duplicate(true)
		match key:
			"foreign":bad.binding_id="a".repeat(64)
			"state":bad.source_state=2
			"cursor":bad.campaign_cursor=2
			"early":bad.rescue_finished.finished[2]=false
			"fade":bad.rescue_finished.fade_active=true
			"cache":bad.rescue_entry.player_cache.values.hull=1
			"progress":bad.rescue_entry.progress.rank_score=999
			"missing":bad.erase("rescue_entry")
			"extra":bad.earned_reward=100
		check(not station.configure(bindings,cat,lib,bad) and station.snapshot().is_empty(),"Invalid station packet accepted: "+key)
	for key in Definitions.SPANS:
		var data: Dictionary=bindings.station_entry.duplicate(true);data.provenance[key].offset+=1
		check(not Definitions.validate(data,source_bytes,"x86_64",bindings.arrival_staging,bindings.arrival_session).is_empty(),"Invalid source span accepted: "+key)
	for kind in ["text","speaker","reward","cursor","boolean","extra"]:
		var altered: Dictionary=bindings.station_entry.duplicate(true)
		match kind:
			"text":altered.dialogue.events[0].text_id=1679
			"speaker":altered.dialogue.events[0].speaker_id=2
			"reward":altered.mission.reward=100
			"cursor":altered.mission.cursor_after_acknowledgement=3
			"boolean":altered.dialogue.acknowledgement_required=1
			"extra":altered.dialogue.events[0].auto_finish_ms=1
		check(not Definitions.parameters(altered),"Unverified nested station data accepted: "+kind)
	var original: Dictionary=bindings.station_entry
	bindings.station_entry={}
	check(not station.configure(bindings,cat,lib,packet),"Missing station capability invented a starter loadout")
	bindings.station_entry=original
	var seen:=[]
	for language in lib.manifest.languages:
		check(lib.select_language(language) and station.configure(bindings,cat,lib,packet),lib.error+station.error)
		for i in 19:
			var line:=station.snapshot()
			check(line.language==language and line.dialogue.text==lib.strings[1678+i],"Station used another language's text")
			check(station.acknowledge(),station.error)
		seen.append(language)
	print("Verified Mac languages: ",seen)

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
