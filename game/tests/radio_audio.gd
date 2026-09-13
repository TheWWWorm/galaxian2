extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Definitions=preload("res://src/content/radio_audio_definitions.gd")
const Resources=preload("res://src/content/audio_resources.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const TextResources=preload("res://src/presentation/opening_radio_resources.gd")
const OPENING_IDS=[469,470,481,485,486,487,488,489,490,491,471,472,473,474,475,476,477,478,479,480,482,483,484]
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3):
		verify_source(args[i],args[i+1])
		await process_frame
		await process_frame
	print("Radio audio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_source(content: String, pack: String):
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var voice: Dictionary=bindings.opening_dialogue.get("voice",{})
	if voice.is_empty():
		var old:=Resources.new()
		check(old.configure(library,bindings) and old.prepare(469).has("unsupported"),"Legacy pack invented a radio voice owner")
		return
	check(voice.event_ids.map(func(id):return int(id))==OPENING_IDS,"Opening lines did not use their edition's text-to-voice table")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	verify_pack_failures(pack,library.manifest)
	for key in voice.provenance:
		var broken:=voice.duplicate(true);broken.provenance[key].offset+=2
		check(not Definitions.validate(broken,header.source_executable_bytes,header.architecture,bindings.opening_dialogue,bindings.font_bindings,bindings.audio).is_empty(),"Detached radio voice provenance accepted: "+key)
	var broken:=voice.duplicate(true);broken.text_ids[0]+=1
	check(not Definitions.validate(broken,header.source_executable_bytes,header.architecture,bindings.opening_dialogue,bindings.font_bindings,bindings.audio).is_empty(),"Voice bound to another localization row")
	broken=voice.duplicate(true);broken.event_ids[0]=bindings.audio.events.size()
	check(not Definitions.validate(broken,header.source_executable_bytes,header.architecture,bindings.opening_dialogue,bindings.font_bindings,bindings.audio).is_empty(),"Voice outside the FEV event catalogue accepted")
	for code in library.manifest.languages:
		check(Definitions.language(voice,code)==("deutsch" if code=="de" else "english"),"Wrong source speech fallback for "+code)
	check(library.select_language("gb"),library.error)
	verify_missing_recording(library,bindings)
	for code in ["gb","de","fr"]:
		check(library.select_language(code),library.error)
		var resource:=Resources.new();check(resource.configure(library,bindings),resource.error)
		for event in OPENING_IDS:
			var clip:=resource.prepare(event)
			if clip.is_empty() or clip.has("unsupported"):check(false,resource.error+str(clip));continue
			var suffix:="_deu.fsb" if code=="de" else "_eng.fsb"
			check(clip.voice and not clip.looping and not clip.spatial and clip.source_bank.ends_with(suffix),"Radio voice used wrong language, spatial mode or loop")
			check(clip.source_index==310+event-469 and clip.stream.get_length()>0 and clip.fade_out_ms==100,"Source voice sample or fade was lost")
		check(resource.prepare(163).has("unsupported"),"Unconnected later mission voice silently gained a native owner")
		if code!="fr":verify_radio(library,bindings)
	print(library.manifest.profile.edition,": all 23 English/German display cues, language fallback, category stealing and frame isolation verified")

func verify_pack_failures(pack: String, base: Dictionary) -> void:
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-radio-audio-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","wrong_text","outside_event","empty"]:
		var body:=original.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":body.opening_dialogue.erase("voice")
			"wrong_type":body.opening_dialogue.voice=false
			"wrong_text":body.opening_dialogue.events[0].text_id+=1
			"outside_event":body.opening_dialogue.voice.event_ids[0]=body.audio.events.size()
			"empty":body.opening_dialogue.voice={}
		var serialized:=JSON.stringify(body,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,base),reader.error)
		var accepted:=reader.open(directory,base)
		if scenario=="empty":check(accepted and reader.opening_dialogue.voice.is_empty(),"Explicit unsupported voice capability was rejected: "+reader.error)
		else:check(not accepted and reader.opening_dialogue.is_empty() and reader.audio.is_empty(),"Invalid replacement retained radio/audio data: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func verify_missing_recording(library: RefCounted, bindings: RefCounted) -> void:
	var partial:=Bindings.new();partial.base_content_id=bindings.base_content_id;partial.binding_id=bindings.binding_id
	partial.audio=bindings.audio;partial.opening_dialogue=bindings.opening_dialogue.duplicate(true)
	partial.opening_dialogue.voice.event_ids[0]=-1
	var radio:=Radio.new();var counts: Array=[];counts.resize(23);counts.fill(1)
	var audio:=Audio.new();root.add_child(audio)
	if not radio.configure(partial,library,counts) or not audio.configure(library,partial):check(false,radio.error+audio.error);audio.free();return
	var time:=int(partial.opening_dialogue.events[0].values[0]);radio.step(time,{},0)
	var changes:=radio.step(time+2001,{},0)
	var pending:=audio.prepare_frame(0,frame(time+2001,radio,changes))
	check(not pending.is_empty() and pending.operations.is_empty(),"Absent recording invented a replacement voice")
	audio.commit_frame(pending)
	check(audio.snapshot().voice_displayed[0] and audio.snapshot().active.is_empty(),"Missing voice changed the original text display")
	audio.clear();audio.free()

func verify_radio(library: RefCounted, bindings: RefCounted):
	var text:=TextResources.new();var radio:=Radio.new();var audio:=Audio.new();root.add_child(audio)
	if not text.prepare(library,bindings) or not radio.configure(bindings,library,text.line_counts) or not audio.configure(library,bindings):check(false,text.error+radio.error+audio.error);audio.free();return
	audio.set_paused(true)
	var time:=0;var revision:=0;var first: Node
	var original_rng: int=audio.snapshot().random_state
	for event in 23:
		var row: Dictionary=bindings.opening_dialogue.events[event]
		var phase: int=int(row.values[0]) if row.condition==27 else 0
		if row.condition==5:time=maxi(time,int(row.values[0]))
		var started_at:=time
		var changes: Array=radio.step(time,{0:0,1:0,2:0},phase)
		check(changes==[{"kind":"started","event":event}],"Wrong source event became eligible")
		var state:=frame(time,radio,changes)
		var pending:=audio.prepare_frame(revision,state)
		check(not pending.is_empty() and pending.operations.is_empty(),"Radio activation played before its display delay")
		audio.commit_frame(pending);revision+=1
		time+=2000;changes=radio.step(time,{0:0,1:0,2:0},phase)
		pending=audio.prepare_frame(revision,frame(time,radio,changes))
		check(not pending.is_empty() and pending.operations.is_empty(),"Voice played at display-delay equality")
		audio.commit_frame(pending);revision+=1
		time+=1;changes=radio.step(time,{0:0,1:0,2:0},phase);state=frame(time,radio,changes)
		var before:=audio.snapshot();pending=audio.prepare_frame(revision,state)
		check(not pending.is_empty() and audio.snapshot()==before and pending.operations.size()==1 and pending.operations[0].source_id==OPENING_IDS[event],"Display did not prepare exactly its source voice without side effects")
		if event==0:
			var corrupt:=state.duplicate(true);corrupt.radio_changes[0].text_id+=1
			check(audio.prepare_frame(revision,corrupt).is_empty() and audio.snapshot()==before,"Wrong text partially played a voice")
			corrupt=state.duplicate(true);corrupt.radio.language="another-language"
			check(audio.prepare_frame(revision,corrupt).is_empty() and audio.snapshot()==before,"Cross-language radio played")
			corrupt=state.duplicate(true);corrupt.radio_changes.append(42)
			check(audio.prepare_frame(revision,corrupt).is_empty(),"Malformed radio transition accepted")
			corrupt=state.duplicate(true);corrupt.escape={"frame":{"audio":[{"action":"start","source_id":20000}]}}
			check(audio.prepare_frame(revision,corrupt).is_empty() and audio.snapshot()==before,"Late invalid audio consumed the staged display flag")
			corrupt=state.duplicate(true);corrupt.radio.visible=1
			check(audio.prepare_frame(revision,corrupt).is_empty(),"Nonboolean radio visibility accepted")
		audio.commit_frame(pending)
		var committed:=audio.snapshot()
		if event==0:
			pending.voice_displayed[0]=false
			check(audio.snapshot().voice_displayed[0],"Prepared voice frame aliases committed display ownership")
			pending.voice_displayed[0]=true
		check(committed.voice_displayed[event] and committed.active.has(OPENING_IDS[event]) and committed.active[OPENING_IDS[event]].paused,"Accepted display omitted or unpaused its voice")
		check(committed.active.values().filter(func(v):return v.get("voice",false)).size()==mini(event+1,2),"Source voice category limit was not respected")
		if event==0:first=audio._players[469].node
		if event==2:check(first.is_queued_for_deletion() and not committed.active.has(469) and committed.retiring==0,"Third voice did not stop the oldest immediately")
		audio.commit_frame(pending);check(audio.snapshot()==committed,"Repeated frame duplicated radio playback")
		revision+=1
		check(audio.prepare_frame(revision,state).is_empty() and audio.snapshot()==committed,"Later revision replayed an already displayed radio event")
		time=started_at+2000+1500+2000*int(text.line_counts[event])
		changes=radio.step(time,{0:0,1:0,2:0},phase)
		pending=audio.prepare_frame(revision,frame(time,radio,changes))
		check(not pending.is_empty() and pending.operations.is_empty() and not radio.snapshot().finished[event],"Radio finish equality changed voice ownership")
		audio.commit_frame(pending);revision+=1
		time+=1;changes=radio.step(time,{0:0,1:0,2:0},phase)
		pending=audio.prepare_frame(revision,frame(time,radio,changes))
		check(not pending.is_empty() and pending.operations.is_empty() and radio.snapshot().finished[event],"Text completion interrupted or retriggered its voice")
		audio.commit_frame(pending);revision+=1
		check(audio._players.has(OPENING_IDS[event]),"Radio completion stopped a pending source recording")
	check(audio.snapshot().voice_displayed.all(func(v):return v) and audio.snapshot().random_state==original_rng,"Radio consumed audio randomness or missed a source line")
	audio.clear();check(audio.get_child_count()==0 and audio.snapshot().voice_displayed.is_empty(),"Leaving radio retained a voice or display state")
	audio.free()

func frame(time: int, radio: RefCounted, changes: Array) -> Dictionary:
	return {"elapsed_ms":time,"radio":radio.snapshot(),"radio_changes":changes,"camera":{"view":{"pose":Transform3D.IDENTITY}}}
func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
