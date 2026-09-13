extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const EngineOwner=preload("res://src/simulation/opening_engine_audio.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const ParameterLoop=preload("res://src/presentation/parameter_audio.gd")
const Layered=preload("res://src/presentation/layered_audio.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size(),3):
		verify(args[i],args[i+1]);await process_frame;await process_frame
	print("Retained opening engine: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify(content: String,pack: String):
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);return
	var scene:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player_pose":Transform3D(Basis.IDENTITY,Vector3(8,4,9))}
	var engine:=EngineOwner.new()
	if bindings.vehicle_response.get("audio",{}).is_empty():
		check(not engine.configure(bindings,catalogues,scene),"Legacy profile invented a retained engine");return
	if not engine.configure(bindings,catalogues,scene):check(false,engine.error);return
	var first:=engine.snapshot()
	check(first.source_id==45 and first.initial_source_id==45 and first.generation==0 and first.active,"Fresh loadout did not select its retained engine")
	check(first.parameters==[0.0,0.0,0.0] and first.source_commands==Vector2.ZERO and first.position==scene.player_pose.origin,"Engine initial parameters, commands or position changed")
	var snapshot:=engine.snapshot();snapshot.parameters[0]=1.0
	check(engine.snapshot()==first,"Engine snapshot mutated retained parameters")
	for invalid in [Vector2(INF,0),Vector2(0,NAN),Vector2(1.01,0)]:check(not engine.sample_commands(invalid) and engine.snapshot()==first,"Invalid steering changed retained engine input")
	check(not engine.before_motion(-1) and engine.snapshot()==first,"Invalid engine phase advanced controls")
	var audio:=Audio.new();root.add_child(audio)
	if not audio.configure(library,bindings):check(false,audio.error);audio.free();return
	audio.set_paused(true)
	var previous:=audio.snapshot();var prepared:=prepare(audio,engine,0,[])
	check(not prepared.is_empty() and audio.snapshot()==previous,"Preparing retained engine failed or played it before commitment: "+audio.error)
	if prepared.is_empty():audio.free();return
	audio.commit_frame(prepared)
	check(audio._players.has(Audio.PLAYER_ENGINE) and not audio._players.has(45) and audio.snapshot().engine_id==45,"Player engine reused the generic cached event handle")
	var player: Node=audio._players[Audio.PLAYER_ENGINE].node
	check(player is ParameterLoop and audio.snapshot().active[Audio.PLAYER_ENGINE].paused,"Retained engine failed to start with native pause")
	previous=audio.snapshot();audio.commit_frame(prepared)
	check(audio.snapshot()==previous,"Repeated commitment recreated a retained engine")
	check(engine.before_motion(3) and engine.follow_player(scene.player_pose,100,100),engine.error)
	check(engine.sample_commands(Vector2(0.5,0.75)),engine.error)
	check(engine.snapshot().source_commands==Vector2(0.25,-0.5625) and engine.snapshot().parameters==[0.0,0.0,0.0],"Newly released input drove the same movement frame or used raw stick values")
	audio.commit_frame(prepare(audio,engine,1,[]))
	check(audio._players[Audio.PLAYER_ENGINE].node==player and player.snapshot().parameters==[0.0,0.0,0.0],"Late input changed the preceding engine envelope")
	var staged: RefCounted=engine.fork_for_frame()
	check(staged.before_motion(4),staged.error)
	var values: Array=staged.snapshot().parameters
	check(is_equal_approx(values[0],0.5625) and is_equal_approx(values[1],0.3875) and values[2]==0.0,"Next movement pass lost source command signs, squaring or load retention")
	check(staged.snapshot().source_commands==Vector2.ZERO and engine.snapshot().source_commands==Vector2(0.25,-0.5625),"Movement did not clear commands independently in the candidate frame")
	var moved:=Transform3D(Basis.IDENTITY,Vector3(20,4,9))
	check(staged.follow_player(moved,100,100),staged.error)
	var failed:=prepare(audio,staged,2,[{"action":"position","source_id":161,"position":Vector3(INF,0,0)}])
	check(failed.is_empty() and audio._players[Audio.PLAYER_ENGINE].node==player and player.snapshot().parameters==[0.0,0.0,0.0],"A late rejected cue changed live engine parameters")
	engine=staged
	audio.commit_frame(prepare(audio,engine,2,[]))
	check(player.snapshot().parameters==values and audio.snapshot().active[Audio.PLAYER_ENGINE].position==moved.origin,"Accepted motion did not move or control the retained engine")
	check(engine.before_motion(5) and engine.follow_player(moved,100,100),engine.error)
	var cues: Array=[{"action":"stop_player_engine"}]
	check(engine.apply_controller({"frame":{"audio":cues}},moved),engine.error)
	audio.commit_frame(prepare(audio,engine,3,cues))
	check(audio.snapshot().engine_id==45 and audio._players[Audio.PLAYER_ENGINE].node==player and player.snapshot().parameters==values,"Cached slowdown stop incorrectly stopped the retained player instance or cleared cinematic parameters")
	var prior:=engine.snapshot();var replacement: Array=[{"action":"set_player_engine","source_id":156}]
	check(not engine.apply_controller({"frame":{"audio":replacement+replacement}},moved) and engine.snapshot()==prior,"Duplicate replacement partially committed the engine lifetime")
	check(engine.before_motion(11) and engine.follow_player(moved,100,100),engine.error)
	check(engine.apply_controller({"frame":{"audio":replacement}},moved),engine.error)
	previous=audio.snapshot()
	check(prepare(audio,engine,4,[]).is_empty() and audio.snapshot()==previous,"Engine replacement without its controller cue was accepted")
	audio.commit_frame(prepare(audio,engine,4,replacement))
	check(audio.snapshot().engine_id==156 and audio.snapshot().engine_generation==1 and audio.snapshot().retiring==1,"Arrival did not retire the old engine with its source fade")
	var damaged: Node=audio._players[Audio.PLAYER_ENGINE].node
	check(damaged is Layered and damaged!=player and audio.snapshot().active[Audio.PLAYER_ENGINE].position==moved.origin,"Arrival engine lost retained ownership or player position")
	check(damaged.snapshot().sequence.elapsed_ms==0,"Replacement advanced the new timed engine before startup")
	audio.set_paused(false)
	for i in 8:
		moved.origin.x+=1
		check(engine.before_motion(12) and engine.follow_player(moved,100,100),engine.error)
		audio.commit_frame(prepare(audio,engine,5+i,[]))
	check(audio.snapshot().retiring==0 and audio._players[Audio.PLAYER_ENGINE].node==damaged and damaged.snapshot().sequence.elapsed_ms==800,"Retained arrival engine reset its time or leaked its predecessor")
	check(audio.snapshot().active[Audio.PLAYER_ENGINE].position==moved.origin,"Retained arrival engine stopped following source player motion")
	previous=audio.snapshot()
	check(audio.prepare_frame(13,{"elapsed_ms":1200}).is_empty() and audio.snapshot()==previous,"Retained engine silently disappeared from its world")
	audio.clear();audio.free();print("Verified retained engine: ",library.manifest.profile.edition)
func prepare(audio: Node,engine: RefCounted,revision: int,cues: Array) -> Dictionary:
	var sound: Dictionary=engine.snapshot()
	var world:={"base_content_id":sound.base_content_id,"binding_id":sound.binding_id,"elapsed_ms":sound.elapsed_ms,"actor_events":[],"player_engine":sound}
	var state:={"elapsed_ms":sound.elapsed_ms,"escape":{"frame":{"audio":cues}}}
	return audio.prepare_frame(revision,state,world)
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
