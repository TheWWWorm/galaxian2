extends SceneTree
const Escape=preload("res://src/simulation/opening_escape.gd")
const Definitions=preload("res://src/content/opening_escape_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Camera=preload("res://src/simulation/opening_camera.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const AEM=preload("res://src/content/aem.gd")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
var failures:=0
var pose:=Transform3D(Basis.IDENTITY,Vector3(123,456,789))
var eye:=Transform3D(Basis(Vector3.UP,0.3),Vector3(999,2000,-6000))

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Opening escape checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var owner:=Escape.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	if bindings.opening_staging.get("escape",{}).is_empty():
		check(not owner.configure(bindings,library) and owner.snapshot().is_empty(),"Legacy pack invented escape support");return
	check(owner.configure(bindings,library),owner.error)
	if owner.snapshot().is_empty():return
	var definition: Dictionary=bindings.opening_staging.escape
	var arch: String="armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(definition,10000000,arch,bindings.opening_staging).is_empty(),"Source escape declarations rejected")
	for key in definition.provenance:
		var bad:=definition.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,10000000,arch,bindings.opening_staging).is_empty(),"Detached escape provenance accepted")
	var changed:=definition.duplicate(true);changed.cruise_decay_per_update=1.02
	check(not Definitions.parameters(changed),"Unsupported acceleration substituted for source slowdown")
	var decoder:=AEM.new();var decoded:=decoder.decode(library.read_resource(Escape.EFFECT_PATH,AEM.MAX_BYTES));var sampler:=Sampler.new()
	check(not decoded.is_empty() and sampler.configure(decoded.get("surfaces",[])),"Original hyperdrive surfaces cannot be sampled: "+sampler.error)
	check(owner.snapshot().effect.start_ms==50 and owner.snapshot().effect.end_ms==3000 and decoded.surfaces.size()==21,"Original effect timing/geometry changed")
	var radio:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"started":[],"finished":[]}
	for i in 23:radio.started.append(false);radio.finished.append(false)
	check(owner.advance(0,radio,pose,eye),owner.error)
	check(owner.snapshot().phase==4 and owner.snapshot().frame.audio.is_empty(),"Escape began without earned encounter radio")
	finish_through(radio,10)
	check(owner.advance(150,radio,pose,eye),owner.error)
	var state:=owner.snapshot()
	check(state.phase==5 and state.cruise_speed==2.0 and state.elapsed_ms==0,"Entry also consumed a drive frame")
	check(state.input_blocked and not state.hud_visible and state.frame.entry,"Entry did not hold input/HUD")
	check(state.frame.player_pose_override.origin==pose.origin and state.frame.player_pose_override.basis.z.is_equal_approx(Vector3(-1,0,0)),"Entry lost position or yaw convention")
	check(state.eye==pose.origin+Vector3(25000,-200,-1000) and state.frame.camera_operations.size()==1,"Entry camera offset or immediate refresh differs")
	finish_through(radio,11)
	check(owner.advance(150,radio,pose,eye),owner.error)
	check(owner.snapshot().cruise_speed==2.0 and owner.snapshot().frame.audio.is_empty(),"Drive slowed before computer event finished")
	finish_through(radio,12)
	check(owner.advance(0,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.cruise_speed==Escape.single(2.0*definition.cruise_decay_per_update) and state.frame.audio.size()==5,"First eligible zero-time drive update differs")
	var prior: float=state.cruise_speed
	check(owner.advance(150,radio,pose,eye),owner.error)
	check(owner.snapshot().cruise_speed==Escape.single(prior*definition.cruise_decay_per_update) and owner.snapshot().frame.audio.size()==1,"Decay became time-scaled or restarted drive sounds")
	finish_through(radio,13);radio.started[14]=true
	var old_eye: Vector3=owner.snapshot().eye
	check(owner.advance(100,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.phase==6 and state.phase_elapsed_ms==0 and state.eye==old_eye+Vector3(30,0,-20),"Started/finished distinction or final drive pan differs")
	check(owner.advance(100,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.shake_strength==Escape.single(0.025) and state.frame.camera_operations[0].shake_strength==0.0,"Immediate camera used the later shake ramp")
	finish_through(radio,15)
	check(owner.advance(0,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.phase==7 and state.phase_elapsed_ms==0 and state.effect.time_ms==50 and state.effect.playing and not state.frame.effect_sampled,"Departure restart sampled or advanced early")
	step_ms(owner,radio,2000)
	check(owner.snapshot().phase==7 and owner.snapshot().ship_visible,"Ship hidden at inclusive 2000 ms boundary")
	check(owner.advance(1,radio,pose,eye),owner.error)
	check(not owner.snapshot().ship_visible and owner.snapshot().shake_strength==0.0,"Ship stayed visible after 2000 ms")
	step_ms(owner,radio,949)
	state=owner.snapshot()
	check(state.effect.time_ms==3000 and state.effect.playing and state.phase==7,"Effect ended at equality instead of after its last key")
	check(state.frame.effect_orientation=={"view":"immediate","up":Vector3.UP},"Departure effect did not request the immediate camera orientation")
	var saved:=state;var detached: RefCounted=owner.fork_for_frame()
	check(detached.advance(1,radio,pose,eye) and owner.snapshot()==saved,"Prospective escape frame changed the retained owner")
	owner=detached;state=owner.snapshot()
	check(state.phase==8 and not state.effect.playing and state.effect.sample_time_ms==3000,"Original animation completion did not gate the coast")
	step_ms(owner,radio,4000)
	check(owner.snapshot().phase==8,"Coast ended at 4000 ms equality")
	check(owner.advance(1,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.phase==9 and state.effect.time_ms==50 and state.effect.sample_time_ms==3000 and state.effect.playing,"Jump reset lost the retained sampled end pose")
	check(owner.advance(0,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.phase==10 and state.phase_elapsed_ms==0 and state.eye==Vector3(5000,500,-10000),"Relocation camera is wrong")
	check(state.frame.player_pose_override.origin==Vector3.ZERO and state.frame.player_pose_override.basis.z==Vector3.FORWARD,"Jump did not reset position/heading")
	check(state.frame.model_rotation_delta.is_equal_approx(Vector3.ONE*PI/4) and state.frame.camera_operations.is_empty(),"Visual tumble or non-immediate cut differs")
	check(state.frame.world_change=={"sky_mesh_id":17809,"sky_texture_id":10074,"planet_texture_id":10042,"planet_scale_multiplier":2.0},"Source environment substitutions differ")
	step_ms(owner,radio,2000)
	check(owner.snapshot().phase==10 and owner.snapshot().shake_strength==1.0,"Arrival ramp crossed its strict gate early")
	check(owner.advance(1,radio,pose,eye),owner.error)
	check(owner.snapshot().phase==11 and owner.snapshot().effect.time_ms==50,"Arrival effect advanced on its start cue")
	step_ms(owner,radio,2500)
	check(owner.snapshot().phase==11 and not owner.snapshot().ship_visible,"Arrival ship restored at equality")
	check(owner.advance(1,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.phase==12 and state.phase_elapsed_ms==2501 and state.ship_visible and state.frame.ship_restore and state.input_blocked and not state.hud_visible,"Arrival restored controls or reset the retained counter")
	check(state.cruise_speed==2.0 and state.frame.effect_orientation.backward==eye.basis.z,"Arrival failed cruise restore or preceding-camera backward axis")
	check(owner.advance(150,radio,pose,eye),owner.error)
	check(owner.snapshot().frame.model_rotation_delta==Vector3.ONE*Escape.single(0.05) and owner.snapshot().frame.player_pose_override==null,"Visual tumble rotated the logical travel pose")
	step_ms(owner,radio,300)
	check(not owner.snapshot().effect.playing,"Arrival effect failed to finish during drift")
	finish_through(radio,17)
	check(owner.advance(0,radio,pose,eye),owner.error)
	check(owner.snapshot().phase==13 and owner.snapshot().eye==pose.origin+Vector3(-2000,-2000,-5000),"Event-17 camera cut differs")
	step_ms(owner,radio,6000)
	check(owner.snapshot().phase==13,"Second shot ended at equality")
	check(owner.advance(1,radio,pose,eye),owner.error)
	check(owner.snapshot().phase==14 and owner.snapshot().eye==pose.origin+Vector3(700,0,-1700),"Six-second cut differs")
	step_ms(owner,radio,12000)
	check(owner.snapshot().phase==14,"Last pan ended at equality")
	check(owner.advance(1,radio,pose,eye),owner.error)
	state=owner.snapshot()
	check(state.phase==15 and state.eye==pose.origin+Vector3(-3000,3500,-6700) and state.frame.camera_operations[0].eye!=state.eye,"Last pan refresh was replaced by the following camera cut")
	check(owner.advance(0,radio,pose,eye),owner.error)
	check(owner.snapshot().phase==15,"Fade started before final radio completion")
	finish_through(radio,22)
	check(owner.advance(0,radio,pose,eye),owner.error)
	check(owner.snapshot().phase==16 and owner.snapshot().frame.fade_request.duration_ms==5000,"Source five-second fade request is missing")
	check(owner.advance(150,radio,pose,eye,true),owner.error)
	check(owner.snapshot().boundary.is_empty() and owner.snapshot().frame.fade_request.is_empty(),"Fade was repeated or treated as completed")
	var before:=owner.snapshot();var wrong:=radio.duplicate(true);wrong.binding_id="wrong"
	check(not owner.advance(0,wrong,pose,eye) and owner.snapshot()==before,"Foreign radio changed escape state")
	wrong=radio.duplicate(true);wrong.finished[10]=false
	check(not owner.advance(0,wrong,pose,eye) and owner.snapshot()==before,"Regressed radio changed escape state")
	check(not owner.advance(151,radio,pose,eye) and owner.snapshot()==before,"Invalid frame changed escape state")
	check(owner.advance(0,radio,pose,eye,false),owner.error)
	state=owner.snapshot()
	check(state.boundary=="arrival_transition_required" and not state.has("rewards") and not state.has("campaign_complete"),"Unverified arrival awarded progress")
	check(not owner.advance(0,radio,pose,eye,false) and owner.snapshot()==state,"Arrival boundary allowed further simulation")
	verify_radio(bindings,library)
	print("Escape verified: ",library.manifest.profile.edition," (phases 4–16, original 21-surface model)")

func verify_radio(bindings: RefCounted, library: RefCounted) -> void:
	# Composed scheduling fixture: the harness supplies defeated actor hulls;
	# this does not bypass contacts or award anything in a live game session.
	for language in library.manifest.languages:
		check(library.select_language(language),library.error)
		var resources:=RadioResources.new();var radio:=Radio.new();var camera:=Camera.new();var escape:=Escape.new()
		if not resources.prepare(library,bindings) or not radio.configure(bindings,library,resources.line_counts) or not camera.configure(bindings) or not escape.configure(bindings,library):
			check(false,resources.error+radio.error+camera.error+escape.error);return
		var elapsed:=0;var started:=[];var phases:=[]
		for frame in 4000:
			var preceding: Dictionary=radio.snapshot()
			if camera.snapshot().phase<4:
				check(camera.advance(150,preceding),camera.error)
			else:
				if not escape.advance(150,preceding,pose,eye):check(false,escape.error);return
			var phase: int=camera.snapshot().phase if escape.snapshot().phase==4 else escape.snapshot().phase
			if phase not in phases:phases.append(phase)
			var hull:=0 if preceding.finished[8] else 150
			elapsed+=150
			var changes:=radio.step(elapsed,{0:hull,1:hull,2:hull},phase)
			check(radio.error.is_empty(),radio.error)
			for change in changes:
				if change.kind=="started":
					started.append(change.event)
					if change.event==16:check(phase==12,"Radio 16 started outside malfunction drift")
			if not preceding.finished[10] and radio.snapshot().finished[10]:check(escape.snapshot().phase==4,"Fresh presentation flags entered escape in the same logic frame")
			if escape.snapshot().phase==16:break
		check(started==range(23) and radio.snapshot().finished[22],"Original radio did not finish all 23 events in order: "+language)
		for phase in range(5,17):check(phase in phases,"Original radio skipped escape phase %d"%phase)
		check(escape.snapshot().input_blocked and escape.snapshot().boundary.is_empty(),"Radio scheduler invented arrival completion")
		print("Composed radio verified: ",library.manifest.profile.edition," / ",language," / ",elapsed," ms")

func step_ms(owner: RefCounted, radio: Dictionary, total: int) -> void:
	while total>0:
		var delta:=mini(total,150)
		if not owner.advance(delta,radio,pose,eye):check(false,owner.error);return
		total-=delta
func finish_through(radio: Dictionary, event: int) -> void:
	for i in event+1:radio.started[i]=true;radio.finished[i]=true
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
