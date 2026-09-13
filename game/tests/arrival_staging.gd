extends SceneTree
## Checks choreography independently of the unfinished rescue world and station.
const Owner=preload("res://src/simulation/arrival_choreography.gd")
const Definitions=preload("res://src/content/arrival_staging_definitions.gd")
const Fade=preload("res://src/simulation/black_fade.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const TextResources=preload("res://src/presentation/opening_radio_resources.gd")
var checks:=0
var failures:=0

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Arrival staging: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(content: String, pack: String):
	var library:=Library.new();var bindings:=Bindings.new();var owner:=Owner.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	if not Definitions.parameters(bindings.arrival_staging):
		check(not owner.configure(bindings,library) and owner.snapshot().is_empty(),"Legacy pack invented rescue staging");return
	check(owner.configure(bindings,library),owner.error)
	if owner.snapshot().is_empty():return
	var state:=owner.snapshot();var initial:=state.duplicate(true)
	check(state.campaign_cursor==1 and state.phase==0 and state.generation==0 and state.elapsed_ms==0 and state.boundary.is_empty(),"Rescue did not start as an unfinished fresh scene")
	check(state.eye==Vector3(1500,1600,-3000) and state.camera_fixed_eye and state.camera_target=="player_body","Initial rescue camera differs")
	check(state.scripted_player and not state.player_update_enabled and not state.hud_visible and state.player_cruise==0.0,"Rescue player flags differ")
	check(state.frame.player_position==Vector3.ZERO and state.player_model_rotation==Vector3(0.4620000123977661,0.4620000123977661,1.5339000225067139),"Initial player placement/tumble differs")
	check(state.frame.actor.position==Vector3(300,50,-6000) and state.frame.actor.kind==3 and state.frame.actor.hull_catalogue_id==30 and state.frame.actor.factory_subtype==0,"Wrong rescue actor declaration")
	check(state.frame.actor.model_draw_enabled and not state.frame.actor.engine_draw_enabled and state.frame.actor.engine_resource_id==18030 and state.frame.actor.cruise==0 and state.frame.actor.route_points.size()==2 and int(state.frame.actor.route_points[0][2])==-5000 and int(state.frame.actor.route_points[1][2])==0,"Wrong rescue route or model drawing")
	check(state.frame.audio==[{"action":"stop_player_engine"},{"action":"stop_actor_engine","actor_id":0}],"Initial engine stops were lost")
	var radio:=empty_radio(bindings)
	# Stored position deliberately differs from body position; forward is +X.
	var body:=Transform3D(Basis(Vector3(0,0,-1),Vector3.UP,Vector3.RIGHT),Vector3(10,20,-9000))
	check(owner.advance(100,radio,Vector3(0,0,-2500),body,true),owner.error)
	state=owner.snapshot()
	check(state.frame.actor_forward_distance==10 and state.frame.actor_pose_override.origin==Vector3(20,20,-9000) and state.frame.actor_pose_override.basis==body.basis,"Approach used body Z, moved a world axis or changed heading")
	check(state.frame.actor_script_mode==5 and state.eye==Vector3(1510,1600,-3000) and state.frame.audio.is_empty(),"Rescue lost its mode/pan or repeated entry audio")
	check(owner.advance(100,radio,Vector3(0,0,5000),body,true) and owner.snapshot().frame.actor_forward_distance==-20,"Approach added a lower clamp absent from the source")
	check(owner.advance(100,radio,Vector3(0,0,-10000),body,true) and owner.snapshot().frame.actor_forward_distance==20,"Approach exceeded its upper cap")
	verify_numbers(bindings,library,radio)
	verify_invalid_frames(owner,radio,body)
	verify_fades(owner,bindings,library,radio,body)
	var saved_identity:=owner.presentation_identity()
	check(owner.configure(bindings,library) and owner.snapshot()==initial and owner.presentation_identity()!=saved_identity,"Fresh rescue retained a prior run")
	verify_declarations(pack,library,bindings)
	verify_radio(library,bindings)

func verify_numbers(bindings: RefCounted, library: RefCounted, radio: Dictionary):
	# Binary32 reference bits at quantization edges (angle, double-derived pan,
	# approach at half the upper speed); computed independently with struct.
	const VECTORS=[
		[0,0,0,0],
		[1,0,1036831949,1036831949],
		[7,0,1060320051,1060320051],
		[8,986255323,1061997773,1061997773],
		[15,986255323,1069547520,1069547520],
		[16,994643931,1070386381,1070386381],
		[149,1021456854,1097754214,1097754215],
		[150,1021456854,1097859072,1097859072]]
	var owner:=Owner.new();check(owner.configure(bindings,library),owner.error)
	var original:=owner.snapshot()
	for row in VECTORS:
		var next: RefCounted=owner.fork_for_frame()
		check(next.advance(row[0],radio,Vector3(0,0,-2500),Transform3D.IDENTITY,true),next.error)
		var frame: Dictionary=next.snapshot().frame
		check(bits(frame.model_rotation_delta.y)==row[1] and bits(frame.model_rotation_delta.z)==row[1] and frame.model_rotation_delta.x==0,"Tumble quantization differs at %d ms"%row[0])
		check(bits(frame.camera_pan.x)==row[2] and bits(frame.actor_forward_distance)==row[3],"Scalar precision differs at %d ms"%row[0])
		check(owner.snapshot()==original and next.presentation_identity()==owner.presentation_identity(),"Prospective rescue frame mutated its parent")

func verify_invalid_frames(owner: RefCounted, radio: Dictionary, body: Transform3D):
	var prior: Dictionary=owner.snapshot()
	for dt in [-1,151,0.5,NAN,INF,true]:
		check(not owner.advance(dt,radio,Vector3.ZERO,body,true) and owner.snapshot()==prior,"Invalid frame changed rescue state")
	for key in ["base_content_id","binding_id","campaign_cursor","started","finished"]:
		var bad:=radio.duplicate(true);bad.erase(key)
		check(not owner.advance(10,bad,Vector3.ZERO,body,true) and owner.snapshot()==prior,"Incomplete radio changed rescue state")
	var wrong:=radio.duplicate(true);wrong.campaign_cursor=0
	check(not owner.advance(10,wrong,Vector3.ZERO,body,true) and owner.snapshot()==prior,"Opening radio drove rescue")
	wrong=radio.duplicate(true);wrong.finished[0]=true
	check(not owner.advance(10,wrong,Vector3.ZERO,body,true) and owner.snapshot()==prior,"Unstarted event completed rescue")
	wrong=radio.duplicate(true);wrong.started[2]=true
	check(not owner.advance(10,wrong,Vector3.ZERO,body,true) and owner.snapshot()==prior,"Broken started-event dependency accepted")
	check(not owner.advance(10,radio,Vector3(NAN,0,0),body,true) and owner.snapshot()==prior,"Nonfinite statistics changed rescue")
	var bad_body:=body;bad_body.basis=Basis.from_scale(Vector3(2,1,1))
	check(not owner.advance(10,radio,Vector3.ZERO,bad_body,true) and owner.snapshot()==prior,"Scaled body changed rescue")
	bad_body=body;bad_body.basis=Basis.from_scale(Vector3(-1,1,1))
	check(not owner.advance(10,radio,Vector3.ZERO,bad_body,true) and owner.snapshot()==prior,"Reflected body changed rescue")
	wrong=radio.duplicate(true);wrong.started[0]=true
	check(owner.advance(0,wrong,Vector3.ZERO,body,true),owner.error)
	prior=owner.snapshot()
	check(not owner.advance(0,radio,Vector3.ZERO,body,true) and owner.snapshot()==prior,"Radio regression changed rescue")

func verify_fades(owner: RefCounted, bindings: RefCounted, library: RefCounted, radio: Dictionary, body: Transform3D):
	check(owner.configure(bindings,library),owner.error)
	var fade:={"black_plate":false}
	check(Fade.start(fade,owner.snapshot().frame.fade_request) and Fade.alpha(fade)==255,"Initial rescue did not fade in from black")
	for i in 25:check(Fade.advance(fade,100),"Fade rejected ordinary time")
	check(Fade.alpha(fade)==127 and fade.active,"Fade-in midpoint is not truncated binary32 alpha")
	for i in 25:Fade.advance(fade,100)
	check(fade.active and Fade.alpha(fade)==0,"Fade-in ended at duration equality")
	Fade.advance(fade,1);check(not fade.active and Fade.alpha(fade)==0,"Fade-in remained active past duration")
	var finished:=radio.duplicate(true);finished.started=[true,true,true];finished.finished=[true,true,false]
	check(owner.advance(0,finished,Vector3.ZERO,body,false) and owner.snapshot().phase==0,"Rescue faded before its last transmission finished")
	finished.finished[2]=true
	check(owner.advance(150,finished,Vector3(0,0,-5000),body,false),owner.error)
	var state: Dictionary=owner.snapshot()
	check(state.phase==1 and state.boundary.is_empty() and state.frame.camera_pan.x==15 and state.frame.actor_forward_distance==30,"Fade request also exited or skipped movement")
	check(Fade.start(fade,state.frame.fade_request) and Fade.alpha(fade)==0 and fade.elapsed_ms==0,"Fade-out consumed its request frame")
	for i in 50:Fade.advance(fade,100)
	check(fade.active and Fade.alpha(fade)==255,"Fade-out ended at equality")
	check(owner.advance(0,finished,Vector3.ZERO,body,fade.active) and owner.snapshot().boundary.is_empty() and owner.snapshot().frame.fade_request.is_empty(),"Rescue exited at equality or repeated its fade")
	Fade.advance(fade,1)
	var eye: Vector3=owner.snapshot().eye
	check(owner.advance(1,finished,Vector3(0,0,-5000),body,fade.active),owner.error)
	state=owner.snapshot()
	check(state.boundary=="station_transition_required" and state.campaign_cursor==1 and state.eye==eye and state.frame.camera_pan==Vector3.ZERO and state.frame.actor_forward_distance>0,"Exit order, camera or campaign cursor differs")
	fade.black_plate=true;check(Fade.alpha(fade)==255,"Station boundary lost its black plate")
	check(not owner.advance(0,finished,Vector3.ZERO,body,false) and owner.snapshot()==state,"Unsupported station advanced")
	var saved:=fade.duplicate(true)
	check(not Fade.advance(fade,151) and fade==saved,"Invalid fade time mutated state")
	check(not Fade.start(fade,{"duration_ms":5000,"source_direction":0,"source_color_argument":0}) and fade==saved,"Unsupported fade replaced the retained plate")

func verify_declarations(pack: String, library: RefCounted, bindings: RefCounted):
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var data: Dictionary=bindings.arrival_staging
	check(Definitions.validate(data,header.source_executable_bytes,header.architecture,bindings.opening_staging,bindings.arrival_dialogue,bindings.opening_actors).is_empty(),"Source declarations rejected")
	for key in data.provenance:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.opening_staging,bindings.arrival_dialogue,bindings.opening_actors).is_empty(),"Detached staging provenance accepted")
	for key in ["actor_hull_id","rotation_fraction","camera_x_per_ms","fade_duration_ms","exit_after_event_finished"]:
		var bad:=data.duplicate(true);bad[key]+=1
		check(not Definitions.parameters(bad),"Altered rescue cue accepted: "+key)
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-arrival-staging-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","foreign_radio","empty"]:
		var body:=original.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":body.erase("arrival_staging")
			"wrong_type":body.arrival_staging=false
			"changed":body.arrival_staging.actor_hull_id=0
			"foreign_radio":body.arrival_dialogue={}
			"empty":
				body.arrival_staging={}
				if body.opening_actors.player_initialization.has("flight_cache"):body.opening_actors.player_initialization.flight_cache={}
				if body.has("arrival_environment"):body.arrival_environment={}
				if body.has("arrival_actor_motion"):body.arrival_actor_motion={}
				if body.has("arrival_actor_construction"):body.arrival_actor_construction={}
		var serialized:=JSON.stringify(body,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,library.manifest),reader.error)
		var accepted:=reader.open(directory,library.manifest)
		if scenario=="empty":check(accepted and reader.arrival_staging.is_empty() and not reader.arrival_dialogue.is_empty(),"Explicit unsupported staging was rejected")
		else:check(not accepted and reader.arrival_staging.is_empty() and reader.arrival_dialogue.is_empty(),"Failed replacement retained rescue data: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func verify_radio(library: RefCounted, bindings: RefCounted):
	for language in ["gb","de"]:
		check(library.select_language(language),library.error)
		var resources:=TextResources.new();var radio:=Radio.new();var owner:=Owner.new()
		if not resources.prepare(library,bindings,null,1) or not radio.configure(bindings,library,resources.line_counts,1) or not owner.configure(bindings,library):check(false,resources.error+radio.error+owner.error);continue
		var fade:={"black_plate":false};Fade.start(fade,owner.snapshot().frame.fade_request)
		var pose:=Transform3D(Basis.IDENTITY,Vector3(300,50,-6000));var time:=0;var events:=[];var requested:=-1
		# A fixture supplies a body/statistics snapshot each frame. It deliberately
		# does not claim to simulate the source NPC or reconstruct its environment.
		for i in 1000:
			Fade.advance(fade,100)
			if not owner.advance(100,radio.snapshot(),pose.origin,pose,fade.active):check(false,owner.error);break
			var state: Dictionary=owner.snapshot();pose=state.frame.actor_pose_override
			if not state.frame.fade_request.is_empty():
				check(requested==-1 and radio.snapshot().finished[2],"Rescue fade lacks its earned radio gate")
				requested=time;Fade.start(fade,state.frame.fade_request)
			if not state.boundary.is_empty():break
			time+=100
			for event in radio.step(time,{},0):
				if event.kind=="finished":events.append(event.event)
		check(events==[0,1,2] and owner.snapshot().boundary=="station_transition_required" and time-requested==5100,"Source rescue radio/fade sequence failed for "+language)
		check(owner.snapshot().campaign_cursor==1 and not owner.snapshot().has("rewards"),"Rescue invented campaign completion or rewards")

static func empty_radio(bindings: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":1,"started":[false,false,false],"finished":[false,false,false]}
static func bits(value: float) -> int:return PackedFloat32Array([value]).to_byte_array().decode_u32(0)
func check(value: bool, message: String):
	checks+=1
	if not value:failures+=1;printerr(message)
