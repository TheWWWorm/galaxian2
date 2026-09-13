extends SceneTree
## Mac second return. Reuses the disclosed close mining/cue fixture, then flies
## to the authored station with native guidance and the live pirate. Separate
## vitals, boundary and corrupt-state cases are explicitly synthetic fixtures.
const WorldFixture=preload("res://tests/full_hold_world.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Definitions=preload("res://src/content/full_hold_return_definitions.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Session=preload("res://src/presentation/station_session.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
var checks:=0
var failures:=0
var fixture: SceneTree
var lib:=Library.new()
var bindings:=Bindings.new()
var cat:=Catalogues.new()
var returning: RefCounted
var docked: RefCounted

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	if fixture!=null:fixture.free()
	print("Full-hold return: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	fixture=WorldFixture.new();fixture.verify(args.slice(0,3))
	check(fixture.failures==0,"Second-flight world fixture failed")
	if fixture.failures:return
	returning=fixture.world
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(header.architecture=="x86_64","This verification is Mac only")
	if bindings.full_hold_return.is_empty():
		check(not returning.snapshot().station_return_supported and returning.prepare_station().is_empty(),"Older pack fabricated the second return")
		check(Definitions.select(bindings,5).is_empty(),"Absent second return selected first-trip rules")
		return
	var rules: Dictionary=bindings.full_hold_return
	check(Definitions.validate(rules,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.station_return,bindings.full_hold_story).is_empty(),"Second return declarations were refused")
	for key in Definitions.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed return parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.station_return,bindings.full_hold_story).is_empty(),"Changed return extent accepted: "+key)
	check(Definitions.select(bindings,3)==bindings.station_return and Definitions.select(bindings,5)==rules and Definitions.select(bindings,4).is_empty() and Definitions.select(bindings,6).is_empty(),"Return selector confused flight and station cursors")
	for cursor in [null,true,3.0,5.0,"5"]:check(Definitions.select(bindings,cursor).is_empty(),"Return selector accepted a malformed cursor")
	verify_reader(args,header)
	verify_gates()
	if failures:return
	var original: Dictionary=returning.snapshot()
	var flight: RefCounted=returning.start_station_autopilot()
	if flight==null:check(false,returning.error);return
	# Synthetic current pools distinguish the arrival cache from construction.
	flight._player._state.vitals.hull=71;flight._player._state.gamma=37.875
	var steps:=0
	for i in 4000:
		var next: RefCounted=flight.evaluate(100)
		if next==null:check(false,flight.error);return
		flight=next;steps+=1
		if not flight.prepare_station().is_empty() or flight.snapshot().get("boundary")=="player_death_required":break
	check(not flight.prepare_station().is_empty(),"Native second-trip guidance failed to reach Var Hastra: "+str(flight.snapshot().get("boundary")))
	if flight.prepare_station().is_empty():return
	docked=flight
	check(returning.snapshot()==original,"Return flight changed its retained mining branch")
	print("Second-trip native return: ",steps*100,"ms; hull ",flight.snapshot().player.vitals.hull)
	verify_arrival()
	if failures==0:await verify_presentation(args)

