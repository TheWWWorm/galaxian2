extends SceneTree
const Objective=preload("res://src/simulation/mining_objective.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Dialogue=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
const Definitions=preload("res://src/content/mining_objective_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var lib: RefCounted
var bindings: RefCounted
var cat: RefCounted
var construction: RefCounted
var captures:={}
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Mining objective: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify(args: Array):
	lib=Library.new();bindings=Bindings.new();cat=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	if bindings.mining_objective.is_empty():check(not Objective.new().configure(bindings,lib,Construction.new(),"A","E"),"Legacy pack invented a cargo objective");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.mining_objective,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Objective declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.mining_objective.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed objective parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.mining_objective.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached objective provenance accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3));var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	construction=Construction.new()
	if not construction.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000,true,bodies,effects):check(false,construction.error);return
	verify_objective()
	verify_flight()
	if failures==0:await verify_presentation(args)
func fresh() -> RefCounted:
	var objective:=Objective.new();check(objective.configure(bindings,lib,construction,"A","E"),objective.error);return objective
func hold() -> RefCounted:
	var cargo:=Cargo.new();check(cargo.configure_departure(bindings,cat,construction),cargo.error);return cargo
func verify_objective():
	var objective:=fresh();var world: RefCounted=construction.scenery_owner();var cargo:=hold()
	var initial: Dictionary=objective.snapshot()
	check(not initial.cargo_objective_satisfied and initial.required_cargo==10 and initial.phase=="collecting","Cargo objective started earned")
	check(not objective.navigate("next") and objective.snapshot()==initial,"Unseen completion was acknowledged")
	check(not objective.configure(bindings,lib,construction,"#KEY_AUTOPILOT","E") and objective.snapshot()==initial,"Invalid input label replaced a valid objective")
	check(not objective.poll(Cargo.new(),world) and objective.snapshot()==initial,"Unprepared cargo satisfied the objective")
	var foreign: RefCounted=cargo.fork_for_frame();foreign._field_identity=RefCounted.new()
	check(not objective.poll(foreign,world) and objective.snapshot()==initial,"Cargo from another field was accepted")
	# Deliberately seeded cargo isolates the source predicate: it counts total
	# cargo, even when it is neither this asteroid's ore nor newly mined cargo.
	check(cargo.add_entries([{"item_id":0,"quantity":9}]),cargo.error)
	check(objective.poll(cargo,world) and not objective.snapshot().cargo_objective_satisfied and objective.snapshot().cargo_at_check==9,"Nine tons completed the requirement")
	check(cargo.add_entries([{"item_id":1,"quantity":1}]),cargo.error)
	var before: Dictionary=objective.snapshot()
	check(objective.poll(cargo,world,false) and objective.snapshot()==before,"Dead player opened return dialogue")
	var branch: RefCounted=objective.fork_for_frame()
	check(branch.poll(cargo,world) and branch.snapshot().dialogue.visible and objective.snapshot()==before,"Ten total tons did not offer detached return dialogue")
	var opened: Dictionary=branch.snapshot()
	check(opened.campaign_cursor==2 and opened.mission==initial.mission and opened.progress==initial.progress and opened.reward_credits==0 and not opened.mining_completed,"Cargo check granted unacknowledged mission progress")
	check(not branch.navigate("previous") and not branch.navigate("skip") and branch.snapshot()==opened,"Return dialogue skipped its first line")
	for i in 3:
		var line: Dictionary=branch.snapshot().dialogue
		check(line.index==i and line.text_id==1706+i and line.speaker_id==[2,0,16][i] and line.voice_event_id==[327,328,-1][i],"Return dialogue or voice differs from source")
		if i==2:check(line.desktop_text_id==1709 and "#KEY_" not in line.desktop_text and "A" in line.desktop_text and "E" in line.desktop_text,"Return instruction lost its mapped desktop bindings")
		check(branch.navigate("next"),branch.error)
	var finished: Dictionary=branch.snapshot()
	check(finished.campaign_cursor==3 and finished.phase=="return_required" and finished.station_return_required and finished.cargo_objective_acknowledged,"Final acknowledgement did not select the return mission")
	check(finished.mission=={"kind":11,"station_id":78,"reward":0,"bonus":0} and finished.reward_credits==0 and not finished.mining_completed and cargo.snapshot().used==10,"Acknowledgement removed cargo, rewarded credits or claimed station arrival")
	check(finished.progress.rank_score==initial.progress.rank_score+int(bindings.opening_handoff.cursor_weight) and finished.progress.campaign_cursor==3,"Acknowledged progress lost its source cursor rank contribution")
	check(not branch.navigate("next") and branch.poll(cargo,world) and branch.snapshot()==finished,"Final acknowledgement or predicate replayed")
	branch.clear();check(branch.snapshot().is_empty() and objective.snapshot()==before,"Clearing a branch erased its parent")

