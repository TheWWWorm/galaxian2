extends SceneTree
## Mac native flight audio. Close placements, lethal hits and the warmed cached
## music/engine are disclosed fixtures; actual native passes produce the cues.
const Fixture=preload("res://tests/full_hold_control.gd")
const Live=preload("res://tests/player_death_flight.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
var checks:=0
var failures:=0
var lib:=Library.new()
var bindings:=Bindings.new()
var initial: RefCounted
var capture_directory:=""
var capture_rows: Array=[]
var recorder: AudioEffectRecord
var record_index:=-1
var listener_camera: Camera3D

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	# Native spatial playback needs the actual committed source camera as well
	# as the explicit listener pose used for source attenuation and engine spread.
	listener_camera=Camera3D.new();root.add_child(listener_camera);listener_camera.make_current()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional mix output")
	if args.size() in [3,4]:await verify(args)
	listener_camera.free();await process_frame
	print("Full-hold audio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var cat:=Catalogues.new();var construction:=Construction.new();var bodies:=Bodies.new();var effects:=Effects.new();var fixture:=Fixture.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);fixture.free();return
	check(bindings.source_architecture=="x86_64","Mac content required")
	var prepared:=construction.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000,true,bodies,effects);fixture.free()
	if not prepared:check(false,construction.error);return
	initial=Frame.new()
	if not initial.configure(bindings,cat,lib,construction,"E",.5):check(false,initial.error);return
	var audio:=Audio.new();root.add_child(audio)
	if bindings.player_destruction.is_empty():
		check(not audio.configure_full_hold(lib,bindings,initial),"Older world fabricated death audio");audio.free();return
	check(audio.configure_full_hold(lib,bindings,initial,777),audio.error)
	if not audio.error.is_empty():audio.free();return
	check(audio._npc_count==1 and audio._voice_displayed.is_empty() and audio._players.is_empty(),"Second flight borrowed the opening population or started opening audio")
	if args.size()==4:
		capture_directory=args[3];DirAccess.make_dir_recursive_absolute(capture_directory)
		recorder=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS
		record_index=AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,recorder)
	var baseline: Dictionary=initial.snapshot()
	await verify_player(audio)
	audio.clear();audio.free();await process_frame
	if failures==0:verify_pirate()
	check(initial.snapshot()==baseline,"Audio branches modified the prepared world")
	if recorder!=null:
		AudioServer.remove_bus_effect(0,record_index);recorder=null
		var file:=FileAccess.open(capture_directory.path_join("mix.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(capture_rows,"  "));file.close()
	await process_frame

func accept(audio: Node,world: RefCounted) -> bool:
	if world==null:check(false,"Native audio flight failed");return false
	var prior: Dictionary=audio.snapshot();var before: Dictionary=world.snapshot()
	var prepared: Dictionary=audio.prepare_full_hold(world)
	if prepared.is_empty():check(false,audio.error);return false
	if audio.snapshot()!=prior or world.snapshot()!=before:check(false,"Preparing sound changed playback or native state");return false
	listener_camera.transform=world.snapshot().camera_view.pose
	audio.commit_frame(prepared)
	return true

func step(audio: Node,world: RefCounted,ms: int,throttle:=0.0) -> RefCounted:
	var next: RefCounted=world.evaluate(ms,Vector2.ZERO,throttle)
	if next==null:check(false,world.error);return null
	return next if accept(audio,next) else null

func released(audio: Node) -> RefCounted:
	var world: RefCounted=initial.fork_for_frame()
	if not accept(audio,world):return null
	for i in 160:
		if world.dialogue_visible():break
		world=step(audio,world,100,1.0)
		if world==null:return null
	var before: Dictionary=audio.snapshot()
	world=world.navigate("next")
	if world==null or not accept(audio,world):return null
	check(audio.snapshot()==before,"Acknowledgement replayed preceding frame sound")
	return world

func verify_player(audio: Node):
	var world:=released(audio)
	if world==null:return
	# Warm two already-supported cached events to test source death-stop ownership.
	var warm: Dictionary=audio.prepare_frame(int(audio.snapshot().revision)+1,{"elapsed_ms":world.snapshot().encounter.elapsed_ms,"camera":{"view":world.snapshot().camera_view},"escape":{"frame":{"audio":[{"action":"replace_music","source_id":143},{"action":"set_player_engine","source_id":44,"position":world.snapshot().player_pose.origin}]}}})
	check(not warm.is_empty(),audio.error)
	if warm.is_empty():return
	audio.commit_frame(warm)
	check(audio.snapshot().active.has(143) and audio.snapshot().active.has(44),"Could not warm the disclosed cached music/engine fixtures")
	var fixture:=Live.new();var lethal: RefCounted=fixture.lethal(world);check(fixture.failures==0,"Lethal contact fixture failed");fixture.free()
	if lethal==null:return
	var before: Dictionary=audio.snapshot()
	var bad: RefCounted=lethal.fork_for_frame();bad._audio_frame.player_poll.stop_sound_ids=[27]
	check(audio.prepare_full_hold(bad).is_empty() and audio.snapshot()==before,"Invalid death stops changed sound state")
	bad=lethal.fork_for_frame();bad._audio_frame.actors=[{"actor_id":1}]
	check(audio.prepare_full_hold(bad).is_empty() and audio.snapshot()==before,"Late foreign NPC played earlier player stops")
	bad=lethal.fork_for_frame();bad._audio_frame.serial+=1
	check(audio.prepare_full_hold(bad).is_empty() and audio.snapshot()==before,"Skipped audio frame was accepted")
	if not accept(audio,lethal):return
	world=lethal
	var state: Dictionary=audio.snapshot();var stops: Array=state.history.slice(before.history.size())
	check(stops.size()==10 and stops[0].action=="stop_music" and stops[1].action=="stop_player_engine","Death stop order changed")
	for i in bindings.player_destruction.stop_sound_ids.size():
		check(stops[i+2].action=="stop" and stops[i+2].source_id==bindings.player_destruction.stop_sound_ids[i],"Death stop ID/order changed")
	check(not state.active.has(143) and not state.active.has(44) and state.retiring==2,"Cached music/engine stop ignored source fades")
	check(world.snapshot().player_destruction.events.stop_current_music and not world.snapshot().player_destruction.events.has("stop_primary_sound"),"Death mislabeled current music as a primary sound")
	var repeat: Dictionary=audio.prepare_full_hold(world);audio.commit_frame(repeat)
	check(repeat.get("repeat",false) and audio.snapshot()==state,"Repeated death frame replayed stops")
	var paused: RefCounted=world.evaluate(150,Vector2.ZERO,0.0,true)
	check(accept(audio,paused) and audio.snapshot()==state,"Paused native world replayed death audio")
	var breakup_id:=-1
	for i in 110:
		world=step(audio,world,150)
		if world==null:return
		var death: Dictionary=world.snapshot().player_destruction
		if death.events.breakup:
			breakup_id=int(death.events.sound_events[0]);state=audio.snapshot()
			check(state.active.has(breakup_id) and state.active[breakup_id].position==death.physical_pose.origin and not state.active[breakup_id].looping,"Player breakup sound lost physical position or source playback")
			check(state.history.back().source_id==breakup_id and state.history.back().actor_id=="player","Player breakup was not committed once in its early phase")
			await capture_mix(audio,"player-breakup",breakup_id)
		if death.events.failed:
			state=audio.snapshot()
			check(state.active.has(37) and not state.active[37].looping and state.history.back().action=="start","Failure sound did not use its nonspatial source event")
			await capture_mix(audio,"player-failure",37)
		if world.game_over_waiting():break
	check(breakup_id in [18,19] and world.game_over_waiting(),"Native player death did not reach its breakup and completed fade")
	state=audio.snapshot()
	check(state.history.filter(func(row):return row.get("actor_id")=="player" and row.get("source_id")==breakup_id).size()==1 and state.history.filter(func(row):return row.get("actor_id")=="player" and row.get("source_id")==37).size()==1,"Player death replayed a retained sound")
	var exit: RefCounted=world.request_game_over_exit()
	check(exit!=null and accept(audio,exit) and audio.snapshot()==state,"Game-over acknowledgement replayed audio")
	check(state.unsupported.is_empty(),"Connected death sounds retained unsupported playback")

func verify_pirate():
	var audio:=Audio.new();root.add_child(audio)
	if not audio.configure_full_hold(lib,bindings,initial,777):check(false,audio.error);audio.free();return
	var world:=released(audio)
	if world==null:audio.free();return
	world._pose=Transform3D(Basis(Vector3.UP,PI),world.snapshot().actors[0].pose.origin+Vector3(0,0,5000));world._pilot.angular_units=Vector2.ZERO
	var shot:=false
	for i in 30:
		world=step(audio,world,150)
		if world==null:audio.free();return
		if not world.snapshot().flight_audio.actors.is_empty() and not world.snapshot().flight_audio.actors[0].get("firing",{}).is_empty():
			var firing: Dictionary=world.snapshot().flight_audio.actors[0].firing.actors[0]
			if firing.outcome.fired:
				shot=true
				check(audio.snapshot().active.has(61) and audio.snapshot().active[61].position==firing.audio_events[0].position,"Pirate shot lost its source event or pre-motion position")
				break
	check(shot,"Source pirate did not fire in the close native fixture")
	var hull: int=world.snapshot().actors[0].vitals.hull
	check(world._encounter._combat.normal_hit(0,hull,true).get("destroyed_now",false),"Could not stage lethal pirate damage")
	world=step(audio,world,0)
	if world==null:audio.free();return
	check(audio.snapshot().active.has(20) and audio.snapshot().history.back().actor_id==0,"Pirate death entry omitted its small-ship sound")
	var broke:=false
	for i in 60:
		world=step(audio,world,150)
		if world==null:audio.free();return
		var death: Dictionary=world.snapshot().flight_audio.actors[0].get("destruction",{})
		if death.get("breakup",false):
			var cue: Dictionary=death.audio_events.back()
			check(audio.snapshot().active.has(int(cue.source_id)) and audio.snapshot().active[int(cue.source_id)].position==cue.position and audio.snapshot().history.back().actor_id==0,"Pirate breakup lost its effect position or actor")
			broke=true;break
	check(broke and audio.snapshot().unsupported.is_empty(),"Pirate breakup did not reach supported audio")
	var before: Dictionary=audio.snapshot();var foreign:=Frame.new()
	check(audio.prepare_full_hold(foreign).is_empty() and audio.snapshot()==before,"Foreign native world changed playback")
	foreign=world.fork_for_frame();foreign._death._presentation_identity=RefCounted.new()
	check(audio.prepare_full_hold(foreign).is_empty() and audio.snapshot()==before,"Another destruction owner borrowed this flight's sound history")
	audio.clear();audio.free()

func capture_mix(audio: Node,name: String,id: int):
	if recorder==null:return
	recorder.set_recording_active(true)
	await create_timer(.7).timeout
	audio.set_paused(true)
	await create_timer(.6).timeout
	recorder.set_recording_active(false)
	var wave:=recorder.get_recording();var peak:=0;var tail_peak:=0
	if wave!=null:
		for at in range(0,wave.data.size(),2):peak=maxi(peak,absi(wave.data.decode_s16(at)))
		var tail_bytes:=int(wave.mix_rate*.1)*2*(2 if wave.stereo else 1)
		for at in range(maxi(0,wave.data.size()-tail_bytes),wave.data.size(),2):tail_peak=maxi(tail_peak,absi(wave.data.decode_s16(at)))
		wave.save_to_wav(capture_directory.path_join(name+".wav"))
	check(wave!=null and peak>0 and tail_peak==0,"Native mix was silent or pause leaked playback: "+name)
	capture_rows.append({"name":name,"event_id":id,"bytes":0 if wave==null else wave.data.size(),"peak":peak,"paused_tail_peak":tail_peak,"isolated_event":false})
	audio.set_paused(false)

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
