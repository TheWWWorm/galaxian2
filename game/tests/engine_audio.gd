extends SceneTree
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Selection=preload("res://src/simulation/engine_audio.gd")
const Definitions=preload("res://src/content/engine_audio_definitions.gd")
const Envelopes=preload("res://src/content/audio_envelope.gd")
var checks:=0
var failures:=0

func _initialize():call_deferred("run")
func run():
	verify_curves()
	var args:=OS.get_cmdline_user_args()
	for i in range(0,args.size(),3):verify(args[i],args[i+1])
	print("Engine audio declarations: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String):
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);return
	var engine:=Selection.new()
	var rules: Dictionary=bindings.vehicle_response.get("audio",{})
	if rules.is_empty():
		check(not engine.configure(bindings,catalogues) and engine.select(0,[],[]).is_empty(),"Legacy profile invented engine selection")
		return
	check(engine.configure(bindings,catalogues),engine.error)
	check(engine.select(0,[],[]).source_id==44,"Wrong engine variant for catalogue ship 0")
	# Source ship exceptions take precedence even at opposite handling extremes.
	for pair in [[42,1104],[43,1106],[40,1107]]:
		check(engine.select(pair[0],[],[]).source_id==pair[1],"Ship-specific engine was replaced")
		check(Selection.select_event(rules,pair[0],0)==pair[1] and Selection.select_event(rules,pair[0],50)==pair[1],"Handling overrode a ship-specific engine")
	check(Selection.select_event(rules,0,0)==42,"Default engine selection changed")
	for i in 3:
		check(Selection.select_event(rules,0,rules.thresholds[i]-0.000001)==42+i,"Lower engine threshold comparison changed")
		check(Selection.select_event(rules,0,rules.thresholds[i])==43+i,"Exact engine threshold did not select the next variant")
		check(Selection.select_event(rules,0,rules.thresholds[i]+0.000001)==43+i,"Upper engine threshold comparison changed")
	check(engine.select(-1,[],[]).is_empty() and engine.select(catalogues.tables.ships.size(),[],[]).is_empty(),"Missing edition-specific ship was fabricated")
	check(engine.select(0,[3.5],[]).is_empty() and engine.select(0,[],[-1]).is_empty(),"Invalid upgrades/equipment accepted")
	# Equipment affects flight response after source engine selection.
	engine._vehicle._items[0].arrays[2][5]=16
	engine._vehicle._items[0].properties[28]=500
	check(engine.select(0,[],[0]).source_id==44,"Handling equipment silently changed the selected engine")
	check(engine.select(7,[],[]).source_id!=engine.select(7,[3,3,3,3],[]).source_id,"Source upgrade handling was ignored")
	var previous: Array=[0.1,0.2,0.8];var saved:=previous.duplicate()
	var neutral:=engine.controls(Vector2.ZERO,previous)
	check(neutral==[0.0,0.5,0.8] and previous==saved,"Neutral controls changed the unassigned load parameter or input array")
	var steering:=engine.controls(Vector2(-0.6,0.25),previous)
	check(is_equal_approx(steering[0],0.6) and is_equal_approx(steering[1],0.55) and steering[2]==0.8,"Engine command formula used angular units or the wrong axis")
	check(engine.controls(Vector2(-2,-5),previous)==[1.0,0.0,0.8] and engine.controls(Vector2(2,5),previous)==[1.0,1.0,0.8],"Engine controls did not clamp to the source parameter range")
	check(engine.controls(Vector2(NAN,0),previous).is_empty() and engine.controls(Vector2.ZERO,[0,0]).is_empty() and previous==saved,"Invalid engine controls were accepted or mutated prior values")
	for id in range(42,46):
		var program:=engine.program(id)
		check(not program.is_empty(),engine.error)
		if program.is_empty():continue
		var steady:=Selection.evaluate(program,neutral)
		var active:=Selection.evaluate(program,engine.controls(Vector2.ONE,previous))
		check(steady.pitch<1 and active.pitch>1 and active.gain==steady.gain and steady.spread_degrees==0 and active.spread_degrees>0,"Source engine modulation lost pitch, independent load or spread")
		var low:=Selection.evaluate(program,[0,0.5,0]);var high:=Selection.evaluate(program,[0,0.5,1])
		check(is_equal_approx(low.gain,0.7) and high.gain==1,"Load volume endpoints changed")
		check(Selection.evaluate(program,[NAN,0,0]).is_empty(),"Invalid engine parameter value accepted")
		program.envelopes.pitch.points[0][1]=0
		check(engine.program(id).envelopes.pitch.points[0][1]>0,"Caller mutated the retained source envelope")
	for id in [46,47,48,156,1104,1106,1107]:
		check(engine.program(id).is_empty(),"A different engine layout was silently approximated")
	verify_program_rejections(bindings.audio.events[42])
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in rules.provenance:
		var broken:=rules.duplicate(true);broken.provenance[key].offset+=2
		check(not Definitions.validate(broken,header.source_executable_bytes,header.architecture,bindings.vehicle_response,bindings.manual_rotation,bindings.audio).is_empty(),"Disconnected engine source extent accepted: "+key)
	for key in ["thresholds","event_ids","ship_overrides","horizontal_scale","horizontal_offset","steering_parameter"]:
		var broken:=rules.duplicate(true);broken[key]=true
		check(not Definitions.parameters(broken),"Boolean engine metadata accepted: "+key)
	var missing:=bindings.audio.duplicate();missing.events=[]
	check(not Definitions.validate(rules,header.source_executable_bytes,header.architecture,bindings.vehicle_response,bindings.manual_rotation,missing).is_empty(),"Engine events were detached from this edition's catalogue")
	verify_packs(pack,header,library.manifest)
	print("Verified engine profile: ",library.manifest.profile.edition,"; catalogue ship 0 event ",engine.select(0,[],[]).source_id)