func live() -> RefCounted:
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5,Vector2i(960,720)):check(false,flight.error);return null
	for i in 130:
		flight=flight.evaluate(100)
		if flight==null:check(false,"First flight failed before briefing");return null
		if flight.dialogue_visible():break
	check(flight.snapshot().hud_elapsed_ms==0 and flight.snapshot().dialogue.text_id==1699,"Initial briefing did not reset its unsuccessful poll")
	for i in 5:
		flight=flight.navigate("next")
		if flight==null:check(false,"First briefing failed to acknowledge");return null
	return flight
func verify_flight():
	var flight:=live()
	if flight==null:return
	check(flight._cargo.add_entries([{"item_id":0,"quantity":10}]),flight._cargo.error)
	for i in 50:
		flight=flight.evaluate(100)
		if flight==null:check(false,"Cargo poll frame failed");return
	var before: Dictionary=flight.snapshot()
	check(before.hud_elapsed_ms==5000 and not before.cargo_objective_satisfied and not before.dialogue.visible,"Cargo poll ran before its strict threshold")
	var invalid: RefCounted=flight.fork_for_frame();invalid._objective._field_identity=RefCounted.new()
	var held: Dictionary=invalid.snapshot()
	check(invalid.evaluate(1)==null and invalid.snapshot()==held and flight.snapshot()==before,"Rejected objective check partially advanced the world")
	var opened: RefCounted=flight.evaluate(1)
	if opened==null:check(false,flight.error);return
	var modal: Dictionary=opened.snapshot();captures["return-gunant"]=opened
	check(modal.cargo_objective_satisfied and modal.phase=="return_instructions" and modal.dialogue.text_id==1706 and modal.hud_elapsed_ms==5001,"Due cargo check did not open its acknowledged instructions")
	check(modal.world_elapsed_ms==before.world_elapsed_ms+1 and modal.player_pose!=before.player_pose and modal.camera_view==before.camera_view and modal.detail_reference==before.detail_reference,"Completion opening must advance the player but hold the later camera")
	check(flight.snapshot()==before and modal.cargo==before.cargo and modal.progress==before.progress and modal.random_state==before.random_state,"Opening return dialogue changed cargo, progress, RNG or its parent")
	for i in 80:check(opened.evaluate(150,Vector2.ONE,0.0).snapshot()==modal,"Return dialogue advanced the world or auto-dismissed")
	check(opened.navigate("next",true)==null and opened.start_mining()==null and opened.stop_mining()==null and opened.cancel_mining()==null,"Paused or modal flight accepted gameplay input")
	var line2: RefCounted=opened.navigate("next")
	check(line2!=null and line2.navigate("previous").snapshot()==modal,"Previous return instruction altered world state")
	var line3: RefCounted=line2.navigate("next");captures["return-info"]=line3
	var returning: RefCounted=line3.navigate("next")
	if returning==null:check(false,line3.error);return
	var result: Dictionary=returning.snapshot();captures["return-flight"]=returning
	check(result.campaign_cursor==3 and result.station_return_required and not result.dialogue.visible and result.reward_credits==0 and not result.mining_completed,"Acknowledgement invented station return or lost the next mission")
	for key in ["cargo","player_pose","camera_view","scenery","random_state","world_elapsed_ms"]:check(result[key]==modal[key],"Acknowledgement changed flight state: "+key)
	var resumed: RefCounted=returning.evaluate(100)
	check(resumed!=null and resumed.snapshot().camera_view!=result.camera_view and resumed.snapshot().hud_elapsed_ms==0 and resumed.snapshot().campaign_cursor==3 and resumed.snapshot().cargo==result.cargo,"Post-dialogue flight did not resume with retained cargo")
	var idle:=live()
	if idle==null:return
	for i in 34:idle=idle.evaluate(150)
	check(idle.snapshot().hud_elapsed_ms==0 and not idle.snapshot().cargo_objective_satisfied,"Unsuccessful cargo poll retained overshoot or invented success")

