extends SceneTree
## Tests the recovered radio owner independently of the unfinished rescue world.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Definitions=preload("res://src/content/dialogue_definitions.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const TextResources=preload("res://src/presentation/opening_radio_resources.gd")
const Resources=preload("res://src/content/audio_resources.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const RadioPanel=preload("res://src/presentation/radio_panel.gd")
var checks:=0
var failures:=0

func _initialize():call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	root.size=Vector2i(1000,700)
	for i in range(0,args.size()-2,3):
		await verify_source(args[i],args[i+1],args[i+2])
	print("Arrival radio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_source(content: String, pack: String, images: String):
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	if bindings.arrival_dialogue.is_empty():
		check(library.select_language("gb"),library.error)
		var radio:=Radio.new();var audio:=Audio.new();root.add_child(audio)
		check(not radio.configure(bindings,library,[1,1,1],1) and radio.snapshot().is_empty(),"Legacy pack invented rescue dialogue")
		check(not audio.configure(library,bindings,0,1) and audio.snapshot().active.is_empty(),"Legacy pack invented rescue voice ownership")
		audio.free();return
	if not visuals.open(images,library.manifest):check(false,visuals.error);return
	var data: Dictionary=bindings.arrival_dialogue
	var edition: String=library.manifest.profile.edition
	var first:=1697 if edition=="ios-hd" else 1675
	check(data.events.map(func(row):return int(row.text_id))==[first,first+1,first+2],"Wrong edition-local rescue text IDs")
	check(data.events.map(func(row):return int(row.speaker_id))==[2,2,2],"Wrong source rescue speaker")
	check(data.voice.event_ids.map(func(id):return int(id))==[501,502,503],"Wrong source rescue recordings")
	verify_pack_failures(pack,library.manifest)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in ["dispatch","dispatch_table","single_constructor","duration","display_delay"]:
		var changed:=data.duplicate(true);changed.provenance[key].offset+=2
		check(not Definitions.validate(changed,header.source_executable_bytes,header.architecture,1,bindings.opening_dialogue).is_empty(),"Disconnected rescue declaration accepted: "+key)
	check(not Definitions.valid_parameters(data) and Definitions.valid_parameters(data,1),"Rescue accepted as opening dialogue")
	for language in library.manifest.languages:
		check(library.select_language(language),library.error)
		var text:=TextResources.new()
		check(text.prepare(library,bindings,null,1) and text.line_counts.size()==3 and text.speakers.has(2),"Rescue layout/name failed for "+language+": "+text.error)
	for language in ["gb","de","fr"]:
		check(library.select_language(language),library.error)
		var clips:=Resources.new();check(clips.configure(library,bindings,1),clips.error)
		for index in 3:
			var clip:=clips.prepare(501+index)
			if clip.is_empty() or clip.has("unsupported"):check(false,clips.error+str(clip));continue
			check(clip.voice and not clip.spatial and not clip.looping and clip.source_bank.ends_with("_deu.fsb" if language=="de" else "_eng.fsb"),"Rescue clip used another language or playback type")
			check(clip.source_index==342+index and clip.stream.get_length()>0,"Rescue recording selected another sample")
		check(clips.prepare(469).has("unsupported"),"Rescue clip owner accepted an opening-only voice")
		if language!="fr":await verify_sequence(library,bindings,visuals)
	print(edition,": three rescue transmissions, English/German voices, all text languages and source portrait")

func verify_pack_failures(pack: String, base: Dictionary):
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-rescue-radio-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","wrong_voice_text","missing_voice","empty"]:
		var body:=original.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":body.erase("arrival_dialogue")
			"wrong_type":body.arrival_dialogue=false
			"wrong_voice_text":body.arrival_dialogue.voice.text_ids[0]+=1
			"missing_voice":body.arrival_dialogue.erase("voice")
			"empty":
				body.arrival_dialogue={}
				if body.has("arrival_staging"):body.arrival_staging={}
				if body.opening_actors.player_initialization.has("flight_cache"):body.opening_actors.player_initialization.flight_cache={}
				if body.has("arrival_environment"):body.arrival_environment={}
				if body.has("arrival_actor_motion"):body.arrival_actor_motion={}
		var serialized:=JSON.stringify(body,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,base),reader.error)
		var accepted:=reader.open(directory,base)
		if scenario=="empty":check(accepted and reader.arrival_dialogue.is_empty() and not reader.opening_dialogue.is_empty(),"Explicit unsupported rescue capability was rejected")
		else:check(not accepted and reader.arrival_dialogue.is_empty() and reader.opening_dialogue.is_empty() and reader.audio.is_empty(),"Invalid replacement retained scene data: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func verify_sequence(library: RefCounted, bindings: RefCounted, visuals: RefCounted):
	var text:=TextResources.new();var radio:=Radio.new();var audio:=Audio.new();var panel:=RadioPanel.new()
	var surface:=SubViewport.new();surface.size=Vector2i(1000,700);surface.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(audio);root.add_child(surface);surface.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not text.prepare(library,bindings,visuals,1) or not radio.configure(bindings,library,text.line_counts,1) or not audio.configure(library,bindings,73,1):
		check(false,text.error+radio.error+audio.error);audio.free();surface.free();return
	check(text.portrait_diagnostics.is_empty() and text.speakers[2].has("portrait"),"Original rescue portrait unavailable")
	check(panel.configure(bindings.base_content_id,bindings.binding_id,library.active_language,text.speakers,1),panel.error)
	print(library.manifest.profile.edition," ",library.active_language," speaker=",text.speakers[2].name," source_lines=",text.line_counts)
	audio.set_paused(true)
	check(radio.step(9999,{},0).is_empty() and not radio.snapshot().started.any(func(value):return value),"Rescue radio started before its ten-second gate")
	var time:=10000;var revision:=0
	for event in 3:
		var start:=time
		var changes:=radio.step(time,{},0)
		check(changes==[{"kind":"started","event":event}],"Wrong rescue radio order")
		var pending:=audio.prepare_frame(revision,frame(time,radio,changes))
		check(not pending.is_empty() and pending.operations.is_empty(),"Voice played before display")
		audio.commit_frame(pending);revision+=1
		time+=2000;changes=radio.step(time,{},0)
		check(changes.is_empty() and not radio.snapshot().visible,"Radio display equality was shortened")
		time+=1;changes=radio.step(time,{},0)
		var state:=frame(time,radio,changes);var before:=audio.snapshot()
		pending=audio.prepare_frame(revision,state)
		check(not pending.is_empty() and pending.operations.size()==1 and pending.operations[0].source_id==501+event and audio.snapshot()==before,"Radio display did not stage exactly its original voice")
		var corrupt:=state.duplicate(true);corrupt.radio.campaign_cursor=0
		check(audio.prepare_frame(revision,corrupt).is_empty() and audio.snapshot()==before,"Cross-scene audio changed rescue ownership")
		check(not panel.present(corrupt.radio),"Cross-scene radio replaced rescue text")
		audio.commit_frame(pending);revision+=1
		check(audio.snapshot().voice_displayed[event] and audio.snapshot().active.has(501+event),"Accepted rescue voice did not play")
		check(audio.snapshot().active.values().all(func(value):return value.paused),"Rescue voice escaped pause")
		check(panel.present(radio.snapshot()) and panel.visible,panel.error)
		if library.active_language=="gb" or event==0:await capture(panel,library,event,false)
		if library.active_language=="gb" and event==0:await capture(panel,library,event,true)
		var candidate:=radio.fork_for_frame();candidate.step(time+50,{},0)
		check(radio.snapshot()==state.radio,"Uncommitted radio candidate changed scene state")
		time=start+2000+1500+2000*int(text.line_counts[event])
		changes=radio.step(time,{},0)
		check(changes.is_empty() and not radio.snapshot().finished[event],"Rescue radio finish equality was shortened")
		time+=1;changes=radio.step(time,{},0)
		check(changes==[{"kind":"finished","event":event}],"Rescue transmission never finished")
		pending=audio.prepare_frame(revision,frame(time,radio,changes))
		check(not pending.is_empty() and pending.operations.is_empty(),"Finishing rescue text stopped or repeated speech")
		audio.commit_frame(pending);revision+=1
	check(radio.snapshot().finished==[true,true,true] and not radio.snapshot().has("mission_completed"),"Radio granted unsupported mission completion")
	check(panel.present(radio.snapshot()) and not panel.visible,"Finished rescue text remained visible")
	audio.clear();check(audio.get_child_count()==0 and audio.snapshot().voice_displayed.is_empty(),"Leaving rescue retained audio owners")
	check(radio.configure(bindings,library,text.line_counts,1) and radio.step(9999,{},0).is_empty() and radio.snapshot().finished==[false,false,false],"Fresh rescue inherited old timing/completion")
	audio.free();surface.free();await process_frame

func capture(panel: Control, library: RefCounted, event: int, mobile: bool):
	var directory:=OS.get_environment("GOF2_ARRIVAL_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	var surface:=panel.get_viewport() as SubViewport
	panel.set_mobile_layout(mobile)
	surface.size=Vector2i(850,500) if mobile else Vector2i(1000,700)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	var name:="%s-%s-%d-%s.png"%[library.manifest.profile.edition,library.active_language,event,"phone" if mobile else "desktop"]
	var captured:=surface.get_texture().get_image()
	check(captured.get_size()==surface.size and captured.save_png(directory.path_join(name))==OK,"Unable to capture rescue radio at the intended size")
	check(panel._panel.size.x>(400 if mobile else 350) and panel._panel.size.x<surface.size.x,"Rescue composition used a stretched viewport")
	panel.set_mobile_layout(false);surface.size=Vector2i(1000,700)
	await process_frame

func frame(time: int, radio: RefCounted, changes: Array) -> Dictionary:
	return {"elapsed_ms":time,"radio":radio.snapshot(),"radio_changes":changes}

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
