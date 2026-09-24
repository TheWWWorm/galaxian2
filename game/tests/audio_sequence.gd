extends SceneTree
const Sequence=preload("res://src/simulation/audio_sequence.gd")
var checks:=0
var failures:=0

func _initialize():call_deferred("run")
func run():
	check(Sequence.weighted_choice([100,100,100],100,1)==2,"Repeated weighted choice did not select its successor")
	check(Sequence.weighted_choice([100,100,100],299,2)==0,"Last repeated entry did not wrap")
	check(Sequence.weighted_choice([1,3],0,-1)==0 and Sequence.weighted_choice([1,3],3,-1)==1,"Playlist weights were ignored")
	check(is_equal_approx(Sequence.random_gain(1.0,0.5,0),0.5),"Attenuation lower endpoint changed")
	check(is_equal_approx(Sequence.random_gain(1.0,0.5,1073741824),0.75),"Gain randomized in dB instead of linear amplitude")
	check(is_equal_approx(Sequence.random_pitch(0.0,0.025,1073741824),1.0),"Centered pitch draw was shifted")
	check(is_equal_approx(Sequence.random_pitch(0.0,0.025,0),pow(2.0,-0.1)),"Stored pitch deviation lost its factor of four")
	check(is_equal_approx(Sequence.random_pitch(0.0,0.025,2147483647),pow(2.0,0.1)),"Pitch upper endpoint changed")
	var random:=RandomNumberGenerator.new();random.seed=91
	var sequential: Dictionary=fixture().layers[1][0].definition.duplicate(true);sequential.playlist_flags=9
	check(Sequence.sample(sequential,random,2).playlist_index==0,"Retained sequential playlist failed to wrap")
	var repeated: Dictionary=sequential.duplicate(true);repeated.playlist_flags=3
	var choices: Array=[]
	for step in 60:choices.append(Sequence.sample(repeated,random,choices.back() if not choices.is_empty() else -1).playlist_index)
	var has_repeat:=false
	for i in range(1,choices.size()):has_repeat=has_repeat or choices[i]==choices[i-1]
	check(has_repeat,"Random-repeat playlist incorrectly excluded its preceding sample")
	var definition:=fixture()
	var sequence:=Sequence.new();sequence.configure(definition,15)
	var initial:=sequence.snapshot()
	var frame:=sequence.prepare_step(0)
	check(sequence.snapshot()==initial and frame.operations.size()==1 and frame.operations[0].key=="base","Initial preparation mutated state or missed the continuous layer")
	check(sequence.commit_step(frame) and not sequence.commit_step(frame),"Sequence accepted a repeated commit")
	var phases: Array=[]
	var starts: Array=[]
	var previous_choices:={}
	for step in 700:
		frame=sequence.prepare_step(10)
		for op in frame.operations:
			if op.action=="start":
				starts.append([frame.state.elapsed_ms,op.key])
				check(op.key!="base","Wrapping the parameter restarted the continuous sample")
				check(op.playlist_index!=previous_choices.get(op.definition_id,-1),"Random playlist repeated the previous selection")
				previous_choices[op.definition_id]=op.playlist_index
			else:check(false,"A one-shot was cut off when its parameter window ended")
		sequence.commit_step(frame)
		phases.append(sequence.snapshot().parameter)
	check(starts.slice(0,6)==[[170,"a"],[1300,"b"],[2720,"c"],[3500,"a"],[4640,"b"],[6060,"c"]],"Source windows did not trigger at the expected 10ms frame boundaries: "+str(starts))
	var retained:=sequence.snapshot()
	check(sequence.prepare_step(-1).is_empty() and sequence.snapshot()==retained,"Invalid elapsed time advanced audio state")
	var other:=Sequence.new();other.configure(definition,15);other.commit_step(other.prepare_step(0))
	for step in 700:other.commit_step(other.prepare_step(10))
	check(sequence.snapshot()==other.snapshot(),"Private audio randomness did not reproduce for an equal seed and frames")
	definition.parameter.velocity=1.0
	sequence.configure(definition,15);sequence.commit_step(sequence.prepare_step(1000))
	check(sequence.snapshot().parameter==1.0,"Parameter wrapped at equality instead of strictly above its maximum")
	sequence.commit_step(sequence.prepare_step(1))
	check(sequence.snapshot().parameter>0 and sequence.snapshot().parameter<0.002,"Parameter failed to wrap above its maximum")
	verify_external_envelope()
	print("Audio sequence: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_external_envelope() -> void:
	var sound: Dictionary=fixture().layers[0][0]
	sound.volume=0.5;sound.definition.volume=0.8;sound.definition.pitch=0.25
	sound.envelope={"flags":20,"points":[[0.0,0.25,2],[1.0,0.75,2]]}
	var sequence:=Sequence.new()
	sequence.configure({"parameter":{"control":"external","min":0.0,"max":3.0},"layers":[[sound]]},19)
	var start:=sequence.prepare_step(0,0.0)
	check(start.operations.size()==1 and is_equal_approx(start.operations[0].gain,0.4) and is_equal_approx(start.operations[0].pitch,0.5),"External envelope did not combine its initial level with one playlist level")
	sequence.commit_step(start)
	var high:=sequence.prepare_step(100,3.0)
	check(high.operations.size()==1 and high.operations[0].action=="update" and is_equal_approx(high.operations[0].gain,0.4) and is_equal_approx(high.operations[0].pitch,8.0),"Envelope update compounded the prior pitch or volume")
	sequence.commit_step(high)
	var low:=sequence.prepare_step(100,0.0)
	check(low.operations.size()==1 and is_equal_approx(low.operations[0].gain,0.4) and is_equal_approx(low.operations[0].pitch,0.5),"Returning to the original external value changed the voice base level")

func fixture() -> Dictionary:
	var background:={"id":0,"samples":[{}],"weights":[100],"playlist_flags":8,"volume":1.0,"attenuation":1.0,"pitch":0.0,"pitch_random":0.0}
	var variation:={"id":1,"samples":[{},{},{}],"weights":[100,100,100],"playlist_flags":0,"volume":1.0,"attenuation":0.7079457640647888,"pitch":0.0,"pitch_random":0.02500000037252903}
	return {"parameter":{"velocity":0.30000001192092896},"layers":[[{"key":"base","start":0.0,"width":1.0,"volume":1.0,"looping":true,"definition":background}],[
		{"key":"a","start":0.049504999071359634,"width":0.09554140269756317,"volume":0.5699999928474426,"looping":false,"definition":variation},
		{"key":"b","start":0.3894389867782593,"width":0.10000000149011612,"volume":0.5899999737739563,"looping":false,"definition":variation},
		{"key":"c","start":0.8151810169219971,"width":0.10000000149011612,"volume":0.5600000023841858,"looping":false,"definition":variation}]]}

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
