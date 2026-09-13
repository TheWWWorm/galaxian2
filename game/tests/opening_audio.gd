extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const Definitions=preload("res://src/content/audio_definitions.gd")
const Resources=preload("res://src/content/audio_resources.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size(),3):
		verify_source(args[i],args[i+1])
		await process_frame
		await process_frame
	print("Opening audio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify_source(content: String,pack: String):
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var audio:=Audio.new();root.add_child(audio)
	if bindings.audio.is_empty():
		check(not audio.configure(library,bindings),"Legacy bindings fabricated audio events");audio.free();return
	if not audio.configure(library,bindings):check(false,audio.error);audio.free();return
	check(bindings.audio.events.size()==2293 and bindings.audio.sound_definitions.size()==2293,"Event index not read from the selected source")
	check(Definitions.normalized(bindings.audio).sound_settings[29].spawn_min_ms==1000,"Source spawn milliseconds were lost, including legacy float-bit normalization")
	var corrupted: Dictionary=bindings.audio.duplicate(true);corrupted.source_sha256="0".repeat(64)
	check(not Definitions.validate(corrupted,library.manifest.files).is_empty(),"Cross-source FEV provenance accepted")
	var changed:=Bindings.new();changed.base_content_id=bindings.base_content_id;changed.audio=bindings.audio.duplicate(true)
	changed.audio=Definitions.normalized(changed.audio)
	var resource:=Resources.new()
	changed.audio.categories.volume=0.5
	check(resource.configure(library,changed) and resource.prepare(141).has("unsupported"),"Non-neutral category gain was silently discarded")
	changed.audio.categories.volume=1.0;changed.audio.events[157].properties.cone_inside=90.0
	changed.audio.events[157].properties.cone_outside_volume=0.5
	check(resource.configure(library,changed) and resource.prepare(157).has("unsupported"),"Directional cone was silently replaced with an omnidirectional source")
	changed.audio.events[157].properties.cone_inside=360.0;changed.audio.events[157].properties.cone_outside_volume=1.0
	check(resource.configure(library,changed) and is_equal_approx(resource.prepare(141).gain,bindings.audio.events[141].properties.volume),"Authored music gain changed during preparation")
	var layered: Dictionary=resource.prepare(156)
	check(layered.get("kind")=="layered" and layered.layers.size()==2 and layered.layers[1].size()==3 and layered.layers[1][0].definition.samples.size()==14,"Layer preparation lost source windows or playlist entries")
	for id in [18,19,20]:
		var blast: Dictionary=resource.prepare(id)
		check(blast.get("kind")=="playlist" and not blast.looping and blast.definition.playlist_flags==3 and blast.definition.samples.size()=={18:4,19:5,20:2}[id],"Static destruction playlist lost source choices or became a loop")
	var settings_id: int=int(changed.audio.sound_definitions[749].settings)
	changed.audio.sound_settings[settings_id].spawn_min_ms=1
	check(resource.configure(library,changed) and resource.prepare(20).has("unsupported"),"Delayed spawning was silently reduced to one immediate clip")
	changed.audio.sound_settings[settings_id].spawn_min_ms=0
	changed.audio.events[156].properties.flags=1
	check(resource.configure(library,changed) and resource.prepare(156).has("unsupported"),"Unsupported event-level termination was silently discarded")
	var entry:=frame(0,[{"action":"replace_music","source_id":143}])
	var prepared: Dictionary=audio.prepare_frame(0,entry)
	check(not prepared.is_empty() and audio.snapshot().active.is_empty(),"Preparing audio played before commitment")
	audio.commit_frame(prepared)
	check(audio.snapshot().active.has(143) and audio.snapshot().active[143].looping,"Entry music not playing in a loop")
	var old: Dictionary=audio.snapshot()
	audio.commit_frame(prepared)
	check(audio.snapshot()==old,"Duplicate commit restarted playback")
	prepared=audio.prepare_frame(0,entry);audio.commit_frame(prepared)
	check(audio.snapshot()==old,"Repeated presentation replayed a cue")
	prepared=audio.prepare_frame(1,frame(100,[{"action":"start","source_id":161},{"action":"position","source_id":161,"position":Vector3(INF,0,0)}]))
	check(prepared.is_empty() and audio.snapshot()==old,"Late invalid command partially played audio")
	check(audio.prepare_frame(3,frame(100,[])).is_empty(),"Skipped audio revision accepted")
	prepared=audio.prepare_frame(1,frame(100,[{"action":"start_spatial","source_id":157,"position":Vector3(10,0,0)},{"action":"start","source_id":158},{"action":"start","source_id":161}]))
	check(not prepared.is_empty(),audio.error);audio.commit_frame(prepared)
	check(audio.snapshot().active.has(157) and not audio.snapshot().active[157].looping and audio.snapshot().active[158].looping==false,"One-shot escape sounds became loops")
	check(audio.snapshot().active[157].position==Vector3(10,0,0) and audio.snapshot().active[161].looping,"Source positions or damaged drive loop were lost")
	audio.set_paused(true)
	check(audio.snapshot().active.values().all(func(v):return v.paused),"Pause did not freeze all active streams")
	audio.set_paused(false)
	check(audio.snapshot().active.values().all(func(v):return not v.paused),"Resume left an active stream paused")
	prepared=audio.prepare_frame(2,frame(200,[{"action":"stop","source_id":161},{"action":"replace_music","source_id":141},{"action":"start","source_id":160}]))
	audio.commit_frame(prepared)
	check(not audio.snapshot().active.has(161) and audio.snapshot().active.has(141) and audio.snapshot().retiring==2,"Source stop fades did not retain retiring streams")
	prepared=audio.prepare_frame(3,frame(1000,[{"action":"stop","source_id":158},{"action":"set_player_engine","source_id":156}]))
	audio.commit_frame(prepared)
	check(audio.snapshot().retiring==0 and not audio.snapshot().active.has(158),"Stop fade or immediate stop did not finish")
	check(audio.snapshot().unsupported.is_empty() and audio.snapshot().active.has(156) and audio.snapshot().active[156].layers.voices.has("0:0"),"Layered engine did not start its continuous original sound")
	var sequence: Dictionary=audio.snapshot().active[156].layers.sequence
	check(audio.prepare_frame(4,frame(1100,[{"action":"position","source_id":156,"position":Vector3(INF,0,0)}])).is_empty() and audio.snapshot().active[156].layers.sequence==sequence,"Rejected audio frame consumed layered time or randomness")
	audio.commit_frame(audio.prepare_frame(4,frame(1100,[{"action":"stop","source_id":141}])))
	audio.commit_frame(audio.prepare_frame(5,frame(1200,[{"action":"replace_music","source_id":141}])))
	check(audio.snapshot().retiring==0 and audio.snapshot().active.has(141),"Restarting a single-instance event retained its previous fading instance")
	check(audio.snapshot().active[156].layers.voices.has("1:0"),"The damaged engine's first authored one-shot window did not trigger")
	audio.set_paused(true)
	var paused: Dictionary=audio.snapshot().active[156].layers
	check(paused.paused and paused.voices.values().all(func(v):return v.paused),"Pause did not reach every layered voice")
	audio.commit_frame(audio.prepare_frame(6,frame(1200,[])))
	check(audio.snapshot().active[156].layers.sequence==paused.sequence,"Paused layered audio consumed parameter time or randomness")
	audio.set_paused(false)
	check(not audio.snapshot().active[156].layers.paused and audio.snapshot().active[156].layers.voices.values().all(func(v):return not v.paused),"Layered resume left a voice paused")
	for step in 64:audio.commit_frame(audio.prepare_frame(7+step,frame(1300+step*100,[])))
	var history: Array=audio.snapshot().active[156].layers.history
	check(history.size()>=7 and history.filter(func(v):return v.key=="0:0").size()==1,"Layered event missed repeat windows or restarted its continuous loop")
	var last_index:=-1
	var valid_choices:=true
	var windows:={}
	for row in history:
		if row.key=="0:0":continue
		windows[row.key]=true
		valid_choices=valid_choices and row.action=="start" and row.playlist_index!=last_index and row.pitch>=pow(2.0,-0.100001) and row.pitch<=pow(2.0,0.100001) and row.gain>=0.56*0.7079457 and row.gain<=0.590001
		last_index=row.playlist_index
	check(valid_choices and windows.size()==3,"Layered playlist violated source repetition, gain, pitch or window rules")
	audio.commit_frame(audio.prepare_frame(71,frame(7700,[{"action":"stop_player_engine"}])))
	check(not audio.snapshot().active.has(156) and audio.snapshot().retiring==1,"Layered engine did not retain its source stop fade")
	audio.commit_frame(audio.prepare_frame(72,frame(8200,[])))
	check(audio.snapshot().retiring==0,"Layered engine survived its 500ms stop fade")
	audio.clear();check(audio.get_child_count()==0 and audio.snapshot().active.is_empty(),"Audio survived opening cleanup")
	audio.free()
	verify_deaths(library,bindings)

func verify_deaths(library: RefCounted, bindings: RefCounted):
	var audio:=Audio.new();root.add_child(audio)
	check(audio.configure(library,bindings,51),audio.error)
	var world:=death_frame(bindings,0,0,20,Vector3(100,0,0))
	if bindings.opening_actors.get("npc_initialization",{}).get("destruction_audio",{}).is_empty():
		audio.commit_frame(audio.prepare_frame(0,frame(0,[]),world))
		check(audio.snapshot().active.is_empty(),"Legacy motion declarations fabricated connected death audio")
		audio.free();return
	audio.set_paused(true)
	var original:=audio.snapshot()
	var prepared: Dictionary=audio.prepare_frame(0,frame(0,[]),world)
	check(not prepared.is_empty() and original==audio.snapshot(),"Death preparation consumed random state or played before commit")
	audio.commit_frame(prepared)
	var first:=audio.snapshot()
	check(first.active.has(20) and first.active[20].paused and first.active[20].position==Vector3(100,0,0),"Death cue did not retain its source position or pending pause")
	check(first.active[20].pitch>=pow(2.0,-0.050001) and first.active[20].pitch<=pow(2.0,0.050001),"Death cue ignored its original pitch randomization")
	var node: Node=audio.get_child(0)
	world=death_frame(bindings,100,1,20,Vector3(200,0,0))
	audio.commit_frame(audio.prepare_frame(1,frame(100,[]),world))
	var repeated:=audio.snapshot()
	check(audio.get_child(0)==node and repeated.random_state==first.random_state and repeated.active[20].pitch==first.active[20].pitch and repeated.active[20].position==Vector3(200,0,0),"Repeated cached start restarted a paused voice or consumed a new random choice")
	var broken: Dictionary=world.duplicate(true);broken.base_content_id="0".repeat(64);broken.elapsed_ms=200
	check(audio.prepare_frame(2,frame(200,[]),broken).is_empty() and audio.snapshot()==repeated,"Cross-source death frame partially changed audio")
	broken=death_frame(bindings,200,2,18,Vector3(INF,0,0))
	check(audio.prepare_frame(2,frame(200,[]),broken).is_empty() and audio.snapshot()==repeated,"Invalid final death position consumed audio randomness")
	broken=death_frame(bindings,200,2,20,Vector3.ZERO);broken.actor_events[0].destruction.started=false
	check(audio.prepare_frame(2,frame(200,[]),broken).is_empty(),"Death cue was accepted without its lifecycle transition")
	# A finished native voice permits a new cached-event start. The explicit
	# stop emulates sample completion without depending on headless audio time.
	audio.set_paused(false);node.stop()
	world=death_frame(bindings,200,2,20,Vector3(300,0,0))
	audio.commit_frame(audio.prepare_frame(2,frame(200,[]),world))
	check(node.is_queued_for_deletion() and audio.snapshot().random_state!=first.random_state and audio.snapshot().active[20].playing,"Finished cached voice did not start a new randomized sample")
	world=death_frame(bindings,300,0,19,Vector3(150,0,0))
	audio.commit_frame(audio.prepare_frame(3,frame(300,[]),world))
	check(audio.snapshot().active.has(19) and not audio.snapshot().active[19].looping and audio.snapshot().active[19].position==Vector3(150,0,0),"Breakup cue did not use its separately captured effect position")
	check(audio.snapshot().unsupported.is_empty(),"Connected death audio retained an unsupported event")
	audio.clear();audio.free()

func death_frame(bindings: RefCounted, ms: int, actor: int, id: int, position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":ms,"actor_events":[{"actor_id":actor,"destruction":{"started":id==20,"breakup":id!=20,"sound_events":[id],"audio_events":[{"source_id":id,"position":position}]}}]}

func frame(ms: int,commands: Array) -> Dictionary:
	return {"elapsed_ms":ms,"camera":{"view":{"pose":Transform3D.IDENTITY}},"escape":{"frame":{"audio":commands}}}
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