func verify_presentation(args: Array):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var panel:=Dialogue.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var speech:=Speech.new();root.add_child(speech)
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var objective:=fresh();var cargo:=hold();cargo.add_entries([{"item_id":0,"quantity":10}]);objective.poll(cargo,construction.scenery_owner())
		check(panel.configure_mining_objective(lib,bindings,visuals),panel.error)
		if language in ["gb","de"]:check(speech.configure_mining_objective(lib,bindings),speech.error)
		for i in 3:
			var state: Dictionary=objective.snapshot()
			check(panel.present(state) and "#KEY_" not in state.dialogue.desktop_text and not state.dialogue.text.is_empty(),"Unresolved return language "+language)
			if language in ["gb","de"]:
				check(speech.present(i),speech.error)
				if i<2:
					check(speech.snapshot().history.back().source_id==327+i and speech._player!=null,"Wrong return recording")
					var history: Array=speech.snapshot().history;speech.present(i);check(speech.snapshot().history==history,"Painting replayed speech")
					speech.set_paused(true);check(speech._player.stream_paused,"Return speech ignored pause");speech.set_paused(false)
				else:check(speech._player==null and speech.snapshot().history.size()==2,"Silent return instruction retained speech")
			if args.size()==4:
				for mobile in [false,true]:
					canvas.size=Vector2i(420,800) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
					for f in 3:await process_frame
					check(Rect2(Vector2.ZERO,canvas.size).encloses(panel._panel.get_rect()),"Return panel escapes viewport: "+language)
					check(panel._body.get_content_height()<=panel._body.size.y or panel._body.scroll_active,"Return text cannot be read: "+language)
					if i==2 and ((language=="de" and mobile) or (language=="zs" and mobile)):
						check(canvas.get_texture().get_image().save_png(args[3].path_join("return-info-"+language+"-phone.png"))==OK,"Could not capture phone instruction")
			objective.navigate("next")
		check(panel.present(objective.snapshot()) and not panel.visible,"Acknowledged return panel stayed visible")
	canvas.free();speech.free();check(lib.select_language("gb"),lib.error)
	if args.size()==4:
		canvas=SubViewport.new();canvas.size=Vector2i(960,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
		var scene:=Scene.new();canvas.add_child(scene)
		check(scene.build(lib,bindings,visuals,cat,captures["return-gunant"]),scene.error)
		for name in captures:
			check(scene.present(captures[name]),scene.error)
			for f in 3:await process_frame
			check(canvas.get_texture().get_image().save_png(args[3].path_join(name+".png"))==OK,"Could not capture return scene")
		check(scene.present(captures["return-gunant"]),scene.error)
		var position: Transform3D=scene.geometry.player.transform;var shown: Dictionary=scene.dialogue._snapshot.duplicate(true)
		var bad: RefCounted=captures["return-flight"].fork_for_frame();bad._objective._state.campaign_cursor=4
		check(not scene.present(bad) and scene.geometry.player.transform==position and scene.dialogue._snapshot==shown,"Failed return presentation erased accepted dialogue")
		canvas.free()

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",checks,": ",message)
