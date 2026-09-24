extends SceneTree
## Controlled motion-branch integration; the full NPC prefix is not simulated.
const Owner=preload("res://src/simulation/arrival_actor_motion.gd")
const Staging=preload("res://src/simulation/arrival_choreography.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/arrival_actor_motion_definitions.gd")
var checks:=0
var failures:=0

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visual triples")
	for i in range(0,args.size()-2,3):verify_profile(args[i],args[i+1])
	print("Arrival actor motion: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify_profile(content: String, pack: String):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var owner:=Owner.new()
	if bindings.arrival_actor_motion.is_empty() or not preload("res://src/content/arrival_staging_definitions.gd").parameters(bindings.arrival_staging):
		check(not owner.configure(bindings,cat,{},{}),"Legacy profile invented rescue actor motion")
		check(owner.snapshot().is_empty() and not owner.advance({},{}),"Unavailable actor retained motion")
		return
	var fresh:=Player.new();var player:=Player.new();var staging:=Staging.new()
	check(fresh.configure(bindings,cat),fresh.error)
	check(player.configure_arrival(bindings,cat,fresh.cache_snapshot()),player.error)
	check(staging.configure(bindings,lib),staging.error)
	var cache:=player.cache_snapshot();var constructed:=construction(bindings)
	check(owner.configure(bindings,cat,cache,constructed),owner.error)
	if owner.snapshot().is_empty():return
	var initial:=owner.snapshot();var radio:=identity(bindings)
	radio.started=[false,false,false];radio.finished=[false,false,false]
	check(initial.mode==0 and initial.active and initial.model_draw_enabled and not initial.engine_draw_enabled and not initial.targeting_blocked,"Constructor mode, activity or draw state differs")
	check(initial.route_index==0 and Definitions.Declarations.equal_value(initial.route_points,[[0,0,-5000],[0,0,0]]),"Authored rescue route changed")
	# Independent constant-step approach vectors straddle the velocity clamp.
	# The world context explicitly selects a present, eligible target at zero.
	for i in 52:
		var before:=owner.snapshot()
		check(staging.advance(100,radio,before.statistics_pose.origin,before.body_pose,true),staging.error)
		var cues:=staging.snapshot();var context:=dispatch(bindings,cues)
		context.target_relative_position=-cues.frame.actor_pose_override.origin
		check(owner.advance(cues,context),owner.error)
		var after:=owner.snapshot()
		check(after.body_pose.origin==after.statistics_pose.origin and after.mode==1 and after.active and after.model_draw_enabled and not after.engine_draw_enabled and after.targeting_blocked and after.model_visibility_request=={"enabled":true},"Statistics, activation, visibility or engine draw permission diverged")
		check(after.route_index==0 and after.flight.history==initial.flight.history and after.body_pose.basis==Basis.IDENTITY,"Scripted frame advanced route, steering or bank history")
		if i in [0,49,50,51]:
			var expected: Dictionary={0:-5980.0,49:-5000.0,50:-4980.0,51:-4960.080078125}
			check(after.body_pose.origin==Vector3(300,50,expected[i]),"Rescue body used stale statistics or extra ordinary travel")
	verify_frames(bindings,lib,cat,cache,constructed,radio)
	verify_bank(bindings)
	verify_pack(pack,lib,bindings)
	check(not owner.configure(bindings,cat,fresh.cache_snapshot(),constructed) and owner.snapshot().is_empty(),"Opening cache retained a rescue actor")
	print(lib.manifest.profile.edition+": explicit rescue branch, statistics sync, frame isolation and held banking verified")

func verify_frames(bindings: RefCounted, lib: RefCounted, cat: RefCounted, cache: Dictionary, constructed: Dictionary, radio: Dictionary):
	var owner:=Owner.new();var staging:=Staging.new()
	check(owner.configure(bindings,cat,cache,constructed),owner.error)
	check(staging.configure(bindings,lib),staging.error)
	var initial:=owner.snapshot()
	check(staging.advance(0,radio,initial.statistics_pose.origin,initial.body_pose,true),staging.error)
	var cues:=staging.snapshot();var context:=dispatch(bindings,cues)
	for axis in 3:
		for sign_value in [-1,1]:
			for distance in [49999.0,50000.0,50001.0]:
				var child: RefCounted=owner.fork_for_frame();var trial:=context.duplicate(true)
				trial.target_relative_position[axis]=sign_value*distance
				check(child.advance(cues,trial),child.error)
				check(child.snapshot().active==(distance<50000.0),"Mode-five activation box lost a strict boundary")
	for flag in ["target_present","target_excluded"]:
		var child: RefCounted=owner.fork_for_frame();var trial:=context.duplicate(true)
		trial[flag]=(flag=="target_excluded")
		check(child.advance(cues,trial) and child.snapshot().mode==5 and not child.snapshot().active and child.snapshot().model_visibility_request.is_empty(),"Ineligible target activated rescue actor")
	var child: RefCounted=owner.fork_for_frame();var trial:=context.duplicate(true)
	trial.model_local_pose=Transform3D(Basis(Vector3.UP,0.5),Vector3(13,7,-91))
	check(child.advance(cues,trial),child.error)
	check(child.snapshot().body_pose==initial.body_pose and child.snapshot().statistics_pose==initial.body_pose*trial.model_local_pose,"Zero time discarded the child matrix or conflated body and statistics")
	check(owner.snapshot()==initial,"Child motion changed its parent")
	check(not child.advance(cues,trial),"Repeated actor frame accepted")
	for key in ["base_content_id","binding_id","campaign_cursor","generation","mode_at_dispatch","actor_hostile","route_has_targets","target_present","target_excluded","target_relative_position","model_local_pose"]:
		var bad:=context.duplicate(true);bad.erase(key)
		check(not owner.advance(cues,bad) and owner.snapshot()==initial,"Missing context changed actor: "+key)
	for key in ["mode_at_dispatch","generation","base_content_id","route_has_targets","actor_hostile"]:
		var bad:=context.duplicate(true)
		match key:
			"mode_at_dispatch":bad[key]=1
			"generation":bad[key]=4
			"base_content_id":bad[key]="foreign"
			"route_has_targets":bad[key]=false
			"actor_hostile":bad[key]=true
		check(not owner.advance(cues,bad) and owner.snapshot()==initial,"Unresolved/foreign context changed actor: "+key)
	for scenario in ["nan","scale","skipped","stale","time","missing_pose"]:
		var bad:=cues.duplicate(true)
		match scenario:
			"nan":bad.frame.actor_pose_override.origin.x=NAN
			"scale":bad.frame.actor_pose_override.basis=Basis.IDENTITY.scaled(Vector3(2,1,1))
			"skipped":bad.generation=2
			"stale":bad.generation=0
			"time":bad.elapsed_ms=151
			"missing_pose":bad.frame.erase("actor_pose_override")
		check(not owner.advance(bad,context) and owner.snapshot()==initial,"Malformed staging changed actor: "+scenario)
	check(owner.advance(cues,context) and owner.snapshot().active,"Valid frame could not follow rejected frames")
	for key in ["body_pose","statistics_pose","model_local_pose","base_content_id","campaign_cursor","actor_id"]:
		var bad:=constructed.duplicate(true);bad.erase(key)
		check(not owner.configure(bindings,cat,cache,bad) and owner.snapshot().is_empty(),"Invalid reconstruction retained an actor: "+key)

func verify_bank(bindings: RefCounted):
	var flight:=Flight.new();check(flight.configure(bindings,Transform3D.IDENTITY),flight.error)
	check(not flight.advance(100,Vector3.RIGHT,1,true).is_empty(),flight.error)
	var before:=flight.snapshot();var body: Transform3D=before.root_pose;body.origin=Vector3(13,19,23)
	check(before.history!=[0.0,0.0,0.0,0.0,0.0],"Bank preservation test did not establish steering history")
	check(flight.apply_scripted_pose(body),flight.error)
	var after:=flight.snapshot()
	for key in ["bank","target_bank","history","history_cursor","history_wrapped"]:check(before[key]==after[key],"Scripted override reset banking: "+key)
	check(after.root_pose==body,"Scripted override lost its root pose")
	check(not flight.apply_scripted_pose(Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO)) and flight.snapshot()==after,"Rejected override changed banking")

