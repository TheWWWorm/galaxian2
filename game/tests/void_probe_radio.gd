extends SceneTree
## Source-selected radio components only. No mission, stage or save is advanced.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Dialogue=preload("res://src/content/dialogue_definitions.gd")
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const VoidProbe=preload("res://src/content/void_probe_definitions.gd")
const Post=preload("res://src/content/post_sahi_definitions.gd")
const Sahi=preload("res://src/content/sahi_encounter_definitions.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const TextResources=preload("res://src/presentation/opening_radio_resources.gd")
const AudioResources=preload("res://src/content/audio_resources.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const Dima=preload("res://src/content/dima_encounter_definitions.gd")
const Story=preload("res://src/content/story_encounter_definitions.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected explicit content, bindings and visuals");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(args[0]) or not library.select_language("gb") or not bindings.open(args[1],library.manifest):
		check(false,library.error+bindings.error);quit(1);return
	if not Thynome.available(bindings) or not VoidProbe.parameters(bindings.mido_travel.get("void_probe",{})):
		for cursor in [28,29]:
			check(Dialogue.select(bindings,cursor).is_empty(),"Earlier binding exposed unguarded radio "+str(cursor))
			check(not Radio.new().configure(bindings,library,[1],cursor),"Earlier binding configured unguarded radio "+str(cursor))
			check(not AudioResources.new().configure(library,bindings,cursor),"Earlier binding prepared unguarded radio voice "+str(cursor))
			var audio:=Audio.new();root.add_child(audio)
			check(not audio.configure(library,bindings,0,cursor,{}),"Earlier binding admitted unguarded flight voice "+str(cursor))
			audio.free()
		print("Void probe radio (earlier binding): %d checks; %d failures"%[checks,failures])
		quit(1 if failures else 0);return
	verify_source(bindings,library)
	verify_dima(bindings,library)
	verify_probe(bindings,library)
	verify_audio(bindings,library)
	verify_existing(bindings,library)
	print("Void probe radio: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_source(bindings: RefCounted,library: RefCounted) -> void:
	for value in [Thynome.VALUES,Thynome.MAC_VALUES]:
		var events: Array=Dialogue._source_events(value.world28.radio_events)
		check(Dialogue.valid_parameters({"campaign_cursor":28,"events":events,"timing":Sahi.VALUES.radio_timing},28),"Dima radio variant lost its original rows")
		var changed:=events.duplicate(true);changed[0].values=[20001]
		check(not Dialogue.valid_parameters({"campaign_cursor":28,"events":changed,"timing":Sahi.VALUES.radio_timing},28),"Changed Dima activation threshold passed")
	for value in [VoidProbe.VALUES,VoidProbe.MAC_VALUES]:
		var events: Array=Dialogue._source_events(value.world29.radio_events)
		check(Dialogue.valid_parameters({"campaign_cursor":29,"events":events,"timing":Sahi.VALUES.radio_timing},29),"Probe radio variant lost its original rows")
		var changed:=events.duplicate(true);changed[0].condition=5
		check(not Dialogue.valid_parameters({"campaign_cursor":29,"events":changed,"timing":Sahi.VALUES.radio_timing},29),"Elapsed time replaced mother-ship lock")
		changed=events.duplicate(true);changed[4].values=[119999]
		check(not Dialogue.valid_parameters({"campaign_cursor":29,"events":changed,"timing":Sahi.VALUES.radio_timing},29),"Changed phase2 threshold passed")
	for cursor in [28,29]:
		var selected: Dictionary=Dialogue.select(bindings,cursor)
		var source: Array=bindings.mido_travel.thynome_expedition.world28.radio_events if cursor==28 else bindings.mido_travel.void_probe.world29.radio_events
		var expected: Array=Dialogue._source_events(source)
		check(Dialogue.valid_parameters(selected,cursor) and selected.events==expected,"Selected radio changed source text, speakers or conditions")
		check(selected.voice.event_ids==expected.map(func(row):return int(row.voice_event_id)) and selected.voice.text_ids==expected.map(func(row):return int(row.text_id)),"Selected radio voice IDs differ from source text IDs")
		for row in selected.events:
			check(library.strings[int(row.text_id)] is String and not library.strings[int(row.text_id)].is_empty(),"Selected source text is unavailable in English")

func prepared(bindings: RefCounted,library: RefCounted,cursor: int) -> Dictionary:
	var resources:=TextResources.new()
	if not resources.prepare(library,bindings,null,cursor):check(false,resources.error);return {}
	var radio:=Radio.new()
	if not radio.configure(bindings,library,resources.line_counts,cursor):check(false,radio.error);return {}
	return {"radio":radio,"counts":resources.line_counts}

func verify_dima(bindings: RefCounted,library: RefCounted) -> void:
	var fixture:=prepared(bindings,library,28)
	if fixture.is_empty():return
	var radio: RefCounted=fixture.radio
	check(radio.step(19999,{},0).is_empty() and radio.event_state(0)=={"condition_satisfied":false,"playback_finished":false},"Dima radio began before source 20-second threshold")
	check(radio.step(20000,{},0)==[{"kind":"started","event":0}] and radio.event_state(0).condition_satisfied,"Dima source row0 did not start at threshold")
	check(radio.snapshot().text==library.strings[int(Dialogue.select(bindings,28).events[0].text_id)] and radio.snapshot().speaker_id==0,"Dima first row bound another text or speaker")
	var end: int=20000+2000+1500+2000*int(fixture.counts[0])+1
	check(radio.step(end,{},0).back()=={"kind":"finished","event":0} and radio.event_state(0).playback_finished,"Dima first source line did not finish")
	check(radio.step(end,{},0)==[{"kind":"started","event":1}] and radio.snapshot().speaker_id==19,"Dima dependent row added an interline delay or wrong speaker")
	var source: Dictionary=Dialogue.select(bindings,28)
	check(source.events.map(func(row):return int(row.voice_event_id))==[516,548,517],"Dima source voice sequence changed")

func verify_probe(bindings: RefCounted,library: RefCounted) -> void:
	var fixture:=prepared(bindings,library,29)
	if fixture.is_empty():return
	var radio: RefCounted=fixture.radio
	var counts: Array=fixture.counts
	var obs:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":29,"stage_elapsed_ms":0,"mother_ship_locked":false}
	var before: Dictionary=radio.snapshot()
	check(radio.step(0,{},0).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Generic radio step bypassed the typed probe observation")
	for bad in ["base_content_id","binding_id","campaign_cursor","campaign_cursor_type","stage_elapsed_ms","stage_elapsed_type","mother_ship_locked"]:
		var wrong:=obs.duplicate(true)
		match bad:
			"base_content_id":wrong.base_content_id="foreign"
			"binding_id":wrong.binding_id="foreign"
			"campaign_cursor":wrong.campaign_cursor=28
			"campaign_cursor_type":wrong.campaign_cursor=29.0
			"stage_elapsed_ms":wrong.stage_elapsed_ms=-1
			"stage_elapsed_type":wrong.stage_elapsed_ms=1.0
			"mother_ship_locked":wrong.mother_ship_locked=1
		check(radio.step_probe(0,wrong).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Invalid probe observation changed radio: "+bad)
	check(radio.event_state(-1).is_empty() and radio.event_state(6).is_empty(),"Out-of-range radio event exposed state")
	check(radio.step_probe(0,obs).is_empty() and radio.event_state(0)=={"condition_satisfied":false,"playback_finished":false},"Probe started before mother-ship lock")
	obs.mother_ship_locked=true;obs.stage_elapsed_ms=10
	var time:=10
	check(radio.step_probe(time,obs)==[{"kind":"started","event":0}],"Mother-ship lock did not satisfy radio row0")
	check(radio.event_state(0)=={"condition_satisfied":true,"playback_finished":false} and radio.snapshot().active_event==0,"Phase1 trigger waited for playback instead of condition satisfaction")
	check(radio.step_probe(time+2000,obs).is_empty() and not radio.snapshot().visible,"Probe radio lost strict display delay")
	time=finish_event(radio,time,int(counts[0]),0,obs)
	check(radio.event_state(0).playback_finished and radio.snapshot().active_event==-1,"Row0 playback state was not retained")
	check(radio.step_probe(time,obs)==[{"kind":"started","event":1}],"Condition6 did not use row0 condition satisfaction without interline delay")
	check(radio.event_state(1)=={"condition_satisfied":true,"playback_finished":false},"Row1 condition and playback were conflated")
	time=finish_event(radio,time,int(counts[1]),1,obs)
	check(radio.event_state(1).playback_finished and radio.snapshot().active_event==-1,"Phase2 trigger did not wait for row1 playback finish")
	var held: Dictionary=radio.snapshot();var copy: RefCounted=radio.fork_for_frame()
	check(copy.event_state(1)==radio.event_state(1) and copy.snapshot()==held,"Probe row-state latches were lost in a frame fork")
	# The stage resets only its own elapsed time after this radio tick.
	obs.stage_elapsed_ms=0
	check(radio.step_probe(time+1,obs)==[{"kind":"started","event":2}],"Row2 did not first start on the post-reset radio tick")
	time=finish_event(radio,time+1,int(counts[2]),2,obs)
	check(radio.step_probe(time,obs)==[{"kind":"started","event":3}],"Probe row3 lost its started-index dependency")
	time=finish_event(radio,time,int(counts[3]),3,obs)
	obs.stage_elapsed_ms=119999
	var late: int=maxi(200000,time+1)
	check(radio.step_probe(late,obs).is_empty() and not radio.event_state(4).condition_satisfied,"Display elapsed time incorrectly satisfied phase2 condition5")
	obs.stage_elapsed_ms=120000
	check(radio.step_probe(late+1,obs)==[{"kind":"started","event":4}],"Phase2 condition5 missed its inclusive 120-second boundary")
	time=finish_event(radio,late+1,int(counts[4]),4,obs)
	check(radio.step_probe(time,obs)==[{"kind":"started","event":5}],"Probe final row lost its row4 started-index dependency")
	time=finish_event(radio,time,int(counts[5]),5,obs)
	check(radio.snapshot().finished.all(func(value):return value) and radio.event_state(5).playback_finished,"Probe radio did not finish all six source rows")
	var final_state: Dictionary=radio.snapshot();obs.stage_elapsed_ms=0
	check(radio.step_probe(time-1,obs).is_empty() and not radio.error.is_empty() and radio.snapshot()==final_state,"Stage-clock reset incorrectly reset monotonic display time")
	check(Dialogue.select(bindings,29).events.map(func(row):return int(row.voice_event_id))==[518,519,520,521,545,522],"Probe voice order differs from original source")

func finish_event(radio: RefCounted,start: int,lines: int,index: int,obs: Dictionary) -> int:
	var finish_at: int=start+2000+1500+2000*lines
	var at_boundary: Array=radio.step_probe(finish_at,obs)
	check(at_boundary.any(func(row):return row.kind=="display") and not at_boundary.any(func(row):return row.kind=="finished"),"Probe row finished at its inclusive playback boundary: "+str(index))
	var completed: Array=radio.step_probe(finish_at+1,obs)
	check(completed==[{"kind":"finished","event":index}],"Probe row did not finish at its strict playback boundary: "+str(index))
	return finish_at+1

func story_combat(bindings: RefCounted,cursor: int) -> Dictionary:
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":cursor,"station_id":91 if cursor==28 else -1,
		"system_id":18 if cursor==28 else -1,"mission_kind":4,
		"mission_story":true,"mission_completed":false,"mission_failed":false}
	if cursor==28:context.portal_position=Vector3(112345,-45678,12345)
	var population: Dictionary=Dima.population(bindings.mido_travel,context) if cursor==28 else Post.population(bindings.mido_travel,context)
	if population.is_empty():return {}
	var actors: Array=[]
	for row in population.actors:
		var actor: Dictionary=row.duplicate(true)
		actor.merge({"authored_story":true,"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id})
		actors.append(actor)
	return {"campaign_cursor":cursor,"context":context,"actors":actors}

func verify_audio(bindings: RefCounted,library: RefCounted) -> void:
	for cursor in [28,29]:
		var combat: Dictionary=story_combat(bindings,cursor)
		check(Story.combat_population(bindings,combat),"Authored radio audio lacks its selected story cast: "+str(cursor))
		if combat.is_empty():continue
		var dialogue: Dictionary=Dialogue.select(bindings,cursor)
		var resources:=AudioResources.new()
		if not resources.configure(library,bindings,cursor):check(false,resources.error);continue
		for id in dialogue.voice.event_ids:
			var clip: Dictionary=resources.prepare(int(id))
			check(not clip.is_empty() and not clip.has("unsupported") and clip.get("voice")==true and not clip.get("looping",true) and clip.get("source_bank","").ends_with("_eng.fsb") and clip.get("stream") is AudioStream and clip.stream.get_length()>0,"Authored source voice is unavailable: "+str(cursor)+"/"+str(id)+" "+resources.error)
		var audio:=Audio.new();root.add_child(audio)
		if not audio.configure(library,bindings,0,cursor,combat):check(false,audio.error);audio.free();continue
		check(audio._radio_voice.event_ids==dialogue.voice.event_ids and audio._local_radio_rules.is_empty() and audio._voice_displayed.size()==dialogue.events.size(),"Authored voice was replaced by ambient traffic radio: "+str(cursor))
		var invalid: Dictionary=combat.duplicate(true);invalid.actors[0].actor_kind=-1
		var rejected:=Audio.new();root.add_child(rejected)
		check(not rejected.configure(library,bindings,0,cursor,invalid),"Authored voice accepted an unrelated combat cast: "+str(cursor))
		rejected.free()
		var fixture: Dictionary=prepared(bindings,library,cursor)
		if fixture.is_empty():audio.free();continue
		var radio: RefCounted=fixture.radio
		var onset:=20000 if cursor==28 else 10
		var observation:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
			"campaign_cursor":29,"stage_elapsed_ms":10,"mother_ship_locked":true}
		var started: Array=radio.step(onset,{},0) if cursor==28 else radio.step_probe(onset,observation)
		check(started==[{"kind":"started","event":0}],"Authored radio did not start before voice display: "+str(cursor))
		var display_at: int=onset+2001
		var changes: Array=radio.step(display_at,{},0) if cursor==28 else radio.step_probe(display_at,observation)
		var frame:={"elapsed_ms":display_at,"camera":{"view":{"pose":Transform3D.IDENTITY}},"radio":radio.snapshot(),"radio_changes":changes}
		var before: Dictionary=audio.snapshot()
		var pending: Dictionary=audio.prepare_frame(0,frame)
		check(not pending.is_empty() and pending.get("operations",[]).size()==1 and pending.operations[0].source_id==int(dialogue.voice.event_ids[0]) and audio.snapshot()==before,"Authored display did not prepare only its source recording: "+str(cursor)+" "+audio.error)
		if not pending.is_empty():
			audio.commit_frame(pending)
			check(audio.snapshot().voice_displayed[0] and audio.snapshot().active.has(int(dialogue.voice.event_ids[0])),"Authored voice did not commit with its text: "+str(cursor))
		audio.clear();audio.free()

func verify_existing(bindings: RefCounted,library: RefCounted) -> void:
	for cursor in [24,25]:
		var selected: Dictionary=Dialogue.select(bindings,cursor)
		check(Dialogue.valid_parameters(selected,cursor),"Existing Sahi/Void radio declarations changed")
		var source: Array=bindings.mido_travel.sahi_encounter.radio_events if cursor==24 else Dialogue._source_events(bindings.mido_travel.post_sahi["void"].radio)
		check(selected.events==source,"Existing Sahi/Void radio source rows changed")
		var fixture:=prepared(bindings,library,cursor)
		if fixture.is_empty():continue
		var radio: RefCounted=fixture.radio
		if cursor==24:
			var observation:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
				"campaign_cursor":24,"recovery":{"accepted_quantity":0}}
			check(radio.step_sahi(12000,observation)==[{"kind":"started","event":0}],"Sahi24 radio lost its elapsed source row")
		else:
			check(radio.step(20000,{},0)==[{"kind":"started","event":0}],"Void25 radio lost its elapsed source row")
