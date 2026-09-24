extends SceneTree
## Source clip and accepted mining-cue playback checks.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Resources=preload("res://src/content/audio_resources.gd")
const Sequence=preload("res://src/simulation/audio_sequence.gd")
const Layered=preload("res://src/presentation/layered_audio.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==2 and DisplayServer.get_name()!="headless" and not OS.get_environment("GOF2_CAPTURE_DIR").is_empty():args.append(OS.get_environment("GOF2_CAPTURE_DIR"))
	if args.size() not in [2,3]:check(false,"Expected content, bindings and optional PCM capture directory");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):
		check(false,library.error+bindings.error);quit(1);return
	var resources:=Resources.new()
	check(resources.configure(library,bindings),resources.error)
	for id in [1,2,3,26,134,136,137,138,139,140,141,142,145,149,150,151,152]:
		var clip: Dictionary=resources.prepare(id)
		print("Source audio %d: kind=%s unsupported=%s looping=%s"%[id,clip.get("kind"),clip.get("unsupported"),clip.get("looping")])
		check(not clip.is_empty() and not clip.has("unsupported"),"Original audio event %d cannot play: %s"%[id,resources.error])
	var drill: Dictionary=resources.prepare(1)
	if not drill.is_empty() and not drill.has("unsupported"):
		check(drill.parameter=={"control":"external","min":0.0,"max":3.0} and drill.layers.size()==4,"Drill speed lost its four source layers")
		var sequence:=Sequence.new();sequence.configure(drill,77)
		var zero:=sequence.prepare_step(0,0.0)
		check(not zero.is_empty() and zero.operations.map(func(op):return op.key)==["0:0","3:0"],"Drill start lost its base loop and initial effect")
		if not zero.is_empty():sequence.commit_step(zero)
		var middle:=sequence.prepare_step(100,3.0*(17.0-5.0)/33.0)
		check(not middle.is_empty() and middle.operations.any(func(op):return op.action=="start" and op.key=="1:0") and middle.operations.any(func(op):return op.action=="start" and op.key=="3:1"),"Drill layer three did not activate its second loop/effect")
		if not middle.is_empty():sequence.commit_step(middle)
		var high:=sequence.prepare_step(100,3.0*(30.0-5.0)/33.0)
		check(not high.is_empty() and high.operations.any(func(op):return op.action=="start" and op.key=="2:0") and high.operations.any(func(op):return op.action=="start" and op.key=="3:2"),"Drill layer five skipped its crossed threshold effect")
		check(not high.is_empty() and high.operations.any(func(op):return op.action=="update" and op.key=="1:0" and op.pitch>1.0),"Drill's retained layer did not follow its source pitch envelope")
		if not high.is_empty():sequence.commit_step(high)
		check(sequence.prepare_step(0,4.0).is_empty(),"Drill accepted a parameter beyond the source range")
		var recorder: AudioEffectRecord
		var record_index: int=-1
		if args.size()==3 and DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(args[2])
			recorder=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS
			record_index=AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,recorder)
			recorder.set_recording_active(true)
		var node:=Layered.new();get_root().add_child(node);node.configure(drill,77);node.set_initial_parameter(0.0);node.play()
		check(node.snapshot().voices.has("0:0") and node.snapshot().voices.has("3:0"),"Drill player did not create the source voices")
		var frame:=node.prepare_step(100,3.0*(17.0-5.0)/33.0)
		check(not frame.is_empty(),node.error)
		if not frame.is_empty():node.commit_step(frame)
		check(node.snapshot().voices.has("1:0") and node.snapshot().voices.has("3:1"),"Drill player did not commit the source layer transition")
		if recorder!=null:
			await create_timer(0.65).timeout
			node.stream_paused=true
			await create_timer(0.35).timeout
			recorder.set_recording_active(false)
			var wave:=recorder.get_recording()
			var peak:=0;var tail_peak:=0
			if wave!=null:
				for at in range(0,wave.data.size(),2):peak=maxi(peak,absi(wave.data.decode_s16(at)))
				var tail_bytes:=int(wave.mix_rate*0.2)*2*(2 if wave.stereo else 1)
				for at in range(maxi(0,wave.data.size()-tail_bytes),wave.data.size(),2):tail_peak=maxi(tail_peak,absi(wave.data.decode_s16(at)))
				wave.save_to_wav(args[2].path_join("mining-drill.wav"))
			check(wave!=null and peak>0 and tail_peak==0,"Original drill PCM was silent or continued while paused")
			AudioServer.remove_bus_effect(0,record_index)
		node.stop();node.free()
	print("Playtest audio: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
