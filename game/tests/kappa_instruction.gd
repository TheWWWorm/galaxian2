extends SceneTree
## Imported lesson presentation only. No career, mission or save is advanced.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Rules=preload("res://src/content/kappa_rescue_definitions.gd")
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const Lines=preload("res://src/content/dialogue_lines.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==4:DirAccess.make_dir_recursive_absolute(args[3])
	if args.size() in [3,4]:await verify(args)
	else:check(false,"Expected content, bindings, visuals and optional capture directory")
	await process_frame
	print("Kappa original instruction: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var rules:=Ordinary.briefing_presentation(bindings,21)
	if not Rules.available(bindings):
		check(rules.is_empty(),"Legacy content enabled the unprepared rescue lesson")
		return
	var source: Dictionary=bindings.mido_travel.kappa_rescue
	var instruction:=int(source.instruction.source_text_id)
	var desktop_instruction:=1854 if instruction==1853 else 1868
	check(bindings.desktop_text_id(instruction)==desktop_instruction,"The source-specific desktop alias changed")
	check(rules.get("events",[]).size()==2 and rules.events[0].text_id==source.briefing_events[0].text_id and rules.events[1].text_id==instruction and rules.events[1].speaker_id==16 and rules.events[1].voice_event_id==-1,"Rescue briefing lost its silent instruction page")
	check(Ordinary.select(bindings,21).is_empty() and load("res://src/presentation/first_flight_session.gd").supported(bindings,21)==Ordinary.FreeFlight.Campaign.chapter_available(bindings.mido_travel),"Rescue presentation bypassed its connected chapter capability")
	if rules.is_empty():return
	var before: Dictionary=bindings.mido_travel.duplicate(true)
	var labels:={"#KEY_SECONDARY":"R / B / LT","#KEY_SECONDARY_WEAPONS":"G / D-pad right"}
	var reversed:={"#KEY_SECONDARY_WEAPONS":"G / D-pad right","#KEY_SECONDARY":"R / B / LT"}
	var reader:=Lines.new()
	for language in library.manifest.languages:
		if not library.select_language(language):check(false,library.error);return
		var lines:=reader.read(bindings,library,rules.events,labels)
		if lines.is_empty():check(false,language+": "+reader.error);return
		check(lines==reader.read(bindings,library,rules.events,reversed),"Input token substitution depended on dictionary order: "+language)
		var expected: String=library.strings[desktop_instruction].replace("#KEY_SECONDARY_WEAPONS",labels["#KEY_SECONDARY_WEAPONS"]).replace("#KEY_SECONDARY",labels["#KEY_SECONDARY"])
		check(lines[1].text==library.strings[instruction] and lines[1].desktop_text_id==desktop_instruction and lines[1].desktop_text==expected,"Rescue instruction selected the wrong original text: "+language)
		check(reader.read(bindings,library,rules.events,{"#KEY_SECONDARY":"R"}).is_empty(),"Short token swallowed a missing longer binding: "+language)
		check(reader.read(bindings,library,rules.events,{"#KEY_SECONDARY_WEAPONS":"G"}).is_empty(),"Missing firing label was silently accepted: "+language)
		for invalid in ["","#KEY_SECONDARY_WEAPONS","R\nB","R\rB",12]:
			var bad:=labels.duplicate();bad["#KEY_SECONDARY"]=invalid
			check(reader.read(bindings,library,rules.events,bad).is_empty(),"Invalid input label reached the lesson")
		if language not in ["gb","de","pl","ru"]:continue
		var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var panel:=DialoguePanel.new();viewport.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not panel.configure_mining_briefing(library,bindings,visuals,21):check(false,panel.error);viewport.free();return
		var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":language,"dialogue":{}}
		for mobile in [false,true]:
			viewport.size=Vector2i(1280,720) if mobile else Vector2i(960,540)
			panel.set_mobile_layout(mobile)
			for index in lines.size():
				state.dialogue=lines[index].duplicate(true)
				state.dialogue.merge({"visible":true,"index":index,"count":lines.size(),"previous_available":index>0})
				check(panel.present(state),panel.error)
				for frame in 3:await process_frame
				check(panel._portrait.texture!=null and panel._body.text==(lines[index].text if mobile else lines[index].desktop_text),"Original portrait or layout-specific instruction is missing")
				check(panel._next.text==library.strings[180 if index==1 else 179] and panel._previous.disabled==(index==0),"Explicit lesson navigation lost its final acknowledgement")
				check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel._panel.get_rect()),"The translated lesson panel leaves the landscape viewport")
				if index==1 and DisplayServer.get_name()!="headless" and args.size()==4:
					await RenderingServer.frame_post_draw
					check(viewport.get_texture().get_image().save_png(args[3].path_join("emp-instruction-"+language+("-touch" if mobile else "-desktop")+".png"))==OK,"Could not save the instruction capture")
		panel.set_active(false);check(panel._next.disabled and panel._previous.disabled,"Paused instruction left acknowledgement enabled")
		viewport.free()
		if language not in ["gb","de"]:continue
		var speech:=Speech.new();root.add_child(speech)
		if not speech.configure_mining_briefing(library,bindings,21):check(false,speech.error);speech.free();return
		check(speech._clips.size()==2 and speech._clips[0].id==167 and speech._clips[1]==null,"Silent instruction shifted the source voice slots")
		check(speech.valid_line(-1) and speech.valid_line(0) and speech.valid_line(1) and not speech.valid_line(-2) and not speech.valid_line(2),"Silent instruction lost its real slot or accepted a one-past-end page")
		speech.set_paused(true)
		check(speech.present(0) and speech.snapshot().history.size()==1,"Briefing voice did not start once")
		var voiced:=speech.snapshot();var playing: Node=speech._player
		for invalid in [-2,2]:check(not speech.present(invalid) and speech.snapshot()==voiced and speech._player==playing,"Invalid instruction index stopped or changed a valid voice")
		check(speech.present(1) and speech._player==null and speech.snapshot().history.size()==1,"Instruction replayed the preceding voice")
		var silent:=speech.snapshot();await process_frame
		check(speech.present(1) and speech.snapshot()==silent,"Silent instruction advanced or replayed itself")
		check(speech.present(0) and speech.snapshot().history.size()==2,"Explicit previous navigation could not replay the briefing")
		speech.clear();check(speech.get_child_count()==0,"Instruction speech leaked a player")
		check(speech.valid_line(-1) and not speech.valid_line(0) and speech.present(-1),"Empty speech owner accepted a phantom page or could not close")
		speech.free()
	check(bindings.mido_travel==before,"Lesson preparation changed original campaign data")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
