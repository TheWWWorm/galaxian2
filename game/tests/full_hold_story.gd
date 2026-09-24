extends SceneTree
## Mac component proof. Departure packets and preloaded cargo are disclosed
## fixtures; this test does not claim a complete second-flight playthrough.
const Fixtures=preload("res://tests/full_hold_control.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Definitions=preload("res://src/content/full_hold_story_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Briefing=preload("res://src/simulation/mining_briefing.gd")
const Objective=preload("res://src/simulation/mining_objective.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
var checks:=0
var failures:=0
var lib: RefCounted
var bindings: RefCounted
var cat: RefCounted
var construction: RefCounted
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:await verify(args)
	print("Full-hold story: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	lib=Library.new();bindings=Bindings.new();cat=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","This proof requires the Mac profile")
	var fixture:=Fixtures.new();construction=Construction.new()
	var prepared: bool=construction.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000)
	fixture.free()
	if not prepared:check(false,construction.error);return
	if bindings.full_hold_story.is_empty():
		check(not Briefing.new().configure(bindings,lib,construction,"E"),"Legacy pack invented second-trip briefing")
		check(not Objective.new().configure(bindings,lib,construction,"A","E"),"Legacy pack invented second-trip objective")
		return
	var original: Dictionary=construction.snapshot()
	check(original.scenery.world_initialization.npc_construction.actors.size()==1,"Story discarded the actual pirate")
	check(original.departure.loadout.equipment_ids==[90,81],"Starter equipment changed")
	for item_id in original.departure.loadout.equipment_ids:
		check(cat.tables.items[item_id].properties[2]!=13,"This starter unexpectedly has a tractor")
	verify_reader(args[1])
	verify_clocks()
	verify_cargo()
	check(not Frame.new().configure(bindings,cat,lib,construction,"E",1.0),"Component support exposed an incomplete live second world")
	check(construction.snapshot()==original,"Story components mutated their prepared world")
	if failures==0:await verify_presentation(args)

func fresh_briefing() -> RefCounted:
	var value:=Briefing.new();check(value.configure(bindings,lib,construction,"E"),value.error);return value
func fresh_objective() -> RefCounted:
	var value:=Objective.new();check(value.configure(bindings,lib,construction,"A","E"),value.error);return value
func hold() -> RefCounted:
	var value:=Cargo.new();check(value.configure_departure(bindings,cat,construction),value.error);return value

func verify_clocks():
	var briefing:=fresh_briefing();var initial: Dictionary=briefing.snapshot()
	check(initial.campaign_cursor==4 and initial.dialogue.count==1 and not initial.dialogue.visible,"Second briefing lost its source count or cursor")
	for value in [-1,151,1.5,"100"]:
		check(not briefing.advance(value) and briefing.snapshot()==initial,"Invalid duration changed the briefing")
	check(not briefing.navigate("next"),"Unseen briefing was acknowledged")
	# First HUD pass adds 100 ms; subsequent passes are held by the entry
	# controller. Release is strict >7000 and affects the following HUD pass.
	for i in 70:briefing.advance(100)
	var held: Dictionary=briefing.snapshot()
	check(held.entry_elapsed_ms==7000 and held.hud_elapsed_ms==100 and not held.entry_released,"Departure clock boundary changed")
	check(briefing.advance(150,true) and briefing.snapshot()==held and briefing.simulation_delta_ms()==0,"Paused entry consumed time")
	briefing.advance(1)
	check(briefing.snapshot().entry_released and not briefing.snapshot().dialogue.visible,"Release opened dialogue before the HUD poll")
	for i in 49:briefing.advance(100)
	check(briefing.snapshot().hud_elapsed_ms==5000 and not briefing.snapshot().dialogue.visible,"Briefing opened at the inclusive poll boundary")
	briefing.advance(1);var opened: Dictionary=briefing.snapshot()
	check(opened.world_elapsed_ms==11902 and opened.hud_elapsed_ms==0 and opened.dialogue.visible and opened.dialogue.text_id==int(bindings.full_hold_story.briefing_events[0].text_id) and opened.dialogue.voice_event_id==188,"Wrong second briefing or opening frame")
	for duration in [0,1,149,150]:
		check(briefing.advance(duration) and briefing.snapshot()==opened and briefing.simulation_delta_ms()==0,"Modal speech advanced or auto-dismissed")
	check(not briefing.navigate("previous") and not briefing.navigate("skip"),"Single-line briefing accepted unsupported navigation")
	var fork: RefCounted=briefing.fork();check(fork.navigate("next"),fork.error)
	var done: Dictionary=fork.snapshot()
	check(briefing.snapshot()==opened and done.acknowledged and not done.dialogue.visible and not done.briefing_pending,"Acknowledgement changed the parent or left the briefing pending")
	for key in ["campaign_cursor","mission","progress","cargo_used","reward_credits","mining_completed"]:check(done[key]==initial[key],"Briefing granted unearned state: "+key)
	check(fork.advance(100) and fork.snapshot().world_elapsed_ms==12002 and not fork.snapshot().dialogue.visible,"Acknowledged briefing did not resume")
	var saved: Dictionary=bindings.full_hold_story;var appearance: Dictionary=bindings.full_hold_appearance;bindings.full_hold_story={};bindings.full_hold_appearance={}
	check(not briefing.configure(bindings,lib,construction,"E") and briefing.snapshot()==opened,"Missing capability partially replaced a live briefing")
	bindings.full_hold_story=saved;bindings.full_hold_appearance=appearance

func verify_cargo():
	var objective:=fresh_objective();var cargo:=hold();var field: RefCounted=construction.scenery_owner()
	var initial: Dictionary=objective.snapshot()
	check(initial.required_cargo==25 and initial.phase=="collecting" and initial.dialogue.count==2,"Second objective reused the first trip's threshold or lines")
	check(not objective.navigate("next") and objective.snapshot()==initial,"Cargo warning acknowledged before satisfaction")
	# A deliberately preloaded hold isolates total cargo from ore identity. All
	# cargo mutations use the real capacity/identity owner; no timer grants ore.
	check(cargo.add_entries([{"item_id":112,"quantity":10}]),cargo.error)
	check(objective.poll(cargo,field) and not objective.snapshot().dialogue.visible,"Ten tons completed the full hold objective")
	check(cargo.add_entries([{"item_id":118,"quantity":14}]),cargo.error)
	check(objective.poll(cargo,field) and objective.snapshot().cargo_at_check==24 and not objective.snapshot().cargo_objective_satisfied,"Twenty-four tons completed the objective")
	var hold_before: Dictionary=cargo.snapshot()
	check(not cargo.add_entries([{"item_id":118,"quantity":2}]) and cargo.snapshot()==hold_before,"Overfilled hold partially committed")
	check(cargo.add_entries([{"item_id":118,"quantity":1}]),cargo.error)
	var before: Dictionary=objective.snapshot();var full: Dictionary=cargo.snapshot()
	check(objective.poll(cargo,field,false) and objective.snapshot()==before,"Dead player opened the warning")
	var foreign: RefCounted=cargo.fork_for_frame();foreign._field_identity=RefCounted.new()
	check(not objective.poll(foreign,field) and objective.snapshot()==before,"Foreign cargo opened the warning")
	var stale: RefCounted=cargo.fork_for_frame();stale._mined_indices=[0]
	check(not objective.poll(stale,field) and objective.snapshot()==before,"Divergent mining history opened the warning")
	var branch: RefCounted=objective.fork_for_frame()
	check(branch.poll(cargo,field) and branch.snapshot().dialogue.visible and objective.snapshot()==before,"Full cargo poll was not detached")
	var opened: Dictionary=branch.snapshot()
	check(opened.campaign_cursor==4 and opened.progress==initial.progress and opened.mission==initial.mission and opened.reward_credits==0 and not opened.mining_completed,"Cargo check granted premature progress")
	check(opened.dialogue.text_id==int(bindings.full_hold_story.completion_events[0].text_id) and opened.dialogue.speaker_id==0 and opened.dialogue.voice_event_id==431,"Wrong first pirate warning")
	check(not branch.navigate("previous") and not branch.navigate("skip") and branch.snapshot()==opened,"Warning skipped its first line")
	check(branch.navigate("next") and branch.snapshot().dialogue.text_id==int(bindings.full_hold_story.completion_events[1].text_id) and branch.snapshot().dialogue.speaker_id==2 and branch.snapshot().dialogue.voice_event_id==432,"Wrong second pirate warning")
	check(branch.navigate("previous") and branch.snapshot()==opened,"Previous navigation altered cargo warning state")
	branch.navigate("next");branch.navigate("next")
	var done: Dictionary=branch.snapshot()
	check(done.campaign_cursor==5 and done.phase=="return_required" and done.station_return_required and not done.dialogue.visible,"Final warning did not select return")
	check(done.mission=={"kind":11,"station_id":78,"reward":0,"bonus":0} and done.reward_credits==0 and not done.mining_completed,"Warning invented a reward or station arrival")
	var progress: Dictionary=initial.progress.duplicate(true);progress.campaign_cursor=5;progress.rank_score+=1
	check(done.progress==progress and cargo.snapshot()==full,"Acknowledgement changed earned kills, rank or cargo")
	check(not branch.navigate("next") and branch.poll(cargo,field) and branch.snapshot()==done,"Completed warning repeated")
	var forged:=Construction.new();forged._state=construction._state.duplicate(true)
	forged._scenery=construction.scenery_owner();forged._camera=construction.camera_owner();forged._player=construction.player_owner()
	forged._state.departure.mission.source_parameter=10
	check(not objective.configure(bindings,lib,forged,"A","E") and objective.snapshot()==before,"Wrong mission replaced a valid objective")

func verify_reader(pack: String):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var data: Dictionary=bindings.full_hold_story
	check(validate(data,header).is_empty(),"Verified story declarations were refused")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed story value accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not validate(bad,header).is_empty(),"Detached source span accepted: "+key)
	for cursor in [0,1,3,5,6,4.0,"4"]:
		check(Definitions.briefing(bindings,cursor).is_empty() and Definitions.objective(bindings,cursor).is_empty(),"Unsupported story cursor accepted")
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-story-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","value","extent","flight","briefing","objective","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_story")
			"type":changed.full_hold_story=false
			"value":changed.full_hold_story.required_cargo=10
			"extent":changed.full_hold_story.provenance.mode0_events.offset+=1
			"flight":changed.full_hold_flight={}
			"briefing":changed.mining_briefing={}
			"objective":changed.mining_objective={}
			"empty":
				for key in ["full_hold_story","full_hold_appearance","full_hold_return","station_equipment","combat_training","combat_training_control","combat_training_weapons","combat_training_destruction","combat_training_story","combat_training_visuals","mido_travel","ambient_population","ambient_combat","ambient_lifecycle","freighter_destruction","early_contracts"]:changed[key]={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		if scenario=="empty":check(accepted and reader.full_hold_story.is_empty() and not reader.full_hold_flight.is_empty(),"Optional story absence was rejected: "+reader.error)
		else:check(not accepted and reader.binding_id.is_empty() and reader.full_hold_story.is_empty() and reader.mining_briefing.is_empty(),"Failed reopen retained partial state: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func validate(data: Dictionary, header: Dictionary) -> String:
	return Definitions.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_flight,bindings.mining_briefing,bindings.mining_objective)

func verify_presentation(args: PackedStringArray):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var panel:=DialoguePanel.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var speech:=Speech.new();root.add_child(speech)
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		for completion in [false,true]:
			var owner: RefCounted=fresh_objective() if completion else fresh_briefing()
			if completion:
				var cargo:=hold();cargo.add_entries([{"item_id":118,"quantity":25}]);owner.poll(cargo,construction.scenery_owner())
			else:
				for i in 130:owner.advance(100)
			check(panel.configure_mining_objective(lib,bindings,visuals,4) if completion else panel.configure_mining_briefing(lib,bindings,visuals,4),panel.error)
			if language in ["gb","de"]:check(speech.configure_mining_objective(lib,bindings,4) if completion else speech.configure_mining_briefing(lib,bindings,4),speech.error)
			for i in (2 if completion else 1):
				var state: Dictionary=owner.snapshot()
				var expected_text:=int(bindings.full_hold_story.completion_events[i].text_id if completion else bindings.full_hold_story.briefing_events[0].text_id)
				check(state.dialogue.text_id==expected_text and state.dialogue.desktop_text_id==state.dialogue.text_id,"Wrong second-trip text binding")
				check(panel.present(state) and not state.dialogue.text.is_empty() and "#KEY_" not in state.dialogue.desktop_text,panel.error)
				if language in ["gb","de"]:
					check(speech.present(i),speech.error)
					check(speech._player!=null and speech.snapshot().history.back().source_id==(431+i if completion else 188),"Second-trip voice was substituted")
					var history: Array=speech.snapshot().history;speech.present(i)
					check(speech.snapshot().history==history,"Repainting restarted speech")
					speech.set_paused(true);check(speech._player.stream_paused,"Modal speech ignored pause");speech.set_paused(false)
				if args.size()==4:
					for mobile in [false,true]:
						canvas.size=Vector2i(800,450) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
						for f in 3:await process_frame
						check(Rect2(Vector2.ZERO,canvas.size).encloses(panel._panel.get_rect()),"Second-trip panel escapes viewport: "+language)
						check(panel._body.get_content_height()<=panel._body.size.y or panel._body.scroll_active,"Second-trip text is unreadable: "+language)
						if language=="gb" and not mobile or language=="de" and mobile and completion and i==1:
							check(canvas.get_texture().get_image().save_png(args[3].path_join("story-%d-%s-%s.png"%[state.dialogue.text_id,language,"phone" if mobile else "desktop"]))==OK,"Could not save story capture")
				owner.navigate("next")
			check(panel.present(owner.snapshot()) and not panel.visible,"Acknowledged story panel remained visible")
			speech.present(-1)
	canvas.free();speech.free();check(lib.select_language("gb"),lib.error)

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",checks,": ",message)
