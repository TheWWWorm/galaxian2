extends SceneTree
const Briefing=preload("res://src/simulation/mining_briefing.gd")
const Definitions=preload("res://src/content/mining_briefing_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Mining briefing: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	var briefing:=Briefing.new()
	check(briefing.snapshot().is_empty() and not briefing.advance(0),"Unprepared briefing advanced")
	if bindings.mining_briefing.is_empty():
		check(not briefing.configure(bindings,lib,Construction.new(),"E"),"Legacy pack invented a briefing");return
	var source_bytes:=int(JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json"))).source_executable_bytes)
	check(validate(bindings.mining_briefing,bindings,source_bytes).is_empty(),"Imported briefing provenance failed")
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.mining_briefing.duplicate(true);bad.provenance[key].offset+=1
		check(not validate(bad,bindings,source_bytes).is_empty(),"Disconnected briefing extent accepted: "+key)
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.mining_briefing.duplicate(true);bad[key]="unverified"
		check(not Definitions.parameters(bad),"Changed briefing declaration accepted: "+key)
	check(not Definitions.validate(bindings.mining_briefing,source_bytes,"x86_64",bindings.arrival_staging,bindings.first_flight,bindings.station_presentation,{}).is_empty(),"Briefing accepted a missing desktop instruction mapping")
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not complete rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:check(station.acknowledge(),station.error)
	var departure:=station.prepare_departure(bindings,cat)
	var flight:=Construction.new()
	if not flight.prepare(bindings,cat,departure,4096,1789100000):check(false,flight.error);return
	var prepared:=flight.snapshot()
	check(briefing.configure(bindings,lib,flight,"E"),briefing.error)
	var fresh:=briefing.snapshot()
	for invalid in [-1,151,1.5,"100"]:
		check(not briefing.advance(invalid) and briefing.snapshot()==fresh,"Invalid briefing time changed its state")
	for key in ["","#KEY_DOCK","E\nX"]:
		check(not briefing.configure(bindings,lib,flight,key) and briefing.snapshot()==fresh,"Invalid key label replaced a valid briefing")
	check(not briefing.navigate("next") and briefing.snapshot()==fresh,"Entry acknowledged unseen briefing")
	for i in 50:check(briefing.advance(100),briefing.error)
	check(briefing.snapshot().hud_elapsed_ms==100 and not briefing.snapshot().dialogue.visible,"Departure controller did not hold the HUD clock")
	check(briefing.advance(1) and not briefing.snapshot().dialogue.visible,"HUD threshold bypassed entry readiness")
	for i in 19:briefing.advance(100)
	briefing.advance(99)
	check(briefing.snapshot().entry_elapsed_ms==7000 and not briefing.snapshot().entry_released,"Entry released at 7000 ms")
	var held:=briefing.snapshot();briefing.advance(150,true)
	check(briefing.snapshot()==held and briefing.simulation_delta_ms()==0,"Pause advanced entry or passed world time")
	briefing.advance(1)
	check(briefing.snapshot().entry_released and briefing.snapshot().briefing_pending and not briefing.snapshot().dialogue.visible and briefing.snapshot().entry_elapsed_ms==0,"Release and HUD checks were reordered")
	for i in 49:briefing.advance(100)
	check(briefing.snapshot().hud_elapsed_ms==5000 and not briefing.snapshot().dialogue.visible,"Briefing appeared at the inclusive five-second boundary")
	briefing.advance(1)
	var opened:=briefing.snapshot()
	check(opened.dialogue.visible and opened.dialogue.text_id==1699 and opened.world_elapsed_ms==11902 and briefing.simulation_delta_ms()==1 and opened.hud_elapsed_ms==0,"Briefing lost its opening frame")
	for i in 200:briefing.advance(150)
	check(briefing.snapshot()==opened and briefing.simulation_delta_ms()==0,"Modal briefing advanced simulation or auto-dismissed")
	check(not briefing.navigate("previous") and not briefing.navigate("skip") and briefing.snapshot()==opened,"Briefing skipped or moved before its first line")
	var clone: RefCounted=briefing.fork();clone.navigate("next")
	check(briefing.snapshot()==opened and clone.snapshot().dialogue.text_id==1700,"Forked navigation changed the live briefing")
	check(clone.navigate("previous") and clone.snapshot()==opened,"Previous did not restore the first line")
	for i in 5:
		var line: Dictionary=briefing.snapshot().dialogue
		check(line.index==i and line.count==5 and line.text_id==1699+i and line.speaker_id==[0,2,0,2,16][i],"Briefing sequence differs from authored pairs")
		check(line.voice_event_id==([177,178,179,180,-1][i]),"Wrong briefing recording selected")
		if i==4:check(line.desktop_text_id==1704 and "press E" in line.desktop_text and "#KEY_" not in line.desktop_text and "tap Fire" in line.text,"Desktop mining instruction lost its active key or touch variant")
		check(briefing.navigate("next"),briefing.error)
	var done:=briefing.snapshot()
	check(done.phase=="flight" and done.acknowledged and not done.briefing_pending and not done.dialogue.visible,"Final acknowledgement did not close the pending briefing")
	for key in ["mission","progress","cargo_used","campaign_cursor","mining_completed","reward_credits"]:check(done[key]==fresh[key],"Briefing changed unearned gameplay state: "+key)
	check(not briefing.navigate("next") and briefing.snapshot()==done,"Final acknowledgement repeated")
	for i in 100:briefing.advance(100)
	check(briefing.snapshot().phase=="flight" and briefing.snapshot().world_elapsed_ms==21902 and not briefing.snapshot().briefing_pending,"Finished briefing retriggered or stalled world time")
	check(flight.snapshot()==prepared and station.prepare_departure(bindings,cat)==departure,"Briefing mutated its source flight or station")
	# The component uses the shared native panel and decoder, with all Mac text
	# languages and both supplied spoken banks. This is not a live-flight test.
	var canvas:=SubViewport.new();canvas.size=Vector2i(1280,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var panel:=DialoguePanel.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var speech:=Speech.new();root.add_child(speech)
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		check(briefing.configure(bindings,lib,flight,"X"),briefing.error)
		for i in 130:briefing.advance(100)
		briefing.advance(1)
		if not panel.configure_mining_briefing(lib,bindings,visuals):check(false,panel.error);break
		if language in ["gb","de"]:check(speech.configure_mining_briefing(lib,bindings),speech.error)
		for i in 5:
			var state:=briefing.snapshot()
			check(panel.present(state),panel.error)
			check("#KEY_" not in state.dialogue.desktop_text and not state.dialogue.text.is_empty(),"Unresolved localized mining instruction")
			if language in ["gb","de"]:
				check(speech.present(i),speech.error)
				if i==4:check(speech._player==null and speech.snapshot().history.size()==4,"Silent final instruction retained a recording")
				if i<4:check(speech.snapshot().history.back().source_id==177+i,"Wrong original voice played")
			if args.size()==4 and language in ["gb","de","ja","pl"] and i in [0,1,4]:
				for mobile in [false,true]:
					canvas.size=Vector2i(800,450) if mobile else Vector2i(1280,720)
					panel.set_mobile_layout(mobile)
					for f in 3:await process_frame
					check(Rect2(Vector2.ZERO,canvas.size).encloses(panel._panel.get_rect()),"Briefing panel extends beyond its viewport: %s %d %s %s"%[language,i,str(canvas.size),str(panel._panel.get_rect())])
					check(panel._body.get_content_height()<=panel._body.size.y or panel._body.scroll_active,"Localized briefing text cannot be read")
					var capture:=canvas.get_texture().get_image()
					check(capture.get_size()==canvas.size,"Captured another viewport size")
					capture.save_png(args[3].path_join("briefing-%s-%d-%s.png"%[language,i,"phone" if mobile else "desktop"]))
			briefing.navigate("next")
		check(panel.present(briefing.snapshot()) and not panel.visible,"Finished briefing stayed onscreen")
	check(speech.valid_line(-1) and speech.valid_line(4) and not speech.valid_line(5),"Silent final briefing line has wrong bounds")
	speech.present(-1);check(speech.snapshot().line==-1,"Closing briefing retained voice")
	speech.set_paused(true);check(speech.snapshot().paused,"Speech ignored pause")
	canvas.free();speech.free();briefing.clear();check(briefing.snapshot().is_empty(),"Clear retained briefing state")

func validate(data: Dictionary, bindings: RefCounted, bytes: int) -> String:
	return Definitions.validate(data,bytes,"x86_64",bindings.arrival_staging,bindings.first_flight,bindings.station_presentation,bindings.desktop_text)
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