func verify_pack(pack: String, lib: RefCounted, bindings: RefCounted):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var data: Dictionary=body.arrival_actor_motion
	check(Definitions.validate(data,int(header.source_executable_bytes),header.architecture,body.arrival_staging,body.opening_actors,body.arrival_environment).is_empty(),"Verified source actor declarations rejected")
	for key in data.provenance:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,int(header.source_executable_bytes),header.architecture,body.arrival_staging,body.opening_actors,body.arrival_environment).is_empty(),"Disconnected actor provenance accepted: "+key)
	var directory:=OS.get_user_data_dir().path_join("arrival-actor-test-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","changed","environment","staging","flight","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("arrival_actor_motion")
			"type":changed.arrival_actor_motion=false
			"changed":changed.arrival_actor_motion.activation_half_extent=50001
			"environment":changed.arrival_environment={}
			"staging":changed.arrival_staging={}
			"flight":changed.opening_actors.npc_initialization.flight={}
			"empty":changed.arrival_actor_motion={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		check(bindings.open(pack,lib.manifest),bindings.error)
		var accepted: bool=bindings.open(directory,lib.manifest)
		# A retained rescue session requires the removed motion capability.
		if scenario=="empty" and changed.get("arrival_session",{}).is_empty():check(accepted and bindings.arrival_actor_motion.is_empty() and not bindings.arrival_environment.is_empty(),"Explicit unsupported actor capability rejected: "+bindings.error)
		else:check(not accepted and bindings.arrival_actor_motion.is_empty() and bindings.arrival_environment.is_empty(),"Rejected pack retained actor motion: "+scenario)
	check(bindings.open(pack,lib.manifest),bindings.error)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func identity(bindings: RefCounted) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":1}
func construction(bindings: RefCounted) -> Dictionary:
	var result:=identity(bindings)
	# Explicit controlled poses; full NPC construction is a separate owner.
	result.actor_id=0;result.body_pose=Transform3D(Basis.IDENTITY,Vector3(300,50,-6000))
	result.statistics_pose=result.body_pose;result.model_local_pose=Transform3D.IDENTITY
	return result
func dispatch(bindings: RefCounted, cues: Dictionary) -> Dictionary:
	var result:=identity(bindings)
	result.generation=cues.generation;result.mode_at_dispatch=5;result.actor_hostile=false;result.route_has_targets=true
	result.target_present=true;result.target_excluded=false;result.target_relative_position=Vector3.ZERO;result.model_local_pose=Transform3D.IDENTITY
	return result
func check(value: bool, message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