func verify_packs(pack: String,header: Dictionary,manifest: Dictionary):
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:="user://tests/engine-audio-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Cannot create engine binding fixtures")
	for scenario in ["missing","unsupported","malformed","disconnected","missing_voice"]:
		var body:=original.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":body.vehicle_response.erase("audio")
			"unsupported":body.vehicle_response.audio={}
			"malformed":body.vehicle_response.audio.horizontal_scale=true
			"disconnected":body.vehicle_response.audio.provenance.controls.offset+=2
			"missing_voice":body.opening_dialogue.erase("voice")
		var serialized:=JSON.stringify(body,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata,"",true,true));file.close()
		var fixture:=Bindings.new();var accepted:=fixture.open(directory,manifest)
		if scenario=="unsupported":check(accepted and fixture.vehicle_response.audio.is_empty(),"Explicitly unsupported engine capability lost compatible content: "+fixture.error)
		else:check(not accepted and fixture.binding_id.is_empty(),"Malformed engine/voice capability accepted or retained partial content: "+scenario)
	for name in ["registrations.json","bindings.json"]:DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func verify_program_rejections(event: Dictionary):
	for key in ["id","type","parameters","layers"]:
		var broken:=event.duplicate(true);broken[key]=false
		check(Selection.read_program(broken).is_empty(),"Malformed engine accepted: "+key)
	for key in ["name","flags","min","max","velocity","seek_speed","envelopes","sustain_points"]:
		var broken:=event.duplicate(true);broken.parameters[0][key]=false
		check(Selection.read_program(broken).is_empty(),"Malformed engine parameter accepted: "+key)
	for key in ["flags","flags2","sound_def","loop_count","auto_pitch","auto_pitch_reference","auto_pitch_zero","fine_tune","x","width","volume","fade_in","fade_out","fade_in_type","fade_out_type"]:
		var broken:=event.duplicate(true);broken.layers[0].sounds[0][key]=true
		check(Selection.read_program(broken).is_empty(),"Malformed engine sound accepted: "+key)
	for key in ["dsp","dsp_parameter","flags","flags2","name_index","parent_index","parameter_index","points","trailing"]:
		var broken:=event.duplicate(true);broken.layers[0].envelopes[0][key]=true
		check(Selection.read_program(broken).is_empty(),"Malformed engine envelope accepted: "+key)
	var broken:=event.duplicate(true);broken.layers[0].envelopes[1]=broken.layers[0].envelopes[0].duplicate(true)
	check(Selection.read_program(broken).is_empty(),"Duplicate envelope target accepted")
	broken=event.duplicate(true);broken.layers[0].envelopes[1].parameter_index=0
	check(Selection.read_program(broken).is_empty(),"Duplicate envelope parameter owner accepted")

func verify_curves():
	var curve:={"flags":12,"dsp":"","dsp_parameter":0,"flags2":0,"name_index":65535,"parent_index":65535,"parameter_index":0,"trailing":0,"points":[[0.0,0.2,1],[0.8,1.0,2]]}
	check(Envelopes.supported(curve,3),"Valid scalar curve rejected")
	check(is_equal_approx(Envelopes.evaluate(curve,0.2),0.4),"Linear curve used the starting point's curve type")
	curve.points[1][2]=1
	# A quarter of the segment gives 5/32 cubic weight, visibly unlike linear.
	check(is_equal_approx(Envelopes.evaluate(curve,0.2),0.325),"Cubic curve was linearized or solved for Bezier x")
	check(Envelopes.evaluate(curve,1.0)==1.0,"Curve did not hold its last value")
	curve.points=[[0.0,0.5,2]];curve.flags=20
	check(Envelopes.evaluate(curve,0.0)==1.0,"Pitch midpoint is not neutral")
	curve.points[0][1]=0.625
	check(is_equal_approx(Envelopes.evaluate(curve,0.0),2.0),"Envelope pitch confused normalized octaves with raw event pitch")
	curve.flags=260;curve.points[0][1]=0.25
	check(Envelopes.evaluate(curve,0.0)==90,"Speaker spread did not convert to degrees")
	for value in [0,3,4,8,65535]:
		curve.points[0][2]=value
		check(not Envelopes.supported(curve,3),"Unsupported curve type was guessed")
	curve.points[0][2]=2;curve.points[0][0]=0.1
	check(not Envelopes.supported(curve,3),"Unverified leading curve extrapolation accepted")

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
