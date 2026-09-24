extends SceneTree
## The player's earned Microgun drives a real accepted firing cue and its
## original PCM through a held, released and resumed cannon event.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Primary=preload("res://src/simulation/primary_weapons.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var scenario_path:=OS.get_environment("GOF2_SCENARIO_INPUT")
	if args.size() not in [2,3,4] or scenario_path.is_empty():check(false,"Expected original content and an earned equipment scenario");finish();return
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);finish();return
	var equipment:=Scenario.new().open(scenario_path,bindings,catalogues)
	if equipment==null:check(false,"Earned equipment scenario cannot be restored");finish();return
	var player:=Player.new();var mounts:=Mounts.new();var primary:=Primary.new()
	check(player.configure_combat_training(bindings,catalogues,equipment),player.error)
	check(mounts.open(library,catalogues),mounts.error)
	if failures:finish();return
	check(primary.configure(bindings,catalogues,mounts,player.loadout()),primary.error)
	if failures:finish();return
	var camera:=Camera3D.new();root.add_child(camera);camera.make_current()
	var audio:=Audio.new();root.add_child(audio)
	check(audio.configure(library,bindings,123,7),audio.error)
	if failures:audio.free();camera.free();finish();return
	var unarmed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":0,"actor_events":[]}
	var silent: Dictionary=audio.prepare_combat(unarmed,0)
	check(not silent.is_empty() and silent.operations.is_empty(),"An unarmed mining flight required a player gunfire owner: "+audio.error)
	var clip: Dictionary=audio._resources.prepare(66)
	check(not clip.is_empty() and not clip.has("unsupported") and clip.get("looping")==true and clip.get("release_at_sample_end")==true,"The original Microgun loop is still unavailable")
	if not clip.is_empty() and not clip.has("unsupported"):print("Original Microgun sample: ",clip.sample)
	if failures:audio.free();camera.free();finish();return
	var recorder: AudioEffectRecord
	var index:=-1
	if DisplayServer.get_name()!="headless":
		recorder=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS
		index=AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,recorder)
		recorder.set_recording_active(true)
	var random:=Random.new();random.seed_from(1)
	var pose:=Transform3D(Basis.IDENTITY,Vector3.ZERO)
	check(not primary.advance(1).is_empty(),primary.error)
	var first:=primary.fire(pose,true,random.snapshot())
	check(first.weapons.size()==1 and first.weapons[0].result.fired and first.weapons[0].audio_events[0].source_id==66,"Earned Microgun did not emit event 66")
	if failures:cleanup(audio,camera,recorder,index);finish();return
	check(accept(audio,bindings,primary,first,1,0),audio.error)
	check(audio.snapshot().active.has(66) and audio.snapshot().unsupported.is_empty(),"Accepted Microgun cue did not become an active original sound")
	var node: Node=audio._players[66].node
	await create_timer(0.20).timeout
	check(not primary.advance(199).is_empty(),primary.error)
	var waiting:=primary.fire(pose,true,first.random_state)
	check(not waiting.weapons[0].result.fired and waiting.weapons[0].audio_events.is_empty(),"Held interval emitted another shot")
	check(accept(audio,bindings,primary,waiting,200,1),audio.error)
	check(audio._players[66].node==node and node.playing,"Held Microgun loop stopped between accepted shots")
	await create_timer(0.04).timeout
	check(not primary.advance(21).is_empty(),primary.error)
	check(accept(audio,bindings,primary,{},221,2),audio.error)
	check(not audio.snapshot().active.has(66) and audio._retiring.size()==1 and audio._retiring[0].get("release_tail",false),"Trigger release did not finish the current sample")
	if audio._retiring.size()==1:
		audio.set_paused(true)
		var paused_cursor: float=node.get_playback_position()
		var paused_remaining: int=audio._retiring[0].remaining_ms
		await create_timer(0.08).timeout
		check(absf(node.get_playback_position()-paused_cursor)<0.015 and audio._retiring[0].remaining_ms==paused_remaining,"Paused cannon tail consumed its sample or release clock")
		audio.set_paused(false)
	await create_timer(0.08).timeout
	check(not primary.advance(1).is_empty(),primary.error)
	var resumed:=primary.fire(pose,true,waiting.random_state)
	check(resumed.weapons[0].result.fired and resumed.weapons[0].audio_events[0].source_id==66,"Resumed trigger did not launch its next original shot")
	check(accept(audio,bindings,primary,resumed,222,3),audio.error)
	check(audio._players[66].node==node and audio._retiring.is_empty(),"Resumed trigger restarted or lost the cached cannon voice")
	await create_timer(0.03).timeout
	check(accept(audio,bindings,primary,{},252,4),audio.error)
	await create_timer(0.12).timeout
	check(accept(audio,bindings,primary,{},452,5),audio.error)
	check(not audio.snapshot().active.has(66) and audio._retiring.is_empty() and node.is_queued_for_deletion(),"Released cannon continued looping past its sample end")
	if recorder!=null:
		await create_timer(0.16).timeout
		recorder.set_recording_active(false)
		var wave:=recorder.get_recording();var peak:=0;var tail_peak:=0
		if wave!=null:
			for at in range(0,wave.data.size(),2):peak=maxi(peak,absi(wave.data.decode_s16(at)))
			var tail_bytes:=int(wave.mix_rate*0.12)*2*(2 if wave.stereo else 1)
			for at in range(maxi(0,wave.data.size()-tail_bytes),wave.data.size(),2):tail_peak=maxi(tail_peak,absi(wave.data.decode_s16(at)))
			var path:=args[3] if args.size()==4 else OS.get_environment("GOF2_CAPTURE_DIR")
			if not path.is_empty():DirAccess.make_dir_recursive_absolute(path);wave.save_to_wav(path.path_join("earned-microgun.wav"))
		check(peak>0 and tail_peak==0,"Accepted Microgun PCM was silent or continued after release")
		print("Microgun PCM: peak=",peak," tail_peak=",tail_peak)
	var before: Dictionary=audio.snapshot()
	var unowned:=audio.prepare_frame(6,{"elapsed_ms":453,"camera":{"view":{"pose":Transform3D.IDENTITY}},"escape":{"frame":{"audio":[{"action":"start_spatial","source_id":71,"position":Vector3.ZERO}]}}})
	check(unowned.is_empty() and audio.snapshot()==before,"A continuous cannon sound started without a verified primary owner")
	var spoofed:=audio.prepare_frame(6,{"elapsed_ms":453,"camera":{"view":{"pose":Transform3D.IDENTITY}},"escape":{"frame":{"audio":[{"action":"start_spatial","source_id":71,"position":Vector3.ZERO,"mount_id":999,"item_id":30}]}}})
	check(spoofed.is_empty() and audio.snapshot()==before,"An external cannon command impersonated a primary owner")
	var pitched: Dictionary=audio._resources.prepare(71)
	check(pitched.get("kind")=="playlist" and pitched.get("release_at_sample_end",false),"The authored pitched cannon playlist was not prepared")
	if not pitched.is_empty() and not pitched.has("unsupported"):
		audio.start_event({"source_id":71,"clip":pitched,"position":Vector3.ZERO,"pitch_raw":0.25,"mount_id":999,"item_id":30})
		await process_frame
		if audio._players.has(71):
			var held: Dictionary=audio._players[71]
			check(held.clip.has("sample") and held.node.playing,"Pitched cannon choice lost its selected sample")
			if held.node.playing:
				var remaining:=maxi(1,ceili(1000.0*maxf(0.0,float(held.clip.sample.loop_end)/float(held.clip.sample.rate)-held.node.get_playback_position())/held.node.pitch_scale))
				audio.stop_event(71)
				check(audio._retiring.any(func(row):return row.clip.id==71 and absf(float(row.remaining_ms-remaining))<=2.0),"Pitched cannon release ignored playback speed")
	cleanup(audio,camera,recorder,index)
	finish()

func accept(audio: Node,bindings: RefCounted,primary: RefCounted,fire: Dictionary,elapsed: int,revision: int) -> bool:
	var state:={"elapsed_ms":elapsed,"camera":{"view":{"pose":Transform3D.IDENTITY}}}
	var world:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":elapsed,"primaries":primary.snapshot(),"primary_fire":fire,"actor_events":[]}
	var prepared: Dictionary=audio.prepare_frame(revision,state,world)
	if prepared.is_empty():return false
	var before: Dictionary=audio.snapshot()
	if revision==2 or revision==4:check(prepared.operations.any(func(op):return op.action=="stop" and op.source_id==66),"Release did not prepare a stop from the accepted owner")
	if before!=audio.snapshot():check(false,"Preparing the cannon frame changed playback")
	audio.commit_frame(prepared)
	return true

func cleanup(audio: Node,camera: Node,recorder: AudioEffectRecord,index: int) -> void:
	if recorder!=null:AudioServer.remove_bus_effect(0,index)
	audio.clear();audio.free();camera.free()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish() -> void:
	print("Earned Microgun audio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