func verify_reader(args: PackedStringArray, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-return-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","value","extent","first_absent","story_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_return")
			"type":changed.full_hold_return=false
			"value":changed.full_hold_return.refresh_cargo_after_acknowledgement=true
			"extent":changed.full_hold_return.provenance.cargo_list_dispose.offset+=1
			"first_absent":changed.station_return={}
			"story_absent":changed.full_hold_story={};changed.full_hold_appearance={}
			"empty":changed.full_hold_return={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(args[1],lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		check(accepted and reader.full_hold_return.is_empty() if scenario=="empty" else not accepted and reader.binding_id.is_empty() and reader.full_hold_return.is_empty(),"Second-return reader retained stale or malformed data: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func verify_gates():
	var rules: Dictionary=bindings.full_hold_return
	var selected: RefCounted=returning.start_station_autopilot()
	if selected==null:check(false,returning.error);return
	selected._pose.origin=Vector3(0,0,15999)
	selected._station_contact=false
	var arrived: RefCounted=selected.evaluate(100)
	check(arrived!=null and not arrived.prepare_station().is_empty(),"Second return lost the strict pre-motion station contact")
	if arrived==null:return
	check(arrived.snapshot().encounter.controller==selected.snapshot().encounter.controller and arrived.snapshot().encounter.world_elapsed_ms==selected.snapshot().encounter.world_elapsed_ms and arrived.snapshot().camera_view==selected.snapshot().camera_view,"Accepted station return advanced later camera/NPC work")
	for scenario in ["cargo","history","mission","objective","identity"]:
		var bad: RefCounted=selected.fork_for_frame()
		match scenario:
			"cargo":bad._cargo._state.used=24
			"history":bad._cargo._mined_indices=[]
			"mission":bad._objective._state.mission.reward=1
			"objective":bad._objective._state.cargo_objective_acknowledged=false
			"identity":bad._cargo._field_identity=RefCounted.new()
		var before: Dictionary=bad.snapshot()
		check(bad.evaluate(100)==null and bad.snapshot()==before,"Invalid second arrival partially committed: "+scenario)
	var seed: Dictionary=returning._entry.departure.loadout
	var player: Dictionary=returning.snapshot().player
	player.vitals.hull=73;player.vitals.armor=8;player.vitals.shield=17.875;player.gamma=6.75
	var cached:=Cache.station_arrival_cache(rules,seed,player)
	check(Cache.matches(cached,seed,5) and cached.values=={"hull":73,"armor":8,"shield":17,"gamma":6},"Second arrival failed to copy/truncate current pools")
	var wrong:=rules.duplicate(true);wrong.campaign_cursor=3
	check(Cache.station_arrival_cache(wrong,seed,player).is_empty(),"Changed return rules produced an arrival cache")

func verify_arrival():
	var accepted: Dictionary=docked.snapshot();var packet: Dictionary=docked.prepare_station()
	check(packet.campaign_cursor==5 and packet.cargo==returning.snapshot().cargo and packet.player_cache.values.hull==accepted.player.vitals.hull and packet.player_cache.values.gamma==int(accepted.player.gamma),"Second arrival changed cargo or cached stale pools")
	check(packet.player_cache.campaign_cursor==5 and packet.player.campaign_cursor==4 and packet.progress==accepted.progress,"Arrival mixed retained departure identity with current story progress")
	packet.cargo.entries.clear();packet.player_cache.values.hull=0
	check(docked.prepare_station().cargo.entries.size()>0 and docked.prepare_station().player_cache.values.hull>0,"Station packet exposed accepted flight state")
	check(docked.evaluate(150,Vector2.ONE).snapshot()==accepted and docked.navigate("next")==null and docked.start_station_autopilot()==null,"Pending return advanced the encounter or mission")
	var station:=Station.new();check(station.configure_return(bindings,cat,lib,docked),station.error)
	var before: Dictionary=station.snapshot()
	check(not station.configure_return(bindings,cat,lib,returning) and station.snapshot()==before,"Unarrived flight replaced the accepted station")
	check(before.cargo==accepted.cargo and before.arrival_player==accepted.player and before.progress==accepted.progress and before.campaign_cursor==5,"Station changed its accepted cargo/player/progress")
	for i in 6:
		var current: Dictionary=station.snapshot()
		check(current.dialogue.text_id==1719+i and current.dialogue.speaker_id==[2,0,2,0,2,16][i] and current.cargo==accepted.cargo and current.campaign_cursor==5,"Second return line or cargo lifetime differs from source")
		check(station.prepare_departure(bindings,cat).is_empty() and station.snapshot()==current,"Conversation allowed an early departure")
		check(station.acknowledge(),station.error)
	var finished: Dictionary=station.snapshot()
	check(finished.campaign_cursor==6 and finished.delivery_acknowledged and finished.cargo.entries==[] and finished.cargo.used==25 and finished.cargo.free_space==0 and finished.cargo_cache_stale,"Final acknowledgement failed to remove items while retaining source cargo cache")
	check(finished.boundary=="station_equipment_required" and finished.phase=="station_equipment_required" and finished.mission=={"kind":158,"station_id":78,"reward":0,"bonus":0,"source_parameter":0},"Second return skipped the equipment mission")
	check(finished.loadout==before.loadout and finished.player_cache.values==before.player_cache.values and finished.player_cache.campaign_cursor==6 and finished.arrival_player==before.arrival_player,"Second return granted equipment or reset ship pools")
	check(finished.progress.player_kills==before.progress.player_kills and finished.progress.rank_score==before.progress.rank_score+int(bindings.opening_handoff.cursor_weight) and finished.reward_credits==0 and not finished.mining_completed,"Second return granted unearned rewards or tutorial completion")
	check(not station.acknowledge() and station.prepare_departure(bindings,cat).is_empty() and station.snapshot()==finished,"Equipment boundary replayed acknowledgement or fabricated departure")

func verify_presentation(args: PackedStringArray):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var panel:=DialoguePanel.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var speech:=Speech.new();root.add_child(speech)
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var station:=Station.new();check(station.configure_return(bindings,cat,lib,docked) and panel.configure_station_return(lib,bindings,visuals,5),station.error+panel.error)
		if language in ["gb","de"]:check(speech.configure_station_return(lib,bindings,5),speech.error)
		for i in 6:
			check(panel.present(station.snapshot()) and panel._body.text==lib.strings[1719+i],"Wrong second-return localization: "+language)
			if language in ["gb","de"]:
				check(speech.present(i),speech.error)
				if i<5:
					check(speech._player!=null and speech.snapshot().history.back().source_id==433+i,"Wrong second-return voice")
					speech.set_paused(true);check(speech._player.stream_paused,"Second-return voice ignored pause");speech.set_paused(false)
				else:check(speech._player==null and speech.snapshot().history.size()==5,"Silent equipment instruction replayed the last voice")
			if args.size()==4:
				for mobile in [false,true]:
					canvas.size=Vector2i(420,800) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
					for f in 3:await process_frame
					check(Rect2(Vector2.ZERO,canvas.size).encloses(panel._panel.get_rect()) and (panel._body.get_content_height()<=panel._body.size.y or panel._body.scroll_active),"Second-return text escapes viewport: "+language)
			station.acknowledge()
		check(panel.present(station.snapshot()) and not panel.visible,"Acknowledged second return stayed visible")
	speech.free();check(lib.select_language("gb"),lib.error)
	check(panel.configure_station_return(lib,bindings,visuals,5),panel.error);panel.set_mobile_layout(false);canvas.size=Vector2i(960,720)
	var session:=Session.new();canvas.add_child(session)
	if not session.configure_return(lib,bindings,visuals,docked,0,42):check(false,session.error);canvas.free();return
	check(session.activate() and not session.snapshot().conversation_started and session.audio.snapshot().history.is_empty(),"Second return auto-started its conversation")
	for i in 9:session.step((i+1)*100000)
	check(not session.snapshot().conversation_started and not session.navigate("next",panel),"Second return bypassed its entry delay")
	check(session.step(1000000) and session.audio.snapshot().history[0].source_id==433 and panel.present(session.snapshot()),"Second return started the wrong speech")
	session.set_pause("user",true,1000000);var held: Dictionary=session.snapshot()
	check(session.step(5000000) and session.snapshot()==held and not session.navigate("next",panel),"Paused second return advanced dialogue or camera")
	session.set_pause("user",false,5000000);session.step(5100000)
	check(session.snapshot().camera.elapsed_ms==1100,"Second-return pause accumulated catch-up time")
	var foreign:=DialoguePanel.new();canvas.add_child(foreign);held=session.snapshot()
	check(not session.navigate("next",foreign) and session.snapshot()==held,"Rejected second-return panel committed dialogue");foreign.free()
	check(session.navigate("next",panel) and session.navigate("previous",panel),"Second-return speech could not navigate back")
	for i in 6:
		if args.size()==4 and i in [0,5]:
			for mobile in [false,true]:
				canvas.size=Vector2i(420,800) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
				for f in 8:await process_frame
				await RenderingServer.frame_post_draw
				check(canvas.get_texture().get_image().save_png(args[3].path_join("second-return-%d-%s.png"%[i,"phone" if mobile else "desktop"]))==OK,"Could not capture second station return")
		check(session.navigate("next",panel),session.error)
	check(session.snapshot().campaign_cursor==6 and session.snapshot().cargo.entries==[] and session.snapshot().cargo.used==25 and session.audio._player==null and not panel.visible,"Live second return did not commit its cargo/dialogue transaction")
	canvas.free()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL ",checks,": ",message)
