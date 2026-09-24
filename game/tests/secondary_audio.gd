extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Resources=preload("res://src/content/audio_resources.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const Sequence=preload("res://src/simulation/audio_sequence.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	check(is_equal_approx(Sequence.event_pitch(0.0,0.02,0),pow(2.0,-0.08)) and is_equal_approx(Sequence.event_pitch(0.0,0.02,0x7fffffff),pow(2.0,0.08)),"EMP event pitch lost the original raw-unit range")
	check(is_equal_approx(Sequence.event_pitch(0.25,0.02,0x40000000),2.0),"Event variation changed the equipment pitch scale")
	for i in range(0,args.size()-2,3):
		verify(args[i],args[i+1])
		await process_frame
	print("Secondary audio: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var resources:=Resources.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not resources.configure(library,bindings):check(false,library.error+bindings.error+resources.error);return
	for id in [6,7,8]:
		var clip:=resources.prepare(id)
		check(not clip.is_empty() and not clip.has("unsupported") and clip.get("source_index")==100+id and not clip.get("looping",true) and is_equal_approx(clip.get("event_pitch_random",0.0),0.02),"EMP original recording or authored event pitch is unavailable: "+str(id))
	var audio:=Audio.new();root.add_child(audio)
	if not audio.configure(library,bindings,730):check(false,audio.error);audio.free();return
	audio.set_paused(true)
	var position:=Vector3(100,200,300)
	var before:=audio.snapshot();var prepared:=audio.prepare_frame(0,frame(0,6,position))
	check(not prepared.is_empty() and audio.snapshot()==before,"EMP audio preparation consumed random state or played early")
	if prepared.is_empty():check(false,audio.error);audio.free();return
	var random:=RandomNumberGenerator.new();random.state=before.random_state
	var expected:=Sequence.event_pitch(0.0,0.02,random.randi()&0x7fffffff)
	audio.commit_frame(prepared)
	var started:=audio.snapshot();var node: Node=audio._players[6].node
	check(started.unsupported.is_empty() and started.random_state==random.state and is_equal_approx(started.active[6].playback_pitch,expected),"EMP launch lost its independent event pitch draw")
	check(started.active[6].position==position and started.active[6].paused and started.active[6].source_index==106,"EMP launch lost its original sample, source position or pause state")
	prepared=audio.prepare_frame(1,frame(1,6,position+Vector3.RIGHT))
	check(not prepared.is_empty() and audio.snapshot()==started,"Cached EMP preparation changed playback")
	expected=Sequence.event_pitch(0.0,0.02,random.randi()&0x7fffffff)
	audio.commit_frame(prepared)
	var cached:=audio.snapshot()
	check(audio._players[6].node==node and cached.random_state==random.state and is_equal_approx(cached.active[6].playback_pitch,expected),"Cached launch restarted the sample or missed its live pitch setter")
	check(cached.active[6].position==position+Vector3.RIGHT,"Cached EMP launch did not retain the latest owner position")
	audio.commit_frame(prepared)
	check(audio.snapshot()==cached,"Replayed EMP audio frame drew a new pitch")
	check(audio.prepare_frame(2,frame(2,6,Vector3(NAN,0,0))).is_empty() and audio.snapshot()==cached,"Invalid EMP sound position partially committed")
	prepared=audio.prepare_frame(2,frame(2,7,position))
	if prepared.is_empty():check(false,audio.error);audio.free();return
	audio.commit_frame(prepared)
	prepared=audio.prepare_frame(3,frame(3,8,position))
	if prepared.is_empty():check(false,audio.error);audio.free();return
	audio.commit_frame(prepared)
	check(audio.snapshot().active.keys()==[6,7,8],"The three EMP launch sounds did not retain independent source handles")
	audio.set_paused(false);node.stop()
	prepared=audio.prepare_frame(4,frame(4,6,position))
	if prepared.is_empty():check(false,audio.error);audio.free();return
	audio.commit_frame(prepared)
	check(audio._players[6].node!=node and node.is_queued_for_deletion(),"Completed EMP recording could not restart")
	audio.clear();check(audio.get_child_count()==0,"EMP playback survived cleanup");audio.free()

func frame(ms: int,id: int,position: Vector3) -> Dictionary:
	return {"elapsed_ms":ms,"camera":{"view":{"pose":Transform3D.IDENTITY}},"escape":{"frame":{"audio":[{"action":"start_spatial","source_id":id,"position":position,"pitch_raw":0.0}]}}}

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
