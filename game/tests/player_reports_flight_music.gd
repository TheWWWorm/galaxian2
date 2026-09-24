extends SceneTree
## Connected opening battle and first mining peace music on the constructed
## faction-three actors. The source's separate faction-zero random-world group
## can create marked actors and is not represented by these current fixtures.
const OpeningSession=preload("res://src/presentation/opening_session.gd")
const OpeningAudio=preload("res://src/presentation/opening_audio.gd")
const FirstFrame=preload("res://src/simulation/first_flight_frame.gd")
const FirstConstruction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")

var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected Mac content, bindings and visuals")
	if args.size()==3:await verify(args)
	print("Connected flight music: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not library.select_language("gb") or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	check(not bindings.ordinary_music.is_empty(),"Current binding pack omitted ordinary music")
	if failures:return
	await verify_opening(library,bindings,visuals)
	if failures:return
	verify_first_flight(library,bindings)

func verify_opening(library: RefCounted,bindings: RefCounted,visuals: RefCounted) -> void:
	var session:=OpeningSession.new();root.add_child(session);session.set_process(false)
	if not session.configure(library,bindings,visuals,0,0.5,1789100000,true,true):
		check(false,session.error);session.free();return
	var now:=0
	var hidden_sample:=false
	var rejected_music:=false
	var selected_music:=false
	for tick in 3000:
		var phase: int=int(session._timeline.snapshot().camera.shot.phase)
		var next_time:=now+100000
		if phase==3 and not rejected_music:
			var candidate: Dictionary=session._world_frame.evaluate(session._timeline,session._scenery,100,true,1.0,Vector2.ZERO,false,Vector2i(1280,720),true,session.audio.current_music_id())
			if candidate.is_empty():check(false,session._world_frame.error);break
			if int(candidate.timeline.snapshot().camera.shot.phase)==4:
				var before: Dictionary=session.snapshot()
				var proposal: Dictionary=candidate.world_frame.snapshot()
				check(proposal.flight_music.operations==[{"action":"replace_music","source_id":141}],"Opening handoff did not propose the three-actor battle cue")
				var audio_before: Dictionary=session.audio.snapshot()
				check(session._world_frame.evaluate(session._timeline,session._scenery,100,"invalid",1.0,Vector2.ZERO,false,Vector2i(1280,720),true,session.audio.current_music_id()).is_empty() and session.snapshot()==before and session.audio.snapshot()==audio_before,"Rejected parent world frame changed its sources or audio")
				var model: Node3D=session.scenery.objects[0]
				var resource_id: Variant=model.get_meta("source_resource_id")
				model.set_meta("source_resource_id",-1)
				check(not session.step(next_time),"Invalid scenery presentation accepted battle music")
				check(session.snapshot()==before and session.audio.snapshot()==audio_before,"Rejected presentation committed world or music playback")
				model.set_meta("source_resource_id",resource_id)
				check(session.present(),session.error)
				rejected_music=true
				if failures:break
		if not session.step(next_time):check(false,session.error);break
		now=next_time
		phase=int(session._timeline.snapshot().camera.shot.phase)
		if phase<4 and not hidden_sample:
			hidden_sample=true
			check(session._world_frame.snapshot().flight_music.operations.is_empty(),"Hidden cinematic radar changed music")
		if phase==4:
			var state: Dictionary=session.snapshot()
			var radar: Dictionary=session._world_frame._radar.snapshot()
			check(radar.scanner_present and radar.battle_count==3 and radar.battle,"Opening combat music did not use the accepted scanner-gated actor count")
			check(state.combat.actors.size()==3 and state.combat.actors.all(func(actor):return actor.active and actor.actor_kind==8 and actor.get("radar_marked_actor")==false),"Opening battle count included an unproved actor marker or population")
			check(state.world_frame.flight_music.operations==[{"action":"replace_music","source_id":141}],"Opening combat frame lost its selected music operation")
			check(session.audio.current_music_id()==141 and music_history_count(session.audio.snapshot().history,141)==1,"Accepted opening battle cue did not play exactly once")
			var history: Array=session.audio.snapshot().history
			check(session.present() and session.audio.snapshot().history==history,"Repeated opening presentation replayed battle music")
			var held: Dictionary=session._world_frame.evaluate(session._timeline,session._scenery,100,true,1.0,Vector2.ZERO,false,Vector2i(1280,720),true,143)
			check(not held.is_empty() and held.world_frame.snapshot().flight_music.operations.is_empty(),"Retained intro143 did not hold despite a visible battle radar")
			check(session.step(now+100000),session.error)
			var next_state: Dictionary=session.snapshot()
			check(next_state.world_frame.flight_music.operations.is_empty() and music_history_count(session.audio.snapshot().history,141)==1,"Held battle music was replaced or replayed on the next accepted frame: "+str(next_state.world_frame.flight_music)+" cue="+str(session.audio.current_music_id())+" count="+str(session._world_frame._radar.battle_count())+" history="+str(music_history_count(session.audio.snapshot().history,141)))
			selected_music=true
			break
	check(hidden_sample and rejected_music and selected_music,"Opening music acceptance never reached all cinematic, rollback and combat boundaries")
	session.free()

func verify_first_flight(library: RefCounted,bindings: RefCounted) -> void:
	var catalogues:=Catalogues.new();var bodies:=Bodies.new()
	if not catalogues.open(library) or not bodies.configure(library,bindings):check(false,catalogues.error+bodies.error);return
	var player:=Player.new();var handoff:=Handoff.new()
	if not player.configure(bindings,catalogues):check(false,player.error);return
	var packet: Dictionary=handoff.prepare(bindings,catalogues,Fixture.completed(bindings,player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,catalogues,library,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for tick in 500:
		var next: RefCounted=arrival.evaluate(100)
		if next==null:check(false,arrival.error);return
		arrival=next
		if not arrival.snapshot().boundary.is_empty():break
	check(not arrival.snapshot().boundary.is_empty(),"Rescue fixture never earned the first station")
	if failures:return
	var station:=Station.new()
	if not station.configure(bindings,catalogues,library,arrival.prepare_station()):check(false,station.error);return
	for page in 19:station.acknowledge()
	var construction:=FirstConstruction.new()
	if not construction.prepare(bindings,catalogues,station.prepare_departure(bindings,catalogues),4096,1789100000,true,bodies):check(false,construction.error);return
	var flight:=FirstFrame.new()
	if not flight.configure(bindings,catalogues,library,construction,"E",0.5):check(false,flight.error);return
	check(flight.snapshot().get("flight_music",{}).get("operations",null)==[],"First-flight music owner was not attached at departure")
	var audio:=OpeningAudio.new();root.add_child(audio)
	if not audio.configure_full_hold(library,bindings,flight):check(false,audio.error);audio.free();return
	var initial: Dictionary=audio.prepare_full_hold(flight)
	if initial.is_empty():check(false,audio.error);audio.free();return
	audio.commit_frame(initial)
	for tick in 70:
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0,false,Vector2i.ZERO,Vector2.ZERO,false,false,false,audio.current_music_id())
		if next==null:check(false,flight.error);audio.free();return
		flight=next
		var quiet: Dictionary=audio.prepare_full_hold(flight)
		if quiet.is_empty():check(false,audio.error);audio.free();return
		audio.commit_frame(quiet)
	check(not flight.snapshot().entry_released and flight.snapshot().flight_music.operations.is_empty() and audio.current_music_id()==-1,"Hidden first-flight entry selected exploration music")
	if failures:audio.free();return
	var intro_hold: RefCounted=flight.evaluate(1,Vector2.ZERO,0.0,false,Vector2i.ZERO,Vector2.ZERO,false,false,false,143)
	check(intro_hold!=null and intro_hold.snapshot().flight_music.operations.is_empty(),"Retained intro143 was replaced on first-flight release")
	var released: RefCounted=flight.evaluate(1,Vector2.ZERO,0.0,false,Vector2i.ZERO,Vector2.ZERO,false,false,false,audio.current_music_id())
	if released==null:check(false,flight.error);audio.free();return
	check(released.snapshot().entry_released and released.snapshot().fast_forward.battle_count==0,"First mining flight did not publish its empty visible radar")
	check(released.snapshot().flight_music.operations==[{"action":"replace_music","source_id":137}],"First mining flight did not select the Mido faction exploration cue")
	var prepared: Dictionary=audio.prepare_full_hold(released)
	if prepared.is_empty():check(false,audio.error);audio.free();return
	audio.commit_frame(prepared)
	check(audio.current_music_id()==137 and music_history_count(audio.snapshot().history,137)==1,"First-flight presenter did not play exploration music exactly once")
	var retained: RefCounted=released.evaluate(100,Vector2.ZERO,0.0,false,Vector2i.ZERO,Vector2.ZERO,false,false,false,audio.current_music_id())
	if retained==null:check(false,released.error);audio.free();return
	check(retained.snapshot().flight_music.operations.is_empty(),"Retained exploration cue was replaced on the next visible radar sample")
	prepared=audio.prepare_full_hold(retained)
	if prepared.is_empty():check(false,audio.error);audio.free();return
	audio.commit_frame(prepared)
	check(music_history_count(audio.snapshot().history,137)==1,"Retained exploration cue replayed during accepted audio commit")
	audio.free()

func music_history_count(history: Array,source_id: int) -> int:
	return history.filter(func(event):return event.get("action")=="replace_music" and event.get("source_id")==source_id).size()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
