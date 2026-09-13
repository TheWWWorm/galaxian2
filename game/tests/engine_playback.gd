extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Resources=preload("res://src/content/audio_resources.gd")
const Channels=preload("res://src/content/audio_channels.gd")
const ParameterLoop=preload("res://src/presentation/parameter_audio.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
var failures:=0
var checks:=0

func _initialize():call_deferred("run")
func run():
	verify_channels();verify_geometry()
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size(),3):
		verify_source(args[i],args[i+1])
		await process_frame
		await process_frame
	print("Native engine clips: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func fixture() -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.stereo=true;stream.mix_rate=22050;stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin=1;stream.loop_end=4
	var data:=PackedByteArray();data.resize(20)
	var values:=[-32768,32767,1,-1,123,-456,0,7,900,-900]
	for i in values.size():data.encode_s16(i*2,values[i])
	stream.data=data;return stream

func verify_channels():
	var original:=fixture();var before:=original.data
	var split:=Channels.split_stereo(original)
	check(split.size()==2,"Stereo source was not split into two channels")
	for side in 2:
		check(not split[side].stereo and split[side].mix_rate==22050 and split[side].loop_begin==1 and split[side].loop_end==4 and split[side].loop_mode==AudioStreamWAV.LOOP_FORWARD,"Channel split changed sample clock or loop indices")
		for frame in 5:check(split[side].data.decode_s16(frame*2)==original.data.decode_s16(frame*4+side*2),"PCM channel sample changed")
	check(original.data==before,"Channel split changed the source PCM")
	for invalid in [null,AudioStreamMP3.new(),{}]:check(Channels.split_stereo(invalid).is_empty(),"Unsupported stream type was accepted")
	for key in ["stereo","format","loop_mode","loop_end","loop_begin","data"]:
		var invalid:=fixture()
		match key:
			"stereo":invalid.stereo=false
			"format":invalid.format=AudioStreamWAV.FORMAT_8_BITS
			"loop_mode":invalid.loop_mode=AudioStreamWAV.LOOP_DISABLED
			"loop_end":invalid.loop_end=6
			"loop_begin":invalid.loop_begin=4
			"data":invalid.data=PackedByteArray([1,2,3])
		check(Channels.split_stereo(invalid).is_empty(),"Invalid PCM channel metadata accepted: "+key)

func verify_geometry():
	var origin:=Vector3(0,0,-10)
	var center:=ParameterLoop.channel_positions(origin,Transform3D.IDENTITY,0)
	check(center==[Vector3(0,0,-1),Vector3(0,0,-1)],"Zero spread did not collapse to the source direction")
	var wide:=ParameterLoop.channel_positions(origin,Transform3D.IDENTITY,180)
	check(wide[0].is_equal_approx(Vector3.LEFT) and wide[1].is_equal_approx(Vector3.RIGHT),"Stereo channels have reversed angular spread")
	var reverse:=ParameterLoop.channel_positions(origin,Transform3D.IDENTITY,360)
	check(reverse[0].is_equal_approx(Vector3.BACK) and reverse[1].is_equal_approx(Vector3.BACK),"Full spread did not meet behind the listener")
	var listener:=Transform3D(Basis(Vector3.UP,0.7),Vector3(30,20,-8))
	var shifted:=ParameterLoop.channel_positions(listener*origin,listener,180)
	check(shifted[0].is_equal_approx(listener*Vector3.LEFT) and shifted[1].is_equal_approx(listener*Vector3.RIGHT),"Listener translation or orientation changed speaker-space spread")
	check(ParameterLoop.channel_positions(Vector3.ZERO,Transform3D.IDENTITY,0)==center,"Coincident native source policy is not deterministic")
	for spread in [-1,INF,NAN,361]:check(ParameterLoop.channel_positions(origin,listener,spread).is_empty(),"Invalid spread accepted")
	check(ParameterLoop.channel_positions(Vector3(INF,0,0),listener,10).is_empty(),"Nonfinite source accepted")
	var invalid:=Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
	check(ParameterLoop.channel_positions(origin,invalid,10).is_empty(),"Singular listener accepted")

func verify_source(content: String,pack: String):
	var library:=Library.new();var bindings:=Bindings.new();var resources:=Resources.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not resources.configure(library,bindings):check(false,library.error+bindings.error+resources.error);return
	var clips: Array=[]
	for id in range(42,46):
		var clip: Dictionary=resources.prepare(id);clips.append(clip)
		if clip.get("kind")!="parameter_loop":check(false,"Engine clip unsupported: "+str(clip));return
		check(clip.looping and clip.spatial and clip.channels.size()==2 and clip.fade_in_ms==800 and clip.fade_out_ms==800,"Original engine loop, spatial mode or fades changed")
		check(clip.source_index=={42:122,43:122,44:120,45:121}[id],"Engine clip selected a different original sample")
		var source: PackedByteArray=clip.stream.data
		for side in 2:
			var channel: PackedByteArray=clip.channels[side].data
			var equal:=channel.size()*2==source.size()
			for frame in channel.size()/2:
				if channel.decode_s16(frame*2)!=source.decode_s16(frame*4+side*2):equal=false;break
			check(equal,"Original engine PCM changed during separation")
		var bytes: int=resources._decoded_bytes
		check(resources.prepare(id)==clip and resources._decoded_bytes==bytes,"Repeated preparation decoded or allocated the loop again")
		verify_player(clip)
	check(clips[0].channels[0]==clips[1].channels[0] and clips[0].channels[1]==clips[1].channels[1],"Engine variants duplicated their shared sample channels")
	for id in [46,47,48,1104,1106,1107]:check(resources.prepare(id).has("unsupported"),"A different engine layout silently reused ordinary playback")
	verify_unsupported(library,bindings)
	verify_owner(library,bindings)
	print("Verified native engine clips: ",library.manifest.profile.edition)

func verify_unsupported(library: RefCounted,bindings: RefCounted):
	var changed:=Bindings.new();changed.base_content_id=bindings.base_content_id;changed.audio=bindings.audio.duplicate(true)
	var resources:=Resources.new()
	for angle in [-1.0,361.0,NAN,false]:
		changed.audio.events[45].properties.cone_inside=angle
		check(resources.configure(library,changed) and resources.prepare(45).has("unsupported"),"Invalid engine cone was silently discarded")
	changed.audio.events[45].properties.cone_inside=0.0
	changed.audio.events[45].properties.cone_outside_volume=0.5
	check(resources.configure(library,changed) and resources.prepare(45).has("unsupported"),"Directional engine attenuation was silently discarded")

func verify_player(clip: Dictionary):
	var node:=ParameterLoop.new();root.add_child(node)
	if not node.configure(clip):check(false,node.error);node.free();return
	var initial:=node.snapshot()
	check(initial.parameters==[0.0,0.0,0.0] and initial.levels.gain>0.69 and initial.levels.gain<0.71 and initial.levels.pitch<1 and initial.levels.spread_degrees>119,"Engine parameter initialization changed")
	var values: Array=[1.0,0.5,1.0]
	check(node.set_parameters(values),node.error);values[0]=0.0
	var current:=node.snapshot()
	check(current.parameters[0]==1 and current.levels.pitch>1 and current.levels.spread_degrees==0 and current.levels.gain==1,"Engine envelopes or parameter isolation failed")
	node.volume_db=linear_to_db(0.5);node.pitch_scale=2.0
	check(is_equal_approx(db_to_linear(node.snapshot().channels[0].gain_db),0.5) and is_equal_approx(node.snapshot().channels[1].pitch,2.0*current.levels.pitch),"Native level/pitch did not multiply the envelope values")
	check(node.set_spatial(Vector3(10,0,-10),Transform3D.IDENTITY),node.error)
	current=node.snapshot()
	check(current.channels[0].position==current.channels[1].position and current.source_position==Vector3(10,0,-10),"Collapsed channels lost the source direction")
	for invalid in [[],[0.0,0.0],[0.0,0.0,INF],[false,0,0],[0,2,0]]:
		check(not node.set_parameters(invalid) and node.snapshot()==current,"Invalid parameter update partially changed playback")
	check(not node.set_spatial(Vector3(INF,0,0),Transform3D.IDENTITY) and node.snapshot()==current,"Invalid spatial update partially changed playback")
	node.stream_paused=true;node.play()
	check(node.playing and node.snapshot().channels.all(func(row):return row.pending_resume),"Paused startup lost a stereo channel")
	node.stream_paused=false
	check(node.snapshot().channels.all(func(row):return not row.pending_resume),"Resume left a channel pending")
	node.stream_paused=true;node.stop()
	check(not node.playing,"Stop retained a paused stereo channel")
	node.clear();check(node.get_child_count()==0,"Clearing the loop retained a channel")
	node.free()

func verify_owner(library: RefCounted,bindings: RefCounted):
	var audio:=Audio.new();root.add_child(audio)
	if not audio.configure(library,bindings):check(false,audio.error);audio.free();return
	audio.set_paused(true)
	var initial:=audio.snapshot()
	var state:=frame(0,[{"action":"start_spatial","source_id":44,"position":Vector3(10,0,-10)}])
	var prepared: Dictionary=audio.prepare_frame(0,state)
	check(not prepared.is_empty() and audio.snapshot()==initial,"Preparing a clip started playback before commitment")
	audio.commit_frame(prepared)
	check(audio.snapshot().active.has(44) and audio._players[44].node is ParameterLoop and audio.snapshot().active[44].paused,"Native clip was not committed or paused")
	var player: Node=audio._players[44].node
	var current:=audio.snapshot();audio.commit_frame(prepared)
	check(audio.snapshot()==current,"Repeated commit replaced the native engine loop")
	state=frame(800,[{"action":"start_spatial","source_id":44,"position":Vector3(-10,0,-10)}])
	audio.commit_frame(audio.prepare_frame(1,state))
	check(audio._players[44].node==player and audio.snapshot().active[44].position==Vector3(-10,0,-10),"Cached clip playback reset instead of updating position")
	current=audio.snapshot();state=frame(900,[])
	state.camera={"view":{"pose":Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)}}
	check(audio.prepare_frame(2,state).is_empty() and audio.snapshot()==current,"A singular listener corrupted a retained stereo clip")
	audio.commit_frame(audio.prepare_frame(2,frame(900,[{"action":"stop","source_id":44}])))
	check(not audio.snapshot().active.has(44) and audio.snapshot().retiring==1,"Engine stop lost the original fade")
	audio.commit_frame(audio.prepare_frame(3,frame(1700,[])))
	check(audio.snapshot().retiring==0,"Engine channels survived their stop fade")
	audio.clear();check(audio.get_child_count()==0,"Engine channels survived session cleanup");audio.free()

func frame(time: int,operations: Array) -> Dictionary:return {"elapsed_ms":time,"escape":{"frame":{"audio":operations}}}
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
